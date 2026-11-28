#!/usr/bin/env bash
# system-security.test.sh: unit and integration test suite for
# dots/.config/quickshell/ii/scripts/security/security-status.sh and
# sdata/dist-arch/mainstream-system/system-security.
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
STATUS_SCRIPT="$REPO_ROOT/dots/.config/quickshell/ii/scripts/security/security-status.sh"
HELPER_SCRIPT="$SCRIPT_DIR/system-security"
POLICY_FILE="$SCRIPT_DIR/org.mainstreamos.system-security.policy"
PKGBUILD_FILE="$SCRIPT_DIR/PKGBUILD"

PASS_COUNT=0

TMP_BASE="$(mktemp -d)"
cleanup() {
    # A test that fails while a directory is read-only would otherwise leave it behind.
    find "$TMP_BASE" -type d ! -perm -u+w -exec chmod u+w {} + 2>/dev/null || true
    rm -rf -- "$TMP_BASE"
}
trap cleanup EXIT

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '  [PASS] %s\n' "$1"
}

fail() {
    printf '  [FAIL] %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local got=$1 want=$2 msg=$3
    if [[ $got == "$want" ]]; then
        pass "$msg"
    else
        fail "$msg (got '$got', expected '$want')"
    fi
}

assert_jq() {
    local json=$1 expr=$2 msg=$3
    if jq -e "$expr" <<<"$json" >/dev/null 2>&1; then
        pass "$msg"
    else
        printf 'JSON payload:\n%s\n' "$json" >&2
        fail "$msg (jq expression failed: $expr)"
    fi
}

expect_rc() {
    local want_rc=$1 msg=$2
    shift 2
    local got_rc=0
    "$@" >/dev/null 2>&1 || got_rc=$?
    assert_eq "$got_rc" "$want_rc" "$msg"
}

printf '=== 1. Syntax & Packaging Checks ===\n'
if bash -n "$STATUS_SCRIPT"; then
    pass "bash -n security-status.sh"
else
    fail "bash -n security-status.sh"
fi
if bash -n "$HELPER_SCRIPT"; then
    pass "bash -n system-security"
else
    fail "bash -n system-security"
fi
if bash -n "$0"; then
    pass "bash -n system-security.test.sh"
else
    fail "bash -n system-security.test.sh"
fi

[[ -f $POLICY_FILE ]] || fail "polkit policy file missing"
if grep -q 'id="org.mainstreamos.system-security"' "$POLICY_FILE" && \
   grep -q '<allow_any>no</allow_any>' "$POLICY_FILE" && \
   grep -q '<allow_inactive>no</allow_inactive>' "$POLICY_FILE" && \
   grep -q '<allow_active>auth_admin_keep</allow_active>' "$POLICY_FILE" && \
   grep -q '/usr/lib/mainstream/system-security' "$POLICY_FILE"; then
    pass "polkit policy matches org.mainstreamos.system-security contract"
else
    fail "polkit policy matches org.mainstreamos.system-security contract"
fi

(
    source "$PKGBUILD_FILE"
    assert_eq "${#source[@]}" "${#sha256sums[@]}" "PKGBUILD source and sha256sums array lengths match (${#source[@]})"
    found_helper=0
    found_policy=0
    for s in "${source[@]}"; do
        [[ $s == "system-security" ]] && found_helper=1
        [[ $s == "org.mainstreamos.system-security.policy" ]] && found_policy=1
    done
    [[ $found_helper == 1 && $found_policy == 1 ]] || fail "PKGBUILD missing system-security or policy in source=()"
    found_jq=0
    for d in "${depends[@]}"; do
        [[ $d == "jq" ]] && found_jq=1
    done
    [[ $found_jq == 1 ]] || fail "PKGBUILD missing jq in depends=()"
)
pass "PKGBUILD includes system-security, policy, and jq dependency"

# Every field the probe may print and what each may hold. A field that is missing, or
# one that is not listed here, fails.
PROBE_SHAPE='
    (type == "object") and
    (keys == (["helper", "unsupportedReason", "uefi", "secureBoot", "setupMode",
               "sbctlInstalled", "sbctlKeysExist", "sbctlVerified", "signingKeysKept",
               "windowsDetected", "bitlockerDetected", "antiCheat"] | sort)) and
    ([.helper, .uefi, .secureBoot, .setupMode, .sbctlInstalled, .sbctlKeysExist,
      .sbctlVerified, .signingKeysKept, .windowsDetected, .bitlockerDetected]
        | all(type == "boolean")) and
    (.unsupportedReason | IN("", "snapshot", "boot-tools")) and
    (.antiCheat | type == "object") and
    (.antiCheat | keys == (["tpm2", "measuredBoot", "iommu", "iommuPassthrough",
                            "lockdown", "kexecDisabled", "bpfLsm", "kernelInstalled",
                            "startReady", "certificateEnrolled", "startedThroughIt"] | sort)) and
    (.antiCheat | [.tpm2, .measuredBoot, .iommu, .iommuPassthrough, .kexecDisabled, .bpfLsm,
                   .kernelInstalled, .startReady, .certificateEnrolled, .startedThroughIt]
        | all(type == "boolean")) and
    (.antiCheat.lockdown | IN("none", "integrity", "confidentiality", "unknown"))
'

printf '\n=== 2. Live security-status.sh Schema Verification ===\n'
live_json=$("$STATUS_SCRIPT")
assert_jq "$live_json" "$PROBE_SHAPE" "live security-status.sh prints exactly the agreed fields"

printf '\n=== 3. Mocked security-status.sh State Matrix ===\n'
S_ENV="$TMP_BASE/status-env"
S_BIN="$S_ENV/bin"
S_SBCTL="$S_ENV/bin-sbctl"
S_LIMINE="$S_ENV/bin-limine"
S_NONE="$S_ENV/none"
mkdir -p "$S_BIN" "$S_SBCTL" "$S_LIMINE" "$S_ENV/efivars" "$S_ENV/var/lib/mainstream"

# Write efivars helper (4-byte attributes header + 1-byte value)
write_efivar() {
    local path=$1 val=$2
    printf '\x07\x00\x00\x00' >"$path"
    if [[ $val == 1 ]]; then
        printf '\x01' >>"$path"
    else
        printf '\x00' >>"$path"
    fi
}

# The probe runs on these tools and the stand-ins beside them alone, so what is
# installed on the machine running the suite (sbctl, the Limine tools) decides nothing.
for tool in bash jq od tr grep awk head tail; do
    ln -s "$(command -v "$tool")" "$S_BIN/$tool"
done

printf 'btrfs\n' >"$S_ENV/root-fstype"
printf '/@\n' >"$S_ENV/root-subvol"
printf 'vfat\nbtrfs\n' >"$S_ENV/lsblk-fstypes"
cat >"$S_BIN/findmnt" <<EOF
#!/usr/bin/env bash
printf '%s %s\n' "\$(<"$S_ENV/root-fstype")" "\$(<"$S_ENV/root-subvol")"
EOF
cat >"$S_BIN/lsblk" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$(<"$S_ENV/lsblk-fstypes")"
EOF
cat >"$S_SBCTL/sbctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
for tool in limine-update limine-mkinitcpio limine-enroll-config; do
    cp "$S_SBCTL/sbctl" "$S_LIMINE/$tool"
done
chmod +x "$S_BIN/findmnt" "$S_BIN/lsblk" "$S_SBCTL/sbctl" "$S_LIMINE"/limine-*

# Every path the probe reads points at nothing until a scenario says otherwise.
probe() {  # the arguments are this run's settings, as NAME=value
    env -i PATH="$S_BIN" \
        SECURITY_HELPER="$S_NONE/system-security" \
        SECURITY_STATE_FILE="$S_NONE/security-state.json" \
        EFIVARS_DIR="$S_NONE/efivars" \
        LIMINE_DEFAULT_CONF="$S_NONE/limine" \
        TPM_VERSION_FILE="$S_NONE/tpm_version_major" \
        TPM_PCR_DIR="$S_NONE/pcr-sha256" \
        SYS_IOMMU_CLASS="$S_NONE/iommu" \
        SYS_IOMMU_GROUPS="$S_NONE/iommu_groups" \
        SYS_LOCKDOWN="$S_NONE/lockdown" \
        SYS_LSM="$S_NONE/lsm" \
        PROC_KEXEC_LOAD_DISABLED="$S_NONE/kexec_load_disabled" \
        SBCTL_DB_KEY="$S_NONE/db.key" \
        SBCTL_DB_KEY_ALT="$S_NONE/db.key.alt" \
        KEYS_KEPT_STAMP="$S_NONE/secure-boot-keys" \
        MODULES_DIR="$S_NONE/modules" \
        KERNEL_RELEASE="" \
        "$@" "$STATUS_SCRIPT"
}

S_STATE="$S_ENV/var/lib/mainstream/security-state.json"

# Scenario 3A: UEFI + SetupMode + BitLocker + a state file left by an earlier helper
write_efivar "$S_ENV/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c" 0
write_efivar "$S_ENV/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c" 1
printf 'vfat\nbtrfs\nBitLocker\n' >"$S_ENV/lsblk-fstypes"
cat >"$S_STATE" <<'EOF'
{
  "sbctlKeysExist": false,
  "sbctlVerified": false,
  "slots": {
    "synced": true,
    "tpm2": true,
    "passwordCount": 1
  },
  "lastSynced": "2026-11-19T05:00:00Z"
}
EOF

json_3a=$(probe SECURITY_HELPER="$HELPER_SCRIPT" SECURITY_STATE_FILE="$S_STATE" EFIVARS_DIR="$S_ENV/efivars")
assert_jq "$json_3a" '
    .helper == true and
    .uefi == true and
    .secureBoot == false and
    .setupMode == true and
    .sbctlInstalled == false and
    .sbctlKeysExist == false and
    .sbctlVerified == false and
    .signingKeysKept == false and
    .windowsDetected == true and
    .bitlockerDetected == true
' "Scenario 3A: SetupMode + BitLocker + no keys yet"
assert_jq "$json_3a" "$PROBE_SHAPE" "Scenario 3A: nothing else from the state file is passed on"
printf 'vfat\nbtrfs\n' >"$S_ENV/lsblk-fstypes"

# Scenario 3B: Secure Boot active + sbctl + verified boot files + kept keys
write_efivar "$S_ENV/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c" 1
write_efivar "$S_ENV/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c" 0
printf '{"sbctlKeysExist":true,"sbctlVerified":true,"lastSynced":"2026-11-19T05:00:00Z"}\n' >"$S_STATE"
touch "$S_ENV/db.key" "$S_ENV/secure-boot-keys"

json_3b=$(probe PATH="$S_SBCTL:$S_BIN" SECURITY_STATE_FILE="$S_STATE" EFIVARS_DIR="$S_ENV/efivars" \
                KEYS_KEPT_STAMP="$S_ENV/secure-boot-keys")
assert_jq "$json_3b" '
    .helper == false and
    .secureBoot == true and
    .setupMode == false and
    .sbctlInstalled == true and
    .sbctlKeysExist == true and
    .sbctlVerified == true and
    .signingKeysKept == true
' "Scenario 3B: Secure Boot active + keys and verification recorded by the helper"
assert_jq "$json_3b" "$PROBE_SHAPE" "Scenario 3B: exactly the agreed fields"

printf '{"sbctlKeysExist":false,"sbctlVerified":false}\n' >"$S_STATE"
assert_jq "$(probe SECURITY_STATE_FILE="$S_STATE" SBCTL_DB_KEY="$S_ENV/db.key")" \
    '.sbctlKeysExist == true and .sbctlVerified == false' \
    "Scenario 3B: a readable db.key counts as keys whatever the state file says"
assert_jq "$(probe SECURITY_STATE_FILE="$S_STATE" SBCTL_DB_KEY_ALT="$S_ENV/db.key")" \
    '.sbctlKeysExist == true' "Scenario 3B: so does a db.key in sbctl's older place"

# Scenario 3C: Legacy BIOS + a state file that cannot be trusted
printf 'NOT VALID JSON {{{{\n' >"$S_STATE"
json_3c=$(probe SECURITY_STATE_FILE="$S_STATE")
assert_jq "$json_3c" '
    .uefi == false and
    .secureBoot == false and
    .setupMode == false and
    .sbctlKeysExist == false and
    .sbctlVerified == false
' "Scenario 3C: Corrupt state JSON ignored + Legacy BIOS"
assert_jq "$json_3c" "$PROBE_SHAPE" "Scenario 3C: exactly the agreed fields"

printf '{"sbctlKeysExist":"yes","sbctlVerified":1}\n' >"$S_STATE"
assert_jq "$(probe SECURITY_STATE_FILE="$S_STATE")" \
    '.sbctlKeysExist == false and .sbctlVerified == false' \
    "Scenario 3C: state values that are not true or false count as false"
printf '[true, true]\n' >"$S_STATE"
assert_jq "$(probe SECURITY_STATE_FILE="$S_STATE")" \
    '.sbctlKeysExist == false and .sbctlVerified == false' \
    "Scenario 3C: a state file that is not an object is ignored"

# Scenario 3D: why the helper would refuse this system
assert_eq "$(probe | jq -r '.unsupportedReason')" "boot-tools" \
    "Scenario 3D: no Limine boot tools is reported as boot-tools"
assert_eq "$(probe PATH="$S_LIMINE:$S_BIN" | jq -r '.unsupportedReason')" "" \
    "Scenario 3D: an installed system with the Limine boot tools has no reason"
for tool in limine-update limine-mkinitcpio limine-enroll-config; do
    mv "$S_LIMINE/$tool" "$S_LIMINE/$tool.aside"
    assert_eq "$(probe PATH="$S_LIMINE:$S_BIN" | jq -r '.unsupportedReason')" "boot-tools" \
        "Scenario 3D: a missing $tool is reported as boot-tools"
    mv "$S_LIMINE/$tool.aside" "$S_LIMINE/$tool"
done
printf 'overlay\n' >"$S_ENV/root-fstype"
assert_eq "$(probe PATH="$S_LIMINE:$S_BIN" | jq -r '.unsupportedReason')" "snapshot" \
    "Scenario 3D: a system started from a snapshot is reported as snapshot"
assert_eq "$(probe | jq -r '.unsupportedReason')" "snapshot" \
    "Scenario 3D: snapshot comes before boot-tools, as in the helper"
printf 'btrfs\n' >"$S_ENV/root-fstype"
for subvol in /@/.snapshots/8/snapshot /.snapshots/8/snapshot /@.snapshots/12/snapshot /@snapshots/3/snapshot; do
    printf '%s\n' "$subvol" >"$S_ENV/root-subvol"
    assert_eq "$(probe PATH="$S_LIMINE:$S_BIN" | jq -r '.unsupportedReason')" "snapshot" \
        "Scenario 3D: a root on the snapshot subvolume $subvol is reported as snapshot"
done
assert_eq "$(probe | jq -r '.unsupportedReason')" "snapshot" \
    "Scenario 3D: a snapshot subvolume comes before boot-tools too"
for subvol in / /@ /@/.snapshots /@/.snapshots/8 /@/.snapshots/8/snapshot/etc \
              /@/.snapshots/x/snapshot /@/my.snapshots/8/snapshot /snapshots/8/snapshot; do
    printf '%s\n' "$subvol" >"$S_ENV/root-subvol"
    assert_eq "$(probe PATH="$S_LIMINE:$S_BIN" | jq -r '.unsupportedReason')" "" \
        "Scenario 3D: a root on $subvol is not taken for a snapshot"
done
printf '/@\n' >"$S_ENV/root-subvol"

# Scenario 3E: what an anti-cheat looks at
AC="$S_ENV/anticheat"
mkdir -p "$AC"

anticheat() {  # prints one antiCheat field for the given settings
    local field=$1
    shift
    probe "$@" | jq -c ".antiCheat.$field"
}

json_3e=$(probe)
assert_jq "$json_3e" '.antiCheat == {
    tpm2: false, measuredBoot: false, iommu: false, iommuPassthrough: false,
    lockdown: "unknown", kexecDisabled: false, bpfLsm: false,
    kernelInstalled: false, startReady: false, certificateEnrolled: false, startedThroughIt: false
}' "Scenario 3E: a machine with none of it reports nothing"
assert_jq "$json_3e" "$PROBE_SHAPE" "Scenario 3E: exactly the agreed fields"

printf '2\n' >"$AC/tpm_version_major"
assert_eq "$(anticheat tpm2 TPM_VERSION_FILE="$AC/tpm_version_major")" "true" "tpm2: a version 2 chip counts"
printf '1\n' >"$AC/tpm_version_1"
assert_eq "$(anticheat tpm2 TPM_VERSION_FILE="$AC/tpm_version_1")" "false" "tpm2: a TPM 1.2 does not count"
assert_eq "$(anticheat tpm2)" "false" "tpm2: no chip, or one switched off in the firmware"

PCR_ZERO=$(printf '0%.0s' {1..64})
PCR_MEASURED=$(printf '5A%.0s' {1..32})
write_pcrs() {  # the PCRs to leave measured; every other one reads all zeros
    local n
    rm -rf "$AC/pcr-sha256"
    mkdir -p "$AC/pcr-sha256"
    for n in {0..23}; do
        printf '%s\n' "$PCR_ZERO" >"$AC/pcr-sha256/$n"
    done
    for n in "$@"; do
        printf '%s\n' "$PCR_MEASURED" >"$AC/pcr-sha256/$n"
    done
}

write_pcrs
assert_eq "$(anticheat measuredBoot TPM_PCR_DIR="$AC/pcr-sha256")" "false" "measuredBoot: every PCR all zeros"
write_pcrs 0 1 2 3 4 5 6 7 10 13 14 15 16 17 18 19 20 21 22 23
assert_eq "$(anticheat measuredBoot TPM_PCR_DIR="$AC/pcr-sha256")" "false" \
    "measuredBoot: what the firmware measures by itself does not count"
for pcr in 8 9 11 12; do
    write_pcrs "$pcr"
    assert_eq "$(anticheat measuredBoot TPM_PCR_DIR="$AC/pcr-sha256")" "true" \
        "measuredBoot: PCR $pcr alone is enough"
done
write_pcrs 9 11 12
assert_eq "$(anticheat measuredBoot TPM_PCR_DIR="$AC/pcr-sha256")" "true" \
    "measuredBoot: a kernel image that measured itself"
rm -f "$AC/pcr-sha256"/*
assert_eq "$(anticheat measuredBoot TPM_PCR_DIR="$AC/pcr-sha256")" "false" "measuredBoot: missing PCR files"
: >"$AC/pcr-sha256/8"
printf 'unavailable\n' >"$AC/pcr-sha256/9"
assert_eq "$(anticheat measuredBoot TPM_PCR_DIR="$AC/pcr-sha256")" "false" \
    "measuredBoot: an empty PCR file, or one that holds no digest, is no measurement"

mkdir -p "$AC/iommu-empty" "$AC/iommu/dmar0" "$AC/groups-empty" "$AC/groups/0" "$AC/groups/1" "$AC/groups/2"
for group in 0 1 2; do
    printf 'DMA-FQ\n' >"$AC/groups/$group/type"
done
iommu_pair() {  # prints "iommu iommuPassthrough" for the given settings
    probe "$@" | jq -r '.antiCheat | "\(.iommu) \(.iommuPassthrough)"'
}
assert_eq "$(iommu_pair SYS_IOMMU_CLASS="$AC/iommu-empty" SYS_IOMMU_GROUPS="$AC/groups-empty")" "false false" \
    "iommu: none"
assert_eq "$(iommu_pair SYS_IOMMU_CLASS="$AC/iommu" SYS_IOMMU_GROUPS="$AC/groups-empty")" "false false" \
    "iommu: a unit with no groups is not an active one"
assert_eq "$(iommu_pair SYS_IOMMU_CLASS="$AC/iommu-empty" SYS_IOMMU_GROUPS="$AC/groups")" "false false" \
    "iommu: groups with no unit are not an active one"
assert_eq "$(iommu_pair SYS_IOMMU_CLASS="$AC/iommu" SYS_IOMMU_GROUPS="$AC/groups")" "true false" \
    "iommu: a unit and its groups, every group translated"
printf 'identity\n' >"$AC/groups/1/type"
assert_eq "$(iommu_pair SYS_IOMMU_CLASS="$AC/iommu" SYS_IOMMU_GROUPS="$AC/groups")" "true true" \
    "iommu: one group passed through"

for word in none integrity confidentiality; do
    line='none integrity confidentiality'
    printf '%s\n' "${line/$word/[$word]}" >"$AC/lockdown"
    assert_eq "$(anticheat lockdown SYS_LOCKDOWN="$AC/lockdown")" "\"$word\"" "lockdown: $word"
done
printf 'none integrity confidentiality\n' >"$AC/lockdown"
assert_eq "$(anticheat lockdown SYS_LOCKDOWN="$AC/lockdown")" '"unknown"' "lockdown: no word marked"
printf '[something-else]\n' >"$AC/lockdown"
assert_eq "$(anticheat lockdown SYS_LOCKDOWN="$AC/lockdown")" '"unknown"' "lockdown: a word nobody knows"
assert_eq "$(anticheat lockdown)" '"unknown"' "lockdown: no file"
printf 'none [integrity] confidentiality\n' >"$AC/lockdown"
chmod 000 "$AC/lockdown"
# Root reads the file whatever its mode says.
if [[ ! -r "$AC/lockdown" ]]; then
    assert_eq "$(anticheat lockdown SYS_LOCKDOWN="$AC/lockdown")" '"unknown"' "lockdown: a file that cannot be read"
fi
chmod 644 "$AC/lockdown"

printf '0\n' >"$AC/kexec_load_disabled"
assert_eq "$(anticheat kexecDisabled PROC_KEXEC_LOAD_DISABLED="$AC/kexec_load_disabled")" "false" "kexecDisabled: 0"
printf '1\n' >"$AC/kexec_load_disabled"
assert_eq "$(anticheat kexecDisabled PROC_KEXEC_LOAD_DISABLED="$AC/kexec_load_disabled")" "true" "kexecDisabled: 1"
assert_eq "$(anticheat kexecDisabled)" "false" "kexecDisabled: no file"

# The kernel ends this file without a newline.
printf 'capability,landlock,lockdown,yama,bpf' >"$AC/lsm"
assert_eq "$(anticheat bpfLsm SYS_LSM="$AC/lsm")" "true" "bpfLsm: bpf at the end of the list"
printf 'capability,bpf,landlock,yama' >"$AC/lsm"
assert_eq "$(anticheat bpfLsm SYS_LSM="$AC/lsm")" "true" "bpfLsm: bpf inside the list"
printf 'capability,landlock,lockdown,yama' >"$AC/lsm"
assert_eq "$(anticheat bpfLsm SYS_LSM="$AC/lsm")" "false" "bpfLsm: a list without bpf"
printf 'capability,bpfilter,yama,ebpf' >"$AC/lsm"
assert_eq "$(anticheat bpfLsm SYS_LSM="$AC/lsm")" "false" "bpfLsm: a name that only contains bpf does not count"
assert_eq "$(anticheat bpfLsm)" "false" "bpfLsm: no file"

# All of it at once, as on a machine with a TPM, a kernel image that measured itself,
# no IOMMU and the BPF security module.
write_pcrs 9 11 12
printf '[none] integrity confidentiality\n' >"$AC/lockdown"
printf '0\n' >"$AC/kexec_load_disabled"
printf 'capability,landlock,lockdown,yama,bpf' >"$AC/lsm"
json_3e=$(probe TPM_VERSION_FILE="$AC/tpm_version_major" TPM_PCR_DIR="$AC/pcr-sha256" SYS_LOCKDOWN="$AC/lockdown" \
                PROC_KEXEC_LOAD_DISABLED="$AC/kexec_load_disabled" SYS_LSM="$AC/lsm")
assert_jq "$json_3e" '.antiCheat == {
    tpm2: true, measuredBoot: true, iommu: false, iommuPassthrough: false,
    lockdown: "none", kexecDisabled: false, bpfLsm: true,
    kernelInstalled: false, startReady: false, certificateEnrolled: false, startedThroughIt: false
}' "Scenario 3E: every field together"
assert_jq "$json_3e" "$PROBE_SHAPE" "Scenario 3E: exactly the agreed fields with everything set"

printf '\n=== 4. Privileged Helper system-security Tests ===\n'

# Set up isolated test root and mocked system tools
T_ROOT="$TMP_BASE/root"
T_BIN="$TMP_BASE/mock-bin"
T_STATE="$TMP_BASE/mock-state"
mkdir -p "$T_BIN" "$T_STATE" \
         "$T_ROOT/etc/default" \
         "$T_ROOT/var/lib/mainstream" "$T_ROOT/var/log/mainstream" "$T_ROOT/run/lock" \
         "$T_ROOT/sys/firmware/efi/efivars" "$T_ROOT/boot/efi/EFI/limine" \
         "$T_ROOT/boot/efi/EFI/Linux" "$T_ROOT/boot/efi/EFI/BOOT" \
         "$T_ROOT/proc"

# Initial mock state files
printf 'btrfs\n' >"$T_STATE/fstype"
printf '/@\n' >"$T_STATE/subvol"
printf '0\n' >"$T_STATE/pacman_fail"
printf '0\n' >"$T_STATE/fail_fw_builtin"
printf '1\n' >"$T_STATE/sbctl_verify_ok"
printf '0\n' >"$T_STATE/sbctl_verify_unsigned_rc0"

: >"$T_ROOT/proc/mounts"

cat >"$T_ROOT/etc/default/limine" <<'EOF'
TARGET_OS_NAME="Mainstream OS\\"
ESP_PATH="/boot/efi"
ENABLE_UKI=yes
CUSTOM_UKI_NAME="mainstream"
EOF

cat >"$T_ROOT/etc/fstab" <<'EOF'
# /etc/fstab
UUID=7B6D-771B /boot/efi vfat defaults,umask=0077 0 2
UUID=3a2c52e5-9d08-4bc4-9ff3-2c2f14815f5c / btrfs subvol=@,defaults,noatime 0 0
EOF

ESP_T="$T_ROOT/boot/efi"
printf 'image_path: boot():/EFI/Linux/mainstream_linux.efi\n' >"$ESP_T/limine.conf"
printf 'Limine 12.10.0 with the menu checksum enrolled\n' >"$ESP_T/EFI/limine/limine_x64.efi"
printf 'Limine 12.10.0 as installed\n' >"$ESP_T/EFI/limine/BOOTX64.EFI"
printf 'Limine 12.10.0 as installed\n' >"$ESP_T/EFI/BOOT/BOOTX64.EFI"
touch "$ESP_T/EFI/Linux/mainstream_linux.efi" "$ESP_T/EFI/Linux/left-by-another-system.efi"
: >"$T_STATE/unsigned"
: >"$T_STATE/calls.log"

# Mock binaries
cat >"$T_BIN/findmnt" <<EOF
#!/usr/bin/env bash
echo "/dev/nvme0n1p2[\$(<"$T_STATE/subvol")] \$(<"$T_STATE/fstype") 3a2c52e5-9d08-4bc4-9ff3-2c2f14815f5c"
EOF

cat >"$T_BIN/pacman" <<EOF
#!/usr/bin/env bash
echo "pacman \$*" >>"$T_STATE/calls.log"
if [[ "\$1" == "-S" ]]; then
    [[ \$(<"$T_STATE/pacman_fail") == 1 ]] && exit 1
    if [[ "\$*" == *"sbctl"* ]]; then
        cp "$T_STATE/sbctl.template" "$T_BIN/sbctl"
        chmod +x "$T_BIN/sbctl"
    fi
    exit 0
fi
exit 0
EOF

cat >"$T_STATE/sbctl.template" <<EOF
#!/usr/bin/env bash
echo "sbctl \$*" >>"$T_STATE/calls.log"
case "\${1:-}" in
    status)
        if [[ -f "$T_ROOT/var/lib/sbctl/keys/db/db.key" ]]; then
            echo '{"installed": true}'
        else
            echo '{"installed": false}'
        fi
        ;;
    create-keys)
        mkdir -p "$T_ROOT/var/lib/sbctl/keys/db"
        touch "$T_ROOT/var/lib/sbctl/keys/db/db.key"
        ;;
    enroll-keys)
        if [[ "\$*" == *"--firmware-builtin"* && \$(<"$T_STATE/fail_fw_builtin") == 1 ]]; then
            echo "unsupported flag --firmware-builtin" >&2
            exit 1
        fi
        exit 0
        ;;
    sign)
        exit 0
        ;;
    verify)
        if [[ \$(<"$T_STATE/sbctl_verify_unsigned_rc0") == 1 ]] || grep -qxF -- "\${2:-}" "$T_STATE/unsigned"; then
            echo "✗ \${2:-/boot/efi/EFI/Linux/mainstream_linux.efi} is not signed"
            exit 0
        fi
        if [[ \$(<"$T_STATE/sbctl_verify_ok") == 1 ]]; then
            echo "✓ \${2:-/boot/efi/EFI/Linux/mainstream_linux.efi} is signed"
            exit 0
        fi
        echo "✗ \${2:-/boot/efi/EFI/Linux/mainstream_linux.efi} is not signed"
        exit 1
        ;;
esac
exit 0
EOF
cp "$T_STATE/sbctl.template" "$T_BIN/sbctl"

for tool in limine-install limine-update limine-mkinitcpio limine-enroll-config; do
    cat >"$T_BIN/$tool" <<EOF
#!/usr/bin/env bash
echo "$tool \$*" >>"$T_STATE/calls.log"
exit 0
EOF
    chmod +x "$T_BIN/$tool"
done

cat >"$T_BIN/mount" <<EOF
#!/usr/bin/env bash
echo "mount \$*" >>"$T_STATE/calls.log"
target="\${@: -1}"
if [[ "\$*" == *"subvolid=5"* ]]; then
    if [[ -d "$T_STATE/btrfs_top/@sbctl" ]]; then
        ln -s "$T_STATE/btrfs_top/@sbctl" "\$target/@sbctl"
    fi
elif [[ "\$*" == *"-o subvol=/@ "* ]]; then
    [[ \$(<"$T_STATE/newroot_mount_fail") == 1 ]] && exit 32
    cp -a "$T_STATE/newroot/." "\$target/"
elif [[ "\$*" == *"subvol=/@sbctl"* ]]; then
    rmdir "\$target"
    ln -s "$T_STATE/btrfs_top/@sbctl" "\$target"
    echo "/dev/nvme0n1p2 \$target btrfs rw 0 0" >>"$T_ROOT/proc/mounts"
fi
exit 0
EOF

cat >"$T_BIN/umount" <<EOF
#!/usr/bin/env bash
echo "umount \$*" >>"$T_STATE/calls.log"
target="\${@: -1}"
if [[ -f "$T_ROOT/proc/mounts" ]]; then
    grep -vF " \$target " "$T_ROOT/proc/mounts" >"$T_ROOT/proc/mounts.tmp" 2>/dev/null || true
    mv -f "$T_ROOT/proc/mounts.tmp" "$T_ROOT/proc/mounts"
fi
rm -f "\$target/@sbctl" 2>/dev/null || true
if [[ -e "\$target/.restored-root" ]]; then
    find "\$target" -mindepth 1 -delete
fi
exit 0
EOF

cat >"$T_BIN/chroot" <<EOF
#!/usr/bin/env bash
echo "chroot \$*" >>"$T_STATE/calls.log"
exit "\$(<"$T_STATE/chroot_rc")"
EOF

cat >"$T_BIN/btrfs" <<EOF
#!/usr/bin/env bash
echo "btrfs \$*" >>"$T_STATE/calls.log"
if [[ "\$1 \$2" == "subvolume create" && "\$3" == */@sbctl ]]; then
    mkdir -p "$T_STATE/btrfs_top/@sbctl"
    ln -s "$T_STATE/btrfs_top/@sbctl" "\$3"
    exit 0
fi
exit 0
EOF

chmod +x "$T_BIN/findmnt" "$T_BIN/pacman" "$T_BIN/sbctl" \
         "$T_BIN/mount" "$T_BIN/umount" "$T_BIN/btrfs" "$T_BIN/chroot"
printf '0\n' >"$T_STATE/chroot_rc"
printf '0\n' >"$T_STATE/newroot_mount_fail"

run_helper() {
    SYSTEM_SECURITY_TEST_ROOT="$T_ROOT" \
    SYSTEM_SECURITY_TEST_BIN="$T_BIN" \
    "$HELPER_SCRIPT" "$@"
}

run_helper_without_sbctl() {
    SYSTEM_SECURITY_TEST_NO_SBCTL=1 run_helper "$@"
}

STATE_JSON="$T_ROOT/var/lib/mainstream/security-state.json"
SB_VAR="$T_ROOT/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
SETUP_VAR="$T_ROOT/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c"

check() {  # $1 = message; the rest is a command that must succeed
    local msg=$1
    shift
    if "$@"; then
        pass "$msg"
    else
        fail "$msg"
    fi
}

refute() {  # $1 = message; the rest is a command that must fail
    local msg=$1
    shift
    if "$@"; then
        fail "$msg"
    else
        pass "$msg"
    fi
}

calls() {  # how many logged tool calls match $1
    grep -c -- "$1" "$T_STATE/calls.log" || true
}

call_line() {  # the line of the first logged tool call matching $1
    grep -n -- "$1" "$T_STATE/calls.log" | head -n1 | cut -d: -f1
}

stderr_of() {
    "$@" 2>&1 >/dev/null || true
}

limine_default_has() {
    grep -q -- "$1" "$T_ROOT/etc/default/limine"
}

run_copies() {
    SYSTEM_SECURITY_TEST_BIN="$T_BIN" MAINSTREAM_ESP="$ESP_T" \
    MAINSTREAM_SBCTL_KEYS="$T_ROOT/var/lib/sbctl/keys/db/db.key" \
        "$SCRIPT_DIR/limine-signed-copies"
}

# 4.1 Bad usage
expect_rc 2 "unknown subcommand exits 2" run_helper bogus-cmd
expect_rc 2 "no subcommand exits 2" run_helper
for verb in sb-enable-enroll sb-disable-enroll recovery-generate recovery-remove \
            tpm2-enroll tpm2-remove fido2-enroll fido2-remove hibernate-enable hibernate-disable; do
    expect_rc 2 "$verb is not a subcommand" run_helper "$verb"
done
check "a refused subcommand runs nothing" test ! -s "$T_STATE/calls.log"
for verb in status-sync sb-enable sb-sign sb-restore sb-after-restore; do
    expect_rc 2 "$verb takes no arguments" run_helper "$verb" --force
done

# 4.2 sb-enable preconditions
rm -rf "$T_ROOT/sys/firmware/efi/efivars"
expect_rc 3 "sb-enable on Legacy BIOS exits 3" run_helper sb-enable
check "the reason for a refusal reaches stderr" \
    grep -q '^system-security: Secure Boot requires UEFI firmware' <<<"$(stderr_of run_helper sb-enable)"

mkdir -p "$T_ROOT/sys/firmware/efi/efivars"
write_efivar "$SB_VAR" 0
write_efivar "$SETUP_VAR" 0
expect_rc 3 "sb-enable when SetupMode=0 exits 3" run_helper sb-enable

write_efivar "$SETUP_VAR" 1
echo overlay >"$T_STATE/fstype"
: >"$T_STATE/calls.log"
expect_rc 3 "sb-enable started from a snapshot exits 3" run_helper sb-enable
check "nothing is installed, created or enrolled from a snapshot" test "$(calls '^sbctl\|^pacman -S')" = 0
for verb in sb-sign sb-restore; do
    check "$verb is refused from a snapshot too" \
        grep -q '^system-security: started from a snapshot' <<<"$(stderr_of run_helper "$verb")"
done
check "nothing is rebuilt or signed from a snapshot" test "$(calls '^limine-\|^sbctl')" = 0
echo btrfs >"$T_STATE/fstype"

# The boot menu starts a snapshot on its own read-only subvolume, with no overlay.
for subvol in /@/.snapshots/8/snapshot /.snapshots/8/snapshot; do
    echo "$subvol" >"$T_STATE/subvol"
    : >"$T_STATE/calls.log"
    for verb in sb-enable sb-sign sb-restore; do
        expect_rc 3 "$verb started on the snapshot subvolume $subvol exits 3" run_helper "$verb"
        check "$verb on $subvol names the snapshot as the reason" \
            grep -q '^system-security: started from a snapshot' <<<"$(stderr_of run_helper "$verb")"
    done
    check "nothing is installed, rebuilt, signed or mounted on $subvol" \
        test "$(calls '^limine-\|^sbctl\|^pacman -S\|^mount\|^btrfs')" = 0
done
echo /@ >"$T_STATE/subvol"

rm -f "$T_BIN/sbctl"
echo 1 >"$T_STATE/pacman_fail"
expect_rc 4 "sb-enable exits 4 when pacman fails to install sbctl" \
    run_helper_without_sbctl sb-enable
echo 0 >"$T_STATE/pacman_fail"

expect_rc 3 "sb-sign exits 3 while sbctl is not installed" run_helper_without_sbctl sb-sign
expect_rc 3 "sb-restore exits 3 while sbctl is not installed" run_helper_without_sbctl sb-restore
check "status-sync succeeds while sbctl is not installed" run_helper_without_sbctl status-sync
assert_jq "$(<"$STATE_JSON")" '
    .sbctlKeysExist == false and .sbctlVerified == false and
    (.lastSynced | type == "string") and
    (keys == ["antiCheatCaEnrolled", "antiCheatReady", "lastSynced", "sbctlKeysExist", "sbctlVerified"])
' "status-sync records no keys and nothing verified, and nothing else"

# 4.3 A boot file that is not signed stops sb-enable before the firmware is touched
echo 1 >"$T_STATE/fail_fw_builtin"
printf '%s\n' "$ESP_T/EFI/Linux/mainstream_linux.efi" >"$T_STATE/unsigned"
: >"$T_STATE/calls.log"
expect_rc 1 "sb-enable exits 1 when a boot image is left unsigned" \
    run_helper_without_sbctl sb-enable
check "no keys are enrolled while a boot file is unsigned" test "$(calls '^sbctl enroll-keys')" = 0
check "the keys subvolume is in place before the keys are made" \
    test "$(call_line '^mount .*subvol=/@sbctl')" -lt "$(call_line '^sbctl create-keys')"
: >"$T_STATE/unsigned"

# 4.4 sb-enable
: >"$T_STATE/calls.log"
check "sb-enable succeeds once every boot file is signed" run_helper sb-enable
check "sb-enable turns on Limine config enrollment" limine_default_has '^ENABLE_ENROLL_LIMINE_CONFIG=yes$'
check "sb-enable keeps the other Limine settings, backslashes included" \
    limine_default_has '^TARGET_OS_NAME="Mainstream OS\\\\"$'
update_at=$(call_line '^limine-update')
verify_at=$(call_line '^sbctl verify')
enroll_at=$(call_line '^sbctl enroll-keys')
check "sb-enable enrolls keys only after the boot files are rebuilt and checked" \
    test "${update_at:-0}" -gt 0 -a "${update_at:-0}" -lt "${verify_at:-0}" -a "${verify_at:-0}" -lt "${enroll_at:-0}"
check "sb-enable falls back to enrolling beside Microsoft's keys alone" test "$(calls '^sbctl enroll-keys --microsoft$')" = 1
check "no copy of Limine is signed as it is" test "$(calls '^sbctl sign')" = 0
check "the default-path copy is the enrolled file" \
    cmp -s "$ESP_T/EFI/limine/limine_x64.efi" "$ESP_T/EFI/BOOT/BOOTX64.EFI"
check "the installer's copy is the enrolled file" \
    cmp -s "$ESP_T/EFI/limine/limine_x64.efi" "$ESP_T/EFI/limine/BOOTX64.EFI"
check "the image the boot menu names is checked" test "$(calls '^sbctl verify .*mainstream_linux\.efi')" -ge 1
check "an image the boot menu does not name is not judged" test "$(calls 'left-by-another-system')" = 0
assert_jq "$(<"$STATE_JSON")" '
    .sbctlKeysExist == true and .sbctlVerified == true and
    (keys == ["antiCheatCaEnrolled", "antiCheatReady", "lastSynced", "sbctlKeysExist", "sbctlVerified"])
' "sb-enable records that keys exist and the boot files are verified"
check "the signing keys are made on their own subvolume" test -f "$T_STATE/btrfs_top/@sbctl/keys/db/db.key"
check "the keys subvolume is mounted from /etc/fstab, and a missing one does not stop a start" \
    grep -q '^UUID=3a2c52e5-9d08-4bc4-9ff3-2c2f14815f5c /var/lib/sbctl btrfs subvol=/@sbctl,noatime,nofail 0 0$' "$T_ROOT/etc/fstab"
check "a note that the keys are kept is left beside the log" test -s "$T_ROOT/var/log/mainstream/secure-boot-keys"

# ASUS and Gigabyte boards get Microsoft's keys beside the owner's, never their own as well.
echo 0 >"$T_STATE/fail_fw_builtin"
mkdir -p "$T_ROOT/sys/class/dmi/id"
printf 'Gigabyte Technology Co., Ltd.\n' >"$T_ROOT/sys/class/dmi/id/board_vendor"
: >"$T_STATE/calls.log"
check "sb-enable on a Gigabyte board succeeds" run_helper sb-enable
check "and enrolls without the board's built-in keys" \
    test "$(calls '^sbctl enroll-keys --microsoft$')" = 1 -a "$(calls 'firmware-builtin')" = 0
rm -f "$T_ROOT/sys/class/dmi/id/board_vendor"
echo 1 >"$T_STATE/fail_fw_builtin"

# From here on the firmware enforces Secure Boot, as after turning it on in UEFI setup.
write_efivar "$SETUP_VAR" 0
write_efivar "$SB_VAR" 1

# 4.5 sb-sign and the copies
: >"$T_STATE/calls.log"
check "sb-sign succeeds when keys exist" run_helper sb-sign
check "sb-sign rebuilds and checks the boot files, and enrolls nothing" \
    test "$(calls '^limine-update')" = 1 -a "$(calls '^sbctl verify')" -ge 1 -a "$(calls '^sbctl enroll-keys\|^sbctl create-keys')" = 0

echo 1 >"$T_STATE/sbctl_verify_unsigned_rc0"
expect_rc 1 "sb-sign fails when sbctl verify exits 0 but reports a file as not signed" run_helper sb-sign
run_helper status-sync
assert_jq "$(<"$STATE_JSON")" '.sbctlKeysExist == true and .sbctlVerified == false' \
    "status-sync records an unsigned boot file"
echo 0 >"$T_STATE/sbctl_verify_unsigned_rc0"
run_helper status-sync
assert_jq "$(<"$STATE_JSON")" '.sbctlKeysExist == true and .sbctlVerified == true' \
    "status-sync records the boot files as verified again"

printf 'another system loader\n' >"$ESP_T/EFI/BOOT/BOOTX64.EFI"
printf 'Limine 12.10.0 after a menu change\n' >"$ESP_T/EFI/limine/limine_x64.efi"
run_copies >/dev/null
check "another system's loader on the default path is left alone" \
    grep -q 'another system loader' "$ESP_T/EFI/BOOT/BOOTX64.EFI"
check "a copy of Limine follows the enrolled file" \
    cmp -s "$ESP_T/EFI/limine/limine_x64.efi" "$ESP_T/EFI/limine/BOOTX64.EFI"
printf 'Limine 12.10.0 as installed\n' >"$ESP_T/EFI/BOOT/BOOTX64.EFI"
printf '%s\n' "$ESP_T/EFI/limine/limine_x64.efi" >"$T_STATE/unsigned"
expect_rc 1 "the copies tool reports an enrolled file that is not signed" run_copies
check "an unsigned file is never copied over the others" grep -q 'as installed' "$ESP_T/EFI/BOOT/BOOTX64.EFI"
: >"$T_STATE/unsigned"

run_helper sb-sign
check "sb-sign brings the copies in line" \
    cmp -s "$ESP_T/EFI/limine/limine_x64.efi" "$ESP_T/EFI/BOOT/BOOTX64.EFI"

# 4.6 A snapshot from before Secure Boot was set up: no keys in sight, no fstab line, no setting
restored_root() {
    rm -f "$T_ROOT/var/lib/sbctl"
    mkdir -p "$T_ROOT/var/lib/sbctl"
    grep -v ' /var/lib/sbctl ' "$T_ROOT/etc/fstab" >"$T_ROOT/etc/fstab.new" || true
    mv -f "$T_ROOT/etc/fstab.new" "$T_ROOT/etc/fstab"
    grep -v " $T_ROOT/var/lib/sbctl " "$T_ROOT/proc/mounts" >"$T_ROOT/proc/mounts.new" || true
    mv -f "$T_ROOT/proc/mounts.new" "$T_ROOT/proc/mounts"
    sed -i '/^ENABLE_ENROLL_LIMINE_CONFIG=/d' "$T_ROOT/etc/default/limine"
}

expect_rc 3 "sb-restore does nothing on a system that has its keys" run_helper sb-restore
restored_root
: >"$T_STATE/calls.log"
check "sb-restore succeeds when the keys were kept" run_helper sb-restore
check "sb-restore mounts the kept keys again" test -f "$T_ROOT/var/lib/sbctl/keys/db/db.key"
check "sb-restore puts the keys mount back in /etc/fstab" grep -q ' /var/lib/sbctl btrfs subvol=/@sbctl,' "$T_ROOT/etc/fstab"
check "sb-restore turns Limine config enrollment back on" limine_default_has '^ENABLE_ENROLL_LIMINE_CONFIG=yes$'
check "sb-restore rebuilds, signs and checks the boot files" \
    test "$(calls '^limine-update')" = 1 -a "$(calls '^sbctl verify')" -ge 1
check "sb-restore makes no new keys and enrolls nothing" test "$(calls '^sbctl create-keys\|^sbctl enroll-keys')" = 0
assert_jq "$(<"$STATE_JSON")" '.sbctlKeysExist == true and .sbctlVerified == true' \
    "sb-restore records the keys and the verified boot files"

restored_root
mv "$T_STATE/btrfs_top/@sbctl" "$T_STATE/btrfs_top/@sbctl.aside"
: >"$T_STATE/calls.log"
expect_rc 3 "sb-restore exits 3 when no keys were kept" run_helper sb-restore
check "sb-restore changes nothing when no keys were kept" test "$(calls '^limine-update')" = 0
refute "sb-restore leaves /etc/fstab alone when no keys were kept" grep -q ' /var/lib/sbctl ' "$T_ROOT/etc/fstab"
refute "sb-restore leaves the Limine settings alone when no keys were kept" \
    limine_default_has '^ENABLE_ENROLL_LIMINE_CONFIG='
expect_rc 3 "sb-sign exits 3 when the signing keys are not in sight" run_helper sb-sign

# Keys made by hand before the subvolume existed move into it when Secure Boot is set up.
mkdir -p "$T_ROOT/var/lib/sbctl/keys/db"
printf 'made by hand\n' >"$T_ROOT/var/lib/sbctl/keys/db/db.key"
write_efivar "$SB_VAR" 0
write_efivar "$SETUP_VAR" 1
: >"$T_STATE/calls.log"
run_helper sb-enable
check "keys that predate the subvolume are moved into it" \
    grep -q 'made by hand' "$T_STATE/btrfs_top/@sbctl/keys/db/db.key"
check "keys that already exist are kept, not made again" test "$(calls '^sbctl create-keys')" = 0
rm -rf "$T_STATE/btrfs_top/@sbctl.aside"

chmod 555 "$T_ROOT/etc/default"
: >"$T_STATE/calls.log"
expect_rc 1 "a setting that cannot be written stops the helper" run_helper sb-enable
check "nothing runs after a failed write" test "$(calls '^limine-\|^sbctl enroll-keys')" = 0
chmod 755 "$T_ROOT/etc/default"

# 4.7 A symlink in place of a file the helper writes is refused and left alone
SYM_TARGET="$TMP_BASE/symlink-victim"
printf 'ORIGINAL_CONTENT\n' >"$SYM_TARGET"

refuses_symlink() {  # $1 = path under the test root; the rest is the helper call to try
    local path="$T_ROOT$1"
    shift
    mv "$path" "$path.real"
    ln -s "$SYM_TARGET" "$path"
    expect_rc 1 "a symlink at ${path#"$T_ROOT"} is refused" "$@"
    assert_eq "$(<"$SYM_TARGET")" "ORIGINAL_CONTENT" "the file behind ${path#"$T_ROOT"} is untouched"
    rm -f "$path"
    mv "$path.real" "$path"
}

refuses_symlink /etc/default/limine run_helper sb-enable
refuses_symlink /etc/default/limine run_helper sb-restore
refuses_symlink /etc/fstab run_helper sb-enable
refuses_symlink /etc/fstab run_helper sb-restore
refuses_symlink /var/lib/mainstream/security-state.json run_helper status-sync
refuses_symlink /var/lib/mainstream/security-state.json run_helper sb-sign
refuses_symlink /var/log/mainstream/system-security.log run_helper status-sync
refuses_symlink /run/lock/mainstream-system-security.lock run_helper status-sync

# 4.8 After a snapshot restore, inside the snapshot session
STAMP="$T_ROOT/var/log/mainstream/secure-boot-keys"
NEWROOT="$T_STATE/newroot"
PACKAGED="$T_ROOT/usr/share/limine/BOOTX64.EFI"
mkdir -p "$NEWROOT/usr/lib/mainstream" "$NEWROOT/usr/bin" "$NEWROOT/proc" "$NEWROOT/sys" \
         "$NEWROOT/dev" "$NEWROOT/run" "$NEWROOT/tmp" "$NEWROOT/var/log" "$NEWROOT/boot/efi" \
         "$T_ROOT/usr/share/limine" "$T_ROOT/run/udev"
: >"$NEWROOT/.restored-root"
for f in usr/lib/mainstream/system-security usr/bin/sbctl usr/bin/limine-update; do
    printf '#!/bin/sh\n' >"$NEWROOT/$f"
    chmod +x "$NEWROOT/$f"
done
printf 'Limine 12.10.0 as packaged\n' >"$PACKAGED"

enrolled_loaders() {  # the state a restore finds: three copies holding the old menu checksum
    local f
    for f in EFI/limine/limine_x64.efi EFI/limine/BOOTX64.EFI EFI/BOOT/BOOTX64.EFI; do
        printf 'Limine 12.10.0 with the menu checksum enrolled\n' >"$ESP_T/$f"
    done
}
loaders_are() {  # $1 = the first line every copy must hold
    local f
    for f in EFI/limine/limine_x64.efi EFI/limine/BOOTX64.EFI EFI/BOOT/BOOTX64.EFI; do
        [[ $(<"$ESP_T/$f") == "$1" ]] || return 1
    done
}
after_restore() {  # resets the stand-ins, then runs the step; the arguments set this run up
    enrolled_loaders
    printf '0\n' >"$T_STATE/chroot_rc"
    printf '0\n' >"$T_STATE/newroot_mount_fail"
    printf '/@/.snapshots/6/snapshot\n' >"$T_STATE/subvol"
    date >"$STAMP"
    : >"$T_STATE/calls.log"
    local setup
    for setup in "$@"; do eval "$setup"; done
    AR_ERR=$(run_helper sb-after-restore 2>&1 >/dev/null) && AR_RC=0 || AR_RC=$?
    printf '/@\n' >"$T_STATE/subvol"
}

after_restore 'rm -f "$STAMP"'
assert_eq "$AR_RC" 0 "sb-after-restore exits 0 where signing was never set up"
check "sb-after-restore touches nothing where signing was never set up" \
    test "$(calls '^mount\|^chroot')" = 0
check "the loaders are left alone where signing was never set up" \
    loaders_are 'Limine 12.10.0 with the menu checksum enrolled'

after_restore 'printf "/@\n" >"$T_STATE/subvol"'
assert_eq "$AR_RC" 3 "sb-after-restore exits 3 in the installed system"
check "sb-after-restore changes nothing in the installed system" \
    test "$(calls '^mount\|^chroot')" = 0
check "the loaders are left alone in the installed system" \
    loaders_are 'Limine 12.10.0 with the menu checksum enrolled'

after_restore
assert_eq "$AR_RC" 0 "sb-after-restore succeeds when the restored system signs its boot files"
check "it mounts the subvolume the snapshot was restored into" \
    test "$(calls '^mount -o subvol=/@ /dev/nvme0n1p2 ')" = 1
check "it gives the restored system the EFI partition" \
    test "$(calls "^mount --bind $ESP_T .*/boot/efi\$")" = 1
check "it gives the restored system the log folder that holds the keys stamp" \
    test "$(calls "^mount --bind $T_ROOT/var/log .*/var/log\$")" = 1
check "it gives the restored system the device database" \
    test "$(calls "^mount --bind $T_ROOT/run/udev .*/run/udev\$")" = 1
check "it runs the restore of signing inside the restored system" \
    test "$(calls '^chroot [^ ]* /usr/lib/mainstream/system-security sb-restore$')" = 1
check "it unmounts the restored system afterwards" test "$(calls '^umount -R ')" -ge 1
check "the loaders are left to the restored system's own tools" \
    loaders_are 'Limine 12.10.0 with the menu checksum enrolled'
check "the mounts come before the work and the unmount after it" \
    test "$(call_line '^mount --bind')" -lt "$(call_line '^chroot')" -a \
         "$(call_line '^chroot')" -lt "$(call_line '^umount -R')"

after_restore 'printf "1\n" >"$T_STATE/chroot_rc"'
assert_eq "$AR_RC" 5 "sb-after-restore exits 5 when signing fails in the restored system"
check "every copy of Limine is then the packaged one without a checksum" \
    loaders_are 'Limine 12.10.0 as packaged'
check "the reason says to turn Secure Boot off" grep -q 'turn Secure Boot off in UEFI setup' <<<"$AR_ERR"
check "no half-written loader is left behind" test -z "$(find "$ESP_T" -name '*.new')"

after_restore 'printf "1\n" >"$T_STATE/chroot_rc"' 'printf "another system loader\n" >"$ESP_T/EFI/BOOT/BOOTX64.EFI"'
assert_eq "$AR_RC" 5 "sb-after-restore exits 5 beside another system's loader"
assert_eq "$(<"$ESP_T/EFI/BOOT/BOOTX64.EFI")" "another system loader" \
    "another system's loader on the default path is left alone"
assert_eq "$(<"$ESP_T/EFI/limine/limine_x64.efi")" "Limine 12.10.0 as packaged" \
    "the Limine the firmware entry names still loses its checksum"

after_restore 'mv "$NEWROOT/usr/bin/sbctl" "$NEWROOT/usr/bin/sbctl.aside"'
mv "$NEWROOT/usr/bin/sbctl.aside" "$NEWROOT/usr/bin/sbctl"
assert_eq "$AR_RC" 5 "sb-after-restore exits 5 when the restored system has no sbctl"
check "nothing is run in a restored system without sbctl" test "$(calls '^chroot')" = 0
check "a restored system without sbctl still gets loaders that start" loaders_are 'Limine 12.10.0 as packaged'

after_restore 'printf "1\n" >"$T_STATE/newroot_mount_fail"'
assert_eq "$AR_RC" 5 "sb-after-restore exits 5 when the restored system cannot be mounted"
check "nothing is run when the restored system cannot be mounted" test "$(calls '^chroot')" = 0
check "loaders that start are still put in place" loaders_are 'Limine 12.10.0 as packaged'

after_restore 'printf "/@snapshots/6/snapshot\n" >"$T_STATE/subvol"'
assert_eq "$AR_RC" 5 "sb-after-restore exits 5 on a snapshot layout it cannot follow"
check "it mounts nothing on a layout it cannot follow" test "$(calls '^mount\|^chroot')" = 0
check "loaders that start are put in place on that layout too" loaders_are 'Limine 12.10.0 as packaged'

after_restore 'printf "1\n" >"$T_STATE/chroot_rc"' 'mv "$PACKAGED" "$PACKAGED.aside"'
mv "$PACKAGED.aside" "$PACKAGED"
assert_eq "$AR_RC" 1 "sb-after-restore exits 1 when it has no loader to put in place"
check "the reason says not to restart" grep -q 'do not restart' <<<"$AR_ERR"
check "the loaders are left as they were" loaders_are 'Limine 12.10.0 with the menu checksum enrolled'

after_restore 'printf "1\n" >"$T_STATE/chroot_rc"' 'chmod 555 "$ESP_T/EFI/BOOT"'
chmod 755 "$ESP_T/EFI/BOOT"
assert_eq "$AR_RC" 1 "sb-after-restore exits 1 when a loader cannot be replaced"
check "no temporary directory is left mounted" test -z "$(find "${TMPDIR:-/tmp}" -maxdepth 2 -name .restored-root 2>/dev/null)"
enrolled_loaders
rm -f "$STAMP"


printf '\n=== 5. The anti-cheat start ===\n'

# The ESP is its own partition here, with a PARTUUID the firmware entries name.
cat >"$T_BIN/findmnt" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == *SOURCE* && "\${@: -1}" == "$ESP_T" ]]; then
    echo /dev/nvme0n1p1
    exit 0
fi
echo "/dev/nvme0n1p2[\$(<"$T_STATE/subvol")] \$(<"$T_STATE/fstype") 3a2c52e5-9d08-4bc4-9ff3-2c2f14815f5c"
EOF
cat >"$T_BIN/lsblk" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *PARTUUID*) echo 5a1f0b2c-7e3d-4c8a-9b1e-0123456789ab ;;
    *PKNAME*) echo nvme0n1 ;;
esac
EOF
mkdir -p "$T_ROOT/sys/class/block/nvme0n1p1"
echo 1 >"$T_ROOT/sys/class/block/nvme0n1p1/partition"
: >"$T_STATE/efi_entries"
cat >"$T_BIN/efibootmgr" <<EOF
#!/usr/bin/env bash
echo "efibootmgr \$*" >>"$T_STATE/calls.log"
args=" \$* "
if [[ \$args == *" --create-only "* ]]; then
    label="" loader=""
    while (( \$# )); do
        case \$1 in --label) label=\$2; shift ;; --loader) loader=\$2; shift ;; esac
        shift
    done
    printf 'Boot000A* %s\tHD(1,GPT,5A1F0B2C-7E3D-4C8A-9B1E-0123456789AB,0x800,0x100000)/%s\n' "\$label" "\$loader" >>"$T_STATE/efi_entries"
    exit 0
fi
if [[ \$args == *" --delete-bootnum "* ]]; then
    : >"$T_STATE/efi_entries"
    exit 0
fi
[[ \$args == *" --bootnext "* || \$args == *" --delete-bootnext "* ]] && exit 0
echo "BootCurrent: 0001"
printf 'Boot0001* Mainstream\tHD(1,GPT,5A1F0B2C-7E3D-4C8A-9B1E-0123456789AB,0x800,0x100000)/\\\\EFI\\\\limine\\\\limine_x64.efi\n'
cat "$T_STATE/efi_entries"
EOF
# Every file Mainstream signed says so; "and the owner too" stands for a second signature.
cat >"$T_BIN/sbverify" <<'EOF'
#!/usr/bin/env bash
file=${@: -1}
if [[ $1 == --list ]]; then
    echo "signature 1"
    grep -q 'and the owner too' "$file" && echo "signature 2"
    exit 0
fi
grep -q 'signed by Mainstream' "$file"
EOF
echo 0 >"$T_STATE/mkinitcpio_fail"
cat >"$T_BIN/mkinitcpio" <<EOF
#!/usr/bin/env bash
echo "mkinitcpio \$*" >>"$T_STATE/calls.log"
[[ \$(<"$T_STATE/mkinitcpio_fail") == 1 ]] && exit 1
out="" rel=""
while (( \$# )); do
    case \$1 in -g) out=\$2; shift ;; -k) rel=\$2; shift ;; esac
    shift
done
echo "initramfs for \$rel" >"\$out"
EOF
echo 0 >"$T_STATE/reboot_rc"
cat >"$T_BIN/systemctl" <<EOF
#!/usr/bin/env bash
echo "systemctl \$*" >>"$T_STATE/calls.log"
[[ \$1 == reboot ]] && exit "\$(<"$T_STATE/reboot_rc")"
exit 0
EOF
mkdir -p "$T_STATE/enrolled_db"
: >"$T_STATE/sbctl_files"
cat >"$T_BIN/sbctl" <<EOF
#!/usr/bin/env bash
echo "sbctl \$*" >>"$T_STATE/calls.log"
args=" \$* "
if [[ \$args == *" export-enrolled-keys "* ]]; then
    dir=\${@: -1}
    mkdir -p "\$dir/DB"
    cp "$T_STATE/enrolled_db/." "\$dir/DB/" -r 2>/dev/null
    exit 0
fi
case "\${1:-}" in
    status)
        if [[ -f "$T_ROOT/var/lib/sbctl/keys/db/db.key" ]]; then
            echo '{"installed": true}'
        else
            echo '{"installed": false}'
        fi
        ;;
    enroll-keys)
        [[ \$args == *" --append "* ]] && cp "$T_ROOT/var/lib/sbctl/keys/custom/db/"*.der "$T_STATE/enrolled_db/"
        ;;
    list-files) cat "$T_STATE/sbctl_files" ;;
    verify) echo "✓ \${2:-} is signed" ;;
esac
exit 0
EOF
echo mainstream-performance-eac >"$T_STATE/installed_pkgs"
cat >"$T_BIN/pacman" <<EOF
#!/usr/bin/env bash
echo "pacman \$*" >>"$T_STATE/calls.log"
if [[ \$1 == -Qq ]]; then
    grep -qxF -- "\${@: -1}" "$T_STATE/installed_pkgs" && echo "\${@: -1}"
    exit 0
fi
[[ \$1 == -S && \$(<"$T_STATE/pacman_fail") == 1 ]] && exit 1
exit 0
EOF
chmod +x "$T_BIN/findmnt" "$T_BIN/lsblk" "$T_BIN/efibootmgr" "$T_BIN/sbverify" "$T_BIN/mkinitcpio" \
         "$T_BIN/systemctl" "$T_BIN/sbctl" "$T_BIN/pacman"

AC_REL=7.3.6-arch1-3-mainstream-performance-eac
AC_MODS="$T_ROOT/usr/lib/modules/$AC_REL"
AC_ON_ESP="$ESP_T/EFI/mainstream-eac"
AC_ENTRY_FILE="$ESP_T/loader/entries/mainstream-eac.conf"
mkdir -p "$T_ROOT/usr/share/mainstream-eac" "$T_ROOT/usr/lib/mainstream/anticheat" "$T_ROOT/etc/kernel" \
         "$T_ROOT/var/lib/sbctl/keys/db"
printf 'the CA\n' >"$T_ROOT/usr/share/mainstream-eac/mainstream-secure-boot-ca.crt"
printf 'the CA in DER\n' >"$T_ROOT/usr/share/mainstream-eac/mainstream-secure-boot-ca.der"
printf 'systemd-boot, signed by Mainstream\n' >"$T_ROOT/usr/lib/mainstream/anticheat/systemd-bootx64.efi"
touch "$T_ROOT/var/lib/sbctl/keys/db/db.key"
printf 'root=UUID=3a2c52e5 rw rootflags=subvol=@ quiet resume=UUID=9f1c resume_offset=533760 lockdown=none\n' \
    >"$T_ROOT/etc/kernel/cmdline"
write_efivar "$SETUP_VAR" 0
printf 'btrfs\n' >"$T_STATE/fstype"
printf '/@\n' >"$T_STATE/subvol"
ac_kernel() {  # $1 = what the packaged kernel says about itself
    mkdir -p "$AC_MODS"
    printf '%s\n' "$1" >"$AC_MODS/vmlinuz"
    echo mainstream-performance-eac >"$AC_MODS/pkgbase"
}

: >"$T_STATE/calls.log"
expect_rc 3 "ac-setup without the anti-cheat kernel exits 3" run_helper ac-setup
check "the reason names the kernel" grep -q 'install the anti-cheat kernel first' <<<"$(stderr_of run_helper ac-setup)"
ac_kernel 'kernel 1, signed by Mainstream'
write_efivar "$SETUP_VAR" 1
expect_rc 3 "ac-setup while the firmware is in Setup Mode exits 3" run_helper ac-setup
write_efivar "$SETUP_VAR" 0
mv "$T_ROOT/var/lib/sbctl/keys/db/db.key" "$T_STATE/db.key.aside"
expect_rc 3 "ac-setup before Secure Boot is set up exits 3" run_helper ac-setup
mv "$T_STATE/db.key.aside" "$T_ROOT/var/lib/sbctl/keys/db/db.key"
check "nothing is installed or enrolled before then" test "$(calls '^pacman -S\|enroll-keys\|efibootmgr --create')" = 0

printf '%s\n' "$AC_ON_ESP/vmlinuz" "/boot/efi/EFI/Linux/mainstream_linux.efi" >"$T_STATE/sbctl_files"
: >"$T_STATE/calls.log"
check "ac-setup succeeds" run_helper ac-setup
check "it installs the certificate, the signed systemd-boot and their tools" \
    test "$(calls '^pacman -S --needed --noconfirm mainstream-eac-signing-key systemd-boot-mainstream-signed sbsigntools efibootmgr$')" = 1
check "the certificate is handed to sbctl as a custom db key" \
    cmp -s "$T_ROOT/usr/share/mainstream-eac/mainstream-secure-boot-ca.der" \
           "$T_ROOT/var/lib/sbctl/keys/custom/db/mainstream-secure-boot-ca.der"
check "and appended to the firmware's db with the owner's keys" \
    test "$(calls '^sbctl enroll-keys --append --partial db --custom --ignore-immutable$')" = 1
check "systemd-boot is copied as packaged" \
    cmp -s "$T_ROOT/usr/lib/mainstream/anticheat/systemd-bootx64.efi" "$AC_ON_ESP/systemd-bootx64.efi"
check "the kernel is copied as packaged" cmp -s "$AC_MODS/vmlinuz" "$AC_ON_ESP/vmlinuz"
assert_eq "$(<"$AC_ON_ESP/initramfs.img")" "initramfs for $AC_REL" "its initramfs is built for that kernel"
check "without the post hooks, so sbctl never signs the packaged kernel" test "$(calls "^mkinitcpio --nopost -k $AC_REL -g ")" = 1
assert_eq "$(sed -n 's/^options //p' "$AC_ENTRY_FILE")" \
    "root=UUID=3a2c52e5 rw rootflags=subvol=@ quiet lockdown=integrity lsm=landlock,lockdown,yama,integrity,bpf iommu.passthrough=0 intel_iommu=on module.sig_enforce=1 sysctl.kernel.kexec_load_disabled=1" \
    "the entry keeps the system's options, drops resume and its own old ones, and adds the anti-cheat set"
check "the entry starts the copied kernel" grep -qx 'linux   /EFI/mainstream-eac/vmlinuz' "$AC_ENTRY_FILE"
check "systemd-boot starts that entry at once and lets nobody edit it" \
    test "$(cat "$ESP_T/loader/loader.conf")" = "$(printf '# Mainstream OS anti-cheat start\ndefault mainstream-eac.conf\ntimeout 0\neditor no')"
check "a firmware entry is made, outside the boot order" \
    test "$(calls '^efibootmgr --quiet --create-only --disk /dev/nvme0n1 --part 1 --label Mainstream OS (Anti-Cheat) --loader \\EFI\\mainstream-eac\\systemd-bootx64.efi$')" = 1
check "a copy sbctl had on its list is taken off it" test "$(calls "^sbctl remove-file $AC_ON_ESP/vmlinuz$")" = 1
check "and the owner's own images stay on it" test "$(calls 'remove-file /boot/efi/EFI/Linux')" = 0
assert_jq "$(<"$STATE_JSON")" '.antiCheatReady == true and .antiCheatCaEnrolled == true' \
    "the state records the start as ready and the certificate as enrolled"

: >"$T_STATE/calls.log"
check "ac-setup a second time succeeds" run_helper ac-setup
check "and neither enrolls nor makes a firmware entry again" test "$(calls 'enroll-keys\|efibootmgr --quiet --create')" = 0

ac_kernel 'kernel 2, signed by Mainstream and the owner too'
expect_rc 1 "a kernel that carries a second signature is refused" run_helper ac-setup
ac_kernel 'kernel 2, signed by Mainstream'

printf 'default arch.conf\ntimeout 3\n' >"$ESP_T/loader/loader.conf"
check "ac-setup beside another system's systemd-boot succeeds" run_helper ac-setup
assert_eq "$(<"$ESP_T/loader/loader.conf")" "$(printf 'default arch.conf\ntimeout 3')" "that system's loader.conf is left alone"

: >"$T_STATE/calls.log"
check "ac-start restarts into the start" run_helper ac-start
check "it names the anti-cheat firmware entry for the next start alone" test "$(calls '^efibootmgr --quiet --bootnext 000A$')" = 1
check "and restarts" test "$(calls '^systemctl reboot$')" = 1
ONESHOT="$T_ROOT/sys/firmware/efi/efivars/LoaderEntryOneShot-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f"
assert_eq "$(tail -c +5 "$ONESHOT" | iconv -f UTF-16LE -t UTF-8 | tr -d '\0')" "mainstream-eac.conf" \
    "beside another loader.conf, systemd-boot is told the entry through its one-shot variable"
echo 1 >"$T_STATE/reboot_rc"
: >"$T_STATE/calls.log"
expect_rc 1 "a restart that does not happen fails" run_helper ac-start
check "and takes the choice back" test "$(calls '^efibootmgr --quiet --delete-bootnext$')" = 1
echo 0 >"$T_STATE/reboot_rc"
rm -f "$ESP_T/loader/loader.conf" "$ONESHOT"
run_helper ac-setup

: >"$T_STATE/calls.log"
ac_kernel 'kernel 3, signed by Mainstream'
check "ac-refresh follows a kernel update" run_helper ac-refresh
check "with the new kernel copied" cmp -s "$AC_MODS/vmlinuz" "$AC_ON_ESP/vmlinuz"
check "and its initramfs built again" test "$(calls '^mkinitcpio --nopost')" = 1
echo 1 >"$T_STATE/mkinitcpio_fail"
expect_rc 1 "an initramfs that does not build is reported" run_helper ac-refresh
check "and leaves the one it had" test "$(<"$AC_ON_ESP/initramfs.img")" = "initramfs for $AC_REL"
echo 0 >"$T_STATE/mkinitcpio_fail"
# limine-snapper-sync runs the boot hooks where the kernels' files cannot be seen and the
# firmware's variables cannot be written: the start stays as it is.
mv "$AC_MODS" "$T_STATE/hidden-kernel"
: >"$T_STATE/calls.log"
check "ac-refresh where the kernel files cannot be seen succeeds" run_helper ac-refresh
check "and takes nothing away" test -e "$AC_ON_ESP/vmlinuz" -a -e "$AC_ENTRY_FILE" -a -s "$T_STATE/efi_entries"
check "and changes nothing" test "$(calls '^efibootmgr --quiet\|^mkinitcpio')" = 0
mv "$T_STATE/hidden-kernel" "$AC_MODS"
rm -rf "$AC_MODS"
: >"$T_STATE/installed_pkgs"
check "ac-refresh after the kernel is removed succeeds" run_helper ac-refresh
refute "and takes the start off the EFI partition" test -e "$AC_ON_ESP"
check "with its entry, its loader.conf and its firmware entry" \
    test ! -e "$AC_ENTRY_FILE" -a ! -e "$ESP_T/loader/loader.conf" -a ! -s "$T_STATE/efi_entries"
: >"$T_STATE/calls.log"
check "ac-refresh where nothing is set up does nothing" run_helper ac-refresh
check "not even a build" test ! -s "$T_STATE/calls.log"

ac_kernel 'kernel 3, signed by Mainstream'
echo mainstream-performance-eac >"$T_STATE/installed_pkgs"
run_helper ac-setup
assert_jq "$(env -i PATH="$S_BIN" SECURITY_STATE_FILE="$STATE_JSON" SECURITY_HELPER="$S_NONE/x" \
                 EFIVARS_DIR="$S_NONE/efivars" MODULES_DIR="$S_NONE/modules" KERNEL_RELEASE="" "$STATUS_SCRIPT")" \
    '.antiCheat.startReady == true and .antiCheat.certificateEnrolled == true' \
    "the probe passes on what the helper recorded about the start"
check "ac-remove succeeds" run_helper ac-remove
check "and leaves nothing of the start behind" \
    test ! -e "$AC_ON_ESP" -a ! -e "$AC_ENTRY_FILE" -a ! -s "$T_STATE/efi_entries"
assert_jq "$(<"$STATE_JSON")" '.antiCheatReady == false and .antiCheatCaEnrolled == true' \
    "the state records the start as gone, with the certificate still enrolled"
expect_rc 3 "ac-start with nothing set up exits 3" run_helper ac-start


printf '\nAll %d tests passed.\n' "$PASS_COUNT"
