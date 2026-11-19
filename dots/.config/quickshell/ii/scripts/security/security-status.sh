#!/usr/bin/env bash
# security-status.sh: unprivileged status probe for Secure Boot and the anti-cheat
# checklist in Settings > Gaming.
#
# Prints one JSON object to stdout and needs no root privileges. What only root can
# read (the signing keys, sbctl verification) comes from the state file the helper
# leaves at ${SECURITY_STATE_FILE:-/var/lib/mainstream/security-state.json}.
set -uo pipefail
export LC_ALL=C

SECURITY_HELPER="${SECURITY_HELPER:-/usr/lib/mainstream/system-security}"
SECURITY_STATE_FILE="${SECURITY_STATE_FILE:-/var/lib/mainstream/security-state.json}"
EFIVARS_DIR="${EFIVARS_DIR:-/sys/firmware/efi/efivars}"
LIMINE_DEFAULT_CONF="${LIMINE_DEFAULT_CONF:-/etc/default/limine}"
ROOT_MOUNT="${ROOT_MOUNT:-/}"
TPM_VERSION_FILE="${TPM_VERSION_FILE:-/sys/class/tpm/tpm0/tpm_version_major}"
TPM_PCR_DIR="${TPM_PCR_DIR:-/sys/class/tpm/tpm0/pcr-sha256}"
SYS_IOMMU_CLASS="${SYS_IOMMU_CLASS:-/sys/class/iommu}"
SYS_IOMMU_GROUPS="${SYS_IOMMU_GROUPS:-/sys/kernel/iommu_groups}"
SYS_LOCKDOWN="${SYS_LOCKDOWN:-/sys/kernel/security/lockdown}"
SYS_LSM="${SYS_LSM:-/sys/kernel/security/lsm}"
PROC_KEXEC_LOAD_DISABLED="${PROC_KEXEC_LOAD_DISABLED:-/proc/sys/kernel/kexec_load_disabled}"
SBCTL_DB_KEY="${SBCTL_DB_KEY:-/var/lib/sbctl/keys/db/db.key}"
SBCTL_DB_KEY_ALT="${SBCTL_DB_KEY_ALT:-/usr/share/secureboot/keys/db/db.key}"
KEYS_KEPT_STAMP="${KEYS_KEPT_STAMP:-/var/log/mainstream/secure-boot-keys}"

read_efivar_flag() {
    local file=$1 val=""
    [[ -r $file ]] || return 1
    val=$(od -An -t u1 -j4 -N1 -- "$file" 2>/dev/null | tr -d '[:space:]')
    [[ $val == "1" ]]
}

# Leaves a file's first line in REPLY, or nothing when the file cannot be read.
read_line() {
    REPLY=""
    [[ -r $1 ]] && { IFS= read -r REPLY <"$1"; } 2>/dev/null
    return 0
}

dir_has_entries() {
    local entry
    for entry in "$1"/*; do
        [[ -e $entry ]] && return 0
    done
    return 1
}

helper=false
uefi=false
secure_boot=false
setup_mode=false
sbctl_installed=false
sbctl_keys_exist=false
signing_keys_kept=false
windows_detected=false
bitlocker_detected=false
unsupported_reason=""

tpm2=false
measured_boot=false
iommu=false
iommu_passthrough=false
lockdown=unknown
kexec_disabled=false
bpf_lsm=false

# What the helper last recorded, and what stands in for it until it has.
state_default='{"sbctlKeysExist":false,"sbctlVerified":false}'
state=$state_default

[[ -x $SECURITY_HELPER ]] && helper=true

if [[ -d $EFIVARS_DIR ]]; then
    uefi=true
    if read_efivar_flag "$EFIVARS_DIR/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"; then
        secure_boot=true
    fi
    if read_efivar_flag "$EFIVARS_DIR/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"; then
        setup_mode=true
    fi
fi

command -v sbctl >/dev/null 2>&1 && sbctl_installed=true

if command -v lsblk >/dev/null 2>&1; then
    fstypes=$(lsblk -no FSTYPE 2>/dev/null || true)
    if grep -qiE '^[[:space:]]*BitLocker[[:space:]]*$' <<<"$fstypes"; then
        bitlocker_detected=true
        windows_detected=true
    fi
    if grep -qiE '^[[:space:]]*ntfs[[:space:]]*$' <<<"$fstypes"; then
        windows_detected=true
    fi
fi

if [[ $windows_detected == false ]]; then
    limine_candidates=()
    esp_from_conf=""
    if [[ -r $LIMINE_DEFAULT_CONF ]]; then
        esp_from_conf=$(awk -F= '/^[[:space:]]*ESP_PATH[[:space:]]*=/{v=$2; gsub(/^[[:space:]]*"?|"?[[:space:]]*$/, "", v); print v}' "$LIMINE_DEFAULT_CONF" 2>/dev/null | tail -n1)
    fi
    [[ -n $esp_from_conf ]] && limine_candidates+=("${esp_from_conf%/}/limine.conf")
    limine_candidates+=("/boot/efi/limine.conf" "/efi/limine.conf" "/boot/limine.conf" "/limine/limine.conf")
    for lc in "${limine_candidates[@]}"; do
        if [[ -r $lc ]] && grep -qiE 'bootmgfw|Windows' "$lc" 2>/dev/null; then
            windows_detected=true
            break
        fi
    done
fi

root_fstype=""
root_subvol=""
if command -v findmnt >/dev/null 2>&1; then
    read -r root_fstype root_subvol < <(findmnt -n -o FSTYPE,FSROOT "$ROOT_MOUNT" 2>/dev/null | head -n1) || true
fi

if [[ -r $SECURITY_STATE_FILE && -f $SECURITY_STATE_FILE ]]; then
    state=$(jq -cs '
        (.[0] | if type == "object" then . else {} end)
        | {
            sbctlKeysExist: (.sbctlKeysExist == true),
            sbctlVerified: (.sbctlVerified == true)
        }' "$SECURITY_STATE_FILE" 2>/dev/null) || state=$state_default
fi

# The helper leaves this beside its log once the keys are on their own subvolume. A
# restored snapshot keeps the log, so it shows a system that lost sight of its keys.
[[ -e $KEYS_KEPT_STAMP ]] && signing_keys_kept=true

# Override sbctlKeysExist if db.key is directly readable
if [[ -r $SBCTL_DB_KEY || -r $SBCTL_DB_KEY_ALT ]]; then
    sbctl_keys_exist=true
fi

# Why the helper would refuse to change this system's boot setup, in the order it checks.
if [[ $root_fstype == overlay || $root_subvol =~ (^|/)(@|@?\.)snapshots/[0-9]+/snapshot$ ]]; then
    unsupported_reason=snapshot
elif ! command -v limine-update >/dev/null 2>&1 || ! command -v limine-mkinitcpio >/dev/null 2>&1 \
        || ! command -v limine-enroll-config >/dev/null 2>&1; then
    unsupported_reason=boot-tools
fi

# Absent while the chip is switched off in the firmware. A TPM 1.2 reads 1.
read_line "$TPM_VERSION_FILE"
[[ $REPLY == 2 ]] && tpm2=true

# The firmware fills PCR 0 to 7 by itself. These four are only extended by a boot
# manager or a kernel that measures what it starts.
for pcr in 8 9 11 12; do
    read_line "$TPM_PCR_DIR/$pcr"
    if [[ $REPLY =~ ^[0-9A-Fa-f]+$ && $REPLY == *[!0]* ]]; then
        measured_boot=true
        break
    fi
done

if dir_has_entries "$SYS_IOMMU_CLASS" && dir_has_entries "$SYS_IOMMU_GROUPS"; then
    iommu=true
fi
for group_type in "$SYS_IOMMU_GROUPS"/*/type; do
    read_line "$group_type"
    if [[ $REPLY == identity ]]; then
        iommu_passthrough=true
        break
    fi
done

read_line "$SYS_LOCKDOWN"
if [[ $REPLY =~ \[(none|integrity|confidentiality)\] ]]; then
    lockdown=${BASH_REMATCH[1]}
fi

read_line "$PROC_KEXEC_LOAD_DISABLED"
[[ $REPLY == 1 ]] && kexec_disabled=true

read_line "$SYS_LSM"
[[ ,$REPLY, == *,bpf,* ]] && bpf_lsm=true

exec jq -nc \
    --argjson helper "$helper" \
    --arg unsupportedReason "$unsupported_reason" \
    --argjson uefi "$uefi" \
    --argjson secureBoot "$secure_boot" \
    --argjson setupMode "$setup_mode" \
    --argjson sbctlInstalled "$sbctl_installed" \
    --argjson sbctlKeysExist "$sbctl_keys_exist" \
    --argjson state "$state" \
    --argjson signingKeysKept "$signing_keys_kept" \
    --argjson windowsDetected "$windows_detected" \
    --argjson bitlockerDetected "$bitlocker_detected" \
    --argjson tpm2 "$tpm2" \
    --argjson measuredBoot "$measured_boot" \
    --argjson iommu "$iommu" \
    --argjson iommuPassthrough "$iommu_passthrough" \
    --arg lockdown "$lockdown" \
    --argjson kexecDisabled "$kexec_disabled" \
    --argjson bpfLsm "$bpf_lsm" \
    '{
        helper: $helper,
        unsupportedReason: $unsupportedReason,
        uefi: $uefi,
        secureBoot: $secureBoot,
        setupMode: $setupMode,
        sbctlInstalled: $sbctlInstalled,
        sbctlKeysExist: ($sbctlKeysExist or $state.sbctlKeysExist),
        sbctlVerified: $state.sbctlVerified,
        signingKeysKept: $signingKeysKept,
        windowsDetected: $windowsDetected,
        bitlockerDetected: $bitlockerDetected,
        antiCheat: {
            tpm2: $tpm2,
            measuredBoot: $measuredBoot,
            iommu: $iommu,
            iommuPassthrough: $iommuPassthrough,
            lockdown: $lockdown,
            kexecDisabled: $kexecDisabled,
            bpfLsm: $bpfLsm
        }
    }'
