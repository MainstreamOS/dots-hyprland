#!/usr/bin/env bash
set -euo pipefail

handoff=/var/log/mainstream-install
if (( EUID == 0 )); then
  IFS= read -r username < "$handoff/username"
  uid=$(id -u "$username")
  (( uid >= 1000 && uid < 65534 )) || exit 1

  # Seed Limine with the new root and encryption parameters from Archinstall.
  # The running kernel is still the USB's kernel.
  if [[ ! -s /etc/kernel/cmdline ]]; then
    cmdline=$(awk '$1 == "options" {sub(/^options[[:space:]]+/, ""); print; exit}' /boot/loader/entries/*.conf)
    [[ -n "$cmdline" ]] || { echo 'Missing the installed system kernel command line.' >&2; exit 1; }
    install -d /etc/kernel
    printf '%s\n' "$cmdline" > /etc/kernel/cmdline
  fi

  # Only the temporary chroot has the passwordless rule. An interrupted
  # install leaves no rule in effect after boot because /run is ephemeral.
  runtime=/run/mainstream-install
  include=/etc/sudoers.d/zz-mainstream-install
  install -d -m 750 "$runtime"
  trap 'rm -f -- "$runtime/account" "$include"; rmdir -- "$runtime" || :' EXIT
  (umask 337
    printf '@includedir %s\n' "$runtime" > "$include"
    printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$username" > "$runtime/account"
  )
  visudo -cf /etc/sudoers >/dev/null

  runuser -u "$username" -- env MS_INSTALL_OFFLINE=1 TERM=linux "$handoff/finish-fresh.sh"
  exit
fi

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
  printf '%s\n' 'The existing checkout differs from the source selected at install time.' >&2
  exit 1
fi

mapfile -t options < "$handoff/options"
MS_REQUIRE_COMPLETE_INSTALL=1 "$repo/setup" install --force "${options[@]}"
if tag=$(git -C "$repo" describe --tags --abbrev=0 --match '[0-9]*.[0-9]*.[0-9]*' HEAD 2>/dev/null); then
  printf '%s\n' "$tag" > "$repo/.updatems-applied-tag"
fi
