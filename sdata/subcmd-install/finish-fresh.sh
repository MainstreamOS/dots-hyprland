#!/usr/bin/env bash
set -euo pipefail

handoff=/var/log/mainstream-firstboot
if (( EUID == 0 )); then
  IFS= read -r username < "$handoff/username"
  uid=$(id -u "$username")
  (( uid >= 1000 && uid < 65534 )) || exit 1
  if ! nm-online -q -t 25; then
    printf '%s\n' 'Connect to the internet to finish setting up Mainstream.'
    nmtui connect || :
  fi

  # The fresh account runs the regular installer. Its unattended sudo rule
  # lives in /run, so it is lost even if the machine powers off during setup.
  sudoers=/run/mainstream-firstboot/sudoers
  install -d -m 750 "$sudoers"
  trap 'rm -f -- "$sudoers/account"' EXIT
  (umask 337; printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$username" > "$sudoers/account")
  visudo -cf /etc/sudoers >/dev/null

  systemctl start "user@$uid.service"
  printf '\nFinishing Mainstream setup. The computer will restart when it is ready.\n'
  while ! runuser -u "$username" -- env TERM=linux XDG_RUNTIME_DIR="/run/user/$uid" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$handoff/finish-fresh.sh"; do
    printf '\nSetup is incomplete. Press Enter to retry, N to connect to a network, or Q to exit: '
    IFS= read -r retry
    case "$retry" in
      n|N) nmtui connect || : ;;
      q|Q) exit 1 ;;
    esac
  done

  rm -f -- "$sudoers/account" /etc/sudoers.d/zz-mainstream-firstboot
  systemctl disable mainstream-firstboot.service
  rm -f -- /etc/systemd/system/mainstream-firstboot.service "$handoff/"{finish-fresh.sh,options,source.bundle,username}
  rmdir "$handoff"
  sync
  printf '\nMainstream is ready. Restarting…\n'
  systemctl --no-block reboot
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
