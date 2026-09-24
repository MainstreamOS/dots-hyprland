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
# lsblk: -d is tracked, because a device asked about without it answers for
# everything under it as well, and with it for itself alone, so reading a
# device the wrong way gets the wrong answer here too. SIZE is in bytes, as -b
# asks. A disk's partitions are listed as type:filesystem in table order and
# named after the disk the way the kernel names them. One listed out of table
# order carries its number, as number=type:filesystem, and a device open on
# the partition before it, such as an unlocked root or an array built on a
# member, follows it as >kind:path:filesystem, with no partition type or
# number, as lsblk prints one. That device's own partitions follow it as
# >>type:filesystem, numbered in its table and named after it the way the
# kernel names an array's. Each row names its parent's kernel name as
# PKNAME. A disk is described by the first role it plays of the ESP's, /boot's
# and root's, its TYPE is disk unless a test makes it an array, and any
# partition not named below sits on the root's disk, except that the LUKS
# partition asked for its parent without -d also answers for the device open
# on it. A listing of /boot's disk can also be made to fail after printing,
# and what a failed listing printed is not to be trusted.
cat > "$SHIM/bin/lsblk" <<'EOF'
#!/usr/bin/env bash
col=""; dev=""; nodeps=0; pairs=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -*) [[ "$1" == -*d* ]] && nodeps=1
        [[ "$1" == -*P* ]] && pairs=1
        [[ "$1" == -*o ]] && { col="$2"; shift; } ;;
    *) dev="$1" ;;
  esac; shift
done
row() { # path, table type, partition type, filesystem type, number, device type, parent
  local out="" c v
  for c in ${col//,/ }; do
    case "$c" in PATH) v="$1" ;; PTTYPE) v="$2" ;; PARTTYPE) v="$3" ;; FSTYPE) v="$4" ;; PARTN) v="$5" ;; TYPE) v="$6" ;; PKNAME) v="$7" ;; *) v="" ;; esac
    if [[ $pairs -eq 1 ]]; then out+="${out:+ }$c=\"$v\""; else out+="${out:+ }$v"; fi
  done
  echo "$out"
}
disk() { # table type, device type, the partitions on the disk
  local n=0 num p rest sep="" part="" held="" hn=0
  row "$dev" "$1" "" "" "" "$2" ""
  [[ $nodeps -eq 1 ]] && return
  [[ "$dev" == *[0-9] ]] && sep=p
  for p in $3; do
    if [[ "$p" == ">>"* ]]; then
      p="${p#>>}"; hn=$((hn + 1))
      row "${held}p$hn" "" "${p%%:*}" "${p#*:}" "$hn" part "${held##*/}"
      continue
    fi
    if [[ "$p" == ">"* ]]; then
      p="${p#>}"; rest="${p#*:}"; held="${rest%%:*}"; hn=0
      row "$held" "" "" "${rest#*:}" "" "${p%%:*}" "${part##*/}"
      continue
    fi
    n=$((n + 1)); num=$n
    [[ "$p" == *=* ]] && { num="${p%%=*}"; p="${p#*=}"; }
    part="$dev$sep$num"
    row "$part" "$1" "${p%%:*}" "${p#*:}" "$num" part "${dev##*/}"
  done
}
if [[ -n "$FIX_ESP_DISK" && "$dev" == "/dev/$FIX_ESP_DISK" ]]; then disk "$FIX_ESP_PTTYPE" "$FIX_ESP_DISK_TYPE" "$FIX_ESP_PARTS"; exit 0; fi
if [[ -n "$FIX_BOOT_DISK" && "$dev" == "/dev/$FIX_BOOT_DISK" ]]; then
  disk "$FIX_BOOT_PTTYPE" "$FIX_BOOT_DISK_TYPE" "$FIX_BOOT_PARTS"
  [[ $nodeps -eq 1 || "${FIX_BOOT_LIST_FAILS:-0}" == 0 ]]; exit
fi
if [[ -n "$FIX_ROOT_DISK" && "$dev" == "/dev/$FIX_ROOT_DISK" ]]; then disk "$FIX_ROOT_PTTYPE" "$FIX_ROOT_DISK_TYPE" "$FIX_ROOT_PARTS"; exit 0; fi
case "$col" in
  PARTUUID) [[ "$dev" == "$FIX_ROOT_PLAIN_DEV" ]] && echo "$FIX_ROOT_PARTUUID" ;;
  TYPE)     [[ "$dev" == "$FIX_ROOT_SRC" ]] && echo "${FIX_ROOT_DMTYPE:-part}" ;;
  PARTTYPE) [[ "$dev" == "$FIX_ESP_SRC" ]] && echo "$FIX_ESP_PARTTYPE" ;;
  SIZE)     [[ "$dev" == "$FIX_BOOT_SRC" ]] && echo "$FIX_BOOT_SIZE" ;;
  PKNAME)
    case "$dev" in
      "$FIX_ESP_SRC")  echo "$FIX_ESP_DISK" ;;
      "$FIX_BOOT_SRC") echo "$FIX_BOOT_DISK" ;;
      *) echo "$FIX_ROOT_DISK" ;;
    esac
    [[ $nodeps -eq 0 && -n "$FIX_LUKS_DEV" && "$dev" == "$FIX_LUKS_DEV" ]] && echo "${dev##*/}" ;;
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

ESP_GUID=c12a7328-f81f-11d2-ba4b-00a0c93ec93b
BIOS_BOOT_GUID=21686148-6449-6e6f-744e-656564454649
BASIC_DATA_GUID=ebd0a0a2-b9e5-4433-87c0-68b6b72699c7
LINUX_GUID=0fc63daf-8483-4772-8e79-3d69d8477de4
RAID_GUID=a19d880f-05fc-4d3b-a006-743f0f84911e
MIB=$(( 1024 * 1024 ))
# The ESP's disk defaults to GPT, the only table the installer puts an ESP
# on. The others default to MBR, which is what its BIOS erase layout makes.
reset() {
    export FIX_ROOT_SRC="" FIX_ROOT_FSTYPE="" FIX_ROOT_FSROOT="/" FIX_ROOT_DMTYPE="part" \
           FIX_ROOT_PLAIN_DEV="" FIX_ROOT_PARTUUID="" FIX_ROOT_DISK="" \
           FIX_ROOT_PTTYPE=dos FIX_ROOT_PARTS="0x83:btrfs" FIX_ROOT_DISK_TYPE=disk \
           FIX_ESP_MOUNTED=0 FIX_ESP_SRC="" FIX_ESP_FSTYPE="" FIX_ESP_DISK="" FIX_ESP_DISK_TYPE=disk \
           FIX_ESP_PARTTYPE="$ESP_GUID" FIX_ESP_PTTYPE=gpt FIX_ESP_PARTS="$ESP_GUID:vfat $LINUX_GUID:btrfs" \
           FIX_BOOT_MOUNTED=0 FIX_BOOT_SRC="" FIX_BOOT_FSTYPE="" FIX_BOOT_DISK="" FIX_BOOT_DISK_TYPE=disk \
           FIX_BOOT_SIZE=$(( 1024 * MIB )) FIX_BOOT_PTTYPE=dos FIX_BOOT_PARTS="0xc:vfat 0x83:btrfs" \
           FIX_BOOT_LIST_FAILS=0 \
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
# TARGET_DISK comes from /boot, so the open mapper on the root's partition
# cannot put a second line into it.
chk bios-luks-disk "$TARGET_DISK" /dev/sda
chk bios-luks-cmdline "$(cmdline)" "rd.luks.name=9999=luks-9999 root=/dev/mapper/luks-9999 rootflags=subvol=@ rw rootfstype=btrfs $TAIL"

# ── 12. manual BIOS, /boot on another disk: the loader follows /boot ────────
# limine-bios-sync rewrites the stages on the disk holding /boot after every
# limine upgrade, so the first install has to pick that same disk.
reset; bios
FIX_ROOT_SRC=/dev/sdb1; FIX_ROOT_FSTYPE=ext4; FIX_ROOT_PLAIN_DEV=/dev/sdb1; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=sdb
FIX_BOOT_MOUNTED=1; FIX_BOOT_SRC=/dev/sda1; FIX_BOOT_FSTYPE=vfat; FIX_BOOT_DISK=sda
accepts bios-boot-other-disk
chk bios-boot-other-disk-disk "$TARGET_DISK" /dev/sda
chk bios-boot-other-disk-host "$DISK_HOST_DEV" /dev/sdb1

reset; bios
FIX_ROOT_SRC=/dev/mapper/luks-7777; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/@; FIX_ROOT_DMTYPE=crypt
FIX_LUKS_DEV=/dev/sdb2; FIX_LUKS_UUID=7777; FIX_ROOT_DISK=sdb
FIX_BOOT_MOUNTED=1; FIX_BOOT_SRC=/dev/sda1; FIX_BOOT_FSTYPE=vfat; FIX_BOOT_DISK=sda
accepts bios-luks-other-disk
chk bios-luks-other-disk-disk "$TARGET_DISK" /dev/sda
chk bios-luks-other-disk-host "$DISK_HOST_DEV" /dev/sdb2

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

# ── 18. the ESP type, on the GPT disk it has to be on ────────────────────────
esp_ok() {
    reset; uefi
    FIX_ROOT_SRC=/dev/nvme0n1p2; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/@
    FIX_ROOT_PLAIN_DEV=/dev/nvme0n1p2; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=nvme0n1
    FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/sda1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=sda
}
esp_ok; FIX_ESP_PARTTYPE=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
accepts esp-gpt-uppercase
# efibootmgr pairs this disk with the ESP's partition number, so it is the
# ESP's disk even when root is elsewhere.
chk esp-other-disk "$TARGET_DISK" /dev/sda
chk esp-other-disk-efidev "$EFI_DEV" /dev/sda1
# The partitioning step cannot give an MBR partition type 0xef, so an ESP on
# an MBR disk is refused even when something else already marked it, and one
# that is not marked is not told to set a flag that does not exist there.
esp_ok; FIX_ESP_PTTYPE=dos; FIX_ESP_PARTS="0xef:vfat 0x83:btrfs"; FIX_ESP_PARTTYPE=0xef
refuses esp-mbr "put the EFI system partition on a GPT disk"
esp_ok; FIX_ESP_PTTYPE=dos; FIX_ESP_PARTS="0xc:vfat 0x83:btrfs"; FIX_ESP_PARTTYPE=0xc
refuses esp-mbr-fat32 "put the EFI system partition on a GPT disk"
esp_ok; FIX_ESP_PTTYPE=""
refuses esp-no-pttype "partition table type of /dev/sda, the disk holding /boot/efi"

# ── 19. FAT at /boot/efi without the ESP type: refused ──────────────────────
esp_ok; FIX_ESP_PARTTYPE=$BASIC_DATA_GUID; FIX_ESP_PARTS="$BASIC_DATA_GUID:vfat $LINUX_GUID:btrfs"
refuses esp-gpt-basic-data "set its boot flag"
# A type that cannot be read is not a missing flag, so it is not told to set one.
esp_ok; FIX_ESP_PARTTYPE=""
refuses esp-no-type "partition type of /boot/efi (/dev/sda1) could not be read"

# ── 20. encrypted ESP: refused ───────────────────────────────────────────────
esp_ok; FIX_ESP_SRC=/dev/mapper/luks-esp
refuses esp-encrypted "encrypted or mapped"

# ── 21. BIOS /boot size: 512 MiB is the floor ────────────────────────────────
boot_ok() {
    reset; bios
    FIX_ROOT_SRC=/dev/sda2; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/@
    FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=sda
    FIX_BOOT_MOUNTED=1; FIX_BOOT_SRC=/dev/sda1; FIX_BOOT_FSTYPE=vfat; FIX_BOOT_DISK=sda
}
boot_ok; FIX_BOOT_SIZE=$(( 512 * MIB ))
accepts bios-boot-512
boot_ok; FIX_BOOT_SIZE=$(( 512 * MIB - 1 ))
refuses bios-boot-just-under "at least 512 MiB"
boot_ok; FIX_BOOT_SIZE=$(( 300 * MIB ))
refuses bios-boot-300-names-size "is 300 MiB"
boot_ok; FIX_BOOT_SIZE=$(( 300 * MIB ))
refuses bios-boot-300-names-default "1 GiB is the default"
boot_ok; FIX_BOOT_SIZE=""
refuses bios-boot-no-size "could not be read"

# ── 22. BIOS on a GPT disk: stage 2 needs a BIOS boot partition ──────────────
# boot_ok puts /boot on sda1 and root on sda2, so these tables list those two
# first and any BIOS boot partition after them, unless /boot itself carries
# the type.
bios_gpt() { boot_ok; FIX_BOOT_PTTYPE=gpt; FIX_BOOT_PARTS="$1"; }
bios_gpt "$BASIC_DATA_GUID:vfat $LINUX_GUID:btrfs $BIOS_BOOT_GUID:"
accepts bios-gpt-bios-boot
bios_gpt "$BASIC_DATA_GUID:vfat $LINUX_GUID:btrfs ${BIOS_BOOT_GUID^^}:"
accepts bios-gpt-bios-boot-uppercase
bios_gpt "$BASIC_DATA_GUID:vfat $LINUX_GUID:crypto_LUKS $BIOS_BOOT_GUID:"
accepts bios-gpt-bios-boot-luks-root
bios_gpt "$BASIC_DATA_GUID:vfat $LINUX_GUID:btrfs"
refuses bios-gpt-no-bios-boot "bios-grub flag"
boot_ok; FIX_BOOT_PTTYPE=""
refuses bios-no-pttype "partition table type of /dev/sda, the disk holding /boot"
# Types that cannot be read are not a missing partition, so the person is not
# told to add one.
bios_gpt ":vfat :btrfs :"
refuses bios-gpt-no-types "partition types on /dev/sda, the disk holding /boot, could not be read"
bios_gpt ""
refuses bios-gpt-empty-listing "partition types on /dev/sda"
bios_gpt "$BASIC_DATA_GUID:vfat $LINUX_GUID:btrfs $BIOS_BOOT_GUID:"; FIX_BOOT_LIST_FAILS=1
refuses bios-gpt-listing-fails "partition types on /dev/sda"

# limine bios-install writes stage 2 into the first BIOS boot partition in the
# table, so that one has to be empty; one that holds anything is named.
bios_gpt "$BIOS_BOOT_GUID:vfat $LINUX_GUID:btrfs"
refuses bios-gpt-boot-is-bios-boot "/dev/sda1 is the first partition with the bios-grub flag"
bios_gpt "$BIOS_BOOT_GUID:vfat $LINUX_GUID:btrfs"
refuses bios-gpt-boot-is-bios-boot-says-why "would overwrite the vfat it holds"
bios_gpt "$BASIC_DATA_GUID:vfat $LINUX_GUID:btrfs $BIOS_BOOT_GUID:ext4 $BIOS_BOOT_GUID:"
refuses bios-gpt-formatted-before-clean "/dev/sda3 is the first partition with the bios-grub flag"
bios_gpt "$BASIC_DATA_GUID:vfat $LINUX_GUID:btrfs $BIOS_BOOT_GUID:crypto_LUKS"
refuses bios-gpt-bios-boot-luks "/dev/sda3 is the first partition with the bios-grub flag"
bios_gpt "$BASIC_DATA_GUID:vfat $LINUX_GUID:btrfs $BIOS_BOOT_GUID:swap"
refuses bios-gpt-bios-boot-swap "overwrite the swap"
# Only the first one is written to, so a formatted one after it is left alone.
bios_gpt "$BASIC_DATA_GUID:vfat $LINUX_GUID:btrfs $BIOS_BOOT_GUID: $BIOS_BOOT_GUID:ext4"
accepts bios-gpt-clean-before-formatted

# First means lowest numbered, wherever lsblk lists it. NVMe partitions take
# device numbers in the order they appear, so p10 can be listed before p9, and
# 10 still comes after 9.
bios_nvme() {
    reset; bios
    FIX_ROOT_SRC=/dev/nvme0n1p2; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/@
    FIX_ROOT_PLAIN_DEV=/dev/nvme0n1p2; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=nvme0n1
    FIX_BOOT_MOUNTED=1; FIX_BOOT_SRC=/dev/nvme0n1p1; FIX_BOOT_FSTYPE=vfat; FIX_BOOT_DISK=nvme0n1
    FIX_BOOT_PTTYPE=gpt; FIX_BOOT_PARTS="$BASIC_DATA_GUID:vfat $LINUX_GUID:btrfs $1"
}
bios_nvme "10=$BIOS_BOOT_GUID:ext4 9=$BIOS_BOOT_GUID:"
accepts bios-gpt-out-of-order-clean-first
bios_nvme "10=$BIOS_BOOT_GUID: 9=$BIOS_BOOT_GUID:ext4"
refuses bios-gpt-out-of-order-formatted-first "/dev/nvme0n1p9 is the first partition with the bios-grub flag"

# An unlocked root is listed under its partition, with no partition type or
# number of its own, and is not in the table.
bios_luks_gpt() {
    reset; bios
    FIX_ROOT_SRC=/dev/mapper/luks-9999; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/@; FIX_ROOT_DMTYPE=crypt
    FIX_LUKS_DEV=/dev/sda2; FIX_LUKS_UUID=9999; FIX_ROOT_DISK=sda
    FIX_BOOT_MOUNTED=1; FIX_BOOT_SRC=/dev/sda1; FIX_BOOT_FSTYPE=vfat; FIX_BOOT_DISK=sda
    FIX_BOOT_PTTYPE=gpt; FIX_BOOT_PARTS="$BASIC_DATA_GUID:vfat $LINUX_GUID:crypto_LUKS >crypt:/dev/mapper/luks-9999:btrfs $1"
}
bios_luks_gpt "$BIOS_BOOT_GUID:"
accepts bios-gpt-luks-open
chk bios-gpt-luks-open-disk "$TARGET_DISK" /dev/sda
chk bios-gpt-luks-open-host "$DISK_HOST_DEV" /dev/sda2
bios_luks_gpt ""
refuses bios-gpt-luks-open-no-bios-boot "/dev/sda holds /boot"
# The partition is named with what it holds, not with what is open on it.
bios_luks_gpt "$BIOS_BOOT_GUID:crypto_LUKS >crypt:/dev/mapper/luks-data:ext4 $BIOS_BOOT_GUID:"
refuses bios-gpt-luks-open-on-bios-boot "/dev/sda3 is the first partition with the bios-grub flag on /dev/sda, so the boot loader writes itself there and would overwrite the crypto_LUKS it holds"

# An array built on one of the disk's partitions is listed under the disk
# with its own partitions, whose types and numbers are in the array's table,
# not the disk's, so one of the BIOS boot type there does not count.
bios_gpt "$BASIC_DATA_GUID:vfat $LINUX_GUID:ext4 $RAID_GUID:linux_raid_member >raid1:/dev/md127: >>$BIOS_BOOT_GUID:"
FIX_ROOT_FSTYPE=ext4; FIX_ROOT_FSROOT=/
refuses bios-gpt-bios-boot-on-array "/dev/sda holds /boot"

# The stages go to the disk holding /boot, so only a BIOS boot partition on
# that disk counts, wherever root is.
bios_split() {
    reset; bios
    FIX_ROOT_SRC=/dev/sdb2; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/@
    FIX_ROOT_PLAIN_DEV=/dev/sdb2; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=sdb
    FIX_BOOT_MOUNTED=1; FIX_BOOT_SRC=/dev/sda1; FIX_BOOT_FSTYPE=vfat; FIX_BOOT_DISK=sda
    FIX_ROOT_PTTYPE=gpt; FIX_BOOT_PTTYPE=gpt
}
bios_split; FIX_ROOT_PARTS="$BIOS_BOOT_GUID: $LINUX_GUID:btrfs"; FIX_BOOT_PARTS="$BASIC_DATA_GUID:vfat"
refuses bios-gpt-bios-boot-on-root-disk "/dev/sda holds /boot"
bios_split; FIX_ROOT_PARTS="$LINUX_GUID:btrfs"; FIX_BOOT_PARTS="$BASIC_DATA_GUID:vfat $BIOS_BOOT_GUID:"
accepts bios-gpt-bios-boot-on-boot-disk

# UEFI never needs one, and a formatted one on the ESP's disk is none of its
# business.
reset; uefi
FIX_ROOT_SRC=/dev/sda2; FIX_ROOT_FSTYPE=btrfs; FIX_ROOT_FSROOT=/@
FIX_ROOT_PLAIN_DEV=/dev/sda2; FIX_ROOT_PARTUUID=1; FIX_ROOT_DISK=sda
FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/sda1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=sda
FIX_ESP_PARTS="$ESP_GUID:vfat $LINUX_GUID:btrfs"
accepts uefi-gpt-no-bios-boot
FIX_ESP_PARTS="$ESP_GUID:vfat $LINUX_GUID:btrfs $BIOS_BOOT_GUID:ext4"
accepts uefi-gpt-formatted-bios-boot

# ── 23. software RAID: nothing on the installed system assembles an array ────
# The partitioning step refuses / on an array, and /boot on one on BIOS.
raid_root() {
    reset; uefi
    FIX_ROOT_FSTYPE=ext4
    FIX_ESP_MOUNTED=1; FIX_ESP_SRC=/dev/sda1; FIX_ESP_FSTYPE=vfat; FIX_ESP_DISK=sda
}
# A whole array has no PARTUUID, and that is not what it is refused for.
raid_root; FIX_ROOT_SRC=/dev/md127; FIX_ROOT_PLAIN_DEV=/dev/md127
refuses raid-root-array "root is on software RAID (/dev/md127)"
raid_root; FIX_ROOT_SRC=/dev/md127p1; FIX_ROOT_PLAIN_DEV=/dev/md127p1; FIX_ROOT_PARTUUID=1
FIX_ROOT_DISK=md127; FIX_ROOT_DISK_TYPE=raid1
refuses raid-root-partition "root is on software RAID (/dev/md127p1)"
# Mounted by another name, a partition of an array is known by its array.
raid_root; FIX_ROOT_SRC=/dev/disk/by-id/md-uuid-1234-part1; FIX_ROOT_PLAIN_DEV=$FIX_ROOT_SRC; FIX_ROOT_PARTUUID=1
FIX_ROOT_DISK=md127; FIX_ROOT_DISK_TYPE=raid10
refuses raid-root-by-parent "root is on software RAID (/dev/disk/by-id/md-uuid-1234-part1)"
# Encrypted, the array still has to be put together before it is unlocked.
raid_root; FIX_ROOT_SRC=/dev/mapper/luks-aaaa; FIX_ROOT_DMTYPE=crypt; FIX_LUKS_DEV=/dev/md127; FIX_LUKS_UUID=aaaa
refuses raid-luks-root "root is on software RAID (/dev/md127)"
raid_root; FIX_ROOT_SRC=/dev/mapper/luks-aaaa; FIX_ROOT_DMTYPE=crypt; FIX_LUKS_UUID=aaaa
FIX_LUKS_DEV=/dev/disk/by-id/md-uuid-1234-part2; FIX_ROOT_DISK=md127; FIX_ROOT_DISK_TYPE=raid1
refuses raid-luks-root-by-parent "root is on software RAID (/dev/disk/by-id/md-uuid-1234-part2)"
# A parent that reports a raid level is an array whatever it is called. Asked
# without -d, the unlocked partition would answer for the root open on it too,
# and the parent would come back as two names that are no device at all.
raid_root; FIX_ROOT_SRC=/dev/mapper/luks-aaaa; FIX_ROOT_DMTYPE=crypt; FIX_LUKS_UUID=aaaa
FIX_LUKS_DEV=/dev/disk/by-id/array-part2; FIX_ROOT_DISK=array0; FIX_ROOT_DISK_TYPE=raid1
refuses raid-luks-root-by-level "root is on software RAID (/dev/disk/by-id/array-part2)"
boot_ok; FIX_BOOT_SRC=/dev/md126p1; FIX_BOOT_DISK=md126; FIX_BOOT_DISK_TYPE=raid1
refuses raid-boot "/boot is on software RAID (/dev/md126p1)"
boot_ok; FIX_BOOT_SRC=/dev/disk/by-id/md-uuid-5678-part1; FIX_BOOT_DISK=md126; FIX_BOOT_DISK_TYPE=raid1
refuses raid-boot-by-parent "/boot is on software RAID (/dev/disk/by-id/md-uuid-5678-part1)"
# md also runs linear and multipath arrays, whose levels do not say raid.
raid_root; FIX_ROOT_SRC=/dev/disk/by-id/md-uuid-1234-part1; FIX_ROOT_PLAIN_DEV=$FIX_ROOT_SRC; FIX_ROOT_PARTUUID=1
FIX_ROOT_DISK=md127; FIX_ROOT_DISK_TYPE=linear
refuses raid-root-linear "root is on software RAID (/dev/disk/by-id/md-uuid-1234-part1)"
boot_ok; FIX_BOOT_SRC=/dev/disk/by-id/md-uuid-5678-part1; FIX_BOOT_DISK=md126; FIX_BOOT_DISK_TYPE=multipath
refuses raid-boot-multipath "/boot is on software RAID (/dev/disk/by-id/md-uuid-5678-part1)"

# ── 24. the shared function called the old way still gives the old answer ────
CASES=$((CASES + 1))
chk old-call "$(gpu_base_cmdline_tokens 'root=PARTUUID=abc-123' '/@')" "root=PARTUUID=abc-123 rootflags=subvol=@ rw rootfstype=btrfs $TAIL"
chk old-call-default "$(gpu_base_cmdline_tokens 'root=PARTUUID=abc-123')" "root=PARTUUID=abc-123 rootflags=subvol=@ rw rootfstype=btrfs $TAIL"

echo "boot-layout: $CASES cases, $FAILS failures"
exit $(( FAILS > 0 ? 1 : 0 ))
