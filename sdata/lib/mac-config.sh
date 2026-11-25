# Apple hardware configuration shared by the dots ./setup and archiso install
# paths. This file is sourced, never executed: it defines functions and writes
# nothing until mac_apply_autoconfig is called.
#
# Scope is Intel Macs on a stock kernel. Everything the 2015-2017 machines need
# is in mainline now (applespi, hid_apple, applesmc, apple-gmux), so this is
# module options and initramfs entries rather than drivers.
#
# T2 machines (2018-2020) need a patched kernel for the internal keyboard,
# trackpad, audio and fans. Only the MacBook edition ships one, linux-t2, and
# there this also sets the boot options its T2 drivers want. Wi-Fi and
# Bluetooth run on stock drivers in every edition, with the Broadcom firmware
# fetched where the chip needs it, and the UART Bluetooth models get a
# recovery service.
#
# Write seams match gpu-config.sh so both libraries behave the same when sourced
# together:
#   GPU_SUDO        '' (chroot/root/test) or 'sudo' (dots live)
#   MKINITCPIO_CONF default /etc/mkinitcpio.conf
#   MODPROBE_DIR    default /etc/modprobe.d
#   SYSTEMD_DIR     default /etc/systemd/system
#   KERNEL_CMDLINE  default /etc/kernel/cmdline
#   MAC_HELPER_DIR  default /usr/local/lib/mainstream-mac
#   MAC_STATE_DIR   default /var/lib/mainstream

# ── Hardware probes (overridable for testing) ───────────────────────────────
_mac_sys_vendor()  { cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true; }
_mac_product()     { cat /sys/class/dmi/id/product_name 2>/dev/null || true; }
_mac_pci()         { lspci -nn 2>/dev/null || true; }
_mac_proc_cmdline() { cat /proc/cmdline 2>/dev/null || true; }
# ACPI lists devices the firmware hides (the MacPro7,1's) too, so status bit 0
# decides; no status file means no _STA, which ACPI reads as present.
_mac_acpi_uart_bt() {
    local d s
    for d in "${MAC_ACPI_DIR:-/sys/bus/acpi/devices}"/BCM2E7C*; do
        [ -e "$d" ] || continue
        s="$(cat "$d/status" 2>/dev/null)" || return 0
        [ $(( ${s:-0} & 1 )) -eq 1 ] && return 0
    done
    return 1
}

_mac_write_file() {
    local dest="$1" mode="${2:-644}" tmp
    tmp="$(mktemp)"
    cat >"$tmp"
    ${GPU_SUDO:-} install -m "$mode" -D "$tmp" "$dest"
    rm -f "$tmp"
}

# ── mac_is_apple ────────────────────────────────────────────────────────────
mac_is_apple() {
    case "$(_mac_sys_vendor)" in
        Apple*) return 0 ;;
        *)      return 1 ;;
    esac
}

# ── mac_has_t2 ──────────────────────────────────────────────────────────────
# Apple vendor 106b, T2 device 1801 or 1802. Matched against a captured string
# rather than piped into grep -q: grep closing the pipe early sends SIGPIPE to
# lspci, and under pipefail that reads as a failure on exactly the hardware
# being looked for.
mac_has_t2() {
    local pci; pci="$(_mac_pci)"
    case "$pci" in
        *106b:1801*|*106b:1802*) return 0 ;;
        *)                       return 1 ;;
    esac
}

# ── mac_class ───────────────────────────────────────────────────────────────
# Prints none, intel or t2.
mac_class() {
    if ! mac_is_apple; then echo none; return 0; fi
    if mac_has_t2;     then echo t2;   return 0; fi
    echo intel
}

# ── mac_needs_spi_input ─────────────────────────────────────────────────────
# The 2015-2017 Retina models put the keyboard and trackpad on SPI rather than
# USB. Without applespi in the initramfs there is no keyboard at the disk
# encryption prompt, which strands the machine before it finishes booting.
mac_needs_spi_input() {
    case "$(_mac_product)" in
        MacBook8,1|MacBook9,1|MacBook10,1|MacBookPro13,[123]|MacBookPro14,[123]) return 0 ;;
        *) return 1 ;;
    esac
}

# ── mac_needs_nvme_quirk ────────────────────────────────────────────────────
# The same generation does not come back from suspend while its NVMe is allowed
# to enter D3cold.
mac_needs_nvme_quirk() {
    case "$(_mac_product)" in
        MacBook8,1|MacBook9,1|MacBook10,1|MacBookPro13,[123]|MacBookPro14,[123]) return 0 ;;
        *) return 1 ;;
    esac
}

# ── mac_needs_brcmfmac_quirk ────────────────────────────────────────────────
# Broadcom firmware WPA offload fails the four-way handshake against WPA2/WPA3
# transition mode access points, and the user sees "wrong password" on a correct
# password. BCM4360 and BCM4331 are excluded because they run the out-of-tree wl
# driver, which this option does not apply to.
mac_needs_brcmfmac_quirk() {
    mac_is_apple || return 1
    local pci; pci="$(_mac_pci)"
    case "$pci" in
        *14e4:43a0*|*14e4:4331*) return 1 ;;
    esac
    case "$pci" in
        *14e4:*) return 0 ;;
        *)       return 1 ;;
    esac
}

# ── mac_needs_wl_driver ─────────────────────────────────────────────────────
# The BCM4360 in the 2013-2015 Macs and the BCM4331 in the 2012 ones are the
# two chips brcmfmac never drove; only Broadcom's out-of-tree wl driver does,
# which Arch carries as a DKMS package that blacklists the in-tree drivers
# itself. BCM4360 is 14e4:43a0, BCM4331 is 14e4:4331.
mac_needs_wl_driver() {
    mac_is_apple || return 1
    local pci; pci="$(_mac_pci)"
    case "$pci" in
        *14e4:43a0*|*14e4:4331*) return 0 ;;
        *)                       return 1 ;;
    esac
}

# The packages that driver needs: the module source, DKMS, and headers for
# the kernel that is installed, named for the kernel package in use.
mac_wl_packages() {
    local kernel=linux
    if command -v pacman >/dev/null 2>&1; then
        kernel="$(pacman -Qqs '^linux(-zen|-lts|-hardened|-t2)?$' 2>/dev/null | head -n 1)"
        [ -n "$kernel" ] || kernel=linux
    fi
    echo "broadcom-wl-dkms dkms ${kernel}-headers"
}

# Whether this machine runs a kernel the image's staged header package does not
# match. The MacBook edition boots linux-t2, and the headers staged for an
# offline install are Arch's, so a driver built against them would be built for
# a kernel that is not running.
mac_kernel_is_stock() {
    command -v pacman >/dev/null 2>&1 || return 0
    # By name: linux-t2 provides linux, and pacman -Q answers with a provider.
    [ "$(pacman -Qq linux 2>/dev/null)" = linux ]
}

# Whether the kernel this system runs drives the T2. The MacBook edition ships
# linux-t2, which carries the bridge driver the internal keyboard, trackpad and
# audio hang off; every other edition ships Arch's kernel, which does not. The
# answer changes what is true to say about a T2 machine, so ask before saying
# any of it.
mac_has_t2_support() {
    local kver; kver="$(uname -r)"
    # The kernel that is running is the one that matters, and a running system
    # keeps its modules where they can be read. An installer chroot does not:
    # uname there reports the kernel of the image doing the installing, whose
    # modules sit outside this root, so the absence of that directory is what
    # says to ask the package set instead. Asking the package set first got this
    # backwards on a machine with the T2 kernel installed but booted from an
    # entry for another one, where it is the running kernel that decides whether
    # the keyboard works.
    if [ -d "/usr/lib/modules/$kver" ]; then
        modinfo -k "$kver" apple-bce >/dev/null 2>&1 && return 0
        modinfo -k "$kver" t2bce     >/dev/null 2>&1 && return 0
        return 1
    fi
    command -v pacman >/dev/null 2>&1 || return 1
    [ -n "$(pacman -Qq linux-t2 2>/dev/null)" ]
}

# ── mac_needs_apple_firmware ────────────────────────────────────────────────
# The Broadcom chips Apple paired with the T2, and the one in the 2019 iMacs,
# run on firmware that linux-firmware does not carry and nobody may ship.
# BCM4364 is 14e4:4464, BCM4377 is 14e4:4488, BCM4355 is 14e4:43dc.
mac_needs_apple_firmware() {
    mac_is_apple || return 1
    local pci; pci="$(_mac_pci)"
    case "$pci" in
        *14e4:4464*|*14e4:4488*|*14e4:43dc*) return 0 ;;
        *)                                   return 1 ;;
    esac
}

# Whether the firmware those chips need is already on this system. The chip test
# above answers "does this machine need it", which is not the same question: a
# test image bakes it in, and an installed machine has already fetched it. Same
# names mainstream-mac-firmware --check looks for, kept here so the answer does
# not depend on that script being installed.
#
# The fetch leaves a stamp when the whole set is in. Firmware with no stamp
# (baked into an image, or fetched before the stamp existed) counts only when
# this machine's chip has each kind of file the fetch installs, so a set that
# was cut short part way is fetched again.
mac_apple_firmware_present() {
    local dir="${MAC_FIRMWARE_DIR:-/usr/lib/firmware}" f pci chip="" pattern
    [ -e "$dir/brcm/.mainstream-mac-firmware" ] && return 0
    pci="$(_mac_pci)"
    case "$pci" in
        *14e4:4464*) chip=4364 ;;
        *14e4:4488*) chip=4377 ;;
        *14e4:43dc*) chip=4355 ;;
    esac
    if [ -n "$chip" ]; then
        set -- "brcmfmac${chip}*-pcie.apple*.bin" "brcmfmac${chip}*-pcie.apple*.clm_blob" "brcmfmac${chip}*-pcie.apple*.txt"
        # Only this chip's Bluetooth takes firmware from the same fetch.
        [ "$chip" = 4377 ] && set -- "$@" "brcmbt4377*.bin"
        for pattern in "$@"; do
            for f in "$dir"/brcm/$pattern; do
                [ -e "$f" ] && continue 2
            done
            return 1
        done
        return 0
    fi
    for f in "$dir"/brcm/brcmfmac4364*-pcie.apple*.bin \
             "$dir"/brcm/brcmfmac4377*-pcie.apple*.bin \
             "$dir"/brcm/brcmfmac4355*-pcie.apple*.bin; do
        [ -e "$f" ] && return 0
    done
    return 1
}

# ── mac_needs_t2_cmdline ────────────────────────────────────────────────────
# t2linux's options for the T2 drivers only linux-t2 has; pm_async=off replaced
# pcie_ports=compat in April 2026, as compat turns off Thunderbolt's PCIe hotplug.
mac_t2_cmdline_tokens() { echo intel_iommu=on iommu=pt pm_async=off; }
mac_needs_t2_cmdline() {
    mac_has_t2 && mac_has_t2_support
}

# ── mac_needs_t2_uart_bt ────────────────────────────────────────────────────
# The BCM4364 models, MacBookPro15,1 among them, attach Bluetooth over a UART
# (ACPI BCM2E7C, driven by hci_uart) rather than over PCIe like the BCM4377.
mac_needs_t2_uart_bt() {
    mac_has_t2 && _mac_acpi_uart_bt
}

# Adds the T2 options whose keys the user has not set and drops the earlier
# pcie_ports=compat, once per option set, so an option taken out stays out.
mac_apply_t2_cmdline() {
    local kc="${KERNEL_CMDLINE:-/etc/kernel/cmdline}" tok t found
    local mark="${MAC_STATE_DIR:-/var/lib/mainstream}/t2-cmdline-options"
    local -a toks=() missing=()
    mac_needs_t2_cmdline || return 0
    [ -f "$kc" ] || return 0
    [ "$(cat "$mark" 2>/dev/null)" != "$(mac_t2_cmdline_tokens)" ] || return 0
    declare -F cmdline_upsert >/dev/null && declare -F cmdline_remove >/dev/null || return 0
    read -ra toks <<<"$(_gpu_cmdline_current | tr '\n' ' ')" || true
    for t in "${toks[@]}"; do
        if [ "$t" = pcie_ports=compat ]; then
            cmdline_remove pcie_ports
            break
        fi
    done
    for tok in $(mac_t2_cmdline_tokens); do
        found=0
        for t in "${toks[@]}"; do
            if [ "${t%%=*}" = "${tok%%=*}" ]; then
                found=1
                break
            fi
        done
        [ "$found" -eq 1 ] || missing+=("$tok")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        cmdline_upsert "${missing[@]}" || return 1
    fi
    mac_t2_cmdline_tokens | _mac_write_file "$mark" 644
}

# Whether /etc/kernel/cmdline differs from the running kernel in a T2 option
# it sets or the pcie_ports=compat it dropped, so the boot images need a rebuild.
mac_t2_cmdline_pending() {
    local kc="${KERNEL_CMDLINE:-/etc/kernel/cmdline}" want have tok
    mac_needs_t2_cmdline && [ -f "$kc" ] || return 1
    want=" $(grep -v '^[[:space:]]*#' "$kc" | tr '\n' ' ') "
    have=" $(_mac_proc_cmdline | tr '\n' ' ') "
    for tok in $(mac_t2_cmdline_tokens); do
        if [[ "$want" == *" $tok "* && "$have" != *" $tok "* ]]; then
            return 0
        fi
    done
    [[ "$have" == *" pcie_ports=compat "* && "$want" != *" pcie_ports=compat "* ]]
}

# Reloads hci_uart when no serial-attached Bluetooth controller has appeared
# within the given seconds. POSIX sh, so the units run it without this library.
_mac_t2_bt_recover_script() {
    cat <<'SH'
#!/bin/sh
# Written by mac-config.sh: reloads hci_uart when this Mac's UART Bluetooth has
# no controller after $1 seconds (default 10).
class="${MAC_BLUETOOTH_CLASS:-/sys/class/bluetooth}"
have_uart_hci() {
    for dev in "$class"/hci*; do
        [ -e "$dev/device" ] || continue
        case "$(readlink -f "$dev/device")" in */serial*) return 0 ;; esac
    done
    return 1
}
i=0
while ! have_uart_hci; do
    if [ "$i" -ge "${1:-10}" ]; then
        modprobe -r hci_uart 2>/dev/null
        exec modprobe -b hci_uart
    fi
    sleep 1
    i=$((i + 1))
done
SH
}

# ── mac_apply_autoconfig ────────────────────────────────────────────────────
# Idempotent. A no-op on anything that is not an Apple machine.
mac_apply_autoconfig() {
    local modprobe_dir="${MODPROBE_DIR:-/etc/modprobe.d}"
    local systemd_dir="${SYSTEMD_DIR:-/etc/systemd/system}"
    local helper="${MAC_HELPER_DIR:-/usr/local/lib/mainstream-mac}/t2-bluetooth-recover"
    mac_is_apple || return 0

    # Media keys without holding fn, the way the keycaps read and the way the
    # same machine behaves under macOS. fnmode 1 is fkeyslast: brightness and
    # volume are the plain press and F1 to F12 want fn. Gated on Apple
    # hardware, since an Apple keyboard quirk applied to every machine is a
    # surprise nobody asked for.
    printf 'options hid_apple fnmode=1\n' \
        | _mac_write_file "$modprobe_dir/mainstream-apple.conf" 644
    if mac_needs_spi_input; then
        # These keyboards are not hid_apple at all, so that option never
        # reaches them. applespi carries the same knob under its own name.
        printf 'options applespi fnmode=1\n' \
            | _mac_write_file "$modprobe_dir/mainstream-apple-spi.conf" 644
    fi

    if mac_needs_brcmfmac_quirk; then
        printf 'options brcmfmac feature_disable=0x82000\n' \
            | _mac_write_file "$modprobe_dir/mainstream-apple-wifi.conf" 644
    fi

    if mac_needs_spi_input; then
        # The SPI controller the keyboard hangs off is a plain PCI device on
        # the 2015 12-inch MacBook and sits behind Intel's LPSS bridge on
        # every later model, so the two need different modules to reach it.
        if command -v mkinitcpio_add_modules >/dev/null 2>&1; then
            if [ "$(_mac_product)" = "MacBook8,1" ]; then
                mkinitcpio_add_modules applespi spi_pxa2xx_platform spi_pxa2xx_pci
            else
                mkinitcpio_add_modules applespi intel_lpss_pci spi_pxa2xx_platform
            fi
        fi
    fi

    if mac_needs_nvme_quirk; then
        printf '%s\n' \
            '[Unit]' \
            'Description=Keep the NVMe out of D3cold so this Mac resumes from suspend' \
            'After=multi-user.target' \
            '' \
            '[Service]' \
            'Type=oneshot' \
            'RemainAfterExit=yes' \
            'ExecStart=/bin/sh -c '"'"'for d in /sys/class/nvme/nvme*/device/d3cold_allowed; do [ -w "$d" ] && echo 0 > "$d"; done; exit 0'"'"'' \
            '' \
            '[Install]' \
            'WantedBy=multi-user.target' \
            | _mac_write_file "$systemd_dir/mainstream-mac-nvme.service" 644
        if [ "$systemd_dir" = /etc/systemd/system ]; then
            ${GPU_SUDO:-} systemctl enable mainstream-mac-nvme.service >/dev/null 2>&1 || true
        fi
    fi

    # The firmware fetch needs a network the machine may not have until
    # something wired is plugged in, so a timer keeps asking until the files
    # are in place, and the script stops the timer itself once they are.
    if mac_needs_apple_firmware; then
        printf '%s\n' \
            '[Unit]' \
            "Description=Fetch this Mac's Wi-Fi and Bluetooth firmware from Apple's recovery image" \
            'After=network-online.target' \
            'Wants=network-online.target' \
            'ConditionPathExists=/usr/local/bin/mainstream-mac-firmware' \
            '' \
            '[Service]' \
            'Type=oneshot' \
            'ExecStart=/usr/local/bin/mainstream-mac-firmware --quiet' \
            | _mac_write_file "$systemd_dir/mainstream-mac-firmware.service" 644
        printf '%s\n' \
            '[Unit]' \
            "Description=Keep fetching this Mac's Wi-Fi and Bluetooth firmware until it is in place" \
            '' \
            '[Timer]' \
            'OnBootSec=1min' \
            'OnUnitActiveSec=20min' \
            '' \
            '[Install]' \
            'WantedBy=timers.target' \
            | _mac_write_file "$systemd_dir/mainstream-mac-firmware.timer" 644
        if [ "$systemd_dir" = /etc/systemd/system ]; then
            ${GPU_SUDO:-} systemctl enable mainstream-mac-firmware.timer >/dev/null 2>&1 || true
        fi
    fi

    mac_apply_t2_cmdline

    if mac_needs_t2_uart_bt; then
        _mac_t2_bt_recover_script | _mac_write_file "$helper" 755
        printf '%s\n' \
            '[Unit]' \
            "Description=Bring back this Mac's UART Bluetooth if it did not come up" \
            'ConditionPathExistsGlob=/sys/bus/acpi/devices/BCM2E7C*' \
            'After=systemd-modules-load.service' \
            '' \
            '[Service]' \
            'Type=oneshot' \
            'ExecStart=/usr/local/lib/mainstream-mac/t2-bluetooth-recover 10' \
            '' \
            '[Install]' \
            'WantedBy=multi-user.target' \
            | _mac_write_file "$systemd_dir/mainstream-t2-bluetooth.service" 644
        printf '%s\n' \
            '[Unit]' \
            "Description=Bring back this Mac's UART Bluetooth after sleep" \
            'ConditionPathExistsGlob=/sys/bus/acpi/devices/BCM2E7C*' \
            'After=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target' \
            '' \
            '[Service]' \
            'Type=oneshot' \
            'ExecStart=/usr/local/lib/mainstream-mac/t2-bluetooth-recover 10' \
            '' \
            '[Install]' \
            'WantedBy=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target' \
            | _mac_write_file "$systemd_dir/mainstream-t2-bluetooth-resume.service" 644
        if [ "$systemd_dir" = /etc/systemd/system ]; then
            ${GPU_SUDO:-} systemctl enable \
                mainstream-t2-bluetooth.service \
                mainstream-t2-bluetooth-resume.service >/dev/null 2>&1 || true
            if [ -d /run/systemd/system ] && ! systemd-detect-virt --chroot -q 2>/dev/null; then
                ${GPU_SUDO:-} systemctl daemon-reload >/dev/null 2>&1 || true
                ${GPU_SUDO:-} systemctl start --no-block mainstream-t2-bluetooth.service >/dev/null 2>&1 || true
            fi
        fi
    fi

    return 0
}

# ── mac_load_spi_input ──────────────────────────────────────────────────────
# The keyboard and trackpad of a 2015-2017 Retina Mac, brought up in a running
# session. An installed system gets these through the initramfs; the live image
# the installer runs from has nothing, so a machine whose only pointer is the
# trackpad can arrive at the installer unable to use it.
#
# The reload at the end is for a probe that is known to come up with the
# keyboard alive and the trackpad missing. A machine whose trackpad did appear
# is left alone: reloading a working input device under someone's fingers is
# worse than doing nothing.
mac_load_spi_input() {
    local module waited=0
    local devices="${MAC_INPUT_DEVICES:-/proc/bus/input/devices}"
    mac_needs_spi_input || return 0

    for module in intel_lpss_pci spi_pxa2xx_platform spi_pxa2xx_pci applespi; do
        ${GPU_SUDO:-} modprobe "$module" 2>/dev/null || true
    done

    # Five seconds, because this runs before the network comes up and a slow
    # answer here delays that. A trackpad that has not appeared by then is the
    # case the reload exists for.
    while [ "$waited" -lt 50 ]; do
        if grep -q 'Apple SPI Touchpad' "$devices" 2>/dev/null; then
            return 0
        fi
        waited=$((waited + 1))
        sleep 0.1
    done

    ${GPU_SUDO:-} modprobe -r applespi 2>/dev/null || true
    ${GPU_SUDO:-} modprobe applespi 2>/dev/null || true
    return 0
}

# ── mac_apply_session_quirks ────────────────────────────────────────────────
# The part of the above a running session can take without a reboot, for the
# live image the installer runs from: the Broadcom handshake fix, since the
# firmware's own attempt fails on the routers most homes have and the live
# session is where people first try to get online, and the media keys. The
# Wi-Fi driver is reloaded so the option takes; the keyboard's is not, since
# the keyboard is on it, so its setting goes in through sysfs instead.
mac_apply_session_quirks() {
    local modprobe_dir="${MODPROBE_DIR:-/etc/modprobe.d}"
    local fnmode="${MAC_FNMODE_PARAM:-/sys/module/hid_apple/parameters/fnmode}"
    local spi_fnmode="${MAC_SPI_FNMODE_PARAM:-/sys/module/applespi/parameters/fnmode}"
    mac_is_apple || return 0

    mac_load_spi_input

    printf 'options hid_apple fnmode=1\n' \
        | _mac_write_file "$modprobe_dir/mainstream-apple.conf" 644
    if [ -w "$fnmode" ]; then
        echo 1 > "$fnmode" 2>/dev/null || true
    fi
    if mac_needs_spi_input; then
        printf 'options applespi fnmode=1\n' \
            | _mac_write_file "$modprobe_dir/mainstream-apple-spi.conf" 644
        if [ -w "$spi_fnmode" ]; then
            echo 1 > "$spi_fnmode" 2>/dev/null || true
        fi
    fi

    if mac_needs_brcmfmac_quirk; then
        printf 'options brcmfmac feature_disable=0x82000\n' \
            | _mac_write_file "$modprobe_dir/mainstream-apple-wifi.conf" 644
        ${GPU_SUDO:-} modprobe -r brcmfmac_wcc brcmfmac 2>/dev/null || true
        ${GPU_SUDO:-} modprobe brcmfmac 2>/dev/null || true
    fi

    # In a unit of its own: the live quirks unit holds the network back until it ends.
    if mac_needs_t2_uart_bt && [ -d /run/systemd/system ]; then
        ${GPU_SUDO:-} systemd-run --no-block --collect --quiet --unit=mainstream-t2-bluetooth-live \
            sh -c "$(_mac_t2_bt_recover_script)" t2-bluetooth-recover 10 >/dev/null 2>&1 || true
    fi

    return 0
}

# ── mac_fetch_firmware_now ──────────────────────────────────────────────────
# One attempt from an installer that has a network, so the desktop can come up
# with Wi-Fi on the first boot. Best effort and bounded; the timer covers the
# rest. Prints nothing when there is nothing to do.
mac_fetch_firmware_now() {
    mac_needs_apple_firmware || return 0
    local script="${MAC_FIRMWARE_SCRIPT:-/usr/local/bin/mainstream-mac-firmware}"
    [ -x "$script" ] || return 0
    ${GPU_SUDO:-} timeout 900 "$script" || true
    return 0
}

# ── mac_report ──────────────────────────────────────────────────────────────
# One line per applicable quirk, for the installer log.
mac_report() {
    local class; class="$(mac_class)"
    [ "$class" = none ] && return 0
    echo "Apple hardware: $(_mac_product) (class $class)"
    mac_needs_spi_input      && echo "  SPI keyboard and trackpad: applespi added to the initramfs"
    mac_needs_nvme_quirk     && echo "  NVMe suspend quirk applied"
    mac_needs_brcmfmac_quirk && echo "  Broadcom WPA offload disabled"
    mac_needs_t2_cmdline     && echo "  T2 boot options: $(mac_t2_cmdline_tokens)"
    mac_needs_t2_uart_bt     && echo "  UART Bluetooth (BCM2E7C): recovery service at boot and after sleep"
    mac_needs_wl_driver      && echo "  Broadcom wl driver: $(mac_wl_packages)"
    if mac_needs_apple_firmware; then
        if mac_apple_firmware_present; then
            echo "  Broadcom firmware: already in place"
        else
            echo "  Broadcom firmware: fetched from Apple's recovery image on this machine, timer enabled"
        fi
    fi
    if [ "$class" = t2 ]; then
        if mac_has_t2_support; then
            cat <<'T2'
  T2 security chip present, and this edition carries the kernel that drives it.
  The internal keyboard, trackpad, audio and fan control all work.
T2
        else
            cat <<'T2'
  T2 security chip present. The internal keyboard, trackpad, audio and fan
  control need a patched kernel that is not shipped here. A USB keyboard and
  mouse are required on this machine.
T2
        fi
    fi
    return 0
}
