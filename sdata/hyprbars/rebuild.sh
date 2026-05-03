#!/usr/bin/env bash
# =============================================================================
# hyprbars/rebuild.sh
#
# Rebuild the hyprbars Hyprland plugin against the currently-installed
# Hyprland headers and redistribute the resulting hyprbars.so to every
# user that already has one in ~/.local/share/hyprland/plugins/.
#
# Hyprland's plugin ABI is pinned to an exact compositor version, so a
# previously-built hyprbars.so refuses to load the moment hyprland is
# upgraded (even patch bumps). This script is invoked by the pacman hook
# /etc/pacman.d/hooks/95-hyprbars-rebuild.hook on every `hyprland`
# Install/Upgrade so the plugin tracks the compositor automatically.
#
# Source-of-truth selection (zero user interaction by default):
#
#   1. If $HYPRBARS_REF is set in /etc/hyprbars.conf, use it verbatim
#      with no fallback. Power-user override.
#
#   2. Otherwise, try this list of candidates in order, building each
#      until one succeeds:
#        a. The cached "last known good" commit from a prior successful
#           run (/var/cache/hyprbars/last-good-ref).
#        b. An exact `v<HYPR_VER>` tag if upstream has shipped one.
#        c. The highest `v<MAJOR>.<MINOR>.*` tag.
#        d. `main`.
#        e. Walk backward through `main` commit-by-commit until one
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
# /etc/hyprbars.conf overrides (sourced as bash, all optional):
#   HYPRBARS_REPO=<git url>   default: hyprwm/hyprland-plugins
#   HYPRBARS_REF=<tag/sha>    explicit pin; disables auto-fallback
#   WALK_DEPTH=<N>            commits to try in step 2e (default 50)
# =============================================================================

set -euo pipefail

CONFIG_FILE=/etc/hyprbars.conf
SRC_DIR=/var/cache/hyprbars/src
LAST_GOOD_FILE=/var/cache/hyprbars/last-good-ref
BUILD_LOG=/var/cache/hyprbars/last-build.log
LOG_PFX="[hyprbars-rebuild]"

HYPRBARS_REPO="https://github.com/hyprwm/hyprland-plugins"
HYPRBARS_REF=""
WALK_DEPTH=50

# shellcheck disable=SC1090
[[ -r "$CONFIG_FILE" ]] && . "$CONFIG_FILE"

log() { echo "$LOG_PFX $*"; }
err() { echo "$LOG_PFX ERROR: $*" >&2; }

# Skip silently inside an archiso build environment.
if [[ -f /run/archiso/bootmnt/arch/version ]] || mountpoint -q /run/archiso 2>/dev/null; then
    exit 0
fi

# Find users with an existing hyprbars.so before doing any work.
shopt -s nullglob
TARGETS=()
for home_dir in /home/*; do
    [[ -d "$home_dir" ]] || continue
    so="$home_dir/.local/share/hyprland/plugins/hyprbars.so"
    [[ -f "$so" ]] && TARGETS+=("$so")
done

if (( ${#TARGETS[@]} == 0 )); then
    log "No user has hyprbars.so installed — nothing to rebuild."
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

mkdir -p "$(dirname "$SRC_DIR")"

# Fetch (or fast-update) the source tree with full tag history. Full clone
# is fine — hyprland-plugins is a tiny repo, and we need history to walk
# backward when main fails.
if [[ -d "$SRC_DIR/.git" ]]; then
    if ! git -C "$SRC_DIR" remote get-url origin 2>/dev/null | grep -qF "$HYPRBARS_REPO"; then
        log "Repo URL changed; re-cloning $HYPRBARS_REPO"
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
    git clone "$HYPRBARS_REPO" "$SRC_DIR" >/dev/null 2>&1 \
        || { err "git clone $HYPRBARS_REPO failed"; exit 1; }
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
    make -C "$SRC_DIR/hyprbars" clean >/dev/null 2>&1 || true
    if make -C "$SRC_DIR/hyprbars" all -j"$(nproc)" >>"$BUILD_LOG" 2>&1 \
       && [[ -f "$SRC_DIR/hyprbars/hyprbars.so" ]]; then
        return 0
    fi
    return 1
}

auto_detect_refs() {
    # Echo candidate refs in preferred order, separated by newlines.
    if [[ -f "$LAST_GOOD_FILE" ]]; then
        local cached
        cached=$(cat "$LAST_GOOD_FILE" 2>/dev/null || true)
        [[ -n "$cached" ]] && echo "$cached"
    fi

    if git -C "$SRC_DIR" rev-parse -q --verify "refs/tags/v${HYPR_VER}" >/dev/null 2>&1; then
        echo "v${HYPR_VER}"
    fi

    local mm
    mm=$(echo "$HYPR_VER" | awk -F. '{printf "%s.%s", $1, $2}')
    local highest
    highest=$(git -C "$SRC_DIR" tag -l "v${mm}.*" | sort -V | tail -n1)
    [[ -n "$highest" ]] && echo "$highest"

    echo "main"
}

# ------------------------------------------------------------------
# Resolve and build
# ------------------------------------------------------------------
SUCCESS_REF=""

if [[ -n "$HYPRBARS_REF" ]]; then
    log "Using explicit HYPRBARS_REF=$HYPRBARS_REF (no fallback)"
    if build_at_ref "$HYPRBARS_REF"; then
        SUCCESS_REF="$HYPRBARS_REF"
    else
        err "build failed at pinned ref $HYPRBARS_REF"
        err "full log: $BUILD_LOG"
        tail -n 20 "$BUILD_LOG" >&2
        exit 1
    fi
else
    # Stage 1: try the candidate list (cache → tags → main)
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
        log "All candidate refs failed — walking back through main (max $WALK_DEPTH commits)..."
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
        done < <(git -C "$SRC_DIR" log --format=%H origin/main 2>/dev/null \
                || git -C "$SRC_DIR" log --format=%H main)
    fi
fi

if [[ -z "$SUCCESS_REF" ]]; then
    err "could not find any hyprland-plugins ref that builds against Hyprland $HYPR_VER"
    err "tried up to $WALK_DEPTH commits walking back from main"
    err "full log of last attempt: $BUILD_LOG"
    err "to override, set HYPRBARS_REF=<sha> in $CONFIG_FILE and re-run."
    tail -n 20 "$BUILD_LOG" >&2
    exit 1
fi

BUILT_SO="$SRC_DIR/hyprbars/hyprbars.so"

# Persist the working ref for next time. Resolve to a full SHA so it's
# reproducible even if the original ref was a moving branch like main.
mkdir -p "$(dirname "$LAST_GOOD_FILE")"
git -C "$SRC_DIR" rev-parse HEAD > "$LAST_GOOD_FILE"

# Distribute. Preserve owner so Hyprland (running as the user) can read it.
for target in "${TARGETS[@]}"; do
    user_home="${target%/.local/share/hyprland/plugins/hyprbars.so}"
    user="$(stat -c '%U' "$user_home")"
    install -m 755 -o "$user" -g "$user" "$BUILT_SO" "$target"
    log "Updated $target (owner: $user)"
done

log "Done. ${#TARGETS[@]} user(s) updated against Hyprland $HYPR_VER."
log "Built ref: $SUCCESS_REF (resolved to $(git -C "$SRC_DIR" rev-parse --short HEAD))."
log "Note: relaunch Hyprland for the new plugin to take effect."
