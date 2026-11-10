#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  printf '%s\n' 'Usage: ./setup install --fresh' \
    'From the stock Arch USB, choose a profile and install to free space or erase a disk.' \
    'Archinstall asks for the user account and optional LUKS encryption.' \
    'After rebooting into the new system, run mainstream-finish-install as your new user.'
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
mkdir "$target"
python "$REPO_ROOT/sdata/subcmd-install/archinstall-plan.py" "$disk" "$mode" > "$staging/config.json"
install -Dm755 "$REPO_ROOT/sdata/subcmd-install/archinstall-systemd-run" "$staging/bin/systemd-run"

git -c safe.directory="$REPO_ROOT" bundle create "$staging/source.bundle" HEAD --branches --tags
if [[ $mode == erase ]]; then
  printf '\nArchinstall is set to erase %s.\n' "$disk"
else
  printf '\nArchinstall is set to add a new EFI partition and a Btrfs root in the free space on %s.\n' "$disk"
fi
printf '%s\n' 'Review the disk layout in Archinstall. For encryption, choose LUKS under Disk encryption and select the new Btrfs partition.' \
  'Keep the bootloader preset and create a user with sudo access.' \
  'When Archinstall finishes, choose Exit so Mainstream can stage the desktop setup.'
printf '\nPress Enter to open Archinstall or Ctrl+C to cancel: '
IFS= read -r _
(umask 022; PATH="$staging/bin:$PATH" archinstall --config "$staging/config.json" --mountpoint "$target")

if [[ $(findmnt -n -o FSTYPE --mountpoint "$target") != btrfs || ! -s $target/etc/fstab ]] ||
    ! mountpoint -q "$target/boot" || ! bootctl --esp-path="$target/boot" is-installed; then
  printf '%s\n' 'Archinstall did not complete a new system at the requested mount point.' >&2
  exit 1
fi

handoff="$target/opt/mainstream-install"
install -d -m 755 "$handoff"
install -m 644 "$staging/source.bundle" "$handoff/source.bundle"
{
  printf '%s\n' --profile "$MS_INSTALL_PROFILE"
  if [[ $MS_INSTALL_PROFILE == custom ]]; then
    (IFS=,; printf '%s\n' --apps "${MS_SELECTED_APPS[*]}")
  fi
} > "$handoff/options"
chmod 644 "$handoff/options"
install -Dm755 "$REPO_ROOT/sdata/subcmd-install/finish-fresh.sh" "$target/usr/local/bin/mainstream-finish-install"
sync -f "$target"
printf '\nReboot into the new Arch system, log in as the user you created, and run mainstream-finish-install.\n'
printf '%s\n' 'If using Wi-Fi, connect first with nmtui. The selected Mainstream profile will be applied on this boot.'
