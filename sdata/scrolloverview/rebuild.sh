#!/usr/bin/env bash
# =============================================================================
# scrolloverview/rebuild.sh
#
# Rebuild the hyprland-scroll-overview Hyprland plugin against the currently
# installed Hyprland headers and redistribute the resulting scrolloverview.so
# to every user that already has one in ~/.local/share/hyprland/plugins/.
#
# Hyprland's plugin ABI is pinned to an exact compositor version, so a
# previously-built scrolloverview.so refuses to load the moment hyprland is
# upgraded (even patch bumps). This script is invoked by the pacman hook
# /etc/pacman.d/hooks/95-scrolloverview-rebuild.hook on every `hyprland`
# Install/Upgrade so the plugin tracks the compositor automatically.
#
# Source-of-truth selection (zero user interaction by default):
#
#   1. If $SCROLLOVERVIEW_REF is set in /etc/scrolloverview.conf, use it
#      verbatim with no fallback. Power-user override.
#
#   2. Otherwise, try this list of candidates in order, building each
#      until one succeeds:
#        a. The cached "last known good" commit from a prior successful
#           run (/var/cache/scrolloverview/last-good-ref).
#        b. The plugin SHA paired with the installed Hyprland commit in
#           the upstream hyprpm.toml `commit_pins` table, when present.
#        c. An exact `v<HYPR_VER>` tag if upstream has shipped one.
#        d. The highest `v<MAJOR>.<MINOR>.*` tag.
#        e. `main`.
#        f. Walk backward through `main` commit-by-commit until one
#           builds. Capped at WALK_DEPTH commits to avoid runaway loops
#           against a permanently-broken upstream.
#
#   3. The first working ref is cached as last-known-good for the next
#      run. Subsequent rebuilds short-circuit on step 2a.
#
# This means: when hyprland gets a routine patch bump, rebuild reuses
# the cached commit and finishes in seconds. When hyprland makes a
# breaking change that the cached commit can't handle, the script
# self-heals by walking history and updating the cache.
#
# /etc/scrolloverview.conf overrides (sourced as bash, all optional):
#   SCROLLOVERVIEW_REPO=<git url>   default: MainstreamOS/hyprland-scroll-overview
#   SCROLLOVERVIEW_DEFAULT_BRANCH=<name>   default: mainstream (override
#                                          to "main" when SCROLLOVERVIEW_REPO
#                                          points at upstream yayuuu/...)
#   SCROLLOVERVIEW_REF=<tag/sha>    explicit pin; disables auto-fallback
#   WALK_DEPTH=<N>                  commits to try in step 2f (default 50)
#
# Exit codes:
#   * exit 1 - operator action required: missing build deps, can't read
#              Hyprland version, or a user-pinned SCROLLOVERVIEW_REF didn't
#              build.
#   * exit 0 - either built successfully, OR no upstream commit yet builds
#              against the running Hyprland (treated as transient upstream
#              lag). The pacman transaction stays clean; the systemd timer
#              keeps retrying every 24h until upstream catches up.
#
# Status file (/var/lib/scrolloverview/status):
#   Written on state transitions, read by /usr/local/bin/scrolloverview-status-notify
#   from the user's Hyprland session to show friendly desktop notifications.
#     state=failed     - last attempt failed; overview currently off
#     state=recovered  - succeeded after a prior failure (one-shot, cleared
#                        on next successful build)
#     (absent)         - steady state; no notification
# =============================================================================

set -euo pipefail

CONFIG_FILE=/etc/scrolloverview.conf
SRC_DIR=/var/cache/scrolloverview/src
LAST_GOOD_FILE=/var/cache/scrolloverview/last-good-ref
BUILD_LOG=/var/cache/scrolloverview/last-build.log
# State file (read by scrolloverview-status-notify on Hyprland startup to
# surface friendly desktop notifications). /var/lib instead of /var/cache
# because this is state, not regenerable cache.
STATUS_DIR=/var/lib/scrolloverview
STATUS_FILE="$STATUS_DIR/status"
LOG_PFX="[scrolloverview-rebuild]"

SCROLLOVERVIEW_REPO="https://github.com/MainstreamOS/hyprland-scroll-overview"
SCROLLOVERVIEW_REF=""
SCROLLOVERVIEW_DEFAULT_BRANCH="mainstream"
WALK_DEPTH=50

# shellcheck disable=SC1090
[[ -r "$CONFIG_FILE" ]] && . "$CONFIG_FILE"

log() { echo "$LOG_PFX $*"; }
err() { echo "$LOG_PFX ERROR: $*" >&2; }

# Skip silently inside an archiso build environment.
if [[ -f /run/archiso/bootmnt/arch/version ]] || mountpoint -q /run/archiso 2>/dev/null; then
    exit 0
fi

# Find users with an existing scrolloverview.so before doing any work.
shopt -s nullglob
TARGETS=()
for home_dir in /home/*; do
    [[ -d "$home_dir" ]] || continue
    so="$home_dir/.local/share/hyprland/plugins/scrolloverview.so"
    [[ -f "$so" ]] && TARGETS+=("$so")
done

if (( ${#TARGETS[@]} == 0 )); then
    log "No user has scrolloverview.so installed — nothing to rebuild."
    exit 0
fi

for cmd in git make gcc pkg-config; do
    command -v "$cmd" >/dev/null 2>&1 || { err "missing command: $cmd"; exit 1; }
done
for pc in hyprland pixman-1 libdrm pangocairo libinput libudev wayland-server xkbcommon; do
    pkg-config --exists "$pc" 2>/dev/null || { err "missing pkg-config dep: $pc"; exit 1; }
done

HYPR_VER=$(pkg-config --modversion hyprland 2>/dev/null || echo "")
[[ -n "$HYPR_VER" ]] || { err "could not read Hyprland version"; exit 1; }
log "Installed Hyprland: $HYPR_VER"

# Resolve the running Hyprland's commit SHA so we can match against the
# upstream hyprpm.toml commit_pins. hyprctl is preferred (matches what's
# actually running); pkg-config doesn't expose this. Best-effort only.
HYPR_SHA=""
if command -v hyprctl >/dev/null 2>&1; then
    HYPR_SHA=$(hyprctl version 2>/dev/null | awk '/at commit/{for(i=1;i<=NF;i++) if($i=="commit") print $(i+1)}' | head -n1 || true)
fi

mkdir -p "$(dirname "$SRC_DIR")"

# Fetch (or fast-update) the source tree with full tag history. Full clone
# is fine — hyprland-scroll-overview is a tiny repo, and we need history to
# walk backward when main fails.
if [[ -d "$SRC_DIR/.git" ]]; then
    if ! git -C "$SRC_DIR" remote get-url origin 2>/dev/null | grep -qF "$SCROLLOVERVIEW_REPO"; then
        log "Repo URL changed; re-cloning $SCROLLOVERVIEW_REPO"
        rm -rf "$SRC_DIR"
    else
        git -C "$SRC_DIR" fetch --tags --prune origin >/dev/null 2>&1 || {
            err "git fetch failed; nuking and re-cloning"
            rm -rf "$SRC_DIR"
        }
    fi
fi
if [[ ! -d "$SRC_DIR/.git" ]]; then
    rm -rf "$SRC_DIR"
    git clone "$SCROLLOVERVIEW_REPO" "$SRC_DIR" >/dev/null 2>&1 \
        || { err "git clone $SCROLLOVERVIEW_REPO failed"; exit 1; }
fi

# ------------------------------------------------------------------
# Build helpers
# ------------------------------------------------------------------
build_at_ref() {
    local ref="$1"
    git -C "$SRC_DIR" reset --hard >/dev/null 2>&1 || true
    git -C "$SRC_DIR" clean -fdx >/dev/null 2>&1 || true

    if ! git -C "$SRC_DIR" checkout --quiet "$ref" 2>/dev/null \
       && ! git -C "$SRC_DIR" checkout --quiet "tags/${ref}" 2>/dev/null; then
        return 1
    fi

    : > "$BUILD_LOG"
    make -C "$SRC_DIR" clean >/dev/null 2>&1 || true
    if make -C "$SRC_DIR" all -j"$(nproc)" >>"$BUILD_LOG" 2>&1 \
       && [[ -f "$SRC_DIR/scrolloverview.so" ]]; then
        return 0
    fi
    return 1
}

# Read the scroll-overview SHA paired with $HYPR_SHA in the upstream
# hyprpm.toml. The file lives in the repo we just cloned, so this is run
# AFTER the clone/fetch above. Returns empty string when no match.
hyprpm_pinned_ref() {
    local pin_file="$SRC_DIR/hyprpm.toml"
    [[ -n "$HYPR_SHA" && -r "$pin_file" ]] || return 0
    awk -v sha="$HYPR_SHA" '
        /^\[/{ section=$0 }
        section=="[repository]" && /^[[:space:]]*\[/ {
            gsub(/[",\[\]]/, "")
            if ($1==sha) { print $2; exit }
        }
    ' "$pin_file" 2>/dev/null
}

auto_detect_refs() {
    # Echo candidate refs in preferred order, separated by newlines.
    if [[ -f "$LAST_GOOD_FILE" ]]; then
        local cached
        cached=$(cat "$LAST_GOOD_FILE" 2>/dev/null || true)
        [[ -n "$cached" ]] && echo "$cached"
    fi

    local pinned
    pinned=$(hyprpm_pinned_ref)
    [[ -n "$pinned" ]] && echo "$pinned"

    if git -C "$SRC_DIR" rev-parse -q --verify "refs/tags/v${HYPR_VER}" >/dev/null 2>&1; then
        echo "v${HYPR_VER}"
    fi

    local mm
    mm=$(echo "$HYPR_VER" | awk -F. '{printf "%s.%s", $1, $2}')
    local highest
    highest=$(git -C "$SRC_DIR" tag -l "v${mm}.*" | sort -V | tail -n1)
    [[ -n "$highest" ]] && echo "$highest"

    echo "$SCROLLOVERVIEW_DEFAULT_BRANCH"
}

# ------------------------------------------------------------------
# Status-file helpers (read by /usr/local/bin/scrolloverview-status-notify)
# ------------------------------------------------------------------
write_status_failed() {
    local hypr_ver="$1"
    mkdir -p "$STATUS_DIR"
    cat > "$STATUS_FILE" <<EOF
state=failed
hyprland_version=$hypr_ver
last_attempt=$(date -Iseconds 2>/dev/null || date)
EOF
    chmod 644 "$STATUS_FILE"
}

# Called after a successful build. Three transitions:
#   * no prior status     -> nothing to do (file stays absent)
#   * prior state=failed  -> write state=recovered (one-shot user notification)
#   * prior state=recovered (or anything unrecognized) -> remove the file so
#     the next run is a clean slate and the user-side notify script doesn't
#     re-show stale "is back" messages.
clear_or_recovered_status() {
    local hypr_ver="$1"
    [[ -f "$STATUS_FILE" ]] || return 0
    local prev_state=""
    prev_state=$(grep '^state=' "$STATUS_FILE" 2>/dev/null | head -n1 | cut -d= -f2-)
    if [[ "$prev_state" == "failed" ]]; then
        local prev_ver=""
        prev_ver=$(grep '^hyprland_version=' "$STATUS_FILE" 2>/dev/null | head -n1 | cut -d= -f2-)
        mkdir -p "$STATUS_DIR"
        cat > "$STATUS_FILE" <<EOF
state=recovered
recovered_from=$prev_ver
hyprland_version=$hypr_ver
recovered_at=$(date -Iseconds 2>/dev/null || date)
EOF
        chmod 644 "$STATUS_FILE"
    else
        rm -f "$STATUS_FILE"
    fi
}

# ------------------------------------------------------------------
# Resolve and build
# ------------------------------------------------------------------
SUCCESS_REF=""

if [[ -n "$SCROLLOVERVIEW_REF" ]]; then
    log "Using explicit SCROLLOVERVIEW_REF=$SCROLLOVERVIEW_REF (no fallback)"
    if build_at_ref "$SCROLLOVERVIEW_REF"; then
        SUCCESS_REF="$SCROLLOVERVIEW_REF"
    else
        err "build failed at pinned ref $SCROLLOVERVIEW_REF"
        err "full log: $BUILD_LOG"
        tail -n 20 "$BUILD_LOG" >&2
        write_status_failed "$HYPR_VER"
        exit 1
    fi
else
    # Stage 1: try the candidate list (cache → hyprpm pin → tags → main)
    seen=""
    while IFS= read -r ref; do
        [[ -z "$ref" ]] && continue
        case " $seen " in *" $ref "*) continue;; esac
        seen="$seen $ref"
        log "Trying ref: $ref"
        if build_at_ref "$ref"; then
            SUCCESS_REF="$ref"
            break
        fi
    done < <(auto_detect_refs)

    # Stage 2: walk backward through main if everything above failed
    if [[ -z "$SUCCESS_REF" ]]; then
        log "All candidate refs failed — walking back through $SCROLLOVERVIEW_DEFAULT_BRANCH (max $WALK_DEPTH commits)..."
        attempt=0
        while IFS= read -r commit; do
            attempt=$((attempt + 1))
            (( attempt > WALK_DEPTH )) && break
            short=$(git -C "$SRC_DIR" rev-parse --short "$commit")
            log "  [$attempt/$WALK_DEPTH] trying $short"
            if build_at_ref "$commit"; then
                SUCCESS_REF="$commit"
                break
            fi
        done < <(git -C "$SRC_DIR" log --format=%H "origin/$SCROLLOVERVIEW_DEFAULT_BRANCH" 2>/dev/null \
                || git -C "$SRC_DIR" log --format=%H "$SCROLLOVERVIEW_DEFAULT_BRANCH")
    fi
fi

if [[ -z "$SUCCESS_REF" ]]; then
    err "no hyprland-scroll-overview commit builds against Hyprland $HYPR_VER yet."
    err "this is almost always because upstream hyprland-scroll-overview hasn't"
    err "  shipped a $HYPR_VER-compatible commit yet (the API moved). The"
    err "  scrolloverview-rebuild.timer retries every 24h and self-heals once"
    err "  upstream catches up — no action needed."
    err "tried up to $WALK_DEPTH commits walking back from $SCROLLOVERVIEW_DEFAULT_BRANCH."
    err "full log of last attempt: $BUILD_LOG"
    err "to pin a known-good ref manually, set SCROLLOVERVIEW_REF=<sha> in $CONFIG_FILE."
    tail -n 20 "$BUILD_LOG" >&2
    write_status_failed "$HYPR_VER"
    log "exiting 0 (transient upstream lag, not a system error)."
    exit 0
fi

BUILT_SO="$SRC_DIR/scrolloverview.so"

# Persist the working ref for next time. Resolve to a full SHA so it's
# reproducible even if the original ref was a moving branch like main.
mkdir -p "$(dirname "$LAST_GOOD_FILE")"
git -C "$SRC_DIR" rev-parse HEAD > "$LAST_GOOD_FILE"

# Distribute. Preserve owner so Hyprland (running as the user) can read it.
for target in "${TARGETS[@]}"; do
    user_home="${target%/.local/share/hyprland/plugins/scrolloverview.so}"
    user="$(stat -c '%U' "$user_home")"
    install -m 755 -o "$user" -g "$user" "$BUILT_SO" "$target"
    log "Updated $target (owner: $user)"
done

clear_or_recovered_status "$HYPR_VER"

log "Done. ${#TARGETS[@]} user(s) updated against Hyprland $HYPR_VER."
log "Built ref: $SUCCESS_REF (resolved to $(git -C "$SRC_DIR" rev-parse --short HEAD))."
log "Note: relaunch Hyprland for the new plugin to take effect."
