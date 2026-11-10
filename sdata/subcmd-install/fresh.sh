#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  printf '%s\n' 'Usage: ./setup install --fresh' \
    'From the stock Arch USB, choose a profile and install to free space or erase a disk.' \
    'Choose whether to encrypt the system and create your account here.' \
    'Mainstream finishes desktop setup before restarting.'
  exit 0
fi
[[ $# == 0 ]] || { printf '%s\n' 'Use ./setup install --fresh --help.' >&2; exit 1; }

if (( EUID != 0 )) || ! mountpoint -q /run/archiso/airootfs ||
    [[ $(findmnt -n -t overlay -o SOURCE --mountpoint /) != airootfs ]]; then
  printf '%s\n' 'Run this from the root console on the stock Arch USB. On an installed system, use ./setup install.' >&2
  exit 1
fi
if ! command -v archinstall >/dev/null; then
  printf '%s\n' 'Archinstall is missing from the live system. Boot a current stock Arch USB and retry.' >&2
  exit 1
fi
if [[ ! -d /sys/firmware/efi || ! -t 0 || ! -t 1 ]]; then
  printf '%s\n' 'The terminal installer requires the Arch USB booted in UEFI mode and an interactive terminal.' >&2
  exit 1
fi

REPO_ROOT=$(pwd)
source "$REPO_ROOT/sdata/subcmd-install/profiles.sh"
staging=$(mktemp -d /run/mainstream-install.XXXXXXXX)
target="$staging/target"
saved_font="$staging/console-font.psf"
restore_wizard_font() {
  if [[ -s $saved_font ]]; then
    setfont "$saved_font" 2>/dev/null || :
  fi
  rm -f -- "$saved_font"
}
cleanup() {
  restore_wizard_font
  rm -f -- "$staging/credentials.json" "$staging/config.json" "$staging/source.bundle" "$staging/bin/systemd-run" \
    "$staging/catalog" "$staging/options" "$staging/username"
  if mountpoint -q "$target"; then
    umount -R "$target" || return
  fi
  rmdir -- "$staging/bin" "$target" "$staging" 2>/dev/null || :
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$target"
shopt -s nullglob
wifi_profiles=(/var/lib/iwd/*.psk /var/lib/iwd/*.open)
shopt -u nullglob
network=nm
if (( ${#wifi_profiles[@]} )); then network=nm_iwd; fi
install_app_catalog --groups > "$staging/catalog"
# Use the larger font shipped on the Arch USB when the local console has
# room for it. Keep terminal emulators and serial consoles as they are.
if [[ ${TERM:-} == linux && $(tty) =~ ^/dev/tty[0-9]+$ &&
      -r /usr/share/kbd/consolefonts/ter-132n.psf.gz ]] &&
    read -r rows columns < <(stty size) && (( rows >= 80 && columns >= 160 )); then
  setfont -O "$saved_font" ter-132n 2>/dev/null || :
fi
(umask 077; python "$REPO_ROOT/sdata/subcmd-install/fresh-wizard.py" "$staging" "$network")
restore_wizard_font
[[ -s "$staging/config.json" ]] || exit 0
install -Dm755 "$REPO_ROOT/sdata/subcmd-install/archinstall-systemd-run" "$staging/bin/systemd-run"
git -c safe.directory="$REPO_ROOT" bundle create "$staging/source.bundle" HEAD --branches --tags
printf '\nInstalling the base system. The desktop setup will follow.\n'
(umask 022; PATH="$staging/bin:$PATH" archinstall --silent --config "$staging/config.json" \
  --creds "$staging/credentials.json" --mountpoint "$target")
rm -f -- "$staging/credentials.json"

if [[ $(findmnt -n -o FSTYPE --mountpoint "$target") != btrfs || ! -s $target/etc/fstab ]] ||
    ! mountpoint -q "$target/var/log" || ! mountpoint -q "$target/boot" ||
    ! bootctl --esp-path="$target/boot" is-installed; then
  printf '%s\n' 'Archinstall did not complete a new system at the requested mount point.' >&2
  exit 1
fi

handoff=/var/log/mainstream-install
install -d -m 755 "$target$handoff"
install -m 644 "$staging/"{source.bundle,options,username} "$target$handoff/"
if (( ${#wifi_profiles[@]} )); then
  install -d -m 700 "$target/var/lib/iwd"
  install -m 600 -- "${wifi_profiles[@]}" "$target/var/lib/iwd/"
fi
install -Dm755 "$REPO_ROOT/sdata/subcmd-install/finish-fresh.sh" "$target$handoff/finish-fresh.sh"
printf '\nInstalling the Mainstream desktop…\n'
while ! arch-chroot -S "$target" "$handoff/finish-fresh.sh"; do
  printf '\nDesktop setup is incomplete. Press Enter to retry or Q to exit: '
  IFS= read -r retry
  [[ $retry != [qQ] ]] || exit 1
done
rm -f -- "$target$handoff/"{source.bundle,options,username,finish-fresh.sh}
rmdir "$target$handoff"
sync -f "$target"
printf '\nMainstream is ready. Press Enter to restart, then remove the USB when the screen goes blank.\n'
IFS= read -r _
cleanup
trap - EXIT
systemctl reboot
