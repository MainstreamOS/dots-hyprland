#!/usr/bin/env bash
# Helper script for copying wallpaper to SDDM theme directory.
# Intended to be run via pkexec with a matching polkit rule that
# allows passwordless execution.
#
# Usage: sddm-bg-helper.sh <source> <dest>

set -euo pipefail

src="$1"
dest="$2"
dest_dir="$(dirname "$dest")"

# Strict path validation — only allow the exact pixie theme backgrounds dir
[[ "$dest_dir" == "/usr/share/sddm/themes/pixie/assets/backgrounds" ]] || exit 1

# Source must be a regular file (not a symlink, device, etc.)
[[ -f "$src" && ! -L "$src" ]] || exit 1
# Root copies the file into a world-readable place, so the person asking has
# to be able to read it themselves; otherwise this is a way to publish any
# file on the system by naming it as a wallpaper.
caller="${PKEXEC_UID:-}"
[[ "$caller" =~ ^[0-9]+$ ]] || exit 1
caller_name="$(getent passwd "$caller" | cut -d: -f1)"
[[ -n "$caller_name" ]] || exit 1
runuser -u "$caller_name" -- test -r "$src" || exit 1

# Destination must not be a symlink (prevent symlink attacks)
[[ ! -L "$dest" ]] || exit 1
[[ ! -L "$dest_dir" ]] || exit 1

# Ensure dest filename ends in .jpg
[[ "$dest" == *.jpg ]] || exit 1

mkdir -p "$dest_dir"
cp -- "$src" "$dest"
chmod 644 "$dest"
