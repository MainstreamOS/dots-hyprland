#!/usr/bin/env bash
# boot-layout.sh: what the disks of the system being installed look like, for
# the steps that set up booting. Sourced inside the installer's chroot by
# install-limine and post-install-boot, and baked into the image as
# /usr/local/lib/boot-layout.sh by build.sh.
#
# The installer used to allow one layout, so the boot steps could assume it.
# With the partitioning page open to the user they have to look instead, and
# refuse in plain words when the pieces this image installs cannot boot what
# was built. Every question about the machine goes through a command on PATH,
# so boot-layout.test.sh can stand in for the hardware.

# Firmware. The live session's /sys is mounted into the chroot, so this is
# the same answer the installer's own BIOS layout switch used.
boot_layout_is_uefi() { [[ -d "${BOOT_LAYOUT_EFI_DIR:-/sys/firmware/efi}" ]]; }

# Sets, in the caller's shell:
#   IS_UEFI          true or false
#   BOOT_PATH        /boot/efi on UEFI, /boot on BIOS: where limine.conf goes
#   EFI_DEV          the EFI system partition (UEFI)
#   TARGET_DISK      the whole disk the boot loader is written to
#   DISK_HOST_DEV    the partition that hosts root, LUKS resolved
#   ROOT_PART_DEV    root as findmnt reports it (a mapper on LUKS)
#   ROOT_SPEC        the root= tokens for the kernel command line
#   ROOT_PARTUUID    plain installs only
#   ROOT_FSTYPE      btrfs, ext4, xfs, f2fs, ...
#   ROOT_SUBVOL      the btrfs subvolume root is mounted from, without its
#                    leading slash; "/" when root is the top level or not btrfs
#   LUKS_MAPPER_NAME LUKS_BACKING_DEV LUKS_UUID  encrypted installs only
# Returns 1 with BOOT_LAYOUT_ERROR set to one sentence for the user when the
# layout cannot be booted. Nothing is written.
boot_layout_detect() {
    BOOT_LAYOUT_ERROR=""
    IS_UEFI=false; BOOT_PATH=""; EFI_DEV=""; TARGET_DISK=""; DISK_HOST_DEV=""
    ROOT_PART_DEV=""; ROOT_SPEC=""; ROOT_PARTUUID=""; ROOT_FSTYPE=""; ROOT_SUBVOL="/"
    LUKS_MAPPER_NAME=""; LUKS_BACKING_DEV=""; LUKS_UUID=""

    local src opts
    src=$(findmnt -n -o SOURCE / 2>/dev/null) || src=""
    if [[ -z "$src" ]]; then
        BOOT_LAYOUT_ERROR="the root filesystem is not mounted"
        return 1
    fi
    ROOT_PART_DEV="${src%%\[*}"
    ROOT_FSTYPE=$(findmnt -n -o FSTYPE / 2>/dev/null) || ROOT_FSTYPE=""

    if [[ "$ROOT_FSTYPE" == btrfs ]]; then
        # findmnt names the subvolume in brackets after the device; the mount
        # options carry it too. The bracket is what the old detection read.
        if [[ "$src" == *"["*"]" ]]; then
            ROOT_SUBVOL="${src##*\[}"; ROOT_SUBVOL="${ROOT_SUBVOL%\]}"
        else
            opts=$(findmnt -n -o OPTIONS / 2>/dev/null) || opts=""
            ROOT_SUBVOL=$(printf '%s\n' "$opts" | tr ',' '\n' | sed -n 's/^subvol=//p' | head -n1)
        fi
        ROOT_SUBVOL="${ROOT_SUBVOL#/}"
        [[ -n "$ROOT_SUBVOL" ]] || ROOT_SUBVOL="/"
    fi

    # An encrypted root: what the kernel is told to unlock is the partition
    # under the mapper, found through cryptsetup.
    if [[ "$ROOT_PART_DEV" == /dev/mapper/* ]]; then
        LUKS_MAPPER_NAME=$(basename "$ROOT_PART_DEV")
        LUKS_BACKING_DEV=$(cryptsetup status "$LUKS_MAPPER_NAME" 2>/dev/null \
            | awk '/^[[:space:]]*device:/ {print $2; exit}') || LUKS_BACKING_DEV=""
        if [[ -z "$LUKS_BACKING_DEV" ]]; then
            BOOT_LAYOUT_ERROR="the encrypted root's backing device could not be resolved for $LUKS_MAPPER_NAME"
            return 1
        fi
        LUKS_UUID=$(cryptsetup luksUUID "$LUKS_BACKING_DEV" 2>/dev/null) || LUKS_UUID=""
        if [[ -z "$LUKS_UUID" ]]; then
            BOOT_LAYOUT_ERROR="the LUKS UUID of $LUKS_BACKING_DEV could not be read"
            return 1
        fi
        ROOT_SPEC="rd.luks.name=${LUKS_UUID}=${LUKS_MAPPER_NAME} root=/dev/mapper/${LUKS_MAPPER_NAME}"
        DISK_HOST_DEV="$LUKS_BACKING_DEV"
    else
        ROOT_PARTUUID=$(lsblk -dno PARTUUID "$ROOT_PART_DEV" 2>/dev/null) || ROOT_PARTUUID=""
        if [[ -z "$ROOT_PARTUUID" ]]; then
            BOOT_LAYOUT_ERROR="no PARTUUID for $ROOT_PART_DEV; the boot loader needs a GPT partition for root"
            return 1
        fi
        ROOT_SPEC="root=PARTUUID=${ROOT_PARTUUID}"
        DISK_HOST_DEV="$ROOT_PART_DEV"
    fi

    local fstype disk_boot disk_root
    if boot_layout_is_uefi; then
        IS_UEFI=true
        BOOT_PATH="/boot/efi"
        # The boot image is built onto the EFI system partition at this one
        # path; the installer's own partition page expects it there too.
        if ! mountpoint -q /boot/efi 2>/dev/null; then
            BOOT_LAYOUT_ERROR="this machine starts with UEFI, so the EFI system partition has to be mounted at /boot/efi; go back to the partitioning step and set that mount point"
            return 1
        fi
        fstype=$(findmnt -n -o FSTYPE /boot/efi 2>/dev/null) || fstype=""
        if [[ "$fstype" != vfat ]]; then
            BOOT_LAYOUT_ERROR="the partition at /boot/efi is ${fstype:-unknown}; an EFI system partition has to be FAT32"
            return 1
        fi
        EFI_DEV=$(findmnt -n -o SOURCE /boot/efi 2>/dev/null) || EFI_DEV=""
        TARGET_DISK=$(lsblk -dno PKNAME "$EFI_DEV" 2>/dev/null) || TARGET_DISK=""
    else
        IS_UEFI=false
        BOOT_PATH="/boot"
        # Limine's BIOS stages read FAT and nothing else, and they read the
        # kernel straight off the disk, so on BIOS /boot has to be its own
        # FAT32 partition. Inside an encrypted or Btrfs or ext4 root it is
        # out of the boot loader's reach.
        if ! mountpoint -q /boot 2>/dev/null; then
            BOOT_LAYOUT_ERROR="this machine starts with BIOS, so /boot has to be its own FAT32 partition; go back to the partitioning step and add one (1 GiB is plenty)"
            return 1
        fi
        fstype=$(findmnt -n -o FSTYPE /boot 2>/dev/null) || fstype=""
        if [[ "$fstype" != vfat ]]; then
            BOOT_LAYOUT_ERROR="the partition at /boot is ${fstype:-unknown}; on a BIOS machine it has to be FAT32, the one kind the boot loader can read"
            return 1
        fi
        # -d (nodeps): a LUKS-backing partition also reports its open mapper's
        # PKNAME, and the multi-line value would corrupt TARGET_DISK.
        TARGET_DISK=$(lsblk -dno PKNAME "$DISK_HOST_DEV" 2>/dev/null) || TARGET_DISK=""
        disk_root="$TARGET_DISK"
        disk_boot=$(lsblk -dno PKNAME "$(findmnt -n -o SOURCE /boot 2>/dev/null)" 2>/dev/null) || disk_boot=""
        if [[ -n "$disk_boot" && -n "$disk_root" && "$disk_boot" != "$disk_root" ]]; then
            BOOT_LAYOUT_ERROR="/boot is on a different disk from the root; on a BIOS machine both have to be on the disk the firmware starts from"
            return 1
        fi
    fi

    if [[ -z "$TARGET_DISK" ]]; then
        BOOT_LAYOUT_ERROR="the disk that will hold the boot loader could not be determined"
        return 1
    fi
    [[ "$TARGET_DISK" == /* ]] || TARGET_DISK="/dev/$TARGET_DISK"
    return 0
}
