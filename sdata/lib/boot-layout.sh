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

# Software RAID. An array's own nodes are /dev/md*, and a partition of one is
# known by its array, whatever path it was mounted by. The array's kernel name
# is md* at every level, while its type is only raid* at some: md also runs
# linear and multipath arrays.
boot_layout_on_raid() {
    local parent
    [[ "$1" == /dev/md* ]] && return 0
    parent=$(lsblk -dno PKNAME "$1" 2>/dev/null) || parent=""
    [[ -n "$parent" ]] || return 1
    [[ "$parent" == /* ]] || parent="/dev/$parent"
    [[ "$parent" == /dev/md* ]] && return 0
    [[ "$(lsblk -dno TYPE "$parent" 2>/dev/null)" == raid* ]]
}

# Sets, in the caller's shell:
#   IS_UEFI          true or false
#   BOOT_PATH        /boot/efi on UEFI, /boot on BIOS: where limine.conf goes
#                    and what the boot tooling is pinned to
#   EFI_DEV          the EFI system partition (UEFI)
#   TARGET_DISK      the whole disk the boot loader is written to: the ESP's
#                    disk on UEFI, which efibootmgr pairs with EFI_DEV's
#                    partition number, and the disk holding /boot on BIOS
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
        DISK_HOST_DEV="$LUKS_BACKING_DEV"
    else
        DISK_HOST_DEV="$ROOT_PART_DEV"
    fi

    # The initramfs this image builds has no hook that assembles an array, so
    # the kernel would wait for a root it never finds. The partitioning step
    # refuses the same layouts. A whole array has no PARTUUID either, so this
    # comes first and the missing PARTUUID does not take the blame.
    if boot_layout_on_raid "$DISK_HOST_DEV"; then
        BOOT_LAYOUT_ERROR="root is on software RAID (${DISK_HOST_DEV}); this installer can start from a plain partition or an encrypted one, not from LVM or RAID"
        return 1
    fi

    if [[ -n "$LUKS_MAPPER_NAME" ]]; then
        LUKS_UUID=$(cryptsetup luksUUID "$LUKS_BACKING_DEV" 2>/dev/null) || LUKS_UUID=""
        if [[ -z "$LUKS_UUID" ]]; then
            BOOT_LAYOUT_ERROR="the LUKS UUID of $LUKS_BACKING_DEV could not be read"
            return 1
        fi
        ROOT_SPEC="rd.luks.name=${LUKS_UUID}=${LUKS_MAPPER_NAME} root=/dev/mapper/${LUKS_MAPPER_NAME}"
    else
        ROOT_PARTUUID=$(lsblk -dno PARTUUID "$ROOT_PART_DEV" 2>/dev/null) || ROOT_PARTUUID=""
        if [[ -z "$ROOT_PARTUUID" ]]; then
            BOOT_LAYOUT_ERROR="no PARTUUID for $ROOT_PART_DEV; the boot loader needs root on a partition of its own"
            return 1
        fi
        ROOT_SPEC="root=PARTUUID=${ROOT_PARTUUID}"
    fi

    local fstype boot_src size pttype parttype listing line row readable
    local part_path part_type part_fs part_n bios_path bios_fs bios_n
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
        if [[ "$EFI_DEV" == /dev/mapper/* || "$EFI_DEV" == /dev/dm-* ]]; then
            BOOT_LAYOUT_ERROR="/boot/efi is on an encrypted or mapped device; the firmware reads the EFI system partition before anything is unlocked, so it has to be a plain FAT32 partition"
            return 1
        fi
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
        # The BIOS stages read /boot straight off one disk and cannot put an
        # array together, and the partitioning step refuses the same layouts.
        if boot_layout_on_raid "$boot_src"; then
            BOOT_LAYOUT_ERROR="/boot is on software RAID ($boot_src); on a BIOS machine it has to be a plain FAT32 partition on one disk, which the boot loader reads without assembling anything"
            return 1
        fi
        # Every kernel keeps its image, an initramfs and a larger fallback
        # initramfs here, and the snapshot entries in the boot menu keep
        # copies of their own.
        size=$(lsblk -bdno SIZE "$boot_src" 2>/dev/null) || size=""
        if [[ ! "$size" =~ ^[0-9]+$ ]]; then
            BOOT_LAYOUT_ERROR="the size of the /boot partition ($boot_src) could not be read"
            return 1
        fi
        if (( size < 512 * 1024 * 1024 )); then
            BOOT_LAYOUT_ERROR="the /boot partition is $(( size / 1024 / 1024 )) MiB; it has to hold the kernels and their initramfs images, and the legacy NVIDIA edition's are larger, so make it at least 512 MiB (1 GiB is the default)"
            return 1
        fi
        # Stages 1 and 2 go to the disk that holds /boot, the same disk
        # limine-bios-sync resolves on every later limine upgrade, so both
        # always write the same MBR. Root may sit on any disk: the BIOS
        # stages only ever read /boot.
        TARGET_DISK=$(lsblk -dno PKNAME "$boot_src" 2>/dev/null) || TARGET_DISK=""
    fi

    if [[ -z "$TARGET_DISK" ]]; then
        BOOT_LAYOUT_ERROR="the disk that will hold the boot loader could not be determined"
        return 1
    fi
    [[ "$TARGET_DISK" == /* ]] || TARGET_DISK="/dev/$TARGET_DISK"

    pttype=$(lsblk -dno PTTYPE "$TARGET_DISK" 2>/dev/null) || pttype=""
    pttype="${pttype,,}"
    if [[ -z "$pttype" ]]; then
        BOOT_LAYOUT_ERROR="the partition table type of $TARGET_DISK, the disk holding $BOOT_PATH, could not be read"
        return 1
    fi

    if [[ "$IS_UEFI" == true ]]; then
        # On an MBR disk the partitioning step can only toggle the active bit,
        # never set type 0xef, so it has no way to make an EFI system
        # partition there and its own layout check refuses one. Refusing the
        # same layouts here keeps the two in step.
        if [[ "$pttype" != gpt ]]; then
            BOOT_LAYOUT_ERROR="/boot/efi is on $TARGET_DISK, which has no GPT partition table, so the installer cannot mark it as an EFI system partition; go back to the partitioning step and put the EFI system partition on a GPT disk"
            return 1
        fi
        # UEFI firmware is only required to search partitions of the ESP type,
        # and many search nothing else, so a boot loader written to a plain FAT
        # partition is never found.
        parttype=$(lsblk -dno PARTTYPE "$EFI_DEV" 2>/dev/null) || parttype=""
        parttype="${parttype,,}"
        if [[ -z "$parttype" ]]; then
            BOOT_LAYOUT_ERROR="the partition type of /boot/efi ($EFI_DEV) could not be read"
            return 1
        fi
        if [[ "$parttype" != c12a7328-f81f-11d2-ba4b-00a0c93ec93b ]]; then
            BOOT_LAYOUT_ERROR="the partition at /boot/efi is not marked as an EFI system partition, so the firmware may never look at it; go back to the partitioning step and set its boot flag"
            return 1
        fi
        return 0
    fi

    # On a GPT disk limine bios-install writes stage 2 into the partition of
    # the BIOS boot type with the lowest number in the table, and fails
    # outright when there is none; an MBR disk needs no such partition. It
    # will not write over FAT, NTFS or ext, but it writes straight over LUKS,
    # Btrfs or swap, so that one has to hold nothing at all. The listing drops
    # -d so that it reaches the partitions under the disk, and with them
    # everything stacked on them: an unlocked root, or an array built on a
    # member partition along with the array's own partitions, which carry
    # partition types and numbers of their own from the array's table. Only
    # what names the disk itself as its parent is in the disk's table. The
    # listing comes in device number order, and extended device numbers,
    # which NVMe always uses, go to partitions in the order they appear rather
    # than in table order, so each partition is placed by its own number.
    [[ "$pttype" == gpt ]] || return 0
    row='^PATH="([^"]*)" PARTTYPE="([^"]*)" FSTYPE="([^"]*)" PARTN="([^"]*)" PKNAME="([^"]*)"$'
    readable=false; bios_path=""; bios_fs=""; bios_n=""
    listing=$(lsblk -nP -o PATH,PARTTYPE,FSTYPE,PARTN,PKNAME "$TARGET_DISK" 2>/dev/null) || listing=""
    while IFS= read -r line; do
        [[ "$line" =~ $row ]] || continue
        [[ "${BASH_REMATCH[5]}" == "${TARGET_DISK#/dev/}" ]] || continue
        part_path="${BASH_REMATCH[1]}"; part_type="${BASH_REMATCH[2],,}"
        part_fs="${BASH_REMATCH[3]}"; part_n="${BASH_REMATCH[4]}"
        [[ -n "$part_type" && "$part_n" =~ ^[0-9]+$ ]] || continue
        readable=true
        [[ "$part_type" == 21686148-6449-6e6f-744e-656564454649 ]] || continue
        if [[ -z "$bios_n" ]] || (( part_n < bios_n )); then
            bios_path="$part_path"; bios_fs="$part_fs"; bios_n="$part_n"
        fi
    done <<<"$listing"
    if [[ "$readable" == false ]]; then
        BOOT_LAYOUT_ERROR="the partition types on $TARGET_DISK, the disk holding /boot, could not be read"
        return 1
    fi
    if [[ -z "$bios_path" ]]; then
        BOOT_LAYOUT_ERROR="$TARGET_DISK holds /boot and has a GPT partition table, so on a BIOS machine it also needs a BIOS boot partition for the boot loader; go back to the partitioning step and add a small unformatted partition with the bios-grub flag to that disk (1 MiB is plenty)"
        return 1
    fi
    if [[ -n "$bios_fs" ]]; then
        BOOT_LAYOUT_ERROR="$bios_path is the first partition with the bios-grub flag on $TARGET_DISK, so the boot loader writes itself there and would overwrite the $bios_fs it holds; go back to the partitioning step and leave that partition unformatted, or clear its bios-grub flag"
        return 1
    fi
    return 0
}
