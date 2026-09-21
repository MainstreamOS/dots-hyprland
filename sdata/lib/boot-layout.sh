#!/usr/bin/env bash
# boot-layout.sh: what the disks of the system being installed look like, for
# the steps that set up booting. Sourced inside the installer's chroot by
# install-limine and post-install-boot, and baked into the image as
# /usr/local/lib/boot-layout.sh by build.sh.
#
# The partitioning step can hand these scripts any layout a person builds, so
# they ask rather than assume, and refuse in plain words when the pieces this
# image installs cannot boot what was built. Every question about the machine
# goes through a command on PATH, so boot-layout.test.sh can stand in for the
# hardware.

# Firmware. The live session's /sys is mounted into the chroot, so this is the
# same answer the installer's own BIOS layout switch used.
boot_layout_is_uefi() { [[ -d "${BOOT_LAYOUT_EFI_DIR:-/sys/firmware/efi}" ]]; }

# Sets, in the caller's shell:
#   IS_UEFI          true or false
#   BOOT_PATH        /boot/efi on UEFI, /boot on BIOS: where limine.conf goes
#                    and what the boot tooling is pinned to
#   EFI_DEV          the EFI system partition (UEFI)
#   TARGET_DISK      the whole disk the boot loader is written to
#   DISK_HOST_DEV    the partition that hosts root, LUKS resolved
#   ROOT_PART_DEV    root's device, without the subvolume findmnt appends
#   ROOT_SPEC        the root= tokens for the kernel command line
#   ROOT_PARTUUID    plain installs only
#   ROOT_FSTYPE      btrfs, ext4, xfs, f2fs, ...
#   ROOT_SUBVOL      the btrfs subvolume root is mounted from, without its
#                    leading slash; empty when root is the top level or the
#                    filesystem has no subvolumes
#   LUKS_MAPPER_NAME LUKS_BACKING_DEV LUKS_UUID  encrypted installs only
# Returns 1 with BOOT_LAYOUT_ERROR set to one sentence for the user when the
# layout cannot be booted. Nothing is written.
boot_layout_detect() {
    BOOT_LAYOUT_ERROR=""
    IS_UEFI=false; BOOT_PATH=""; EFI_DEV=""; TARGET_DISK=""; DISK_HOST_DEV=""
    ROOT_PART_DEV=""; ROOT_SPEC=""; ROOT_PARTUUID=""; ROOT_FSTYPE=""; ROOT_SUBVOL=""
    LUKS_MAPPER_NAME=""; LUKS_BACKING_DEV=""; LUKS_UUID=""

    # -v drops the [/subvolume] findmnt appends to a btrfs source, and FSROOT
    # is that same subvolume on its own, so neither has to be parsed out.
    ROOT_PART_DEV=$(findmnt -nv -o SOURCE / 2>/dev/null) || ROOT_PART_DEV=""
    if [[ -z "$ROOT_PART_DEV" ]]; then
        BOOT_LAYOUT_ERROR="the root filesystem is not mounted"
        return 1
    fi
    ROOT_FSTYPE=$(findmnt -n -o FSTYPE / 2>/dev/null) || ROOT_FSTYPE=""
    if [[ -z "$ROOT_FSTYPE" ]]; then
        BOOT_LAYOUT_ERROR="the root filesystem's type could not be read"
        return 1
    fi

    if [[ "$ROOT_FSTYPE" == btrfs ]]; then
        ROOT_SUBVOL=$(findmnt -n -o FSROOT / 2>/dev/null) || ROOT_SUBVOL=""
        ROOT_SUBVOL="${ROOT_SUBVOL#/}"
        # The name goes on the kernel command line, which is split on spaces
        # and read again by the tools that rewrite it, so anything outside a
        # plain path would come back as a different subvolume or as two words.
        if [[ -n "$ROOT_SUBVOL" && ! "$ROOT_SUBVOL" =~ ^[A-Za-z0-9._@+-][A-Za-z0-9._@/+-]*$ ]]; then
            BOOT_LAYOUT_ERROR="the Btrfs subvolume name \"$ROOT_SUBVOL\" cannot be put on the kernel command line; use a name of letters, digits, dot, dash, underscore or @"
            return 1
        fi
    fi

    # An encrypted root: what the kernel is told to unlock is the partition
    # under the mapper. Other mapped devices reach this path too, and the
    # boot loader this image installs cannot start from them.
    if [[ "$ROOT_PART_DEV" == /dev/mapper/* || "$ROOT_PART_DEV" == /dev/dm-* ]]; then
        local dmtype
        dmtype=$(lsblk -dno TYPE "$ROOT_PART_DEV" 2>/dev/null) || dmtype=""
        if [[ "$dmtype" != crypt ]]; then
            BOOT_LAYOUT_ERROR="root is on ${dmtype:-a mapped device} (${ROOT_PART_DEV}); this installer can start from a plain partition or an encrypted one, not from LVM or RAID"
            return 1
        fi
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
            BOOT_LAYOUT_ERROR="no PARTUUID for $ROOT_PART_DEV; the boot loader needs root on a partition of its own"
            return 1
        fi
        ROOT_SPEC="root=PARTUUID=${ROOT_PARTUUID}"
        DISK_HOST_DEV="$ROOT_PART_DEV"
    fi

    local fstype boot_src boot_disk
    if boot_layout_is_uefi; then
        IS_UEFI=true
        BOOT_PATH="/boot/efi"
        # The boot image is built onto the EFI system partition at this one
        # path, which is where the installer's partitioning step puts it and
        # what every later step names.
        if ! mountpoint -q /boot/efi 2>/dev/null; then
            BOOT_LAYOUT_ERROR="this machine starts with UEFI, so the EFI system partition has to be mounted at /boot/efi; go back to the partitioning step and set that mount point"
            return 1
        fi
        fstype=$(findmnt -n -o FSTYPE /boot/efi 2>/dev/null) || fstype=""
        if [[ "$fstype" != vfat ]]; then
            BOOT_LAYOUT_ERROR="the partition at /boot/efi is ${fstype:-unknown}; an EFI system partition has to be FAT32"
            return 1
        fi
        EFI_DEV=$(findmnt -nv -o SOURCE /boot/efi 2>/dev/null) || EFI_DEV=""
        TARGET_DISK=$(lsblk -dno PKNAME "$EFI_DEV" 2>/dev/null) || TARGET_DISK=""
    else
        IS_UEFI=false
        BOOT_PATH="/boot"
        # Limine's BIOS stages read FAT and nothing else, and they read the
        # kernel straight off the disk, so on BIOS /boot has to be its own
        # FAT32 partition. Inside an encrypted, Btrfs or ext4 root it is out
        # of the boot loader's reach.
        if ! mountpoint -q /boot 2>/dev/null; then
            BOOT_LAYOUT_ERROR="this machine starts with BIOS, so /boot has to be its own FAT32 partition; go back to the partitioning step and add one (1 GiB is plenty)"
            return 1
        fi
        boot_src=$(findmnt -nv -o SOURCE /boot 2>/dev/null) || boot_src=""
        fstype=$(findmnt -n -o FSTYPE /boot 2>/dev/null) || fstype=""
        if [[ "$fstype" != vfat ]]; then
            BOOT_LAYOUT_ERROR="the partition at /boot is ${fstype:-unknown}; on a BIOS machine it has to be FAT32, the one kind the boot loader can read"
            return 1
        fi
        # FAT inside an encrypted or mapped device still reports vfat, and the
        # BIOS stages cannot unlock anything.
        if [[ "$boot_src" == /dev/mapper/* || "$boot_src" == /dev/dm-* ]]; then
            BOOT_LAYOUT_ERROR="/boot is on an encrypted or mapped device; on a BIOS machine it has to be a plain FAT32 partition the boot loader can read before anything is unlocked"
            return 1
        fi
        # -d (nodeps): a LUKS-backing partition also reports its open mapper's
        # PKNAME, and the multi-line value would corrupt TARGET_DISK.
        TARGET_DISK=$(lsblk -dno PKNAME "$DISK_HOST_DEV" 2>/dev/null) || TARGET_DISK=""
        boot_disk=$(lsblk -dno PKNAME "$boot_src" 2>/dev/null) || boot_disk=""
        if [[ -n "$boot_disk" && -n "$TARGET_DISK" && "$boot_disk" != "$TARGET_DISK" ]]; then
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
