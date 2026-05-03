#!/usr/bin/env bash
# =============================================================================
# hyprbars/rebuild.sh
#
# Rebuild the hyprbars Hyprland plugin against the currently-installed
# Hyprland headers and redistribute the resulting hyprbars.so to every
# user that already has one in ~/.local/share/hyprland/plugins/.
#
# Hyprland's plugin ABI is pinned to an exact version: a plugin built
# against Hyprland X refuses to load under Hyprland Y, even for a patch
# bump. This script is invoked by /etc/pacman.d/hooks/95-hyprbars-rebuild.hook
# whenever `hyprland` is installed/upgraded so the plugin stays in sync.
# It can also be run manually as root to repair after an out-of-band
# Hyprland update.
#
# Idempotent: no users with hyprbars.so → no work.
# =============================================================================

set -euo pipefail

SRC_DIR=/var/cache/hyprbars/src
LOG_PFX="[hyprbars-rebuild]"

log() { echo "$LOG_PFX $*"; }
err() { echo "$LOG_PFX ERROR: $*" >&2; }

# Skip silently when running inside an archiso build environment — there are
# no real users to distribute to, and the host's hyprland may not even be
# usable as a build target.
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

# Build deps — bail with a clear message rather than a cryptic make error.
for cmd in git make gcc pkg-config; do
    command -v "$cmd" >/dev/null 2>&1 || { err "missing command: $cmd"; exit 1; }
done
for pc in hyprland pixman-1 libdrm pangocairo libinput libudev wayland-server xkbcommon; do
    pkg-config --exists "$pc" 2>/dev/null || { err "missing pkg-config dep: $pc"; exit 1; }
done

HYPR_VER=$(pkg-config --modversion hyprland 2>/dev/null || echo unknown)
log "Rebuilding hyprbars against Hyprland $HYPR_VER"

# Clone or fast-forward the source tree under /var/cache so we don't litter
# user homes with build artifacts. --depth=1 keeps it small.
mkdir -p "$(dirname "$SRC_DIR")"
if [[ -d "$SRC_DIR/.git" ]]; then
    git -C "$SRC_DIR" fetch --depth=1 origin main >/dev/null 2>&1 || {
        err "git fetch failed; nuking and re-cloning"
        rm -rf "$SRC_DIR"
    }
fi
if [[ ! -d "$SRC_DIR/.git" ]]; then
    rm -rf "$SRC_DIR"
    git clone --depth=1 https://github.com/hyprwm/hyprland-plugins "$SRC_DIR" >/dev/null 2>&1 \
        || { err "git clone failed"; exit 1; }
else
    git -C "$SRC_DIR" reset --hard origin/main >/dev/null 2>&1 || true
fi

# Always clean — a partial build from a prior Hyprland version cannot be
# trusted to relink correctly against new headers.
make -C "$SRC_DIR/hyprbars" clean >/dev/null 2>&1 || true
if ! make -C "$SRC_DIR/hyprbars" all -j"$(nproc)" >/dev/null 2>&1; then
    err "build failed — re-run with full output: make -C $SRC_DIR/hyprbars all"
    exit 1
fi

BUILT_SO="$SRC_DIR/hyprbars/hyprbars.so"
[[ -f "$BUILT_SO" ]] || { err "expected $BUILT_SO not produced"; exit 1; }

# Distribute. Preserve each target's owner so Hyprland (running as the user)
# can still read it.
for target in "${TARGETS[@]}"; do
    user_home="${target%/.local/share/hyprland/plugins/hyprbars.so}"
    user="$(stat -c '%U' "$user_home")"
    install -m 755 -o "$user" -g "$user" "$BUILT_SO" "$target"
    log "Updated $target (owner: $user)"
done

log "Done. ${#TARGETS[@]} user(s) updated against Hyprland $HYPR_VER."
log "Note: relaunch Hyprland for the new plugin to take effect."
