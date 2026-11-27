#!/usr/bin/env bash
# mac-config.test.sh: the Apple and T2 paths in mac-config.sh, run against
# stand-ins for the hardware. Writes only under a temporary directory.
# Run: bash sdata/lib/mac-config.test.sh   (exit 0 = all green)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gpu-config.sh
source "$DIR/gpu-config.sh"
# shellcheck source=mac-config.sh
source "$DIR/mac-config.sh"

# Drive detection from fixture globals instead of real hardware.
FIX_VENDOR=""; FIX_PRODUCT=""; FIX_PCI=""; FIX_T2_SUPPORT=false; FIX_PROC=""
FIX_T2FANRD=false; FIX_INSTALLED=""
_mac_sys_vendor()   { printf '%s\n' "$FIX_VENDOR"; }
_mac_product()      { printf '%s\n' "$FIX_PRODUCT"; }
_mac_pci()          { printf '%s\n' "$FIX_PCI"; }
_mac_proc_cmdline() { printf '%s\n' "$FIX_PROC"; }
_mac_t2fanrd_installed() { [[ $FIX_T2FANRD == true ]]; }
_mac_pkg_installed() { [[ " $FIX_INSTALLED " == *" $1 "* ]]; }
eval "real_$(declare -f mac_has_t2_support)"
mac_has_t2_support() { [[ $FIX_T2_SUPPORT == true ]]; }

FAILS=0; CASES=0
chk() { CASES=$((CASES + 1)); if [[ "$2" != "$3" ]]; then echo "  FAIL [$1]: got '$2' want '$3'"; FAILS=$((FAILS + 1)); fi; }
has() { grep -qF -- "$2" "$1" 2>/dev/null && echo yes || echo no; }
exists() { [[ -e "$1" ]] && echo yes || echo no; }
count() { grep -o -- "$1" "$2" | wc -l | tr -d '[:space:]'; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
GPU_SUDO=''

# A fresh machine root: $1 names it, $2 is its /etc/kernel/cmdline ("-" for none).
setup() {
    R="$WORK/$1"
    mkdir -p "$R/modprobe" "$R/systemd" "$R/acpi" "$R/helper"
    MODPROBE_DIR="$R/modprobe" SYSTEMD_DIR="$R/systemd" MAC_ACPI_DIR="$R/acpi"
    MAC_HELPER_DIR="$R/helper" MAC_STATE_DIR="$R/state" KERNEL_CMDLINE="$R/cmdline" MKINITCPIO_CONF="$R/mkinitcpio.conf"
    MODULES_LOAD_DIR="$R/modules-load" MAC_T2FAND_CONF="$R/t2fand.conf" MAC_HWMON_DIR="$R/hwmon"
    printf 'MODULES=()\n' > "$MKINITCPIO_CONF"
    [[ "$2" == - ]] || printf '%s\n' "$2" > "$KERNEL_CMDLINE"
}
uart_bt() { mkdir -p "$R/acpi/BCM2E7C:00"; [[ -z "${1:-}" ]] || echo "$1" > "$R/acpi/BCM2E7C:00/status"; }

T2_PCI="01:00.0 Non-VGA unclassified device [0000]: Apple Inc. T2 Bridge Controller [106b:1801]
03:00.0 Network controller [0280]: Broadcom Inc. BCM4364 [14e4:4464]"
T2_4377_PCI="01:00.0 Non-VGA unclassified device [0000]: Apple Inc. T2 [106b:1802]
03:00.0 Network controller [0280]: Broadcom Inc. BCM4377 [14e4:4488]"

# 1. Not an Apple machine: nothing written.
setup non-apple "root=UUID=1111 rw quiet"
FIX_VENDOR="LENOVO"; FIX_PRODUCT="21KC"; FIX_PCI="00:02.0 VGA compatible controller [0300]: Intel Corporation [8086:7d55]"
mac_apply_autoconfig
chk non-apple-class "$(mac_class)" none
chk non-apple-cmdline "$(cat "$R/cmdline")" "root=UUID=1111 rw quiet"
chk non-apple-files "$(ls -A "$R/modprobe" "$R/systemd" "$R/helper" | grep -cv ':$\|^$')" 0

# 2. MacBookPro14,1, before the T2: the 2017 fixes, no T2 options, no UART Bluetooth.
setup mbp141 "root=UUID=2222 rw quiet"
FIX_VENDOR="Apple Inc."; FIX_PRODUCT="MacBookPro14,1"; FIX_PCI="02:00.0 Network controller [0280]: Broadcom Inc. [14e4:43ba]"
mac_apply_autoconfig
chk mbp141-class "$(mac_class)" intel
chk mbp141-cmdline "$(cat "$R/cmdline")" "root=UUID=2222 rw quiet"
chk mbp141-hid "$(has "$R/modprobe/mainstream-apple.conf" "options hid_apple fnmode=1")" yes
chk mbp141-spi "$(has "$R/modprobe/mainstream-apple-spi.conf" "options applespi fnmode=1")" yes
chk mbp141-nvme "$(has "$R/systemd/mainstream-mac-nvme.service" d3cold_allowed)" yes
chk mbp141-no-bt-helper "$(exists "$R/helper/t2-bluetooth-recover")" no

# 3. MacBookPro15,1 on linux-t2, installed with the old pcie_ports=compat: the
#    current options, compat gone, the rest of the line kept; UART Bluetooth recovery.
setup mbp151 "root=UUID=3333 rw rootfstype=btrfs pcie_ports=compat quiet splash"
uart_bt 15
FIX_PRODUCT="MacBookPro15,1"; FIX_PCI="$T2_PCI"; FIX_T2_SUPPORT=true
mac_apply_autoconfig
chk mbp151-class "$(mac_class)" t2
chk mbp151-cmdline "$(cat "$R/cmdline")" "root=UUID=3333 rw rootfstype=btrfs quiet splash intel_iommu=on iommu=pt pm_async=off"
chk mbp151-wifi "$(has "$R/modprobe/mainstream-apple-wifi.conf" "options brcmfmac feature_disable=0x82000")" yes
chk mbp151-helper-exec "$([[ -x "$R/helper/t2-bluetooth-recover" ]] && echo yes || echo no)" yes
chk mbp151-unit-boot "$(has "$R/systemd/mainstream-t2-bluetooth.service" "ExecStart=/usr/local/lib/mainstream-mac/t2-bluetooth-recover 10")" yes
chk mbp151-unit-resume "$(has "$R/systemd/mainstream-t2-bluetooth-resume.service" "WantedBy=suspend.target")" yes
mac_apply_autoconfig
chk mbp151-rerun-same "$(cat "$R/cmdline")" "root=UUID=3333 rw rootfstype=btrfs quiet splash intel_iommu=on iommu=pt pm_async=off"
printf 'root=UUID=3333 rw quiet intel_iommu=on iommu=pt\n' > "$R/cmdline"
mac_apply_autoconfig
chk mbp151-removed-stays-out "$(cat "$R/cmdline")" "root=UUID=3333 rw quiet intel_iommu=on iommu=pt"
rm -f "$R/state/t2-cmdline-options"
mac_apply_autoconfig
chk mbp151-new-option-set "$(cat "$R/cmdline")" "root=UUID=3333 rw quiet intel_iommu=on iommu=pt pm_async=off"
chk mbp151-report "$(mac_report | grep -c 'T2 boot options: intel_iommu=on iommu=pt pm_async=off')" 1

# 4. Keys the user set keep their values; only the unset options are added.
setup override "root=UUID=4444 pcie_ports=native iommu=off rw"
uart_bt 15
mac_apply_autoconfig
chk override-cmdline "$(cat "$R/cmdline")" "root=UUID=4444 pcie_ports=native iommu=off rw intel_iommu=on pm_async=off"

# 5. A T2 Mac on a kernel without the T2 drivers: no boot options, Bluetooth recovery still.
setup stock-t2 "root=UUID=5555 rw"
uart_bt 15
FIX_T2_SUPPORT=false
mac_apply_autoconfig
chk stock-t2-cmdline "$(cat "$R/cmdline")" "root=UUID=5555 rw"
chk stock-t2-helper "$(exists "$R/helper/t2-bluetooth-recover")" yes
chk stock-t2-pending "$(mac_t2_cmdline_pending && echo yes || echo no)" no

# 6. A BCM4377 T2 (Bluetooth over PCIe): the options, no UART recovery.
setup t2-4377 "root=UUID=6666 rw"
FIX_PRODUCT="MacBookAir9,1"; FIX_PCI="$T2_4377_PCI"; FIX_T2_SUPPORT=true
mac_apply_autoconfig
chk t2-4377-cmdline "$(cat "$R/cmdline")" "root=UUID=6666 rw intel_iommu=on iommu=pt pm_async=off"
chk t2-4377-no-helper "$(exists "$R/helper/t2-bluetooth-recover")" no
chk t2-4377-no-unit "$(exists "$R/systemd/mainstream-t2-bluetooth.service")" no

# 7. BCM2E7C the firmware marks absent (MacPro7,1) is not UART Bluetooth; one
#    with no status file (no _STA) is.
setup acpi-status "root=UUID=7777 rw"
FIX_PCI="$T2_PCI"
uart_bt 0
chk acpi-status-absent "$(mac_needs_t2_uart_bt && echo yes || echo no)" no
rm -f "$R/acpi/BCM2E7C:00/status"
chk acpi-status-none "$(mac_needs_t2_uart_bt && echo yes || echo no)" yes

# 8. No /etc/kernel/cmdline (not a Limine install): none is created.
setup no-cmdline -
mac_apply_autoconfig
chk no-cmdline "$(exists "$R/cmdline")" no

# 9. Whether the running kernel is behind /etc/kernel/cmdline.
setup pending "# pm_async=off is noted here only
root=UUID=9999 rw intel_iommu=on iommu=pt pm_async=off"
FIX_PROC="BOOT_IMAGE=/vmlinuz root=UUID=9999 rw intel_iommu=on iommu=pt pm_async=off"
chk pending-current "$(mac_t2_cmdline_pending && echo yes || echo no)" no
FIX_PROC="BOOT_IMAGE=/vmlinuz root=UUID=9999 rw intel_iommu=on iommu=pt"
chk pending-new-option "$(mac_t2_cmdline_pending && echo yes || echo no)" yes
FIX_PROC="BOOT_IMAGE=/vmlinuz root=UUID=9999 rw intel_iommu=on iommu=pt pcie_ports=compat pm_async=off"
chk pending-compat-left "$(mac_t2_cmdline_pending && echo yes || echo no)" yes
printf 'root=UUID=9999 rw iommu=off\n' > "$R/cmdline"
FIX_PROC="root=UUID=9999 rw iommu=off"
chk pending-user-override "$(mac_t2_cmdline_pending && echo yes || echo no)" no

# 10. The recovery script: POSIX sh, quiet while a serial controller is there,
#     reloads hci_uart when only a USB one is.
setup helper "root=UUID=1010 rw"
_mac_t2_bt_recover_script > "$R/recover"
chk helper-sh-syntax "$(sh -n "$R/recover" 2>&1 && echo ok)" ok
mkdir -p "$R/bin" "$R/sys/serial0/serial0-0" "$R/sys/usb1/1-1" "$R/bt/hci0"
printf '#!/bin/sh\necho "$*" >> "%s"\n' "$R/modprobe.log" > "$R/bin/modprobe"
chmod +x "$R/bin/modprobe"
ln -s "$R/sys/usb1/1-1" "$R/bt/hci0/device"
PATH="$R/bin:$PATH" MAC_BLUETOOTH_CLASS="$R/bt" sh "$R/recover" 0
chk helper-usb-only-reloads "$(tr '\n' ';' < "$R/modprobe.log" 2>/dev/null)" "-r hci_uart;-b hci_uart;"
rm -f "$R/modprobe.log"
mkdir -p "$R/bt/hci1"
ln -s "$R/sys/serial0/serial0-0" "$R/bt/hci1/device"
PATH="$R/bin:$PATH" MAC_BLUETOOTH_CLASS="$R/bt" sh "$R/recover" 0
chk helper-serial-quiet "$(exists "$R/modprobe.log")" no

# 11. The wl driver's packages: headers for every installed kernel, by its
#     package name, so a Mainstream-only install never asks for Arch's.
MAC_MODULES_DIR="$WORK/modules"
kernel() { mkdir -p "$MAC_MODULES_DIR/$1"; : > "$MAC_MODULES_DIR/$1/vmlinuz"; echo "$2" > "$MAC_MODULES_DIR/$1/pkgbase"; }
FIX_REPO="linux-headers mainstream-headers mainstream-performance-headers linux-t2-headers"
_mac_pkg_available() { [[ " $FIX_REPO " == *" $1 "* ]]; }
chk wl-no-kernel "$(mac_wl_packages)" "broadcom-wl-dkms dkms linux-headers"
kernel 7.3.6-1-mainstream mainstream
chk wl-mainstream-only "$(mac_wl_packages)" "broadcom-wl-dkms dkms mainstream-headers"
kernel 7.3.6-1-mainstream-performance mainstream-performance
kernel 7.3.6-arch1-1 linux
chk wl-every-kernel "$(mac_wl_packages | tr ' ' '\n' | sort | paste -sd' ')" "broadcom-wl-dkms dkms linux-headers mainstream-headers mainstream-performance-headers"
rm -rf "$MAC_MODULES_DIR"; kernel 7.3.6-arch1-1-t2 linux-t2
chk wl-t2 "$(mac_wl_packages)" "broadcom-wl-dkms dkms linux-t2-headers"
# A headers-only tree is no kernel; headers no repository carries are left out.
mkdir -p "$MAC_MODULES_DIR/7.3.5-1-mainstream"; echo mainstream > "$MAC_MODULES_DIR/7.3.5-1-mainstream/pkgbase"
kernel 7.2.0-1-custom linux-custom
chk wl-skips "$(mac_wl_packages 2>/dev/null)" "broadcom-wl-dkms dkms linux-t2-headers"
chk wl-skips-says "$(mac_wl_packages 2>&1 >/dev/null)" "mac-config: no linux-custom-headers in the repositories"
unset MAC_MODULES_DIR

# 12. Whether the kernel drives the T2, read off t2bce_core in its module tree:
#     the running kernel's when its tree is here, otherwise any installed kernel's.
MAC_MODULES_DIR="$WORK/t2-modules"
FIX_UNAME="7.3.6-2-mainstream"
_mac_uname_r() { printf '%s\n' "$FIX_UNAME"; }
tree() {  # release, "dep" or "builtin" or "none", [vmlinuz]
    local d="$MAC_MODULES_DIR/$1"
    mkdir -p "$d"
    : > "$d/modules.dep"; : > "$d/modules.builtin"
    case "$2" in
        dep)     printf '%s\n' 'kernel/drivers/staging/t2bce/t2bce_vhci.ko.zst: kernel/drivers/staging/t2bce/t2bce_core.ko.zst' \
                     'kernel/drivers/staging/t2bce/t2bce_core.ko.zst:' > "$d/modules.dep" ;;
        builtin) echo 'kernel/drivers/staging/t2bce/t2bce_core.ko' > "$d/modules.builtin" ;;
    esac
    [[ -z "${3:-}" ]] || : > "$d/vmlinuz"
}
supported() { real_mac_has_t2_support && echo yes || echo no; }
tree 7.3.6-2-mainstream dep vmlinuz
chk support-running-module "$(supported)" yes
rm -rf "$MAC_MODULES_DIR"; tree 7.3.6-2-mainstream builtin vmlinuz
chk support-running-builtin "$(supported)" yes
# Mid-transaction: the module is unpacked but depmod has not run yet.
rm -rf "$MAC_MODULES_DIR"; tree 7.3.6-2-mainstream none vmlinuz
rm -f "$MAC_MODULES_DIR/7.3.6-2-mainstream/modules.dep"
mkdir -p "$MAC_MODULES_DIR/7.3.6-2-mainstream/kernel/drivers/staging/t2bce/t2bce_core"
: > "$MAC_MODULES_DIR/7.3.6-2-mainstream/kernel/drivers/staging/t2bce/t2bce_core/t2bce_core.ko.zst"
chk support-running-no-depmod "$(supported)" yes
# The old bridge driver's name is not the T2 support of today's kernels.
rm -rf "$MAC_MODULES_DIR"; tree 7.3.6-2-mainstream none vmlinuz
echo 'kernel/drivers/misc/apple-bce.ko.zst:' > "$MAC_MODULES_DIR/7.3.6-2-mainstream/modules.dep"
chk support-running-none "$(supported)" no
# The running kernel decides, even with a T2 kernel installed beside it.
tree 7.3.6-2-mainstream-performance dep vmlinuz
chk support-running-wins "$(supported)" no
# An installer chroot: the running kernel's tree is not here, the installed ones are.
FIX_UNAME="7.3.5-1-live"
chk support-chroot-any "$(supported)" yes
rm -rf "$MAC_MODULES_DIR"; tree 7.3.6-arch1-1 none vmlinuz
chk support-chroot-none "$(supported)" no
# A headers-only tree is no kernel.
tree 7.3.4-1-mainstream dep
chk support-chroot-headers-only "$(supported)" no
unset MAC_MODULES_DIR

# 13. A T2 Mac whose kernel drives it: the keyboard early, at boot and in the
#     initramfs, and fan control with a section for every fan t2fanrd will find.
setup t2-early "root=UUID=1313 rw"
FIX_PRODUCT="MacBookPro16,1"; FIX_PCI="$T2_4377_PCI"; FIX_T2_SUPPORT=true; FIX_T2FANRD=true
mac_apply_autoconfig
chk t2-early-modules-load "$(cat "$R/modules-load/mainstream-t2.conf" 2>/dev/null | tr '\n' ' ')" "t2bce_vhci t2bce_ave "
chk t2-early-initramfs "$(tr ' ' '\n' < "$R/mkinitcpio.conf" | sed 's/^MODULES=(//; s/)$//' | grep -v '^$' | sort | paste -sd' ')" \
    "hid_apple hid_generic t2bce_vhci? usbhid xhci_hcd xhci_pci"
chk t2-early-fan1 "$(sed -n '/^\[Fan1\]$/,/^$/p' "$R/t2fand.conf" | grep -c -e '^low_temp=55$' -e '^high_temp=75$' -e '^speed_curve=linear$' -e '^always_full_speed=false$')" 4
chk t2-early-fan2 "$(grep -c '^\[Fan2\]$' "$R/t2fand.conf")" 1
chk t2-early-two-fans "$(grep -c '^\[Fan' "$R/t2fand.conf")" 2
mac_apply_autoconfig
chk t2-early-rerun-once "$(grep -o 't2bce_vhci?' "$R/mkinitcpio.conf" | wc -l | tr -d ' ')" 1
chk t2-early-report "$(mac_report | grep -c -e 'T2 keyboard: t2bce_vhci' -e 'T2 fan control: t2fanrd enabled')" 2
# A configuration that is already there is the user's.
printf '[Fan1]\nlow_temp=40\n' > "$R/t2fand.conf"
mac_apply_autoconfig
chk t2-fan-conf-kept "$(cat "$R/t2fand.conf")" "$(printf '[Fan1]\nlow_temp=40')"
# Three fans t2fanrd would count, and the GPU's that it leaves out.
setup t2-fans "root=UUID=1314 rw"
for h in 0:macsmc_hwmon:fan1 0:macsmc_hwmon:fan2 1:macsmc_hwmon:fan3 2:amdgpu:fan1; do
    IFS=: read -r n name fan <<<"$h"
    mkdir -p "$R/hwmon/hwmon$n"; echo "$name" > "$R/hwmon/hwmon$n/name"; : > "$R/hwmon/hwmon$n/${fan}_input"
done
mac_apply_autoconfig
chk t2-fans-three "$(grep -c '^\[Fan' "$R/t2fand.conf")" 3
# Without t2fanrd there is no configuration for it.
setup t2-no-fanrd "root=UUID=1315 rw"
FIX_T2FANRD=false
mac_apply_autoconfig
chk t2-no-fanrd-conf "$(exists "$R/t2fand.conf")" no
chk t2-no-fanrd-keyboard "$(exists "$R/modules-load/mainstream-t2.conf")" yes
# A kernel without the T2 drivers gets neither.
setup t2-unsupported "root=UUID=1316 rw"
FIX_T2_SUPPORT=false; FIX_T2FANRD=true
mac_apply_autoconfig
chk t2-unsupported-modules-load "$(exists "$R/modules-load/mainstream-t2.conf")" no
chk t2-unsupported-initramfs "$(cat "$R/mkinitcpio.conf")" "MODULES=()"
chk t2-unsupported-fan "$(exists "$R/t2fand.conf")" no
# A Mac without the T2 gets neither.
setup t2-none "root=UUID=1317 rw"
FIX_PRODUCT="MacBookPro14,1"; FIX_PCI="02:00.0 Network controller [0280]: Broadcom Inc. [14e4:43ba]"; FIX_T2_SUPPORT=true
mac_apply_autoconfig
chk t2-none-modules-load "$(exists "$R/modules-load/mainstream-t2.conf")" no
chk t2-none-fan "$(exists "$R/t2fand.conf")" no

# 14. The T2 packages: on a T2 Mac only, those not installed that a repository offers.
FIX_REPO="t2fanrd apple-t2-audio-config"; FIX_INSTALLED=""
chk t2-pkgs-not-t2 "$(mac_t2_packages)" ""
FIX_PCI="$T2_PCI"
chk t2-pkgs-both "$(mac_t2_packages)" "t2fanrd apple-t2-audio-config"
FIX_INSTALLED="t2fanrd"
chk t2-pkgs-missing-one "$(mac_t2_packages)" "apple-t2-audio-config"
FIX_INSTALLED=""; FIX_REPO="apple-t2-audio-config"
chk t2-pkgs-offered-only "$(mac_t2_packages)" "apple-t2-audio-config"
FIX_REPO=""
chk t2-pkgs-none-offered "$(mac_t2_packages)" ""

# 15. The live session: a T2 Mac gets its keyboard and camera drivers and its fan
#     control started; anything else gets neither.
CALLS="$WORK/calls"
modprobe() { echo "modprobe $*" >> "$CALLS"; }
systemctl() { echo "systemctl $*" >> "$CALLS"; }
systemd-run() { echo "systemd-run $*" >> "$CALLS"; }
session() {  # name pci product t2-support fanrd
    setup "session-$1" -
    : > "$CALLS"
    MAC_FNMODE_PARAM="$R/fnmode" MAC_SPI_FNMODE_PARAM="$R/spi-fnmode" MAC_INPUT_DEVICES="$R/input"
    FIX_VENDOR="Apple Inc."; FIX_PCI="$2"; FIX_PRODUCT="$3"; FIX_T2_SUPPORT="$4"; FIX_T2FANRD="$5"
    mac_apply_session_quirks
}
session t2 "$T2_PCI" "MacBookPro15,1" true true
chk session-t2-drivers "$(count 'modprobe -a t2bce_vhci t2bce_ave' "$CALLS")" 1
chk session-t2-fan-conf "$(grep -c '^\[Fan' "$R/t2fand.conf")" 2
chk session-t2-fan-start "$( [[ -d /run/systemd/system ]] && count 'systemctl start --no-block t2fanrd.service' "$CALLS" || echo 1)" 1
printf '[Fan1]\nlow_temp=40\n' > "$R/t2fand.conf"
mac_apply_session_quirks
chk session-t2-fan-conf-kept "$(cat "$R/t2fand.conf")" "$(printf '[Fan1]\nlow_temp=40')"
session t2-no-fanrd "$T2_PCI" "MacBookPro15,1" true false
chk session-no-fanrd-drivers "$(count 'modprobe -a t2bce_vhci' "$CALLS")" 1
chk session-no-fanrd-start "$(count 't2fanrd' "$CALLS")" 0
chk session-no-fanrd-conf "$(exists "$R/t2fand.conf")" no
session t2-unsupported "$T2_PCI" "MacBookPro15,1" false true
chk session-unsupported "$(count 't2bce\|t2fanrd' "$CALLS") $(exists "$R/t2fand.conf")" "0 no"
session no-t2 "02:00.0 Network controller [0280]: Broadcom Inc. [14e4:43ba]" "MacBookPro14,1" true true
chk session-no-t2 "$(count 't2bce\|t2fanrd' "$CALLS") $(exists "$R/t2fand.conf")" "0 no"
setup session-non-apple -
: > "$CALLS"; FIX_VENDOR="LENOVO"; FIX_PCI="$T2_PCI"; FIX_T2_SUPPORT=true; FIX_T2FANRD=true
mac_apply_session_quirks
chk session-non-apple "$(wc -l < "$CALLS" | tr -d '[:space:]') $(exists "$R/t2fand.conf")" "0 no"
unset -f modprobe systemctl systemd-run

if [[ $FAILS -eq 0 ]]; then echo "mac_config: all $CASES cases PASS"; exit 0
else echo "mac_config: $FAILS assertion(s) FAILED across $CASES cases"; exit 1; fi
