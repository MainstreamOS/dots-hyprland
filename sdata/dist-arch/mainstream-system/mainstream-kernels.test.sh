#!/usr/bin/env bash
# mainstream-kernels.test.sh: unit and integration test suite for
# dots/.config/quickshell/ii/scripts/security/kernel-status.sh and
# sdata/dist-arch/mainstream-system/mainstream-kernels.
#
# Everything runs on temporary directories and stand-ins: no package is installed or
# removed and no firmware variable is written.
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
STATUS_SCRIPT="$REPO_ROOT/dots/.config/quickshell/ii/scripts/security/kernel-status.sh"
HELPER_SCRIPT="$SCRIPT_DIR/mainstream-kernels"
POLICY_FILE="$SCRIPT_DIR/org.mainstreamos.kernels.policy"
PKGBUILD_FILE="$SCRIPT_DIR/PKGBUILD"

PASS_COUNT=0

TMP_BASE="$(mktemp -d)"
cleanup() {
    # A test that fails while a directory is read-only would otherwise leave it behind.
    find "$TMP_BASE" ! -perm -u+w -exec chmod u+w {} + 2>/dev/null || true
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

stderr_of() {
    "$@" 2>&1 >/dev/null || true
}

V3_FLAGS='fpu vme sse sse2 ssse3 fma cx16 sse4_1 sse4_2 movbe popcnt xsave avx f16c lahf_lm abm bmi1 avx2 bmi2 rdseed'
write_cpuinfo() {  # $1 = file, $2 = the flags
    printf 'processor\t: 0\nvendor_id\t: GenuineIntel\nflags\t\t: %s\nbogomips\t: 4800.00\n' "$2" >"$1"
}

ENTRY_GUID=03884334-1756-4978-9c8c-86fb8998b4ea
# The menu's parent entry as Limine records it on an installed system.
MENU_PARENT='Mainstream OS\\\\'
write_entry_var() {  # $1 = file, $2 = the entry's path in the menu
    printf '\x07\x00\x00\x00%s\0' "$2" >"$1"
}
entry_var_is() {  # $1 = file, $2 = the entry it must hold, byte for byte
    cmp -s "$1" <(printf '\x07\x00\x00\x00%s\0' "$2")
}

printf '=== 1. Syntax & Packaging Checks ===\n'
for script in "$STATUS_SCRIPT" "$HELPER_SCRIPT" "$0"; do
    if bash -n "$script"; then
        pass "bash -n ${script##*/}"
    else
        fail "bash -n ${script##*/}"
    fi
done
check "the helper is executable" test -x "$HELPER_SCRIPT"

[[ -f $POLICY_FILE ]] || fail "polkit policy file missing"
if grep -q 'id="org.mainstreamos.kernels"' "$POLICY_FILE" && \
   grep -q '<allow_any>no</allow_any>' "$POLICY_FILE" && \
   grep -q '<allow_inactive>no</allow_inactive>' "$POLICY_FILE" && \
   grep -q '<allow_active>auth_admin_keep</allow_active>' "$POLICY_FILE" && \
   grep -q '>/usr/lib/mainstream/mainstream-kernels<' "$POLICY_FILE"; then
    pass "polkit policy matches the org.mainstreamos.kernels contract"
else
    fail "polkit policy matches the org.mainstreamos.kernels contract"
fi

(
    source "$PKGBUILD_FILE"
    assert_eq "${#source[@]}" "${#sha256sums[@]}" "PKGBUILD source and sha256sums array lengths match (${#source[@]})"
    found_helper=0
    found_policy=0
    for s in "${source[@]}"; do
        [[ $s == "mainstream-kernels" ]] && found_helper=1
        [[ $s == "org.mainstreamos.kernels.policy" ]] && found_policy=1
    done
    [[ $found_helper == 1 && $found_policy == 1 ]] || fail "PKGBUILD missing mainstream-kernels or its policy in source=()"
)
pass "PKGBUILD lists mainstream-kernels and its policy"
check "PKGBUILD installs the helper where the policy names it" \
    grep -q 'install -Dm755 "$srcdir/mainstream-kernels" *"$pkgdir/usr/lib/mainstream/mainstream-kernels"' "$PKGBUILD_FILE"
check "PKGBUILD installs the policy among the polkit actions" \
    grep -q '"$pkgdir/usr/share/polkit-1/actions/org.mainstreamos.kernels.policy"' "$PKGBUILD_FILE"

# Every field the probe may print and what each may hold. A field that is missing, or
# one that is not listed here, fails.
PROBE_SHAPE='
    (type == "object") and
    (keys == (["helper", "canChangeStandard", "unsupportedReason", "uefi", "espFreeBytes",
               "standardImageBytes", "nextKernel", "canChooseNext", "installedKernels",
               "kernels"] | sort)) and
    ([.helper, .canChangeStandard, .uefi, .canChooseNext] | all(type == "boolean")) and
    (.unsupportedReason | IN("", "snapshot", "boot-tools")) and
    ([.espFreeBytes, .standardImageBytes] | all(type == "number" or type == "null")) and
    (.nextKernel | type == "string") and
    (.installedKernels | type == "array" and all(type == "string")) and
    ([.kernels[].name] == ["linux", "linux-mainstream", "linux-mainstream-performance"]) and
    (.kernels | all(
        (keys == (["name", "installed", "version", "running", "available", "cpuSupported",
                   "downloadBytes", "driverMissing"] | sort)) and
        ([.installed, .running, .available, .cpuSupported, .driverMissing] | all(type == "boolean")) and
        (.version | type == "string") and
        (.downloadBytes | type == "number" or type == "null")))
'

printf '\n=== 2. Live kernel-status.sh Schema Verification ===\n'
live_json=$("$STATUS_SCRIPT")
assert_jq "$live_json" "$PROBE_SHAPE" "live kernel-status.sh prints exactly the agreed fields"

printf '\n=== 3. Mocked kernel-status.sh State Matrix ===\n'
S_ENV="$TMP_BASE/status-env"
S_BIN="$S_ENV/bin"
S_LIMINE="$S_ENV/bin-limine"
S_NONE="$S_ENV/none"
S_MODULES="$S_ENV/modules"
S_ESP="$S_ENV/esp"
mkdir -p "$S_BIN" "$S_LIMINE" "$S_ENV/efivars" "$S_MODULES" "$S_ESP/EFI/Linux"

# The probe runs on these tools and the stand-ins beside them alone, so what is
# installed on the machine running the suite decides nothing.
for tool in bash jq od tr grep awk head tail stat; do
    ln -s "$(command -v "$tool")" "$S_BIN/$tool"
done

printf 'btrfs\n' >"$S_ENV/root-fstype"
printf '/@\n' >"$S_ENV/root-subvol"
printf '7.3.5-arch1-1\n' >"$S_ENV/release"
printf '928555008\n' >"$S_ENV/esp-avail"
: >"$S_ENV/installed"
: >"$S_ENV/repo"

cat >"$S_BIN/findmnt" <<STUB_END
#!/usr/bin/env bash
[[ "\$*" == *"-M"* ]] && exit 1
printf '%s %s\n' "\$(<"$S_ENV/root-fstype")" "\$(<"$S_ENV/root-subvol")"
STUB_END
cat >"$S_BIN/uname" <<STUB_END
#!/usr/bin/env bash
printf '%s\n' "\$(<"$S_ENV/release")"
STUB_END
cat >"$S_BIN/df" <<STUB_END
#!/usr/bin/env bash
printf '    Avail\n%s\n' "\$(<"$S_ENV/esp-avail")"
STUB_END
# installed: "<name> <version>" lines. repo: "<name> <download size> <unit>" lines.
# plan-<kernel>: what installing that kernel with its headers would fetch, "<name> <bytes>" lines.
cat >"$S_BIN/pacman" <<STUB_END
#!/usr/bin/env bash
op=\$1
shift
[[ \${1:-} == -- ]] && shift
case \$op in
    -Q)
        grep -m1 -- "^\$1 " "$S_ENV/installed" || exit 1 ;;
    -Si)
        rc=0
        for name in "\$@"; do
            if line=\$(grep -m1 -- "^\$name " "$S_ENV/repo"); then
                read -r _ size unit <<<"\$line"
                printf 'Repository      : mainstream\nName            : %s\nVersion         : 7.3.5-1\n' "\$name"
                printf 'Download Size   : %s %s\nInstalled Size  : 150.00 MiB\n\n' "\$size" "\$unit"
            else
                echo "error: package '\$name' was not found" >&2
                rc=1
            fi
        done
        exit \$rc ;;
    -Sp)
        if [[ "\$*" != "--needed --print-format %n %s -- \${5:-} \${5:-}-headers" ]]; then
            echo "the probe must only ask what a kernel and its headers would fetch: pacman -Sp \$*" >&2
            exit 99
        fi
        if [[ ! -f "$S_ENV/plan-\$5" ]]; then
            echo "error: target not found: \$5" >&2
            exit 1
        fi
        grep -- '' "$S_ENV/plan-\$5" || true ;;
    *)
        echo "the probe must only query: pacman \$op \$*" >&2
        exit 99 ;;
esac
STUB_END
cat >"$S_LIMINE/limine-update" <<'STUB_END'
#!/usr/bin/env bash
exit 0
STUB_END
cp "$S_LIMINE/limine-update" "$S_LIMINE/limine-mkinitcpio"
cp "$S_LIMINE/limine-update" "$S_LIMINE/limine-enroll-config"
chmod +x "$S_BIN/findmnt" "$S_BIN/uname" "$S_BIN/df" "$S_BIN/pacman" "$S_LIMINE"/limine-*

S_CPU="$S_ENV/cpuinfo"
write_cpuinfo "$S_CPU" "$V3_FLAGS"
S_VAR="$S_ENV/efivars/LimineLastBootedEntry-$ENTRY_GUID"

s_tree() {  # $1 = release, $2 = package: a kernel this stand-in system can start
    mkdir -p "$S_MODULES/$1"
    : >"$S_MODULES/$1/vmlinuz"
    printf '%s\n' "$2" >"$S_MODULES/$1/pkgbase"
}

# Every path the probe reads points at nothing until a scenario says otherwise.
probe() {  # the arguments are this run's settings, as NAME=value
    env -i PATH="$S_LIMINE:$S_BIN" \
        KERNELS_HELPER="$S_NONE/mainstream-kernels" \
        EFIVARS_DIR="$S_NONE/efivars" \
        LIMINE_DEFAULT_CONF="$S_NONE/limine" \
        MODULES_DIR="$S_MODULES" \
        PROC_CPUINFO="$S_CPU" \
        ESP_CANDIDATES="$S_NONE/esp" \
        "$@" "$STATUS_SCRIPT"
}
kernel_field() {  # $1 = json, $2 = kernel, $3 = field
    jq -c --arg k "$2" ".kernels[] | select(.name == \$k) | .$3" <<<"$1"
}

# Scenario 3A: a fresh system. Only the standard kernel, both others on offer.
s_tree 7.3.5-arch1-1 linux
printf 'linux 7.3.5.arch1-1\nlinux-headers 7.3.5.arch1-1\n' >"$S_ENV/installed"
cat >"$S_ENV/repo" <<'REPO_END'
linux 151.12 MiB
linux-headers 30.00 MiB
linux-mainstream 150.00 MiB
linux-mainstream-headers 30.50 MiB
linux-mainstream-performance 160.25 MiB
linux-mainstream-performance-headers 512.00 KiB
REPO_END
printf 'linux-mainstream 157286400\nlinux-mainstream-headers 31981568\n' >"$S_ENV/plan-linux-mainstream"
cat >"$S_ENV/plan-linux-mainstream-performance" <<'PLAN_END'
llvm-libs 13000000
clang 60000000
lld 5000000
linux-mainstream-performance 168034304
linux-mainstream-performance-headers 524288
PLAN_END
write_entry_var "$S_VAR" "$MENU_PARENT/linux"
json_3a=$(probe KERNELS_HELPER="$HELPER_SCRIPT" EFIVARS_DIR="$S_ENV/efivars" ESP_CANDIDATES="$S_ESP")
assert_jq "$json_3a" "$PROBE_SHAPE" "Scenario 3A: exactly the agreed fields"
assert_jq "$json_3a" '
    .helper == true and .canChangeStandard == true and .unsupportedReason == "" and .uefi == true and
    .nextKernel == "linux" and .canChooseNext == true and
    .espFreeBytes == 928555008 and .standardImageBytes == null
' "Scenario 3A: an installed UEFI system whose menu starts the standard kernel next"
assert_jq "$json_3a" '.kernels[0] == {
    name: "linux", installed: true, version: "7.3.5.arch1-1", running: true, available: true,
    cpuSupported: true, downloadBytes: null, driverMissing: false
}' "Scenario 3A: the standard kernel is installed and running"
assert_jq "$json_3a" '.kernels[1] == {
    name: "linux-mainstream", installed: false, version: "", running: false, available: true,
    cpuSupported: true, downloadBytes: 189267968, driverMissing: false
}' "Scenario 3A: the Mainstream kernel is on offer, with the size of it and its headers"
assert_eq "$(kernel_field "$json_3a" linux-mainstream-performance downloadBytes)" "246558592" \
    "Scenario 3A: packages the headers pull in are counted in the download"
assert_jq "$json_3a" '.kernels | all(.installed == (.name == "linux"))' \
    "Scenario 3A: nothing else is installed"
assert_jq "$json_3a" '.installedKernels == ["linux"]' \
    "Scenario 3A: the standard kernel is the only kernel this system can start"

# An older helper refuses to install or remove the standard kernel, and says so in its text.
printf '#!/usr/bin/env bash\ndie 8 "the standard kernel stays installed as the fallback"\n' >"$S_ENV/old-helper"
chmod +x "$S_ENV/old-helper"
assert_jq "$(probe KERNELS_HELPER="$S_ENV/old-helper")" '.helper == true and .canChangeStandard == false' \
    "Scenario 3A: an older helper cannot change the standard kernel"
assert_jq "$(probe)" '.helper == false and .canChangeStandard == false' \
    "Scenario 3A: with no helper, nothing can change the standard kernel"

# What the install would fetch is not always known; the kernel stays on offer without a size.
mv "$S_ENV/plan-linux-mainstream" "$S_ENV/plan.kept"
json_3a=$(probe)
assert_jq "$json_3a" '.kernels[1] | .available == true and .downloadBytes == null' \
    "Scenario 3A: a kernel pacman cannot plan for is on offer with no download size"
assert_eq "$(kernel_field "$json_3a" linux-mainstream-performance downloadBytes)" "246558592" \
    "Scenario 3A: and the other kernel keeps its size"
printf 'linux-mainstream 157286400\nlinux-mainstream-headers unknown\n' >"$S_ENV/plan-linux-mainstream"
assert_eq "$(kernel_field "$(probe)" linux-mainstream downloadBytes)" "null" \
    "Scenario 3A: a size that is not a number gives no download size"
: >"$S_ENV/plan-linux-mainstream"
assert_eq "$(kernel_field "$(probe)" linux-mainstream downloadBytes)" "null" \
    "Scenario 3A: nothing to fetch gives no download size"
mv "$S_ENV/plan.kept" "$S_ENV/plan-linux-mainstream"

# Scenario 3B: both Mainstream kernels installed, one of them running.
s_tree 7.3.5-arch1-1-mainstream linux-mainstream
s_tree 7.3.5-1-mainstream-performance linux-mainstream-performance
cat >>"$S_ENV/installed" <<'INSTALLED_END'
linux-mainstream 7.3.5-1
linux-mainstream-headers 7.3.5-1
linux-mainstream-performance 7.3.5-1
linux-mainstream-performance-headers 7.3.5-1
INSTALLED_END
printf '7.3.5-1-mainstream-performance\n' >"$S_ENV/release"
write_entry_var "$S_VAR" "$MENU_PARENT/linux-mainstream-performance"
: >"$S_ESP/EFI/Linux/mainstream_linux.efi"
truncate -s 37322752 "$S_ESP/EFI/Linux/mainstream_linux.efi"
truncate -s 99999999 "$S_ESP/EFI/Linux/mainstream_linux-mainstream.efi"
json_3b=$(probe EFIVARS_DIR="$S_ENV/efivars" ESP_CANDIDATES="$S_ESP")
assert_jq "$json_3b" "$PROBE_SHAPE" "Scenario 3B: exactly the agreed fields"
assert_jq "$json_3b" '
    (.kernels | all(.installed)) and
    ([.kernels[] | select(.running) | .name] == ["linux-mainstream-performance"]) and
    .nextKernel == "linux-mainstream-performance" and .canChooseNext == true and .helper == false
' "Scenario 3B: all three installed, the performance kernel running and started next"
assert_eq "$(kernel_field "$json_3b" linux-mainstream version)" '"7.3.5-1"' "Scenario 3B: the installed version is read"
assert_jq "$json_3b" '(.installedKernels | sort) == ["linux", "linux-mainstream", "linux-mainstream-performance"]' \
    "Scenario 3B: every kernel this system can start is listed"
assert_jq "$json_3b" '.kernels | all(.downloadBytes == null)' "Scenario 3B: an installed kernel has no download size"
assert_jq "$json_3b" '.standardImageBytes == 99999999' \
    "Scenario 3B: the largest boot image of the installed kernels is measured"
truncate -s 123456789 "$S_ESP/EFI/Linux/mainstream_linux-zen.efi"
assert_eq "$(probe ESP_CANDIDATES="$S_ESP" | jq -c '.standardImageBytes')" "99999999" \
    "Scenario 3B: the image of a kernel that is not installed is not measured"
rm "$S_ESP/EFI/Linux/mainstream_linux-zen.efi"

# The running kernel's module tree is gone after its package was updated under it.
mv "$S_MODULES/7.3.5-1-mainstream-performance" "$S_MODULES/7.3.6-1-mainstream-performance"
assert_eq "$(probe | jq -c '[.kernels[] | select(.running) | .name]')" '["linux-mainstream-performance"]' \
    "Scenario 3B: a running kernel whose module tree is gone is still recognized"
printf '7.3.5-arch1-1-mainstream\n' >"$S_ENV/release"
mv "$S_MODULES/7.3.5-arch1-1-mainstream" "$S_MODULES/aside"
assert_eq "$(probe | jq -c '[.kernels[] | select(.running) | .name]')" '["linux-mainstream"]' \
    "Scenario 3B: the same for the Mainstream kernel"
mv "$S_MODULES/aside" "$S_MODULES/7.3.5-arch1-1-mainstream"
mv "$S_MODULES/7.3.6-1-mainstream-performance" "$S_MODULES/7.3.5-1-mainstream-performance"
printf '6.12.1-1-lts\n' >"$S_ENV/release"
assert_eq "$(probe | jq -c '[.kernels[] | select(.running) | .name]')" '[]' \
    "Scenario 3B: a kernel that is none of the three is nobody's running kernel"
printf '7.3.5-arch1-1\n' >"$S_ENV/release"

# A package without a kernel image under it cannot be started.
rm "$S_MODULES/7.3.5-arch1-1-mainstream/vmlinuz"
assert_eq "$(kernel_field "$(probe)" linux-mainstream installed)" "false" \
    "Scenario 3B: a kernel package with no kernel image does not count as installed"
assert_jq "$(probe)" '.installedKernels | index("linux-mainstream") == null' \
    "Scenario 3B: and is not listed among the kernels this system can start"
: >"$S_MODULES/7.3.5-arch1-1-mainstream/vmlinuz"

# The NVIDIA module, where the DKMS driver and the prebuilt driver put it.
mkdir -p "$S_MODULES/7.3.5-arch1-1/extramodules" "$S_MODULES/7.3.5-arch1-1-mainstream/updates/dkms"
assert_jq "$(probe)" '.kernels | all(.driverMissing == false)' \
    "Scenario 3B: no kernel has an NVIDIA module, so none is missing one"
: >"$S_MODULES/7.3.5-arch1-1/extramodules/nvidia.ko.zst"
: >"$S_MODULES/7.3.5-arch1-1-mainstream/updates/dkms/nvidia.ko.zst"
assert_eq "$(probe | jq -c '[.kernels[] | select(.driverMissing) | .name]')" '["linux-mainstream-performance"]' \
    "Scenario 3B: the one kernel without the NVIDIA module the others have is reported"
rm "$S_MODULES/7.3.5-arch1-1/extramodules/nvidia.ko.zst" "$S_MODULES/7.3.5-arch1-1-mainstream/updates/dkms/nvidia.ko.zst"

# Scenario 3C: a processor without AVX2.
write_cpuinfo "$S_CPU" "${V3_FLAGS/ avx2/}"
json_3c=$(probe)
assert_jq "$json_3c" "$PROBE_SHAPE" "Scenario 3C: exactly the agreed fields"
assert_jq "$json_3c" '[.kernels[] | .cpuSupported] == [true, true, false]' \
    "Scenario 3C: a processor without AVX2 cannot run the performance kernel, and runs the others"
for flag in avx bmi1 bmi2 f16c fma movbe xsave; do
    write_cpuinfo "$S_CPU" "${V3_FLAGS/ $flag / }"
    assert_eq "$(kernel_field "$(probe)" linux-mainstream-performance cpuSupported)" "false" \
        "Scenario 3C: a processor without $flag cannot run the performance kernel"
done
write_cpuinfo "$S_CPU" "${V3_FLAGS/ abm / lzcnt }"
assert_eq "$(kernel_field "$(probe)" linux-mainstream-performance cpuSupported)" "true" \
    "Scenario 3C: lzcnt stands for abm"
write_cpuinfo "$S_CPU" "${V3_FLAGS/ abm / }"
assert_eq "$(kernel_field "$(probe)" linux-mainstream-performance cpuSupported)" "false" \
    "Scenario 3C: neither abm nor lzcnt"
write_cpuinfo "$S_CPU" "${V3_FLAGS/ avx2 / avx2_extra }"
assert_eq "$(kernel_field "$(probe)" linux-mainstream-performance cpuSupported)" "false" \
    "Scenario 3C: a flag that only starts with avx2 does not count"
assert_eq "$(kernel_field "$(probe PROC_CPUINFO="$S_NONE/cpuinfo")" linux-mainstream-performance cpuSupported)" "false" \
    "Scenario 3C: a processor that cannot be read is not taken to be able"
write_cpuinfo "$S_CPU" "$V3_FLAGS"

# Scenario 3D: why the helper would refuse this system.
printf 'overlay\n' >"$S_ENV/root-fstype"
json_3d=$(probe)
assert_jq "$json_3d" "$PROBE_SHAPE" "Scenario 3D: exactly the agreed fields"
assert_eq "$(jq -r '.unsupportedReason' <<<"$json_3d")" "snapshot" \
    "Scenario 3D: a system started from a snapshot is reported as snapshot"
assert_eq "$(probe PATH="$S_BIN" | jq -r '.unsupportedReason')" "snapshot" \
    "Scenario 3D: snapshot comes before boot-tools, as in the helper"
printf 'btrfs\n' >"$S_ENV/root-fstype"
for subvol in /@/.snapshots/8/snapshot /.snapshots/8/snapshot /@.snapshots/12/snapshot /@snapshots/3/snapshot; do
    printf '%s\n' "$subvol" >"$S_ENV/root-subvol"
    assert_eq "$(probe | jq -r '.unsupportedReason')" "snapshot" \
        "Scenario 3D: a root on the snapshot subvolume $subvol is reported as snapshot"
done
for subvol in / /@ /@/.snapshots/8 /@/.snapshots/x/snapshot /snapshots/8/snapshot; do
    printf '%s\n' "$subvol" >"$S_ENV/root-subvol"
    assert_eq "$(probe | jq -r '.unsupportedReason')" "" \
        "Scenario 3D: a root on $subvol is not taken for a snapshot"
done
printf '/@\n' >"$S_ENV/root-subvol"
assert_eq "$(probe PATH="$S_BIN" | jq -r '.unsupportedReason')" "boot-tools" \
    "Scenario 3D: no Limine boot tools is reported as boot-tools"
for tool in limine-update limine-mkinitcpio limine-enroll-config; do
    mv "$S_LIMINE/$tool" "$S_LIMINE/$tool.aside"
    assert_eq "$(probe | jq -r '.unsupportedReason')" "boot-tools" \
        "Scenario 3D: a missing $tool is reported as boot-tools"
    mv "$S_LIMINE/$tool.aside" "$S_LIMINE/$tool"
done

# Scenario 3E: what the boot menu starts next.
assert_jq "$(probe)" '.uefi == false and .canChooseNext == false and .nextKernel == ""' \
    "Scenario 3E: without UEFI the choice cannot be stored"
next_pair() {
    probe EFIVARS_DIR="$S_ENV/efivars" "$@" | jq -c '[.nextKernel, .canChooseNext]'
}
write_entry_var "$S_VAR" "$MENU_PARENT/Snapshots/2026-11-22 10:00:00/linux-mainstream"
assert_eq "$(next_pair)" '["",false]' "Scenario 3E: a remembered snapshot is not a kernel to start next"
write_entry_var "$S_VAR" "Windows Boot Manager"
assert_eq "$(next_pair)" '["",false]' "Scenario 3E: an entry with no parent is not a kernel of this system"
write_entry_var "$S_VAR" "Other System/Fallback"
assert_eq "$(next_pair)" '["",false]' "Scenario 3E: an entry that names no kernel of this system is left alone"
write_entry_var "$S_VAR" "/linux"
assert_eq "$(next_pair)" '["",false]' "Scenario 3E: an entry with an empty parent is left alone"
s_tree 6.12.1-1-lts linux-lts
write_entry_var "$S_VAR" "$MENU_PARENT/linux-lts"
assert_eq "$(next_pair)" '["linux-lts",true]' "Scenario 3E: another installed kernel is recognized as the one started next"
assert_jq "$(probe)" '.installedKernels | index("linux-lts") != null' \
    "Scenario 3E: a kernel that is none of the three is listed among the installed kernels"
rm -rf "$S_MODULES/6.12.1-1-lts"
assert_eq "$(next_pair)" '["",false]' "Scenario 3E: and no longer once it is gone"
rm -f "$S_VAR"
assert_eq "$(next_pair)" '["",false]' "Scenario 3E: no record in the firmware"
write_entry_var "$S_VAR" "$MENU_PARENT/linux-mainstream"
assert_eq "$(next_pair)" '["linux-mainstream",true]' "Scenario 3E: a Mainstream kernel started next"

# Scenario 3F: what the repositories offer.
grep -v '^linux-mainstream-performance-headers ' "$S_ENV/repo" >"$S_ENV/repo.new"
mv "$S_ENV/repo.new" "$S_ENV/repo"
json_3f=$(probe)
assert_jq "$json_3f" '[.kernels[] | .available] == [true, true, false]' \
    "Scenario 3F: a kernel whose headers no repository offers is not available"
assert_eq "$(kernel_field "$json_3f" linux-mainstream-performance downloadBytes)" "null" \
    "Scenario 3F: and has no download size"
: >"$S_ENV/repo"
json_3f=$(probe)
assert_jq "$json_3f" "$PROBE_SHAPE" "Scenario 3F: exactly the agreed fields with empty repositories"
assert_jq "$json_3f" '.kernels | all(.available == false and .downloadBytes == null)' \
    "Scenario 3F: nothing is available when no repository offers anything"

# Scenario 3G: the EFI partition.
assert_jq "$(probe)" '.espFreeBytes == null and .standardImageBytes == null' \
    "Scenario 3G: no EFI partition found, nothing measured"
printf 'ESP_PATH="%s"\n' "$S_ESP" >"$S_ENV/limine-default"
printf '123456789\n' >"$S_ENV/esp-avail"
assert_jq "$(probe LIMINE_DEFAULT_CONF="$S_ENV/limine-default")" \
    '.espFreeBytes == 123456789 and .standardImageBytes == 99999999' \
    "Scenario 3G: the EFI partition named in the Limine settings is measured"
# Without Arch's kernel the room is still known, from the kernels that are installed.
mv "$S_MODULES/7.3.5-arch1-1" "$S_ENV/stock.aside"
rm "$S_ESP/EFI/Linux/mainstream_linux-mainstream.efi"
truncate -s 88888888 "$S_ESP/EFI/Linux/mainstream_linux-mainstream-performance.efi"
assert_eq "$(probe ESP_CANDIDATES="$S_ESP" | jq -c '.standardImageBytes')" "88888888" \
    "Scenario 3G: without Arch's kernel, the Mainstream kernels' images are measured"
mv "$S_ENV/stock.aside" "$S_MODULES/7.3.5-arch1-1"
rm "$S_ESP/EFI/Linux/mainstream_linux.efi" "$S_ESP/EFI/Linux/mainstream_linux-mainstream-performance.efi"
mkdir -p "$S_ESP/0123abcd/linux" "$S_ESP/0123abcd/linux-mainstream"
truncate -s 14000000 "$S_ESP/0123abcd/linux/vmlinuz-linux"
truncate -s 20000000 "$S_ESP/0123abcd/linux/initramfs-linux.img"
truncate -s 30000000 "$S_ESP/0123abcd/linux-mainstream/vmlinuz-linux-mainstream"
assert_eq "$(probe ESP_CANDIDATES="$S_ESP" | jq -c '.standardImageBytes')" "34000000" \
    "Scenario 3G: a kernel and initramfs kept apart are measured together"
truncate -s 77000000 "$S_ESP/0123abcd/linux-mainstream/vmlinuz-linux-mainstream"
assert_eq "$(probe ESP_CANDIDATES="$S_ESP" | jq -c '.standardImageBytes')" "77000000" \
    "Scenario 3G: and the largest kernel's files set the size"

# Scenario 3H: a Mainstream-only install, where Arch's kernel is on offer like the others.
rm -rf "${S_MODULES:?}"/*
s_tree 7.3.5-arch1-1-mainstream linux-mainstream
printf 'linux-mainstream 7.3.5-1\nlinux-mainstream-headers 7.3.5-1\n' >"$S_ENV/installed"
printf '7.3.5-arch1-1-mainstream\n' >"$S_ENV/release"
cat >"$S_ENV/repo" <<'REPO_END'
linux 151.12 MiB
linux-headers 30.00 MiB
linux-mainstream 150.00 MiB
linux-mainstream-headers 30.50 MiB
REPO_END
printf 'linux 158460723\nlinux-headers 31457280\n' >"$S_ENV/plan-linux"
json_3h=$(probe)
assert_jq "$json_3h" "$PROBE_SHAPE" "Scenario 3H: exactly the agreed fields"
assert_jq "$json_3h" '.kernels[0] == {
    name: "linux", installed: false, version: "", running: false, available: true,
    cpuSupported: true, downloadBytes: 189918003, driverMissing: false
}' "Scenario 3H: Arch's kernel is on offer, with the size of it and its headers"
assert_jq "$json_3h" '[.kernels[] | select(.installed) | .name] == ["linux-mainstream"]' \
    "Scenario 3H: the Mainstream kernel is the one installed"
assert_jq "$json_3h" '.installedKernels == ["linux-mainstream"]' \
    "Scenario 3H: and the only kernel this system can start"
grep -v '^linux-headers ' "$S_ENV/repo" >"$S_ENV/repo.new"
mv "$S_ENV/repo.new" "$S_ENV/repo"
assert_jq "$(probe)" '.kernels[0] | .available == false and .downloadBytes == null' \
    "Scenario 3H: Arch's kernel is not on offer when its headers are not"

printf '\n=== 4. Privileged Helper mainstream-kernels Tests ===\n'

T_ROOT="$TMP_BASE/root"
T_BIN="$TMP_BASE/mock-bin"
T_STATE="$TMP_BASE/mock-state"
T_MODULES="$T_ROOT/usr/lib/modules"
T_EFIVARS="$T_ROOT/sys/firmware/efi/efivars"
T_VAR="$T_EFIVARS/LimineLastBootedEntry-$ENTRY_GUID"
ESP_T="$T_ROOT/boot/efi"
T_LOG="$T_ROOT/var/log/mainstream/mainstream-kernels.log"
mkdir -p "$T_BIN" "$T_STATE" "$T_MODULES" "$T_EFIVARS" \
         "$T_ROOT/etc/default" "$T_ROOT/proc" "$T_ROOT/usr/local/lib" \
         "$T_ROOT/var/log/mainstream" "$T_ROOT/var/lib/pacman" "$T_ROOT/run/lock" \
         "$ESP_T/EFI/Linux"

printf 'btrfs\n' >"$T_STATE/fstype"
printf '/@\n' >"$T_STATE/subvol"
printf '7.3.5-arch1-1\n' >"$T_STATE/release"
printf '0\n' >"$T_STATE/pacman_fail"
printf '0\n' >"$T_STATE/pacman_no_effect"
printf 'false\n' >"$T_STATE/has_nvidia"
printf '0\n' >"$T_STATE/gpu_detect_rc"
printf '0\n' >"$T_STATE/ensure_rc"
: >"$T_STATE/calls.log"

IMAGE_BYTES=$((36 * 1024 * 1024))
NEEDED_BYTES=$((IMAGE_BYTES * 2 + 32 * 1024 * 1024))
printf '%s\n' "$((900 * 1024 * 1024))" >"$T_STATE/esp_avail"

cat >"$T_ROOT/etc/default/limine" <<'LIMINE_END'
TARGET_OS_NAME="Mainstream OS\\"
ESP_PATH="/boot/efi"
ENABLE_UKI=yes
CUSTOM_UKI_NAME="mainstream"
LIMINE_END
truncate -s "$IMAGE_BYTES" "$ESP_T/EFI/Linux/mainstream_linux.efi"
write_cpuinfo "$T_ROOT/proc/cpuinfo" "$V3_FLAGS"

release_of() {
    case $1 in
        linux) echo 7.3.5-arch1-1 ;;
        linux-mainstream) echo 7.3.5-arch1-1-mainstream ;;
        linux-mainstream-performance) echo 7.3.5-1-mainstream-performance ;;
        *) echo "6.0.0-$1" ;;
    esac
}
t_tree() {  # $1 = package: a kernel the test system can start
    local dir
    dir="$T_MODULES/$(release_of "$1")"
    mkdir -p "$dir"
    : >"$dir/vmlinuz"
    printf '%s\n' "$1" >"$dir/pkgbase"
}
t_install() {  # the packages the test system has from the start of a case
    local pkg
    for pkg in "$@"; do
        printf '%s\n' "$pkg" >>"$T_STATE/installed"
        [[ $pkg == *-headers ]] || t_tree "$pkg"
    done
}
t_reset() {  # back to a fresh system: the standard kernel alone, everything on offer
    rm -rf "${T_MODULES:?}"/*
    : >"$T_STATE/installed"
    t_install linux linux-headers
    printf '%s\n' linux linux-headers linux-mainstream linux-mainstream-headers \
        linux-mainstream-performance linux-mainstream-performance-headers >"$T_STATE/repo"
    printf '7.3.5-arch1-1\n' >"$T_STATE/release"
    write_entry_var "$T_VAR" "$MENU_PARENT/linux"
    rm -f "$ESP_T/EFI/Linux/mainstream_linux-mainstream.efi"
    : >"$T_STATE/calls.log"
}

t_mainstream_only() {  # a Default install: the Mainstream kernel alone, and running
    t_reset
    rm -rf "${T_MODULES:?}"/*
    : >"$T_STATE/installed"
    t_install "$PLAIN" "$PLAIN-headers"
    printf '7.3.5-arch1-1-mainstream\n' >"$T_STATE/release"
    write_entry_var "$T_VAR" "$MENU_PARENT/$PLAIN"
    truncate -s "$IMAGE_BYTES" "$ESP_T/EFI/Linux/mainstream_linux-mainstream.efi"
}

# The helper runs on these tools and the stand-ins beside them alone: a package
# manager or boot tool with no stand-in is missing, never the real one.
for tool in bash date mkdir flock head tail tr od dd stat grep mv rm cat; do
    ln -s "$(command -v "$tool")" "$T_BIN/$tool"
done

cat >"$T_BIN/findmnt" <<STUB_END
#!/usr/bin/env bash
echo "/dev/nvme0n1p2[\$(<"$T_STATE/subvol")] \$(<"$T_STATE/fstype")"
STUB_END

cat >"$T_BIN/uname" <<STUB_END
#!/usr/bin/env bash
printf '%s\n' "\$(<"$T_STATE/release")"
STUB_END

cat >"$T_BIN/df" <<STUB_END
#!/usr/bin/env bash
echo "df \$*" >>"$T_STATE/calls.log"
printf '    Avail\n%s\n' "\$(<"$T_STATE/esp_avail")"
STUB_END

cat >"$T_BIN/chattr" <<STUB_END
#!/usr/bin/env bash
echo "chattr \$*" >>"$T_STATE/calls.log"
exit 0
STUB_END

# A stand-in for the package database: one installed package per line, one offered
# package per line. An install or a removal moves names and module trees about.
cat >"$T_BIN/pacman" <<STUB_END
#!/usr/bin/env bash
echo "pacman \$*" >>"$T_STATE/calls.log"
release_of() {
    case \$1 in
        linux) echo 7.3.5-arch1-1 ;;
        linux-mainstream) echo 7.3.5-arch1-1-mainstream ;;
        linux-mainstream-performance) echo 7.3.5-1-mainstream-performance ;;
        *) echo "6.0.0-\$1" ;;
    esac
}
op=\$1
shift
case \$op in
    -Qq)
        [[ \${1:-} == -- ]] && shift
        grep -qxF -- "\$1" "$T_STATE/installed" || exit 1
        printf '%s\n' "\$1" ;;
    -Si)
        [[ \${1:-} == -- ]] && shift
        grep -qxF -- "\$1" "$T_STATE/repo" || exit 1 ;;
    -S)
        [[ \$(<"$T_STATE/pacman_fail") == 1 ]] && exit 1
        [[ \$(<"$T_STATE/pacman_no_effect") == 1 ]] && exit 0
        for arg in "\$@"; do
            [[ \$arg == -* ]] && continue
            grep -qxF -- "\$arg" "$T_STATE/installed" || printf '%s\n' "\$arg" >>"$T_STATE/installed"
            [[ \$arg == *-headers ]] && continue
            dir="$T_MODULES/\$(release_of "\$arg")"
            mkdir -p "\$dir"
            : >"\$dir/vmlinuz"
            printf '%s\n' "\$arg" >"\$dir/pkgbase"
        done ;;
    -Rns)
        [[ \$(<"$T_STATE/pacman_fail") == 1 ]] && exit 1
        for arg in "\$@"; do
            [[ \$arg == -* ]] && continue
            grep -vxF -- "\$arg" "$T_STATE/installed" >"$T_STATE/installed.new" || true
            mv -f "$T_STATE/installed.new" "$T_STATE/installed"
            [[ \$arg == *-headers ]] || rm -rf "$T_MODULES/\$(release_of "\$arg")"
        done ;;
    *)
        echo "unexpected pacman operation \$op" >&2
        exit 99 ;;
esac
exit 0
STUB_END

for tool in limine-update limine-mkinitcpio limine-enroll-config; do
    cat >"$T_BIN/$tool" <<STUB_END
#!/usr/bin/env bash
echo "$tool \$*" >>"$T_STATE/calls.log"
exit 0
STUB_END
done
chmod +x "$T_BIN"/findmnt "$T_BIN"/uname "$T_BIN"/df "$T_BIN"/chattr "$T_BIN"/pacman "$T_BIN"/limine-*
refute "the real package manager cannot be reached from the test system" \
    env -i PATH="$T_BIN" bash -c 'command -v pacman | grep -q "^/usr"'

# Stand-ins for the shared GPU steps. Each records that it ran and with what.
write_gpu_libs() {
    cat >"$T_ROOT/usr/local/lib/gpu-config.sh" <<STUB_END
gpu_detect() {
    echo "gpu_detect" >>"$T_STATE/calls.log"
    HAS_NVIDIA=\$(<"$T_STATE/has_nvidia")
    return "\$(<"$T_STATE/gpu_detect_rc")"
}
gpu_classify_nvidia_driver() {
    echo "gpu_classify_nvidia_driver" >>"$T_STATE/calls.log"
    NVIDIA_DRIVER_FAMILY=nvidia-open
}
STUB_END
    cat >"$T_ROOT/usr/local/lib/gpu-driver-install.sh" <<STUB_END
gpu_nvidia_ensure_modules() {
    echo "gpu_nvidia_ensure_modules family=\$NVIDIA_DRIVER_FAMILY sudo=[\$GPU_SUDO] refresh=\$GPU_DB_REFRESH" >>"$T_STATE/calls.log"
    return "\$(<"$T_STATE/ensure_rc")"
}
STUB_END
}
write_gpu_libs

run_helper() {
    MAINSTREAM_KERNELS_TEST_ROOT="$T_ROOT" \
    MAINSTREAM_KERNELS_TEST_BIN="$T_BIN" \
    "$HELPER_SCRIPT" "$@"
}

calls() {  # how many logged tool calls match $1
    grep -c -- "$1" "$T_STATE/calls.log" || true
}

call_line() {  # the line of the first logged tool call matching $1
    grep -n -- "$1" "$T_STATE/calls.log" | head -n1 | cut -d: -f1
}

is_installed() {
    grep -qxF -- "$1" "$T_STATE/installed"
}

no_package_change() {
    [[ $(calls '^pacman -S \|^pacman -R') == 0 ]]
}

reason_of() {  # the one sentence a refused call prints
    stderr_of run_helper "$@"
}

PLAIN=linux-mainstream
PERF=linux-mainstream-performance

# 4.1 Bad usage and names
t_reset
expect_rc 2 "unknown subcommand exits 2" run_helper bogus-cmd "$PLAIN"
expect_rc 2 "no subcommand exits 2" run_helper
for verb in install remove next; do
    expect_rc 2 "$verb with no kernel exits 2" run_helper "$verb"
    expect_rc 2 "$verb with two kernels exits 2" run_helper "$verb" "$PLAIN" "$PERF"
    expect_rc 2 "$verb with an option after the kernel exits 2" run_helper "$verb" "$PLAIN" --force
done
SENTINEL="$TMP_BASE/metacharacter-ran"
for name in linux-lts linux-zen linux-mainstream-headers linux-mainstream-performance-headers \
            linux-mainstream-anticheat LINUX-MAINSTREAM "" " " "linux-mainstream " " linux-mainstream" \
            "linux-mainstream linux-mainstream-headers" "linux-mainstream;touch $SENTINEL" \
            "\$(touch $SENTINEL)" "\`touch $SENTINEL\`" "linux-mainstream|touch $SENTINEL" \
            "linux-mainstream&&touch $SENTINEL" "linux-mainstream*" "linux-mainstrea?" \
            "../../$PLAIN" "/var/cache/pacman/pkg/linux-mainstream-7.3.5-1-x86_64.pkg.tar.zst" \
            "./linux-mainstream.pkg.tar.zst" "-U" "--overwrite=*" $'linux-mainstream\nlinux' "linux-mainstream'"; do
    for verb in install remove next; do
        expect_rc 2 "$verb refuses the name '${name//$'\n'/\\n}'" run_helper "$verb" "$name"
    done
done
check "a refused name runs nothing" test ! -s "$T_STATE/calls.log"
refute "a name with shell metacharacters is never run" test -e "$SENTINEL"
check "a refused name changes no package" no_package_change
check "the reason for a refusal reaches stderr as one line" \
    test "$(reason_of install linux-lts)" = "mainstream-kernels: not a kernel that can be installed here"
check "a name with a line break stays one line in the log" \
    test "$(grep -c 'invoked: install linux-mainstream?linux' "$T_LOG")" = 1

# 4.2 install: every refusal
t_reset
echo overlay >"$T_STATE/fstype"
expect_rc 3 "install started from a snapshot exits 3" run_helper install "$PLAIN"
check "install from a snapshot names the snapshot as the reason" \
    grep -q '^mainstream-kernels: started from a snapshot' <<<"$(reason_of install "$PLAIN")"
check "nothing is installed from a snapshot" no_package_change
echo btrfs >"$T_STATE/fstype"
for subvol in /@/.snapshots/8/snapshot /.snapshots/8/snapshot /@.snapshots/12/snapshot; do
    echo "$subvol" >"$T_STATE/subvol"
    expect_rc 3 "install started on the snapshot subvolume $subvol exits 3" run_helper install "$PERF"
done
check "nothing is installed on a snapshot subvolume" no_package_change
echo /@ >"$T_STATE/subvol"

for tool in limine-update limine-mkinitcpio limine-enroll-config; do
    mv "$T_BIN/$tool" "$T_BIN/$tool.aside"
    expect_rc 3 "install without $tool exits 3" run_helper install "$PLAIN"
    mv "$T_BIN/$tool.aside" "$T_BIN/$tool"
done
check "nothing is installed without the Limine boot tools" no_package_change

for flag in avx avx2 bmi1 bmi2 f16c fma movbe xsave abm; do
    write_cpuinfo "$T_ROOT/proc/cpuinfo" "${V3_FLAGS/ $flag / }"
    expect_rc 5 "install of the performance kernel on a processor without $flag exits 5" run_helper install "$PERF"
done
write_cpuinfo "$T_ROOT/proc/cpuinfo" "${V3_FLAGS/ avx2/}"
expect_rc 5 "install of the performance kernel on a processor without AVX2 exits 5" run_helper install "$PERF"
check "the reason names the kernel and what it needs" \
    grep -q "^mainstream-kernels: this processor cannot run $PERF" <<<"$(reason_of install "$PERF")"
mv "$T_ROOT/proc/cpuinfo" "$T_ROOT/proc/cpuinfo.aside"
expect_rc 5 "install of the performance kernel on a processor that cannot be read exits 5" run_helper install "$PERF"
mv "$T_ROOT/proc/cpuinfo.aside" "$T_ROOT/proc/cpuinfo"
check "the performance kernel is never installed on a processor that cannot run it" no_package_change
check "the Mainstream kernel installs on a processor without AVX2" run_helper install "$PLAIN"
check "and it is installed" is_installed "$PLAIN"
write_cpuinfo "$T_ROOT/proc/cpuinfo" "${V3_FLAGS/ abm / lzcnt }"
t_reset
check "the performance kernel installs on a processor that names lzcnt in place of abm" run_helper install "$PERF"
write_cpuinfo "$T_ROOT/proc/cpuinfo" "$V3_FLAGS"

t_reset
printf '%s\n' "$((NEEDED_BYTES - 1))" >"$T_STATE/esp_avail"
expect_rc 6 "install exits 6 when the EFI partition is one byte short of twice the image plus 32 MiB" \
    run_helper install "$PLAIN"
check "the reason gives the free space and the need" \
    grep -q '^mainstream-kernels: the EFI partition has 103 MiB free and another kernel needs 104 MiB$' <<<"$(reason_of install "$PLAIN")"
check "nothing is installed without room" no_package_change
check "the free space asked about is the EFI partition's" test "$(calls "^df -B1 --output=avail -- $ESP_T\$")" -ge 1
printf '%s\n' "$NEEDED_BYTES" >"$T_STATE/esp_avail"
check "install succeeds with exactly twice the image plus 32 MiB free" run_helper install "$PLAIN"
t_reset
printf '%s\n' "$((IMAGE_BYTES + 32 * 1024 * 1024))" >"$T_STATE/esp_avail"
expect_rc 6 "room for one copy of the image is not enough" run_helper install "$PLAIN"
printf 'not a number\n' >"$T_STATE/esp_avail"
expect_rc 6 "free space that cannot be read exits 6" run_helper install "$PLAIN"
printf '%s\n' "$((900 * 1024 * 1024))" >"$T_STATE/esp_avail"
mv "$ESP_T/EFI/Linux/mainstream_linux.efi" "$TMP_BASE/image.aside"
truncate -s "$((500 * 1024 * 1024))" "$ESP_T/EFI/Linux/mainstream_linux-mainstream.efi"
expect_rc 6 "install exits 6 when no installed kernel's boot image can be found" run_helper install "$PLAIN"
check "the image of a kernel that is not installed is not measured" \
    grep -q "could not find an installed kernel's boot image" <<<"$(reason_of install "$PLAIN")"
rm "$ESP_T/EFI/Linux/mainstream_linux-mainstream.efi"
mkdir -p "$ESP_T/0123abcd/linux"
truncate -s "$((16 * 1024 * 1024))" "$ESP_T/0123abcd/linux/vmlinuz-linux"
truncate -s "$((20 * 1024 * 1024))" "$ESP_T/0123abcd/linux/initramfs-linux.img"
printf '%s\n' "$((NEEDED_BYTES - 1))" >"$T_STATE/esp_avail"
expect_rc 6 "a kernel and initramfs kept apart are measured together: one byte short" run_helper install "$PLAIN"
printf '%s\n' "$NEEDED_BYTES" >"$T_STATE/esp_avail"
check "a kernel and initramfs kept apart are measured together: exactly enough" run_helper install "$PLAIN"
rm -rf "$ESP_T/0123abcd"
# A Mainstream-only install has no boot image of Arch's kernel. The room comes from
# the kernels it has.
t_mainstream_only
printf '%s\n' "$((NEEDED_BYTES - 1))" >"$T_STATE/esp_avail"
expect_rc 6 "without Arch's kernel the Mainstream kernel's image is measured: one byte short" run_helper install "$PERF"
printf '%s\n' "$NEEDED_BYTES" >"$T_STATE/esp_avail"
check "without Arch's kernel the Mainstream kernel's image is measured: exactly enough" run_helper install "$PERF"
mv "$TMP_BASE/image.aside" "$ESP_T/EFI/Linux/mainstream_linux.efi"
t_reset
t_install "$PLAIN" "$PLAIN-headers"
truncate -s "$((IMAGE_BYTES + 1024 * 1024))" "$ESP_T/EFI/Linux/mainstream_linux-mainstream.efi"
expect_rc 6 "the largest image of the installed kernels sets the room" run_helper install "$PERF"
rm "$ESP_T/EFI/Linux/mainstream_linux-mainstream.efi"
printf '%s\n' "$((900 * 1024 * 1024))" >"$T_STATE/esp_avail"
mv "$ESP_T" "$ESP_T.aside"
t_reset
expect_rc 6 "install exits 6 when the EFI partition cannot be found" run_helper install "$PLAIN"
check "nothing is installed when the room cannot be measured" no_package_change
mv "$ESP_T.aside" "$ESP_T"
printf '%s\n' "$((900 * 1024 * 1024))" >"$T_STATE/esp_avail"

t_reset
grep -vxF "$PLAIN" "$T_STATE/repo" >"$T_STATE/repo.new"
mv "$T_STATE/repo.new" "$T_STATE/repo"
expect_rc 11 "install exits 11 when no repository offers the kernel" run_helper install "$PLAIN"
t_reset
grep -vxF "$PERF-headers" "$T_STATE/repo" >"$T_STATE/repo.new"
mv "$T_STATE/repo.new" "$T_STATE/repo"
expect_rc 11 "install exits 11 when no repository offers the kernel's headers" run_helper install "$PERF"
check "a kernel is never installed without its headers on offer" no_package_change

t_reset
echo 1 >"$T_STATE/pacman_fail"
expect_rc 4 "install exits 4 when the transaction fails" run_helper install "$PLAIN"
check "no driver step runs after a failed transaction" test "$(calls '^gpu_')" = 0
echo 0 >"$T_STATE/pacman_fail"
echo 1 >"$T_STATE/pacman_no_effect"
expect_rc 4 "install exits 4 when the transaction leaves the kernel not installed" run_helper install "$PLAIN"
check "no driver step runs for a kernel that is not there" test "$(calls '^gpu_')" = 0
echo 0 >"$T_STATE/pacman_no_effect"

# 4.3 install: the transaction and the driver step
t_reset
check "install succeeds on a fresh system" run_helper install "$PLAIN"
check "the transaction is the kernel and its headers, and nothing else" \
    test "$(grep -c '^pacman -S ' "$T_STATE/calls.log")" = 1 -a \
         "$(grep -cx "pacman -S --needed --noconfirm $PLAIN $PLAIN-headers" "$T_STATE/calls.log")" = 1
check "nothing is removed by an install" test "$(calls '^pacman -R')" = 0
check "no package file and no database refresh is ever asked for" test "$(calls '^pacman -U\|^pacman -Sy\|^pacman .* -U')" = 0
check "the kernel and its headers are installed" test -f "$T_MODULES/7.3.5-arch1-1-mainstream/vmlinuz" -a \
    "$(grep -cxF -e "$PLAIN" -e "$PLAIN-headers" "$T_STATE/installed")" = 2
check "the card is looked for after the transaction" \
    test "$(call_line '^pacman -S ')" -lt "$(call_line '^gpu_detect')"
check "no NVIDIA step runs without an NVIDIA card" test "$(calls '^gpu_classify\|^gpu_nvidia_ensure')" = 0
check "the boot menu's record is left alone by an install" entry_var_is "$T_VAR" "$MENU_PARENT/linux"
check "the transaction is logged" grep -q "install: pacman -S --needed --noconfirm $PLAIN $PLAIN-headers" "$T_LOG"

t_reset
check "install of the performance kernel succeeds" run_helper install "$PERF"
check "its transaction is that kernel and its headers" \
    test "$(grep -c '^pacman -S ' "$T_STATE/calls.log")" = 1 -a \
         "$(grep -cx "pacman -S --needed --noconfirm $PERF $PERF-headers" "$T_STATE/calls.log")" = 1

t_reset
echo 1 >"$T_STATE/gpu_detect_rc"
echo true >"$T_STATE/has_nvidia"
check "install succeeds on a machine where no display device is found" run_helper install "$PLAIN"
check "no NVIDIA step runs when no display device is found" test "$(calls '^gpu_classify\|^gpu_nvidia_ensure')" = 0
echo 0 >"$T_STATE/gpu_detect_rc"

t_reset
check "install succeeds with an NVIDIA card" run_helper install "$PLAIN"
check "with an NVIDIA card every installed kernel is given a module, once" \
    test "$(grep -cx 'gpu_nvidia_ensure_modules family=nvidia-open sudo=\[\] refresh=false' "$T_STATE/calls.log")" = 1
check "the driver is classified before the modules are built" \
    test "$(call_line '^gpu_detect')" -lt "$(call_line '^gpu_classify')" -a \
         "$(call_line '^gpu_classify')" -lt "$(call_line '^gpu_nvidia_ensure')"
check "the modules are built after the kernel is in" \
    test "$(call_line '^pacman -S ')" -lt "$(call_line '^gpu_nvidia_ensure')"

t_reset
echo 1 >"$T_STATE/ensure_rc"
expect_rc 7 "install exits 7 when only the driver step fails" run_helper install "$PERF"
check "the kernel stays installed when the driver step fails" is_installed "$PERF"
check "its headers stay too" is_installed "$PERF-headers"
check "nothing is removed after a failed driver step" test "$(calls '^pacman -R')" = 0
t_reset
check "the reason names the kernel and says to stay on the current one" \
    grep -q "^mainstream-kernels: $PLAIN is installed, but the graphics driver could not be built for it; keep using the kernel you are on" \
        <<<"$(reason_of install "$PLAIN")"
echo 0 >"$T_STATE/ensure_rc"
echo false >"$T_STATE/has_nvidia"

for lib in gpu-config.sh gpu-driver-install.sh; do
    t_reset
    echo true >"$T_STATE/has_nvidia"
    rm "$T_ROOT/usr/local/lib/$lib"
    : >"$TMP_BASE/stderr"
    install_rc=0
    run_helper install "$PLAIN" 2>"$TMP_BASE/stderr" >/dev/null || install_rc=$?
    assert_eq "$install_rc" "0" "install carries on without $lib"
    check "and says that $lib is missing" grep -q "^mainstream-kernels: /usr/local/lib/$lib is missing" "$TMP_BASE/stderr"
    check "and runs no driver step" test "$(calls '^gpu_')" = 0
    check "and the kernel is installed" is_installed "$PLAIN"
    write_gpu_libs
done
echo false >"$T_STATE/has_nvidia"

# Arch's kernel comes from Arch's repositories like the others come from theirs.
t_mainstream_only
check "install of Arch's kernel succeeds on a Mainstream-only system" run_helper install linux
check "its transaction is Arch's kernel and its headers" \
    test "$(grep -c '^pacman -S ' "$T_STATE/calls.log")" = 1 -a \
         "$(grep -cx "pacman -S --needed --noconfirm linux linux-headers" "$T_STATE/calls.log")" = 1
check "Arch's kernel and its headers are installed" test -f "$T_MODULES/7.3.5-arch1-1/vmlinuz" -a \
    "$(grep -cxF -e linux -e linux-headers "$T_STATE/installed")" = 2
check "the boot menu's record is left alone by installing Arch's kernel" entry_var_is "$T_VAR" "$MENU_PARENT/$PLAIN"
t_mainstream_only
write_cpuinfo "$T_ROOT/proc/cpuinfo" "${V3_FLAGS/ avx2/}"
check "Arch's kernel installs on a processor without AVX2" run_helper install linux
write_cpuinfo "$T_ROOT/proc/cpuinfo" "$V3_FLAGS"
t_mainstream_only
grep -vxF linux-headers "$T_STATE/repo" >"$T_STATE/repo.new"
mv "$T_STATE/repo.new" "$T_STATE/repo"
expect_rc 11 "install of Arch's kernel exits 11 when no repository offers its headers" run_helper install linux
check "Arch's kernel is never installed without its headers on offer" no_package_change

# 4.4 remove
t_reset
t_install "$PLAIN" "$PLAIN-headers" "$PERF" "$PERF-headers"
expect_rc 8 "remove refuses Arch's kernel while it is the kernel running now" run_helper remove linux
echo overlay >"$T_STATE/fstype"
expect_rc 3 "remove started from a snapshot exits 3" run_helper remove "$PLAIN"
echo btrfs >"$T_STATE/fstype"
mv "$T_BIN/limine-update" "$T_BIN/limine-update.aside"
expect_rc 3 "remove without the Limine boot tools exits 3" run_helper remove "$PLAIN"
mv "$T_BIN/limine-update.aside" "$T_BIN/limine-update"

printf '7.3.5-arch1-1-mainstream\n' >"$T_STATE/release"
expect_rc 8 "remove refuses the kernel that is running now" run_helper remove "$PLAIN"
check "the reason says to restart with another kernel" \
    grep -q "^mainstream-kernels: $PLAIN is the kernel running now" <<<"$(reason_of remove "$PLAIN")"
# Updated under the running kernel: the tree of the running release is gone.
mv "$T_MODULES/7.3.5-arch1-1-mainstream" "$T_MODULES/7.3.6-arch1-1-mainstream"
expect_rc 8 "remove refuses the running kernel when its module tree is gone" run_helper remove "$PLAIN"
mv "$T_MODULES/7.3.6-arch1-1-mainstream" "$T_MODULES/7.3.5-arch1-1-mainstream"
printf '7.3.5-1-mainstream-performance\n' >"$T_STATE/release"
mv "$T_MODULES/7.3.5-1-mainstream-performance" "$T_MODULES/7.3.6-1-mainstream-performance"
expect_rc 8 "the same for the performance kernel" run_helper remove "$PERF"
mv "$T_MODULES/7.3.6-1-mainstream-performance" "$T_MODULES/7.3.5-1-mainstream-performance"
check "the running kernel is never removed" no_package_change
printf '7.3.5-arch1-1\n' >"$T_STATE/release"

# Arch's kernel goes like the others once another kernel runs.
t_reset
t_install "$PLAIN" "$PLAIN-headers"
printf '7.3.5-arch1-1-mainstream\n' >"$T_STATE/release"
check "remove of Arch's kernel succeeds while another kernel is running" run_helper remove linux
check "the removal is Arch's kernel and its headers, and nothing else" \
    test "$(grep -c '^pacman -R' "$T_STATE/calls.log")" = 1 -a \
         "$(grep -cx "pacman -Rns --noconfirm linux linux-headers" "$T_STATE/calls.log")" = 1
refute "Arch's kernel is gone" is_installed linux
check "the boot menu goes to the Mainstream kernel" entry_var_is "$T_VAR" "$MENU_PARENT/$PLAIN"
# The only kernel stays, Arch's too.
t_reset
printf '6.12.1-1-lts\n' >"$T_STATE/release"
expect_rc 8 "remove refuses Arch's kernel when it is the only kernel" run_helper remove linux
check "the reason says no kernel would be left" \
    grep -q "^mainstream-kernels: removing linux would leave this system with no kernel$" <<<"$(reason_of remove linux)"
check "the only kernel is never removed" no_package_change

t_reset
expect_rc 8 "remove refuses a kernel that is not installed" run_helper remove "$PLAIN"
check "the reason says it is not installed" \
    grep -q "^mainstream-kernels: $PLAIN is not installed$" <<<"$(reason_of remove "$PLAIN")"
check "nothing is removed for a kernel that is not installed" no_package_change

# The standard kernel removed by hand, and the one kernel left started from another
# release of itself.
t_reset
t_install "$PLAIN" "$PLAIN-headers"
rm -rf "$T_MODULES/7.3.5-arch1-1"
printf '7.3.4-arch1-1\n' >"$T_STATE/release"
expect_rc 8 "remove refuses a removal that would leave no kernel" run_helper remove "$PLAIN"
check "the reason says no kernel would be left" \
    grep -q "^mainstream-kernels: removing $PLAIN would leave this system with no kernel$" <<<"$(reason_of remove "$PLAIN")"
check "the last kernel is never removed" no_package_change
# A tree with headers only is not a kernel that can start the system.
mkdir -p "$T_MODULES/7.3.5-arch1-1"
printf 'linux\n' >"$T_MODULES/7.3.5-arch1-1/pkgbase"
expect_rc 8 "a module tree with no kernel image does not count as a kernel" run_helper remove "$PLAIN"

t_reset
t_install "$PLAIN" "$PLAIN-headers" "$PERF" "$PERF-headers"
write_entry_var "$T_VAR" "$MENU_PARENT/$PERF"
check "remove succeeds for an installed kernel that is not running" run_helper remove "$PLAIN"
check "the removal is the kernel and its headers, and nothing else" \
    test "$(grep -c '^pacman -R' "$T_STATE/calls.log")" = 1 -a \
         "$(grep -cx "pacman -Rns --noconfirm $PLAIN $PLAIN-headers" "$T_STATE/calls.log")" = 1
check "nothing is installed by a removal" test "$(calls '^pacman -S ')" = 0
refute "the kernel is gone" is_installed "$PLAIN"
check "the other kernels stay" test -f "$T_MODULES/7.3.5-arch1-1/vmlinuz" -a -f "$T_MODULES/7.3.5-1-mainstream-performance/vmlinuz"
check "a remembered entry of another kernel is left alone" entry_var_is "$T_VAR" "$MENU_PARENT/$PERF"
check "and the firmware variable is not touched for it" test "$(calls '^chattr')" = 0

t_reset
t_install "$PLAIN"
check "remove succeeds for a kernel whose headers are not installed" run_helper remove "$PLAIN"
check "the headers are not named when they are not installed" \
    test "$(grep -cx "pacman -Rns --noconfirm $PLAIN" "$T_STATE/calls.log")" = 1

t_reset
t_install "$PLAIN" "$PLAIN-headers"
write_entry_var "$T_VAR" "$MENU_PARENT/$PLAIN"
check "remove succeeds for the kernel the boot menu remembers" run_helper remove "$PLAIN"
check "the boot menu is pointed back at the standard kernel, byte for byte" entry_var_is "$T_VAR" "$MENU_PARENT/linux"
check "the record is rewritten after the removal" \
    test "$(call_line '^pacman -Rns')" -lt "$(call_line '^chattr -i')"

t_reset
t_install "$PLAIN" "$PLAIN-headers"
write_entry_var "$T_VAR" "$MENU_PARENT/$PLAIN"
echo 1 >"$T_STATE/pacman_fail"
expect_rc 4 "remove exits 4 when the transaction fails" run_helper remove "$PLAIN"
check "the boot menu still remembers a kernel that could not be removed" entry_var_is "$T_VAR" "$MENU_PARENT/$PLAIN"
echo 0 >"$T_STATE/pacman_fail"

t_reset
t_install "$PLAIN" "$PLAIN-headers"
write_entry_var "$T_VAR" "$MENU_PARENT/Snapshots/2026-11-22 10:00:00/$PLAIN"
cp "$T_VAR" "$TMP_BASE/var.before"
check "remove succeeds while the boot menu remembers a snapshot" run_helper remove "$PLAIN"
check "a remembered snapshot is left for the startup service to replace" cmp -s "$T_VAR" "$TMP_BASE/var.before"

t_reset
t_install "$PLAIN" "$PLAIN-headers"
rm -rf "$T_EFIVARS"
check "remove succeeds on a system without UEFI" run_helper remove "$PLAIN"
mkdir -p "$T_EFIVARS"

# The default entry ./setup writes as a path names the removed kernel's entry.
T_CONF="$ESP_T/limine.conf"
write_conf() {  # $1 = the default_entry value
    printf 'timeout: 5\nremember_last_entry: yes\ndefault_entry: %s\n\n/+Mainstream OS\\\\\n    //linux\n        protocol: efi\n    //Snapshots\n' "$1" >"$T_CONF"
}
t_reset
t_install "$PLAIN" "$PLAIN-headers"
write_conf "Mainstream OS\\\\/$PLAIN"
check "remove succeeds when the default entry names the kernel" run_helper remove "$PLAIN"
check "the default entry is pointed at the standard kernel in the same block" \
    grep -qxF 'default_entry: Mainstream OS\\/linux' "$T_CONF"
check "only that line changes" test "$(grep -c '' "$T_CONF")" = 8 -a "$(grep -c "$PLAIN" "$T_CONF")" = 0
check "the menu is changed after the removal" \
    test "$(grep -c '^pacman -Rns' "$T_STATE/calls.log")" = 1
check "no checksum is enrolled where the setting is off" test "$(calls '^limine-enroll-config')" = 0
refute "no work file is left beside the menu" test -e "$T_CONF.mainstream-kernels"
printf 'ENABLE_ENROLL_LIMINE_CONFIG=yes\n' >>"$T_ROOT/etc/default/limine"
t_reset
t_install "$PLAIN" "$PLAIN-headers"
write_conf "Mainstream OS\\\\/$PLAIN"
check "remove succeeds with the menu's checksum enrolled" run_helper remove "$PLAIN"
check "the new checksum is enrolled" test "$(calls '^limine-enroll-config')" = 1
grep -v '^ENABLE_ENROLL_LIMINE_CONFIG=' "$T_ROOT/etc/default/limine" >"$TMP_BASE/limine.new"
mv "$TMP_BASE/limine.new" "$T_ROOT/etc/default/limine"
for value in 2 "Mainstream OS\\\\/linux" "Mainstream OS\\\\/$PERF"; do
    t_reset
    t_install "$PLAIN" "$PLAIN-headers" "$PERF" "$PERF-headers"
    write_conf "$value"
    cp "$T_CONF" "$TMP_BASE/conf.before"; : >"$T_LOG"
    check "remove succeeds with default_entry: $value" run_helper remove "$PLAIN"
    check "a default entry that is a number or another kernel is left alone ($value)" cmp -s "$T_CONF" "$TMP_BASE/conf.before"
    refute "and nothing says it was changed ($value)" grep -q "default entry names" "$T_LOG"
done
# An entry body that mentions the kernel is not the setting.
t_reset
t_install "$PLAIN" "$PLAIN-headers"
write_conf "Mainstream OS\\\\/$PLAIN"
printf '    //x\n        default_entry: Mainstream OS/%s\n' "$PLAIN" >>"$T_CONF"
check "remove succeeds with the name inside an entry" run_helper remove "$PLAIN"
check "only the header line is changed" test "$(grep -c "/$PLAIN" "$T_CONF")" = 1 -a "$(grep -c '^default_entry: Mainstream OS.*/linux$' "$T_CONF")" = 1
# Without Arch's kernel the menu goes to the best kernel that is left.
t_mainstream_only
t_install "$PERF" "$PERF-headers"
printf '7.3.5-1-mainstream-performance\n' >"$T_STATE/release"
write_conf "Mainstream OS\\\\/$PLAIN"
check "remove succeeds without the standard kernel" run_helper remove "$PLAIN"
check "the default entry is pointed at the performance kernel without the standard kernel" \
    grep -qxF "default_entry: Mainstream OS\\\\/$PERF" "$T_CONF"
check "the remembered entry is pointed at the performance kernel too" entry_var_is "$T_VAR" "$MENU_PARENT/$PERF"
check "and the log names it" grep -q "remove: the boot menu starts $PERF next" "$T_LOG"
# The best kernel left: performance, then Mainstream, then Arch's, and one with the
# NVIDIA module where another kernel has one.
t_reset
t_install "$PLAIN" "$PLAIN-headers" "$PERF" "$PERF-headers"
write_entry_var "$T_VAR" "$MENU_PARENT/$PERF"
write_conf "Mainstream OS\\\\/$PERF"
check "remove succeeds for the remembered performance kernel" run_helper remove "$PERF"
check "the Mainstream kernel comes before Arch's" entry_var_is "$T_VAR" "$MENU_PARENT/$PLAIN"
check "in the default entry too" grep -qxF "default_entry: Mainstream OS\\\\/$PLAIN" "$T_CONF"
t_reset
t_install "$PLAIN" "$PLAIN-headers" "$PERF" "$PERF-headers"
mkdir -p "$T_MODULES/7.3.5-arch1-1/updates/dkms" "$T_MODULES/7.3.5-1-mainstream-performance/updates/dkms"
: >"$T_MODULES/7.3.5-arch1-1/updates/dkms/nvidia.ko.zst"
: >"$T_MODULES/7.3.5-1-mainstream-performance/updates/dkms/nvidia.ko.zst"
write_entry_var "$T_VAR" "$MENU_PARENT/$PERF"
check "remove succeeds with the NVIDIA module on Arch's kernel and not on the Mainstream one" run_helper remove "$PERF"
check "the kernel with the NVIDIA module is the one the menu goes to" entry_var_is "$T_VAR" "$MENU_PARENT/linux"
# None of the three left: the kernel that is.
t_mainstream_only
t_install linux-t2
printf '6.0.0-linux-t2\n' >"$T_STATE/release"
write_conf "Mainstream OS\\\\/$PLAIN"
check "remove succeeds with only another kernel left" run_helper remove "$PLAIN"
check "the menu goes to that kernel" entry_var_is "$T_VAR" "$MENU_PARENT/linux-t2"
check "in the default entry too" grep -qxF "default_entry: Mainstream OS\\\\/linux-t2" "$T_CONF"
# A menu that is a symlink is not written through.
t_reset
t_install "$PLAIN" "$PLAIN-headers"
write_conf "Mainstream OS\\\\/$PLAIN"
mv "$T_CONF" "$TMP_BASE/conf.target"; ln -s "$TMP_BASE/conf.target" "$T_CONF"
check "remove succeeds with a symlinked menu" run_helper remove "$PLAIN"
check "a symlinked menu is not written" grep -qF "/$PLAIN" "$TMP_BASE/conf.target"
check "nor replaced" test -L "$T_CONF"
rm -f "$T_CONF"

# 4.5 next
t_reset
t_install "$PLAIN" "$PLAIN-headers" "$PERF" "$PERF-headers"
check "next succeeds for an installed kernel" run_helper next "$PERF"
check "next writes the parent the record had, then the kernel, byte for byte" \
    entry_var_is "$T_VAR" "$MENU_PARENT/$PERF"
check "the record is 4 attribute bytes, the entry and one zero byte" \
    test "$(stat -c %s "$T_VAR")" = "$((4 + ${#MENU_PARENT} + 1 + ${#PERF} + 1))"
check "the immutable flag is lifted before the write" test "$(grep -cx "chattr -i -- $T_VAR" "$T_STATE/calls.log")" = 1
check "next changes no package" no_package_change
check "next to the Mainstream kernel" run_helper next "$PLAIN"
check "replaces the kernel and keeps the parent" entry_var_is "$T_VAR" "$MENU_PARENT/$PLAIN"
check "next to the standard kernel, to go back" run_helper next linux
check "writes the standard kernel's entry" entry_var_is "$T_VAR" "$MENU_PARENT/linux"
: >"$T_STATE/calls.log"
check "next to the kernel that is already next succeeds" run_helper next linux
check "and writes nothing" test "$(calls '^chattr')" = 0

# The attributes the firmware gave the variable are kept, whatever they are.
printf '\x27\x00\x00\x80%s\0' 'Another Name/linux' >"$T_VAR"
check "next succeeds with other attributes and another parent" run_helper next "$PLAIN"
check "the attributes and the parent are kept as they were" \
    cmp -s "$T_VAR" <(printf '\x27\x00\x00\x80%s\0' "Another Name/$PLAIN")
printf '\x07\x00\x00\x00%s\0' 'Top/Sub Menu/100% /linux' >"$T_VAR"
check "next succeeds under a deeper parent with a percent sign" run_helper next "$PERF"
check "only the last part of the path is replaced" entry_var_is "$T_VAR" "Top/Sub Menu/100% /$PERF"

t_reset
t_install "$PLAIN" "$PLAIN-headers"
expect_rc 9 "next refuses a kernel that is not installed" run_helper next "$PERF"
check "the record is unchanged" entry_var_is "$T_VAR" "$MENU_PARENT/linux"
# The package is there and its kernel image is not.
rm "$T_MODULES/7.3.5-arch1-1-mainstream/vmlinuz"
expect_rc 9 "next refuses a kernel package with no kernel image" run_helper next "$PLAIN"
: >"$T_MODULES/7.3.5-arch1-1-mainstream/vmlinuz"

for entry in "$MENU_PARENT/Snapshots/2026-11-22 10:00:00/linux" "$MENU_PARENT/Snapshots/41/$PLAIN"; do
    write_entry_var "$T_VAR" "$entry"
    expect_rc 9 "next refuses while the boot menu remembers the snapshot entry '${entry#"$MENU_PARENT"}'" run_helper next "$PLAIN"
    check "the snapshot record is unchanged" entry_var_is "$T_VAR" "$entry"
done
check "the reason names the snapshot" \
    grep -q '^mainstream-kernels: the boot menu remembers a snapshot' <<<"$(reason_of next "$PLAIN")"
for entry in "Windows Boot Manager" "Other System/Fallback" "/linux" "linux" "$MENU_PARENT/"; do
    write_entry_var "$T_VAR" "$entry"
    expect_rc 9 "next refuses while the boot menu remembers '$entry'" run_helper next "$PLAIN"
    check "that record is unchanged" entry_var_is "$T_VAR" "$entry"
done
printf '\x07\x00\x00\x00' >"$T_VAR"
expect_rc 9 "next refuses an empty record" run_helper next "$PLAIN"
printf '\x07\x00' >"$T_VAR"
expect_rc 9 "next refuses a record cut short" run_helper next "$PLAIN"
: >"$T_STATE/calls.log"
rm -f "$T_VAR"
expect_rc 9 "next refuses when the firmware has no record" run_helper next "$PLAIN"
refute "and makes none" test -e "$T_VAR"
write_entry_var "$TMP_BASE/var.elsewhere" "$MENU_PARENT/linux"
ln -s "$TMP_BASE/var.elsewhere" "$T_VAR"
expect_rc 9 "next refuses a symlink in place of the record" run_helper next "$PLAIN"
check "and the file behind it is unchanged" entry_var_is "$TMP_BASE/var.elsewhere" "$MENU_PARENT/linux"
rm -f "$T_VAR"
rm -rf "$T_EFIVARS"
expect_rc 9 "next refuses on a system that does not start through UEFI" run_helper next "$PLAIN"
check "the reason says where to choose instead" \
    grep -q '^mainstream-kernels: this computer does not start through UEFI.*choose the kernel in the boot menu$' <<<"$(reason_of next "$PLAIN")"
mkdir -p "$T_EFIVARS"
check "nothing is written by a refused next" test "$(calls '^chattr')" = 0

t_reset
t_install "$PLAIN" "$PLAIN-headers"
echo overlay >"$T_STATE/fstype"
expect_rc 3 "next started from a snapshot exits 3" run_helper next "$PLAIN"
check "the record is unchanged from a snapshot" entry_var_is "$T_VAR" "$MENU_PARENT/linux"
echo btrfs >"$T_STATE/fstype"

# Another installed kernel as the remembered entry is a place in the menu like any other.
t_install linux-lts
write_entry_var "$T_VAR" "$MENU_PARENT/linux-lts"
check "next succeeds when the boot menu remembers another installed kernel" run_helper next "$PLAIN"
check "and replaces it" entry_var_is "$T_VAR" "$MENU_PARENT/$PLAIN"
expect_rc 2 "that other kernel is still not one this helper handles" run_helper next linux-lts

# A kernel without the NVIDIA module the other kernels have would start without graphics.
t_reset
t_install "$PLAIN" "$PLAIN-headers" "$PERF" "$PERF-headers"
mkdir -p "$T_MODULES/7.3.5-arch1-1/extramodules" "$T_MODULES/7.3.5-1-mainstream-performance/updates/dkms"
: >"$T_MODULES/7.3.5-arch1-1/extramodules/nvidia.ko.zst"
expect_rc 12 "next refuses a kernel with no NVIDIA module while another kernel has one" run_helper next "$PLAIN"
check "the record is unchanged" entry_var_is "$T_VAR" "$MENU_PARENT/linux"
check "the reason says to stay on the current kernel" \
    grep -q "^mainstream-kernels: the graphics driver is not built for $PLAIN; keep using the kernel you are on$" <<<"$(reason_of next "$PLAIN")"
: >"$T_MODULES/7.3.5-1-mainstream-performance/updates/dkms/nvidia.ko.zst"
check "next succeeds for a kernel that has its NVIDIA module" run_helper next "$PERF"
rm "$T_MODULES/7.3.5-arch1-1/extramodules/nvidia.ko.zst" "$T_MODULES/7.3.5-1-mainstream-performance/updates/dkms/nvidia.ko.zst"
check "next succeeds when no kernel has an NVIDIA module" run_helper next "$PLAIN"

if [[ $EUID -ne 0 ]]; then
    t_reset
    t_install "$PLAIN" "$PLAIN-headers"
    chmod 444 "$T_VAR"
    expect_rc 1 "next exits 1 when the firmware does not take the write" run_helper next "$PLAIN"
    chmod 644 "$T_VAR"
fi

# 4.6 Nothing runs beside another change
t_reset
t_install "$PLAIN" "$PLAIN-headers"
: >"$T_ROOT/var/lib/pacman/db.lck"
for verb in install remove next; do
    expect_rc 10 "$verb exits 10 while the package database is locked" run_helper "$verb" "$PLAIN"
done
check "the reason says another package change is running" \
    grep -q '^mainstream-kernels: another package change is still running' <<<"$(reason_of install "$PERF")"
rm -f "$T_ROOT/var/lib/pacman/db.lck"
# A snapshot carries the lock of the transaction it was taken in.
echo overlay >"$T_STATE/fstype"
: >"$T_ROOT/var/lib/pacman/db.lck"
for verb in install remove next; do
    expect_rc 3 "$verb started from a snapshot that holds the package lock exits 3" run_helper "$verb" "$PLAIN"
done
rm -f "$T_ROOT/var/lib/pacman/db.lck"
echo btrfs >"$T_STATE/fstype"
for lock in mainstream-kernels.lock mainstream-system-security.lock mainstream-update.lock; do
    exec {held}>>"$T_ROOT/run/lock/$lock"
    flock -n "$held"
    for verb in install remove next; do
        expect_rc 10 "$verb exits 10 while $lock is held" run_helper "$verb" "$PLAIN"
    done
    exec {held}>&-
done
check "nothing is changed beside another change" test "$(calls '^pacman -S \|^pacman -R\|^chattr')" = 0
check "the kernel is still installed and the record unchanged" \
    test "$(grep -cxF "$PLAIN" "$T_STATE/installed")" = 1 -a "$(od -An -tx1 "$T_VAR")" = "$(write_entry_var /dev/stdout "$MENU_PARENT/linux" | od -An -tx1)"
check "the locks are free again afterwards" run_helper next "$PLAIN"

# 4.7 A symlink in place of a file the helper writes is refused and left alone
SYM_TARGET="$TMP_BASE/symlink-victim"
printf 'ORIGINAL_CONTENT\n' >"$SYM_TARGET"
: >"$T_ROOT/run/lock/mainstream-update.lock"
: >"$T_ROOT/run/lock/mainstream-system-security.lock"

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

refuses_symlink /var/log/mainstream/mainstream-kernels.log run_helper next linux
refuses_symlink /run/lock/mainstream-kernels.lock run_helper next linux
refuses_symlink /run/lock/mainstream-system-security.lock run_helper install "$PERF"
refuses_symlink /run/lock/mainstream-update.lock run_helper remove "$PLAIN"

printf '\nAll %d tests passed.\n' "$PASS_COUNT"
