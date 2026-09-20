#!/usr/bin/env bash
# boot-layout.test.sh: the layouts the installer can hand to the boot steps,
# run against stand-ins for the hardware.
# Run: bash sdata/lib/boot-layout.test.sh   (exit 0 = all green)
#
# The first three cases are the layouts the installer built before the
# partitioning page was opened up. Their command lines are compared against
# the exact strings those installs have always produced, spelled out here
# rather than derived, so the shared library cannot drift under them.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=boot-layout.sh
source "$DIR/boot-layout.sh"
# shellcheck source=gpu-config.sh
source "$DIR/gpu-config.sh"

FAILS=0; CASES=0
chk() { if [[ "$2" != "$3" ]]; then echo "  FAIL [$1]: got '$2' want '$3'"; FAILS=$((FAILS + 1)); fi; }

# ── stand-ins ────────────────────────────────────────────────────────────────
SHIM="$(mktemp -d)"; trap 'rm -rf "$SHIM"' EXIT
export PATH="$SHIM/bin:$PATH"; mkdir -p "$SHIM/bin"

# Each fixture is a set of FIX_* variables the stand-ins answer from.
cat > "$SHIM/bin/findmnt" <<'EOF'
#!/usr/bin/env bash
col=""; path=""
while [[ $# -gt 0 ]]; do case "$1" in -n) ;; -o) col="$2"; shift ;; *) path="$1" ;; esac; shift; done
case "$path" in
  /)         src="$FIX_ROOT_SRC"; fs="$FIX_ROOT_FSTYPE"; opts="$FIX_ROOT_OPTS"; mounted=1 ;;
  /boot/efi) src="$FIX_ESP_SRC"; fs="$FIX_ESP_FSTYPE"; opts=""; mounted="${FIX_ESP_MOUNTED:-0}" ;;
  /boot)     src="$FIX_BOOT_SRC"; fs="$FIX_BOOT_FSTYPE"; opts=""; mounted="${FIX_BOOT_MOUNTED:-0}" ;;
  *) exit 1 ;;
esac
[[ "$mounted" == 1 ]] || exit 1
case "$col" in SOURCE) echo "$src" ;; FSTYPE) echo "$fs" ;; OPTIONS) echo "$opts" ;; *) exit 1 ;; esac
EOF
cat > "$SHIM/bin/mountpoint" <<'EOF'
#!/usr/bin/env bash
case "${2:-$1}" in /boot/efi) [[ "${FIX_ESP_MOUNTED:-0}" == 1 ]] ;; /boot) [[ "${FIX_BOOT_MOUNTED:-0}" == 1 ]] ;; *) exit 1 ;; esac
EOF
cat > "$SHIM/bin/lsblk" <<'EOF'
#!/usr/bin/env bash
col=""; dev=""
while [[ $# -gt 0 ]]; do case "$1" in -dno|-no) col="$2"; shift ;; -d|-n) ;; *) dev="$1" ;; esac; shift; done
case "$col" in
  PARTUUID) [[ "$dev" == "$FIX_ROOT_PLAIN_DEV" ]] && echo "$FIX_ROOT_PARTUUID" ;;
  PKNAME)   case "$dev" in "$FIX_ESP_SRC") echo "$FIX_ESP_DISK" ;; "$FIX_BOOT_SRC") echo "$FIX_BOOT_DISK" ;; *) echo "$FIX_ROOT_DISK" ;; esac ;;
  PARTN)    echo 1 ;;
esac
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
    unset "${!FIX_@}"
    export FIX_ROOT_SRC="" FIX_ROOT_FSTYPE="" FIX_ROOT_OPTS="" FIX_ROOT_PLAIN_DEV="" FIX_ROOT_PARTUUID="" FIX_ROOT_DISK=""
    export FIX_ESP_MOUNTED=0 FIX_ESP_SRC="" FIX_ESP_FSTYPE="" FIX_ESP_DISK=""
    export FIX_BOOT_MOUNTED=0 FIX_BOOT_SRC="" FIX_BOOT_FSTYPE="" FIX_BOOT_DISK=""
    export FIX_LUKS_DEV="" FIX_LUKS_UUID=""
    rm -rf "$SHIM/efi"
}
uefi() { mkdir -p "$SHIM/efi"; export BOOT_LAYOUT_EFI_DIR="$SHIM/efi"; }
bios() { rm -rf "$SHIM/efi"; export BOOT_LAYOUT_EFI_DIR="$SHIM/efi"; }
cmdline() { gpu_base_cmdline_tokens "$ROOT_SPEC" "$ROOT_SUBVOL" "$ROOT_FSTYPE"; }
# The canonical tail every install has carried, verbatim.
TAIL='zswap.enabled=0 quiet splash rd.udev.log_level=3 vt.global_cursor_default=0 consoleblank=0 nowatchdog nmi_watchdog=0'

# ── 1. the default UEFI install: btrfs root on @, ESP at /boot/efi ───────────
reset; uefi; CASES=$((CASES + 1))
FIX_ROOT_SRC='/dev/nvme0n1p2[/@]'; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_OPTS='rw,noatime,compress=zstd:3,ssd,subvol=/@'
FIX_ROOT_PLAIN_DEV=/dev/nvme0n1p2; FIX_ROOT_PARTUUID=aaaa-1111; FIX_ROOT_DISK=nvme0n1
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/nvme0n1p1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=nvme0n1
boot_layout_detect; chk uefi-default-rc "$?" 0
chk uefi-default-uefi "$IS_UEFI" true
chk uefi-default-bootpath "$BOOT_PATH" /boot/efi
chk uefi-default-efidev "$EFI_DEV" /dev/nvme0n1p1
chk uefi-default-disk "$TARGET_DISK" /dev/nvme0n1
chk uefi-default-host "$DISK_HOST_DEV" /dev/nvme0n1p2
chk uefi-default-cmdline "$(cmdline)" "root=PARTUUID=aaaa-1111 rootflags=subvol=@ rw rootfstype=btrfs $TAIL"

# ── 2. the default encrypted UEFI install ────────────────────────────────────
reset; uefi; CASES=$((CASES + 1))
FIX_ROOT_SRC='/dev/mapper/luks-bbbb-2222[/@]'; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_OPTS='rw,subvol=/@'
FIX_LUKS_DEV=/dev/nvme0n1p2; FIX_LUKS_UUID=bbbb-2222; FIX_ROOT_DISK=nvme0n1
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/nvme0n1p1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=nvme0n1
boot_layout_detect; chk luks-default-rc "$?" 0
chk luks-default-host "$DISK_HOST_DEV" /dev/nvme0n1p2
chk luks-default-cmdline "$(cmdline)" "rd.luks.name=bbbb-2222=luks-bbbb-2222 root=/dev/mapper/luks-bbbb-2222 rootflags=subvol=@ rw rootfstype=btrfs $TAIL"

# ── 3. the default BIOS install: FAT32 /boot, btrfs root on @ ────────────────
reset; bios; CASES=$((CASES + 1))
FIX_ROOT_SRC='/dev/sda2[/@]'; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_OPTS='rw,subvol=/@'
FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=cccc-3333; FIX_ROOT_DISK=sda
FIX_BOOT_MOUNTED=1; FIX_BOOT_SRC=/dev/sda1; FIX_BOOT_FSTYPE=vfat; FIX_BOOT_DISK=sda
boot_layout_detect; chk bios-default-rc "$?" 0
chk bios-default-uefi "$IS_UEFI" false
chk bios-default-bootpath "$BOOT_PATH" /boot
chk bios-default-disk "$TARGET_DISK" /dev/sda
chk bios-default-cmdline "$(cmdline)" "root=PARTUUID=cccc-3333 rootflags=subvol=@ rw rootfstype=btrfs $TAIL"

# ── 4. manual UEFI, ext4 root ─────────────────────────────────────────────────
reset; uefi; CASES=$((CASES + 1))
FIX_ROOT_SRC='/dev/sda2'; FIX_ROOT_FSTYPE=ext4; FIX_ROOT_OPTS='rw,relatime'
FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=dddd-4444; FIX_ROOT_DISK=sda
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/sda1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=sda
boot_layout_detect; chk ext4-rc "$?" 0
chk ext4-subvol "$ROOT_SUBVOL" /
chk ext4-cmdline "$(cmdline)" "root=PARTUUID=dddd-4444 rw rootfstype=ext4 $TAIL"

# ── 5. manual UEFI, btrfs root mounted from the top level (no subvolume) ─────
reset; uefi; CASES=$((CASES + 1))
FIX_ROOT_SRC='/dev/sda2'; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_OPTS='rw,relatime,ssd'
FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=eeee-5555; FIX_ROOT_DISK=sda
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/sda1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=sda
boot_layout_detect; chk toplevel-rc "$?" 0
chk toplevel-cmdline "$(cmdline)" "root=PARTUUID=eeee-5555 rw rootfstype=btrfs $TAIL"

# ── 6. manual UEFI, subvolume only in the options (no bracket) ───────────────
reset; uefi; CASES=$((CASES + 1))
FIX_ROOT_SRC='/dev/sda2'; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_OPTS='rw,subvol=/@'
FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=ffff-6666; FIX_ROOT_DISK=sda
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/sda1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=sda
boot_layout_detect; chk opts-subvol-rc "$?" 0
chk opts-subvol-cmdline "$(cmdline)" "root=PARTUUID=ffff-6666 rootflags=subvol=@ rw rootfstype=btrfs $TAIL"

# ── 7. manual UEFI, ESP not at /boot/efi: refused ────────────────────────────
reset; uefi; CASES=$((CASES + 1))
FIX_ROOT_SRC='/dev/sda2[/@]'; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=sda
boot_layout_detect; chk esp-missing-rc "$?" 1
chk esp-missing-msg "$([[ "$BOOT_LAYOUT_ERROR" == *"/boot/efi"* ]] && echo names-the-path)" names-the-path

# ── 8. manual UEFI, something not FAT at /boot/efi: refused ──────────────────
reset; uefi; CASES=$((CASES + 1))
FIX_ROOT_SRC='/dev/sda2[/@]'; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=sda
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/sda1; FIX_ESP_FSTYPE=ext4; FIX_ESP_DISK=sda
boot_layout_detect; chk esp-ext4-rc "$?" 1

# ── 9. manual BIOS, /boot inside the root: refused ───────────────────────────
reset; bios; CASES=$((CASES + 1))
FIX_ROOT_SRC='/dev/sda1[/@]'; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_PLAIN_DEV=/dev/sda1; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=sda
boot_layout_detect; chk bios-noboot-rc "$?" 1
chk bios-noboot-msg "$([[ "$BOOT_LAYOUT_ERROR" == *"FAT32"* ]] && echo says-fat32)" says-fat32

# ── 10. manual BIOS, ext4 /boot: refused ─────────────────────────────────────
reset; bios; CASES=$((CASES + 1))
FIX_ROOT_SRC='/dev/sda2'; FIX_ROOT_FSTYPE=ext4; FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=sda
FIX_BOOT_MOUNTED=1; FIX_BOOT_SRC=/dev/sda1; FIX_BOOT_FSTYPE=ext4; FIX_BOOT_DISK=sda
boot_layout_detect; chk bios-ext4boot-rc "$?" 1

# ── 11. manual BIOS, encrypted root with FAT32 /boot: fine ───────────────────
reset; bios; CASES=$((CASES + 1))
FIX_ROOT_SRC='/dev/mapper/luks-9999[/@]'; FIX_ROOT_FSTYPE=btrfs
FIX_LUKS_DEV=/dev/sda2; FIX_LUKS_UUID=9999; FIX_ROOT_DISK=sda
FIX_BOOT_MOUNTED=1; FIX_BOOT_SRC=/dev/sda1; FIX_BOOT_FSTYPE=vfat; FIX_BOOT_DISK=sda
boot_layout_detect; chk bios-luks-rc "$?" 0
chk bios-luks-disk "$TARGET_DISK" /dev/sda
chk bios-luks-cmdline "$(cmdline)" "rd.luks.name=9999=luks-9999 root=/dev/mapper/luks-9999 rootflags=subvol=@ rw rootfstype=btrfs $TAIL"

# ── 12. manual BIOS, /boot on another disk: refused ──────────────────────────
reset; bios; CASES=$((CASES + 1))
FIX_ROOT_SRC='/dev/sdb1'; FIX_ROOT_FSTYPE=ext4; FIX_ROOT_PLAIN_DEV=/dev/sdb1; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=sdb
FIX_BOOT_MOUNTED=1; FIX_BOOT_SRC=/dev/sda1; FIX_BOOT_FSTYPE=vfat; FIX_BOOT_DISK=sda
boot_layout_detect; chk bios-twodisks-rc "$?" 1

# ── 13. manual UEFI, xfs root, ESP on another disk (allowed on UEFI) ─────────
reset; uefi; CASES=$((CASES + 1))
FIX_ROOT_SRC='/dev/sdb1'; FIX_ROOT_FSTYPE=xfs; FIX_ROOT_PLAIN_DEV=/dev/sdb1; FIX_ROOT_PARTUUID=abcd; FIX_ROOT_DISK=sdb
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/sda1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=sda
boot_layout_detect; chk xfs-rc "$?" 0
chk xfs-disk "$TARGET_DISK" /dev/sda
chk xfs-cmdline "$(cmdline)" "root=PARTUUID=abcd rw rootfstype=xfs $TAIL"

# ── 14. the shared function called the old way still gives the old answer ────
CASES=$((CASES + 1))
chk old-call "$(gpu_base_cmdline_tokens 'root=PARTUUID=abc-123' '/@')" "root=PARTUUID=abc-123 rootflags=subvol=@ rw rootfstype=btrfs $TAIL"
chk old-call-default "$(gpu_base_cmdline_tokens 'root=PARTUUID=abc-123')" "root=PARTUUID=abc-123 rootflags=subvol=@ rw rootfstype=btrfs $TAIL"

echo "boot-layout: $CASES cases, $FAILS failures"
exit $(( FAILS > 0 ? 1 : 0 ))
