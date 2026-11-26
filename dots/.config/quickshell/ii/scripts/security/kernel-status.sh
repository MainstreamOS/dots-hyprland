#!/usr/bin/env bash
# kernel-status.sh: unprivileged status probe for the Kernel section in
# Settings > Gaming.
#
# Prints one JSON object to stdout and needs no root privileges. Every change runs
# through ${KERNELS_HELPER:-/usr/lib/mainstream/mainstream-kernels}, which checks all
# of this again as root.
set -uo pipefail
export LC_ALL=C

KERNELS_HELPER="${KERNELS_HELPER:-/usr/lib/mainstream/mainstream-kernels}"
EFIVARS_DIR="${EFIVARS_DIR:-/sys/firmware/efi/efivars}"
LAST_ENTRY_VAR="${LAST_ENTRY_VAR:-$EFIVARS_DIR/LimineLastBootedEntry-03884334-1756-4978-9c8c-86fb8998b4ea}"
LIMINE_DEFAULT_CONF="${LIMINE_DEFAULT_CONF:-/etc/default/limine}"
ROOT_MOUNT="${ROOT_MOUNT:-/}"
MODULES_DIR="${MODULES_DIR:-/usr/lib/modules}"
PROC_CPUINFO="${PROC_CPUINFO:-/proc/cpuinfo}"
# Where the EFI partition is looked for when the Limine settings do not name it.
ESP_CANDIDATES="${ESP_CANDIDATES:-/boot/efi /efi /boot /limine}"

STANDARD_KERNEL=linux
PERFORMANCE_KERNEL=mainstream-performance
KERNELS=("$STANDARD_KERNEL" mainstream "$PERFORMANCE_KERNEL")
# Mainstream's kernels under the package names they had before. A system keeps the
# old packages until an update swaps them, and each kernel is reported under its
# name today with the package it is installed or offered as.
declare -A OLD_NAMES=(
    [mainstream]=linux-mainstream
    [mainstream-performance]=linux-mainstream-performance
    [mainstream-performance-eac]=linux-mainstream-performance-eac
)

# A kernel's name today, whichever of its names $1 is.
kernel_name() {
    local name
    for name in "${!OLD_NAMES[@]}"; do
        if [[ $1 == "${OLD_NAMES[$name]}" ]]; then
            printf '%s' "$name"
            return 0
        fi
    done
    printf '%s' "$1"
}

helper=false
can_change_standard=false
can_use_new_names=false
uefi=false
unsupported_reason=""
esp_free=null
standard_image=null
next_kernel=""
can_choose_next=false
performance_cpu=false

[[ -x $KERNELS_HELPER ]] && helper=true
[[ -d $EFIVARS_DIR ]] && uefi=true

# Older helpers refuse to install or remove Arch's kernel, with this message.
if [[ $helper == true ]]; then
    rc=0
    grep -qF -- 'the standard kernel stays installed as the fallback' "$KERNELS_HELPER" 2>/dev/null || rc=$?
    (( rc == 1 )) && can_change_standard=true
    # Older helpers know Mainstream's kernels by their old package names alone.
    grep -qF -- 'RENAMED_KERNELS=(' "$KERNELS_HELPER" 2>/dev/null && can_use_new_names=true
fi

root_fstype=""
root_subvol=""
if command -v findmnt >/dev/null 2>&1; then
    read -r root_fstype root_subvol < <(findmnt -n -o FSTYPE,FSROOT "$ROOT_MOUNT" 2>/dev/null | head -n1) || true
fi

# Why the helper would refuse to change this system, in the order it checks.
if [[ $root_fstype == overlay || $root_subvol =~ (^|/)(@|@?\.)snapshots/[0-9]+/snapshot$ ]]; then
    unsupported_reason=snapshot
elif ! command -v limine-update >/dev/null 2>&1 || ! command -v limine-mkinitcpio >/dev/null 2>&1 \
        || ! command -v limine-enroll-config >/dev/null 2>&1; then
    unsupported_reason=boot-tools
fi

# The performance kernel is built for x86-64-v3.
if [[ -r $PROC_CPUINFO ]]; then
    flags=""
    while IFS= read -r line; do
        if [[ $line == flags* ]]; then
            flags=" ${line#*:} "
            break
        fi
    done <"$PROC_CPUINFO"
    performance_cpu=true
    for flag in avx avx2 bmi1 bmi2 f16c fma movbe xsave; do
        [[ $flags == *" $flag "* ]] || performance_cpu=false
    done
    [[ $flags == *" abm "* || $flags == *" lzcnt "* ]] || performance_cpu=false
fi

# The package of every kernel this system can start, and of the one running.
installed_bases=()
installed_names=()
with_nvidia=()
for dir in "$MODULES_DIR"/*/; do
    [[ -f "${dir}vmlinuz" && -r "${dir}pkgbase" ]] || continue
    base=""
    IFS= read -r base <"${dir}pkgbase" || true
    [[ -n $base ]] || continue
    installed_bases+=("$base")
    installed_names+=("$(kernel_name "$base")")
    for module in "${dir}"updates/dkms/nvidia.ko* "${dir}"extramodules/nvidia.ko* \
                  "${dir}"kernel/drivers/video/nvidia.ko*; do
        if [[ -f $module ]]; then
            with_nvidia+=("$base")
            break
        fi
    done
done

running=""
release=$(uname -r 2>/dev/null) || release=""
if [[ -n $release && -r "$MODULES_DIR/$release/pkgbase" ]]; then
    IFS= read -r running <"$MODULES_DIR/$release/pkgbase" || true
fi
# The module tree is gone once the package was updated or removed under the running
# kernel, and the release still ends in the package's name.
if [[ -z $running ]]; then
    case $release in
        *-mainstream-performance-eac) running=mainstream-performance-eac ;;
        *-mainstream-performance) running=$PERFORMANCE_KERNEL ;;
        *-mainstream) running=mainstream ;;
        *-arch[0-9]*) running=$STANDARD_KERNEL ;;
    esac
fi
running=$(kernel_name "$running")

in_list() {  # $1 = word, $2... = the words it may be
    local word=$1 w
    shift
    for w in "$@"; do
        [[ $w == "$word" ]] && return 0
    done
    return 1
}

# Limine records the entry it started and preselects it at the next start: four bytes
# of attributes, then the entry's path in the menu, ended by a zero byte.
if [[ $uefi == true && -f $LAST_ENTRY_VAR && -r $LAST_ENTRY_VAR ]]; then
    entry=$(tail -c +5 -- "$LAST_ENTRY_VAR" 2>/dev/null | tr -d '\0') || entry=""
    if [[ $entry == ?*/?* && $entry != */Snapshots/* ]] \
            && in_list "$(kernel_name "${entry##*/}")" "${KERNELS[@]}" "${installed_names[@]}"; then
        next_kernel=$(kernel_name "${entry##*/}")
        can_choose_next=true
    fi
fi

esp=""
if [[ -r $LIMINE_DEFAULT_CONF ]]; then
    esp=$(awk -F= '/^[[:space:]]*ESP_PATH[[:space:]]*=/{v=$2; gsub(/^[[:space:]]*"?|"?[[:space:]]*$/, "", v); print v}' "$LIMINE_DEFAULT_CONF" 2>/dev/null | tail -n1)
fi
if [[ -z $esp || ! -d $esp ]]; then
    esp=""
    for candidate in $ESP_CANDIDATES; do
        if [[ -d $candidate/EFI || -e $candidate/limine.conf ]] \
                || [[ $(findmnt -no FSTYPE -M "$candidate" 2>/dev/null | head -n1) == vfat ]]; then
            esp=$candidate
            break
        fi
    done
fi
if [[ -n $esp ]]; then
    avail=$(df -B1 --output=avail -- "$esp" 2>/dev/null | tail -n1 | tr -d '[:space:]')
    [[ $avail =~ ^[0-9]+$ ]] && esp_free=$avail
    # The largest boot image of the installed kernels, measured as the helper does.
    # Only root can read most EFI partitions, so this is often not known here.
    largest=0
    for base in "${installed_bases[@]}"; do
        best=0
        for image in "$esp"/EFI/Linux/*_"$base".efi "$esp/EFI/Linux/$base.efi"; do
            [[ -f $image ]] || continue
            size=$(stat -c %s -- "$image" 2>/dev/null) || continue
            [[ $size =~ ^[0-9]+$ ]] && (( size > best )) && best=$size
        done
        if (( best == 0 )); then
            for dir in "$esp"/*/"$base"/; do
                [[ -d $dir ]] || continue
                total=0
                for image in "$dir"*; do
                    [[ -f $image ]] || continue
                    size=$(stat -c %s -- "$image" 2>/dev/null) || continue
                    [[ $size =~ ^[0-9]+$ ]] && total=$((total + size))
                done
                (( total > best )) && best=$total
            done
        fi
        (( best > largest )) && largest=$best
    done
    (( largest > 0 )) && standard_image=$largest
fi

# What installing kernel $1 with its headers would fetch, dependencies included. pacman
# only works it out here and changes nothing. Prints nothing when it cannot.
download_bytes() {
    local plan total=0 name size
    plan=$(pacman -Sp --needed --print-format '%n %s' -- "$1" "$1-headers" 2>/dev/null) || return 0
    while read -r name size; do
        [[ -n $name ]] || continue
        [[ $size =~ ^[0-9]+$ ]] || return 0
        total=$((total + size))
    done <<<"$plan"
    (( total > 0 )) && printf '%s\n' "$total"
    return 0
}

# One query for what the repositories offer.
declare -A on_offer=()
if command -v pacman >/dev/null 2>&1; then
    queried=()
    for kernel in "${KERNELS[@]}"; do
        queried+=("$kernel" "$kernel-headers")
        [[ -n ${OLD_NAMES[$kernel]:-} ]] && queried+=("${OLD_NAMES[$kernel]}" "${OLD_NAMES[$kernel]}-headers")
    done
    while IFS= read -r name; do
        [[ -n $name ]] && on_offer[$name]=1
    done < <(pacman -Si -- "${queried[@]}" 2>/dev/null | awk '/^Name[[:space:]]*:/ { print $NF }')
fi

kernels_json="[]"
for kernel in "${KERNELS[@]}"; do
    names=("$kernel")
    [[ -n ${OLD_NAMES[$kernel]:-} ]] && names+=("${OLD_NAMES[$kernel]}")
    installed=false
    version=""
    package=""
    if command -v pacman >/dev/null 2>&1; then
        for name in "${names[@]}"; do
            read -r q_name q_version < <(pacman -Q -- "$name" 2>/dev/null) || true
            if [[ ${q_name:-} == "$name" ]] && in_list "$name" "${installed_bases[@]}"; then
                installed=true
                version=${q_version:-}
                package=$name
            fi
            q_name="" q_version=""
        done
    fi

    # The helper installs a kernel with its headers, so both must be on offer, under a
    # name the helper knows.
    available=false
    download=null
    for name in "${names[@]}"; do
        [[ $name == "$kernel" && -n ${OLD_NAMES[$kernel]:-} && $helper == true && $can_use_new_names == false ]] && continue
        if [[ -n ${on_offer[$name]:-} && -n ${on_offer[$name-headers]:-} ]]; then
            available=true
            [[ -n $package ]] || package=$name
            break
        fi
    done
    [[ -n $package ]] || package=$kernel
    if [[ $available == true && $installed == false ]]; then
        total=$(download_bytes "$package")
        [[ -n $total ]] && download=$total
    fi

    cpu_supported=true
    [[ $kernel == "$PERFORMANCE_KERNEL" ]] && cpu_supported=$performance_cpu

    is_running=false
    [[ $running == "$kernel" ]] && is_running=true

    # A kernel with no NVIDIA module on a machine whose other kernels have one would
    # start without graphics.
    driver_missing=false
    if [[ $installed == true && ${#with_nvidia[@]} -gt 0 ]] && ! in_list "$package" "${with_nvidia[@]}"; then
        driver_missing=true
    fi

    kernels_json=$(jq -c \
        --arg name "$kernel" \
        --arg package "$package" \
        --argjson installed "$installed" \
        --arg version "$version" \
        --argjson running "$is_running" \
        --argjson available "$available" \
        --argjson cpuSupported "$cpu_supported" \
        --argjson downloadBytes "$download" \
        --argjson driverMissing "$driver_missing" \
        '. + [{
            name: $name,
            package: $package,
            installed: $installed,
            version: $version,
            running: $running,
            available: $available,
            cpuSupported: $cpuSupported,
            downloadBytes: $downloadBytes,
            driverMissing: $driverMissing
        }]' <<<"$kernels_json") || exit 1
done

exec jq -nc \
    --argjson helper "$helper" \
    --argjson canChangeStandard "$can_change_standard" \
    --argjson canUseNewNames "$can_use_new_names" \
    --arg unsupportedReason "$unsupported_reason" \
    --argjson uefi "$uefi" \
    --argjson espFreeBytes "$esp_free" \
    --argjson standardImageBytes "$standard_image" \
    --arg nextKernel "$next_kernel" \
    --argjson canChooseNext "$can_choose_next" \
    --argjson kernels "$kernels_json" \
    '{
        helper: $helper,
        canChangeStandard: $canChangeStandard,
        canUseNewNames: $canUseNewNames,
        unsupportedReason: $unsupportedReason,
        uefi: $uefi,
        espFreeBytes: $espFreeBytes,
        standardImageBytes: $standardImageBytes,
        nextKernel: $nextKernel,
        canChooseNext: $canChooseNext,
        installedKernels: $ARGS.positional,
        kernels: $kernels
    }' --args "${installed_names[@]}"
