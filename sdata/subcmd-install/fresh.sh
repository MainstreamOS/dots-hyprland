#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  printf '%s\n' 'Usage: ./setup install --fresh' \
    'From the stock Arch USB, choose a profile and install to free space or erase a disk.' \
    'Choose whether to encrypt the system and create your account here.' \
    'Mainstream finishes desktop setup automatically after restarting.'
  exit 0
fi
[[ $# == 0 ]] || { printf '%s\n' 'Use ./setup install --fresh --help.' >&2; exit 1; }

if (( EUID != 0 )) || ! mountpoint -q /run/archiso/bootmnt || ! command -v archinstall >/dev/null; then
  printf '%s\n' 'Run this from the root console on the stock Arch USB. On an installed system, use ./setup install.' >&2
  exit 1
fi
if [[ ! -d /sys/firmware/efi || ! -t 0 || ! -t 1 ]]; then
  printf '%s\n' 'The terminal installer requires the Arch USB booted in UEFI mode and an interactive terminal.' >&2
  exit 1
fi

REPO_ROOT=$(pwd)
source "$REPO_ROOT/sdata/subcmd-install/profiles.sh"
prepare_install_profile
printf '\nDisk setup\n  1. Install alongside (use existing unallocated space)\n  2. Erase a disk\n'
printf 'Choose 1 or 2: '
IFS= read -r choice
case "$choice" in
  1) mode=alongside ;;
  2) mode=erase ;;
  *) printf '%s\n' 'No disk mode selected.' >&2; exit 1 ;;
esac
printf '\n'
lsblk -d -e 7,11 -p -o NAME,SIZE,MODEL,TYPE
printf '\nEnter the whole disk path (for example /dev/nvme0n1): '
IFS= read -r disk
[[ $disk == /dev/* && -b $disk ]] || { printf '%s\n' 'Select a whole disk under /dev.' >&2; exit 1; }

staging=$(mktemp -d /run/mainstream-install.XXXXXXXX)
target="$staging/target"
cleanup() {
  rm -f -- "$staging/credentials.json" "$staging/config.json" "$staging/source.bundle" "$staging/bin/systemd-run"
  if mountpoint -q "$target"; then
    umount -R "$target" || return
  fi
  rmdir -- "$staging/bin" "$target" "$staging" 2>/dev/null || :
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$target"
plan="$REPO_ROOT/sdata/subcmd-install/archinstall-plan.py"
python "$plan" "$disk" "$mode" > "$staging/config.json"

printf '\nEncrypt the system with a passphrase? [y/N] '
IFS= read -r encryption
case "$encryption" in
  y|Y) encryption=on ;;
  ''|n|N) encryption=off ;;
  *) printf '%s\n' 'Enter y or n for encryption.' >&2; exit 1 ;;
esac

while :; do
  printf '\nUsername (lowercase letters, numbers, underscores or hyphens): '
  IFS= read -r username
  if [[ $username =~ ^[a-z][a-z0-9_-]{0,31}$ ]] && ! getent passwd "$username" >/dev/null; then
    break
  fi
  printf '%s\n' 'Choose an unused username starting with a lowercase letter.' >&2
done

read_secret() {
  local label=$1
  local -n secret=$2
  local confirmation
  while :; do
    printf '%s: ' "$label"
    IFS= read -rs secret || exit 1
    printf '\nConfirm %s: ' "${label,,}"
    IFS= read -rs confirmation || exit 1
    printf '\n'
    if [[ -n $secret && $secret == "$confirmation" ]]; then
      return
    fi
    printf '%s\n' 'Use a non-empty value and enter it the same way twice.' >&2
  done
}
read_secret 'Account password' password
passphrase=
if [[ $encryption == on ]]; then
  read_secret 'Disk passphrase' passphrase
fi

printf '\nReview your installation\n  Profile: %s\n  Username: %s\n  Disk encryption: %s\n' \
  "$MS_INSTALL_PROFILE" "$username" "$encryption"
if [[ $MS_INSTALL_PROFILE == custom ]]; then
  printf '  Selected apps: %s\n' "${MS_SELECTED_APPS[*]:-(none)}"
fi
if [[ $mode == erase ]]; then
  printf '  Disk: erase all data on %s\n' "$disk"
else
  printf '  Disk: use free space on %s for a new EFI partition and a Btrfs root\n' "$disk"
fi
printf '\nType INSTALL to begin, or press Enter to cancel: '
IFS= read -r confirmation
[[ $confirmation == INSTALL ]] || exit 0

shopt -s nullglob
wifi_profiles=(/var/lib/iwd/*.psk /var/lib/iwd/*.open)
shopt -u nullglob
network=nm
if (( ${#wifi_profiles[@]} )); then network=nm_iwd; fi
(umask 077
  printf '%s\0%s' "$password" "$passphrase" |
    python "$plan" "$disk" "$mode" "$username" "$network" "$staging/credentials.json" > "$staging/config.json"
)
unset password passphrase
install -Dm755 "$REPO_ROOT/sdata/subcmd-install/archinstall-systemd-run" "$staging/bin/systemd-run"
git -c safe.directory="$REPO_ROOT" bundle create "$staging/source.bundle" HEAD --branches --tags
printf '\nInstalling the base system. Mainstream will set up your desktop after restart.\n'
(umask 022; PATH="$staging/bin:$PATH" archinstall --silent --config "$staging/config.json" \
  --creds "$staging/credentials.json" --mountpoint "$target")
rm -f -- "$staging/credentials.json"

if [[ $(findmnt -n -o FSTYPE --mountpoint "$target") != btrfs || ! -s $target/etc/fstab ]] ||
    ! mountpoint -q "$target/var/log" || ! mountpoint -q "$target/boot" ||
    ! bootctl --esp-path="$target/boot" is-installed; then
  printf '%s\n' 'Archinstall did not complete a new system at the requested mount point.' >&2
  exit 1
fi

# Keep the handoff on @log so restoring a root snapshot cannot run it again.
handoff="$target/var/log/mainstream-firstboot"
install -d -m 755 "$handoff"
install -m 644 "$staging/source.bundle" "$handoff/source.bundle"
printf '%s\n' "$username" > "$handoff/username"
{
  printf '%s\n' --profile "$MS_INSTALL_PROFILE"
  if [[ $MS_INSTALL_PROFILE == custom ]]; then
    (IFS=,; printf '%s\n' --apps "${MS_SELECTED_APPS[*]}")
  fi
} > "$handoff/options"
chmod 644 "$handoff/options"
if (( ${#wifi_profiles[@]} )); then
  install -d -m 700 "$target/var/lib/iwd"
  install -m 600 -- "${wifi_profiles[@]}" "$target/var/lib/iwd/"
fi
install -Dm755 "$REPO_ROOT/sdata/subcmd-install/finish-fresh.sh" "$handoff/finish-fresh.sh"
install -Dm644 "$REPO_ROOT/sdata/subcmd-install/mainstream-firstboot.service" "$target/etc/systemd/system/mainstream-firstboot.service"
install -d -m 750 "$target/etc/sudoers.d"
(umask 337; printf '%s\n' '@includedir /run/mainstream-firstboot/sudoers' > "$target/etc/sudoers.d/zz-mainstream-firstboot")
systemctl --root="$target" enable mainstream-firstboot.service
sync -f "$target"
printf '\nThe base system is ready. Press Enter to restart, then remove the USB when the screen goes blank.\n'
printf '%s\n' 'Mainstream will finish setup automatically. If you encrypted the system, enter your disk passphrase when asked.'
IFS= read -r _
cleanup
trap - EXIT
systemctl reboot
