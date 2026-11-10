#!/usr/bin/env bash
set -euo pipefail

if (( EUID == 0 )) || [[ ! -t 0 ]]; then
  printf '%s\n' 'Run mainstream-finish-install from a terminal as the user you created.' >&2
  exit 1
fi

handoff=/opt/mainstream-install
repo="${XDG_CACHE_HOME:-$HOME/.cache}/dots-hyprland"
mkdir -p "$(dirname "$repo")"
exec {lock_fd}>"$repo.install.lock"
if ! flock -n "$lock_fd"; then
  printf '%s\n' 'Another Mainstream setup is already running.' >&2
  exit 1
fi

if [[ ! -e "$repo" ]]; then
  git clone "$handoff/source.bundle" "$repo"
  git -C "$repo" remote set-url origin https://github.com/MainstreamOS/dots-hyprland.git
fi
if [[ $(git -C "$repo" rev-parse HEAD) != $(git bundle list-heads "$handoff/source.bundle" HEAD | cut -d ' ' -f 1) ]]; then
  printf '%s\n' 'The existing checkout differs from the source selected at install time. Move it aside and try again.' >&2
  exit 1
fi

mapfile -t options < "$handoff/options"
if ! MS_REQUIRE_COMPLETE_INSTALL=1 "$repo/setup" install --force "${options[@]}"; then
  printf '%s\n' 'Run mainstream-finish-install again to retry with the same app choices.' >&2
  exit 1
fi
if tag=$(git -C "$repo" describe --tags --abbrev=0 --match '[0-9]*.[0-9]*.[0-9]*' HEAD 2>/dev/null); then
  printf '%s\n' "$tag" > "$repo/.updatems-applied-tag"
fi
if sudo unlink "$handoff/source.bundle" && sudo unlink "$handoff/options"; then
  sudo rmdir "$handoff" || true
  sudo unlink /usr/local/bin/mainstream-finish-install || true
fi
printf '%s\n' 'Mainstream is set up. Reboot to start the desktop.'
