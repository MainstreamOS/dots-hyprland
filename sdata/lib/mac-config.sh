# Apple hardware configuration shared by the dots ./setup and archiso install
# paths. This file is sourced, never executed: it defines functions and writes
# nothing until mac_apply_autoconfig is called.
#
# Scope is Intel Macs on a stock kernel. Everything the 2015-2017 machines need
# is in mainline now (applespi, hid_apple, applesmc, apple-gmux), so this is
# module options and initramfs entries rather than drivers.
#
# T2 machines (2018-2020) are detected but not configured. Their internal
# keyboard, trackpad, audio and fan control live behind a patched kernel this
# project does not ship, and reporting that plainly beats leaving someone to
# work out why the keyboard is dead.
#
# Write seams match gpu-config.sh so both libraries behave the same when sourced
# together:
#   GPU_SUDO        '' (chroot/root/test) or 'sudo' (dots live)
#   MKINITCPIO_CONF default /etc/mkinitcpio.conf
#   MODPROBE_DIR    default /etc/modprobe.d
#   SYSTEMD_DIR     default /etc/systemd/system

# ── Hardware probes (overridable for testing) ───────────────────────────────
_mac_sys_vendor()  { cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true; }
_mac_product()     { cat /sys/class/dmi/id/product_name 2>/dev/null || true; }
_mac_pci()         { lspci -nn 2>/dev/null || true; }

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

# ── mac_apply_autoconfig ────────────────────────────────────────────────────
# Idempotent. A no-op on anything that is not an Apple machine.
mac_apply_autoconfig() {
    local modprobe_dir="${MODPROBE_DIR:-/etc/modprobe.d}"
    local systemd_dir="${SYSTEMD_DIR:-/etc/systemd/system}"
    mac_is_apple || return 0

    # Media keys without holding fn, which is what the printed keycaps promise.
    # Gated on Apple hardware: an Apple keyboard quirk applied to every machine
    # is a surprise nobody asked for.
    printf 'options hid_apple fnmode=2\n' \
        | _mac_write_file "$modprobe_dir/mainstream-apple.conf" 644

    if mac_needs_brcmfmac_quirk; then
        printf 'options brcmfmac feature_disable=0x82000\n' \
            | _mac_write_file "$modprobe_dir/mainstream-apple-wifi.conf" 644
    fi

    if mac_needs_spi_input; then
        # intel_lpss_pci brings up the SPI controller the keyboard hangs off.
        if command -v mkinitcpio_add_modules >/dev/null 2>&1; then
            mkinitcpio_add_modules applespi intel_lpss_pci spi_pxa2xx_platform
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
        ${GPU_SUDO:-} systemctl enable mainstream-mac-nvme.service >/dev/null 2>&1 || true
    fi

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
    [ "$class" = t2 ] && cat <<'T2'
  T2 security chip present. The internal keyboard, trackpad, audio and fan
  control need a patched kernel that is not shipped here. A USB keyboard and
  mouse are required on this machine.
T2
    return 0
}
