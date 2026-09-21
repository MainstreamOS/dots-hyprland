#!/usr/bin/env bash
# boot-layout.test.sh: the layouts the installer can hand to the boot steps,
# run against stand-ins for the hardware.
# Run: bash sdata/lib/boot-layout.test.sh   (exit 0 = all green)
#
# The first three cases are the layouts the installer builds on its own. Their
# command lines are compared against the exact strings those installs have
# always produced, spelled out here rather than derived, so the shared library
# cannot drift under them. A refusal is checked by the words it gives the
# person, not only by its exit code, so a refusal from the wrong check fails.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=boot-layout.sh
source "$DIR/boot-layout.sh"
# shellcheck source=gpu-config.sh
source "$DIR/gpu-config.sh"

FAILS=0; CASES=0
chk() { if [[ "$2" != "$3" ]]; then echo "  FAIL [$1]: got '$2' want '$3'"; FAILS=$((FAILS + 1)); fi; }
# A refusal has to name the thing the person can change.
refuses() { # name, expected substring
    CASES=$((CASES + 1))
    if boot_layout_detect; then echo "  FAIL [$1]: accepted a layout that cannot boot"; FAILS=$((FAILS + 1)); return; fi
    [[ "$BOOT_LAYOUT_ERROR" == *"$2"* ]] || { echo "  FAIL [$1]: message '$BOOT_LAYOUT_ERROR' does not mention '$2'"; FAILS=$((FAILS + 1)); }
}
accepts() { CASES=$((CASES + 1)); boot_layout_detect || { echo "  FAIL [$1]: refused a valid layout: $BOOT_LAYOUT_ERROR"; FAILS=$((FAILS + 1)); }; }

# ── stand-ins ────────────────────────────────────────────────────────────────
SHIM="$(mktemp -d)"; trap 'rm -rf "$SHIM"' EXIT
export PATH="$SHIM/bin:$PATH"; mkdir -p "$SHIM/bin"

# findmnt: -v drops the subvolume from SOURCE, FSROOT is that subvolume.
cat > "$SHIM/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
col=""; path=""; nofsroot=0
while [[ $# -gt 0 ]]; do case "$1" in -n) ;; -v) nofsroot=1 ;; -nv|-vn) nofsroot=1 ;; -o) col="$2"; shift ;; *) path="$1" ;; esac; shift; done
case "$path" in
  /)         src="$FIX_ROOT_SRC"; fs="$FIX_ROOT_FSTYPE"; fsroot="$FIX_ROOT_FSROOT"; mounted=1 ;;
  /boot/efi) src="$FIX_ESP_SRC"; fs="$FIX_ESP_FSTYPE"; fsroot="/"; mounted="${FIX_ESP_MOUNTED:-0}" ;;
  /boot)     src="$FIX_BOOT_SRC"; fs="$FIX_BOOT_FSTYPE"; fsroot="/"; mounted="${FIX_BOOT_MOUNTED:-0}" ;;
  *) exit 1 ;;
esac
[[ "$mounted" == 1 ]] || exit 1
# Without -v the real findmnt appends [<fsroot>] to a subvolume mount.
if [[ "$col" == SOURCE && $nofsroot -eq 0 && -n "$fsroot" && "$fsroot" != "/" ]]; then src="$src[$fsroot]"; fi
case "$col" in SOURCE) [[ -n "$src" ]] || exit 1; echo "$src" ;; FSTYPE) [[ -n "$fs" ]] || exit 1; echo "$fs" ;; FSROOT) echo "$fsroot" ;; *) exit 1 ;; esac
EOF
cat > "$SHIM/bin/mountpoint" <<'EOF'
#!/usr/bin/env bash
case "${2:-$1}" in /boot/efi) [[ "${FIX_ESP_MOUNTED:-0}" == 1 ]] ;; /boot) [[ "${FIX_BOOT_MOUNTED:-0}" == 1 ]] ;; *) exit 1 ;; esac
EOF
# lsblk: -d is tracked, because without it a partition that hosts an open
# mapper reports its own parent AND the mapper's, which is what the library's
# -d exists to prevent.
cat > "$SHIM/bin/lsblk" <<'EOF'
#!/usr/bin/env bash
col=""; dev=""; nodeps=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -dno|-dn) nodeps=1; col="$2"; shift ;;
    -no|-n) col="$2"; shift ;;
    -d) nodeps=1 ;;
    -*) ;;
    *) dev="$1" ;;
  esac; shift
done
case "$col" in
  PARTUUID) [[ "$dev" == "$FIX_ROOT_PLAIN_DEV" ]] && echo "$FIX_ROOT_PARTUUID" ;;
  TYPE)     [[ "$dev" == "$FIX_ROOT_SRC" ]] && echo "${FIX_ROOT_DMTYPE:-part}" ;;
  PKNAME)
    case "$dev" in
      "$FIX_ESP_SRC")  echo "$FIX_ESP_DISK" ;;
      "$FIX_BOOT_SRC") echo "$FIX_BOOT_DISK" ;;
      "$FIX_LUKS_DEV")
        echo "$FIX_ROOT_DISK"
        # The open mapper's own parent line, which only -d suppresses.
        if [[ $nodeps -eq 0 ]]; then echo "${FIX_LUKS_DEV#/dev/}"; fi
        ;;
      *) echo "$FIX_ROOT_DISK" ;;
    esac ;;
esac
exit 0
EOF
cat > "$SHIM/bin/cryptsetup" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  status)   printf '  device:  %s\n' "$FIX_LUKS_DEV" ;;
  luksUUID) echo "$FIX_LUKS_UUID" ;;
esac
EOF
chmod +x "$SHIM"/bin/*

reset() {
    export FIX_ROOT_SRC="" FIX_ROOT_FSTYPE="" FIX_ROOT_FSROOT="/" FIX_ROOT_DMTYPE="part" \
           FIX_ROOT_PLAIN_DEV="" FIX_ROOT_PARTUUID="" FIX_ROOT_DISK="" \
           FIX_ESP_MOUNTED=0 FIX_ESP_SRC="" FIX_ESP_FSTYPE="" FIX_ESP_DISK="" \
           FIX_BOOT_MOUNTED=0 FIX_BOOT_SRC="" FIX_BOOT_FSTYPE="" FIX_BOOT_DISK="" \
           FIX_LUKS_DEV="" FIX_LUKS_UUID=""
}
uefi() { mkdir -p "$SHIM/efi"; export BOOT_LAYOUT_EFI_DIR="$SHIM/efi"; }
bios() { rm -rf "$SHIM/efi"; export BOOT_LAYOUT_EFI_DIR="$SHIM/efi"; }
cmdline() { gpu_base_cmdline_tokens "$ROOT_SPEC" "$ROOT_SUBVOL" "$ROOT_FSTYPE"; }
TAIL='zswap.enabled=0 quiet splash rd.udev.log_level=3 vt.global_cursor_default=0 consoleblank=0 nowatchdog nmi_watchdog=0'

# ── 1. the default UEFI install: btrfs root on @, ESP at /boot/efi ───────────
reset; uefi
FIX_ROOT_SRC=/dev/nvme0n1p2; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/@
FIX_ROOT_PLAIN_DEV=/dev/nvme0n1p2; FIX_ROOT_PARTUUID=aaaa-1111; FIX_ROOT_DISK=nvme0n1
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/nvme0n1p1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=nvme0n1
accepts uefi-default
chk uefi-default-uefi "$IS_UEFI" true
chk uefi-default-bootpath "$BOOT_PATH" /boot/efi
chk uefi-default-efidev "$EFI_DEV" /dev/nvme0n1p1
chk uefi-default-disk "$TARGET_DISK" /dev/nvme0n1
chk uefi-default-host "$DISK_HOST_DEV" /dev/nvme0n1p2
chk uefi-default-subvol "$ROOT_SUBVOL" @
chk uefi-default-cmdline "$(cmdline)" "root=PARTUUID=aaaa-1111 rootflags=subvol=@ rw rootfstype=btrfs $TAIL"

# ── 2. the default encrypted UEFI install ────────────────────────────────────
reset; uefi
FIX_ROOT_SRC=/dev/mapper/luks-bbbb-2222; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/@; FIX_ROOT_DMTYPE=crypt
FIX_LUKS_DEV=/dev/nvme0n1p2; FIX_LUKS_UUID=bbbb-2222; FIX_ROOT_DISK=nvme0n1
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/nvme0n1p1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=nvme0n1
accepts luks-default
chk luks-default-host "$DISK_HOST_DEV" /dev/nvme0n1p2
chk luks-default-cmdline "$(cmdline)" "rd.luks.name=bbbb-2222=luks-bbbb-2222 root=/dev/mapper/luks-bbbb-2222 rootflags=subvol=@ rw rootfstype=btrfs $TAIL"

# ── 3. the default BIOS install: FAT32 /boot, btrfs root on @ ────────────────
reset; bios
FIX_ROOT_SRC=/dev/sda2; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/@
FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=cccc-3333; FIX_ROOT_DISK=sda
FIX_BOOT_MOUNTED=1; FIX_BOOT_SRC=/dev/sda1; FIX_BOOT_FSTYPE=vfat; FIX_BOOT_DISK=sda
accepts bios-default
chk bios-default-uefi "$IS_UEFI" false
chk bios-default-bootpath "$BOOT_PATH" /boot
chk bios-default-disk "$TARGET_DISK" /dev/sda
chk bios-default-cmdline "$(cmdline)" "root=PARTUUID=cccc-3333 rootflags=subvol=@ rw rootfstype=btrfs $TAIL"

# ── 4. manual UEFI, ext4 root ─────────────────────────────────────────────────
reset; uefi
FIX_ROOT_SRC=/dev/sda2; FIX_ROOT_FSTYPE=ext4
FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=dddd-4444; FIX_ROOT_DISK=sda
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/sda1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=sda
accepts ext4
chk ext4-subvol "$ROOT_SUBVOL" ""
chk ext4-cmdline "$(cmdline)" "root=PARTUUID=dddd-4444 rw rootfstype=ext4 $TAIL"

# ── 5. manual UEFI, btrfs root mounted from the top level ────────────────────
reset; uefi
FIX_ROOT_SRC=/dev/sda2; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/
FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=eeee-5555; FIX_ROOT_DISK=sda
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/sda1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=sda
accepts btrfs-toplevel
chk toplevel-subvol "$ROOT_SUBVOL" ""
chk toplevel-cmdline "$(cmdline)" "root=PARTUUID=eeee-5555 rw rootfstype=btrfs $TAIL"

# ── 6. manual UEFI, a subvolume that is not @ ────────────────────────────────
reset; uefi
FIX_ROOT_SRC=/dev/sda2; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/arch/root
FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=ffff-6666; FIX_ROOT_DISK=sda
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/sda1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=sda
accepts other-subvol
chk other-subvol-cmdline "$(cmdline)" "root=PARTUUID=ffff-6666 rootflags=subvol=arch/root rw rootfstype=btrfs $TAIL"

# ── 7-10. layouts the boot loader cannot start ───────────────────────────────
reset; uefi
FIX_ROOT_SRC=/dev/sda2; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/@; FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=sda
refuses uefi-no-esp "/boot/efi"

reset; uefi
FIX_ROOT_SRC=/dev/sda2; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/@; FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=sda
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/sda1; FIX_ESP_FSTYPE=ext4; FIX_ESP_DISK=sda
refuses uefi-esp-not-fat "FAT32"

reset; bios
FIX_ROOT_SRC=/dev/sda1; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/@; FIX_ROOT_PLAIN_DEV=/dev/sda1; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=sda
refuses bios-no-boot "its own FAT32 partition"

reset; bios
FIX_ROOT_SRC=/dev/sda2; FIX_ROOT_FSTYPE=ext4; FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=sda
FIX_BOOT_MOUNTED=1; FIX_BOOT_SRC=/dev/sda1; FIX_BOOT_FSTYPE=ext4; FIX_BOOT_DISK=sda
refuses bios-boot-not-fat "has to be FAT32"

# ── 11. manual BIOS, encrypted root with FAT32 /boot: fine ───────────────────
reset; bios
FIX_ROOT_SRC=/dev/mapper/luks-9999; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/@; FIX_ROOT_DMTYPE=crypt
FIX_LUKS_DEV=/dev/sda2; FIX_LUKS_UUID=9999; FIX_ROOT_DISK=sda
FIX_BOOT_MOUNTED=1; FIX_BOOT_SRC=/dev/sda1; FIX_BOOT_FSTYPE=vfat; FIX_BOOT_DISK=sda
accepts bios-luks
# The -d on the backing-device lookup is what keeps the mapper's own parent
# line out of this value; without it TARGET_DISK would carry two lines.
chk bios-luks-disk "$TARGET_DISK" /dev/sda
chk bios-luks-cmdline "$(cmdline)" "rd.luks.name=9999=luks-9999 root=/dev/mapper/luks-9999 rootflags=subvol=@ rw rootfstype=btrfs $TAIL"

# ── 12. manual BIOS, /boot on another disk: refused ──────────────────────────
reset; bios
FIX_ROOT_SRC=/dev/sdb1; FIX_ROOT_FSTYPE=ext4; FIX_ROOT_PLAIN_DEV=/dev/sdb1; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=sdb
FIX_BOOT_MOUNTED=1; FIX_BOOT_SRC=/dev/sda1; FIX_BOOT_FSTYPE=vfat; FIX_BOOT_DISK=sda
refuses bios-boot-other-disk "different disk"

# ── 13. manual BIOS, encrypted /boot: refused ────────────────────────────────
reset; bios
FIX_ROOT_SRC=/dev/mapper/luks-8888; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/@; FIX_ROOT_DMTYPE=crypt
FIX_LUKS_DEV=/dev/sda2; FIX_LUKS_UUID=8888; FIX_ROOT_DISK=sda
FIX_BOOT_MOUNTED=1; FIX_BOOT_SRC=/dev/mapper/luks-boot; FIX_BOOT_FSTYPE=vfat; FIX_BOOT_DISK=sda
refuses bios-encrypted-boot "encrypted or mapped"

# ── 14. root on LVM: refused, and the message says so ────────────────────────
reset; uefi
FIX_ROOT_SRC=/dev/mapper/vg-root; FIX_ROOT_FSTYPE=ext4; FIX_ROOT_DMTYPE=lvm; FIX_ROOT_DISK=sda
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/sda1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=sda
refuses lvm-root "LVM"

# ── 15. a subvolume name the kernel command line cannot carry ────────────────
reset; uefi
FIX_ROOT_SRC=/dev/sda2; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT='/my root'
FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=sda
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/sda1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=sda
refuses subvol-with-space "kernel command line"

# ── 16. the root filesystem type could not be read ───────────────────────────
reset; uefi
FIX_ROOT_SRC=/dev/sda2; FIX_ROOT_FSTYPE=""
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/sda1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=sda
refuses no-fstype "type could not be read"

# ── 17. root is not mounted ──────────────────────────────────────────────────
reset; uefi
refuses no-root "not mounted"

# ── 18. the shared function called the old way still gives the old answer ────
CASES=$((CASES + 1))
chk old-call "$(gpu_base_cmdline_tokens 'root=PARTUUID=abc-123' '/@')" "root=PARTUUID=abc-123 rootflags=subvol=@ rw rootfstype=btrfs $TAIL"
chk old-call-default "$(gpu_base_cmdline_tokens 'root=PARTUUID=abc-123')" "root=PARTUUID=abc-123 rootflags=subvol=@ rw rootfstype=btrfs $TAIL"

echo "boot-layout: $CASES cases, $FAILS failures"
exit $(( FAILS > 0 ? 1 : 0 ))
