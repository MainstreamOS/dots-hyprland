#!/usr/bin/env bash
# gpu-config.sh — shared GPU detection + configuration library for Mainstream OS.
#
# Sourced by BOTH install paths so GPU detection, driver classification, kernel
# cmdline, modprobe.d, mkinitcpio MODULES, NVIDIA services, and Hyprland env are
# authored in exactly one place:
#   - dots ./setup (live system, runs as the user, needs sudo, writes ~/.config)
#   - archiso post-install / install-gpu-drivers (chroot, runs as root, no sudo,
#     writes $MAIN_USER_HOME)
#
# Context seams the CALLER sets before sourcing (functions never say "sudo"):
#   WRITE      install command for /etc files (default: 'sudo install -m644 -D'
#              live; 'install -m644 -D' in chroot)
#   SYSTEMCTL  systemctl invoker ('sudo systemctl' live; 'systemctl' chroot)
#   user_home  passed as an ARG to the hypr/env/hypridle writers ($HOME vs
#              $MAIN_USER_HOME)
# Detection + classification are pure reads and need no seams.
#
# All functions are written to be safe under `set -euo pipefail`.

# ── Hardware probes (overridable for testing) ───────────────────────────────
# Tests redefine these to emit fixture data instead of touching real hardware.
_gpu_lspci()      { lspci 2>/dev/null || true; }
_gpu_lspci_nn()   { lspci -nn 2>/dev/null || true; }
_gpu_sys_vendor() { cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true; }
_gpu_installed_nvidia_branch() {
    # Which frozen NVIDIA branch, if any, is installed on the system being
    # asked about. Empty on a fresh install and inside a not-yet-provisioned
    # chroot, so classification falls through to the generation map.
    command -v pacman >/dev/null 2>&1 || { printf ''; return 0; }
    local b
    for b in 580xx 470xx 390xx; do
        if pacman -Q "nvidia-${b}-dkms" >/dev/null 2>&1; then printf '%s' "$b"; return 0; fi
    done
    printf ''
}

# ── gpu_detect ──────────────────────────────────────────────────────────────
# Single detection pass. Exports (true/false unless noted):
#   HAS_NVIDIA HAS_AMD HAS_INTEL  IS_HYBRID  IS_VM
#   NVIDIA_PCI_DEC (int)  NVIDIA_GEN (turing|maxwell|kepler|fermi|prefermi|none)
#   AMD_DEC (int)         IS_OLD_AMD  IS_RDNA4
#   INTEL_GEN (xe|modern|legacy|none)
# Generation ladder (PCI device-id decimal): 7682 Turing+ (0x1E02 TITAN RTX /
# 0x1E03 RTX 2080 Ti 12GB are the lowest Turing IDs), 4928 Maxwell-Volta,
# 4032 Kepler, 1728 Fermi, below Fermi -> prefermi (nouveau).
# AMD "old" = pre-GCN: dec < 26112 AND NOT an APU (4864-5887 exemption), OR a
# pre-GCN name (HD 2xxx-6xxx / RV / RS / R[67]xx), OR one of the pre-GCN fusion
# APU id windows (Llano/Sumo 0x9640-0x964f, Wrestler 0x9802-0x980a, Trinity/
# Richland 0x9900-0x9919 and 0x9990-0x99a4). Those VLIW4/VLIW5 APUs sit well
# above the 26112 ceiling and advertise HD 7xxx/8xxx names, so neither of the
# first two tests sees them, yet they run the radeon module and predate RADV.
# The GCN APUs sharing those pages stay modern by falling outside the windows:
# Kabini/Temash 0x9830-0x983d, Mullins 0x9850-0x985f, Carrizo/Stoney
# 0x9870-0x98e4, Kaveri 0x1300-0x131d. RDNA4 (Navi 4x / RX 9xxx / gfx12) always
# forces modern.
# Intel tiers track the two userspace boundaries that actually change packages:
#   xe     Gen12+ / Arc (Tiger Lake, Alder/Raptor/Meteor/Arrow/Lunar Lake, DG1,
#          Alchemist, Battlemage). Only tier the OpenCL compute runtime and the
#          VPL runtime support — both are Gen12-and-newer upstream.
#   modern Gen8-Gen11 (Broadwell..Ice Lake). iHD VA-API, no OpenCL: upstream
#          moved Gen8-11 compute to legacy1 packages that Arch does not ship.
#   legacy Gen4-Gen7.5 (G45..Haswell). i965 VA-API — predates iHD entirely.
# Intel device IDs are not monotonic, so the tiers match known id prefixes
# newest-first and anything unrecognised falls to 'modern', which is the safe
# middle: iHD works on every Gen8+ part and no compute runtime is assumed.
# Returns 1 if no display device is found (lspci missing or none present).
gpu_detect() {
    HAS_NVIDIA=false HAS_AMD=false HAS_INTEL=false IS_HYBRID=false IS_VM=false
    NVIDIA_PCI_DEC=0 NVIDIA_GEN=none
    AMD_DEC=0 IS_OLD_AMD=false IS_RDNA4=false
    INTEL_GEN=none

    # Probe each lspci form once and reuse: -nn (with [vendor:device] IDs) for
    # the ID matches, plain names for the marketing-name regexes. Kept separate
    # on purpose — the bracketed IDs in -nn output can false-match a name regex.
    local lspci_nn lspci_names gpu_lines
    lspci_nn="$(_gpu_lspci_nn)"
    lspci_names="$(_gpu_lspci)"
    gpu_lines="$(grep -iE 'VGA|3D|Display' <<<"$lspci_nn" || true)"
    [[ -n "$gpu_lines" ]] || return 1

    case "$(_gpu_sys_vendor)" in
        *QEMU*|*VirtualBox*|*VMware*|*Microsoft*|*Parallels*|*Xen*) IS_VM=true ;;
    esac

    if grep -q '\[10de:' <<<"$gpu_lines"; then HAS_NVIDIA=true; fi
    if grep -q '\[1002:' <<<"$gpu_lines"; then HAS_AMD=true;    fi
    if grep -q '\[8086:' <<<"$gpu_lines"; then HAS_INTEL=true;  fi

    local count=0
    [[ $HAS_NVIDIA == true ]] && count=$((count + 1)) || true
    [[ $HAS_AMD    == true ]] && count=$((count + 1)) || true
    [[ $HAS_INTEL  == true ]] && count=$((count + 1)) || true
    [[ $count -gt 1 ]] && IS_HYBRID=true || true

    if [[ $HAS_NVIDIA == true ]]; then
        local pci_line pci_id
        pci_line="$(grep -iE 'NVIDIA|GeForce|Quadro|Tesla' <<<"$gpu_lines" | head -1 || true)"
        pci_id="$(grep -oE '\[10de:[0-9a-fA-F]{4}\]' <<<"$pci_line" | tail -1 | grep -oE '[0-9a-fA-F]{4}' | tail -1 || true)"
        NVIDIA_PCI_DEC=$((16#${pci_id:-0}))
        if   [[ $NVIDIA_PCI_DEC -ge 7682 ]]; then NVIDIA_GEN=turing
        elif [[ $NVIDIA_PCI_DEC -ge 4928 ]]; then NVIDIA_GEN=maxwell
        # Fermi and Kepler interleave: GF119 0x1040, GF110 0x1080, GF117 0x1140
        # and GF116 0x1240 all sit above GK107 at 0x0FC0, while Kepler owns
        # 0x0FC0-0x103F, 0x1180-0x123F and 0x1280 up. A 390xx card handed
        # 470xx here has no driver at all.
        elif (( (NVIDIA_PCI_DEC >= 16#1040 && NVIDIA_PCI_DEC <= 16#117f) \
             || (NVIDIA_PCI_DEC >= 16#1240 && NVIDIA_PCI_DEC <= 16#127f) )); then NVIDIA_GEN=fermi
        elif [[ $NVIDIA_PCI_DEC -ge 4032 ]]; then NVIDIA_GEN=kepler
        elif [[ $NVIDIA_PCI_DEC -ge 1728 ]]; then NVIDIA_GEN=fermi
        else                                       NVIDIA_GEN=prefermi
        fi
    fi

    if [[ $HAS_AMD == true ]]; then
        local amd_id amd_name
        amd_id="$(grep '1002:' <<<"$gpu_lines" | grep -oE '1002:[0-9a-fA-F]{4}' | head -1 | cut -d: -f2 || true)"
        AMD_DEC=$((16#${amd_id:-ffff}))
        if [[ $AMD_DEC -lt 26112 ]] && ! [[ $AMD_DEC -ge 4864 && $AMD_DEC -le 5887 ]]; then IS_OLD_AMD=true; fi
        amd_name="$(grep -iE 'VGA|3D|Display' <<<"$lspci_names" | grep -iE 'AMD|ATI|Radeon' | head -1 || true)"
        if grep -iqE '\bHD [2-6][0-9]{3}\b|\bRS[0-9]+\b|\bRV[0-9]+\b|\bR[67][0-9]{2}\b' <<<"$amd_name"; then IS_OLD_AMD=true; fi
        # Modern integrated Radeon (Ryzen APUs) — some new IDs sit below the
        # APU-exemption window (e.g. Krackan 0x1114), so rescue them by name.
        # 'Radeon NxxxM' / bare 'Radeon Graphics' never appear on pre-GCN parts.
        local amd_display_names
        amd_display_names="$(grep -iE 'VGA|3D|Display' <<<"$lspci_names" || true)"
        if grep -iqE '\bRadeon [678][0-9]0M\b|Radeon Graphics' <<<"$amd_display_names"; then IS_OLD_AMD=false; fi
        # Pre-GCN fusion APUs (radeon module, no RADV) — exact id windows win
        # over the name tests above; see the header for the GCN parts excluded.
        if (( (AMD_DEC >= 16#9640 && AMD_DEC <= 16#964f) \
           || (AMD_DEC >= 16#9802 && AMD_DEC <= 16#980a) \
           || (AMD_DEC >= 16#9900 && AMD_DEC <= 16#9919) \
           || (AMD_DEC >= 16#9990 && AMD_DEC <= 16#99a4) )); then IS_OLD_AMD=true; fi
        if grep -iqE 'Navi 4[0-9]|RX 9[0-9]{3}|gfx12' <<<"$amd_display_names"; then IS_RDNA4=true; IS_OLD_AMD=false; fi
    fi

    if [[ $HAS_INTEL == true ]]; then
        local intel_id intel_name
        intel_id="$(grep -oE '8086:[0-9a-fA-F]{4}' <<<"$gpu_lines" | head -1 | cut -d: -f2 | tr 'A-F' 'a-f' || true)"
        intel_name="$(grep -iE 'VGA|3D|Display' <<<"$lspci_names" | grep -i 'Intel' | head -1 || true)"
        # 46 Alder Lake, 4c Rocket Lake, 56 DG2/Alchemist, 64 Lunar Lake,
        # 7d Meteor/Arrow Lake, 9a Tiger Lake, a7 Raptor Lake, b0 Panther Lake,
        # e2 Battlemage, 4905-4909 DG1. Gen9 'Iris Plus'/'Iris Pro' deliberately
        # do not match the name test — only 'Iris Xe' is Gen12.
        if [[ "$intel_id" =~ ^(46|4c|56|64|7d|9a|a7|b0|e2)[0-9a-f]{2}$ || "$intel_id" =~ ^490[5-9]$ ]] \
            || grep -iqE '\bArc\b|Iris Xe|Alchemist|Battlemage|\bDG[12]\b' <<<"$intel_name"; then
            INTEL_GEN=xe
        # Ironlake/Sandy/Ivy/Haswell all live in 0xxx; Gen4 spans 2772-2e92.
        # 0x22xx (Cherryview, Gen8) is excluded from the second range on purpose.
        elif [[ "$intel_id" =~ ^0[0-9a-f]{3}$ || "$intel_id" =~ ^2[6-9a-e][0-9a-f]{2}$ ]]; then
            INTEL_GEN=legacy
        else
            INTEL_GEN=modern
        fi
    fi

    return 0
}

# ── gpu_classify_nvidia_driver ──────────────────────────────────────────────
# Maps NVIDIA_GEN (set by gpu_detect) to the driver family + package sets.
# Exports: NVIDIA_DRIVER_FAMILY, and arrays NVIDIA_REPO_PKGS (pacman -S) and
# NVIDIA_LOCAL_PKGS (legacy DKMS prebuilts, pacman -U). The CALLER owns the
# install (live -S from repo; chroot -S + -U + DKMS-against-target-kernel), and
# is responsible for the nouveau+breadcrumb fallback when local pkgs are absent.
# Turing+ default is nvidia-open (the locked policy).
_gpu_frozen_family() {
    case "$1" in
        580xx)
            NVIDIA_DRIVER_FAMILY=nvidia-580xx
            NVIDIA_LOCAL_PKGS=(nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils nvidia-580xx-settings libxnvctrl-580xx) ;;
        470xx)
            NVIDIA_DRIVER_FAMILY=nvidia-470xx
            NVIDIA_LOCAL_PKGS=(nvidia-470xx-dkms nvidia-470xx-utils lib32-nvidia-470xx-utils) ;;
        390xx)
            NVIDIA_DRIVER_FAMILY=nvidia-390xx
            NVIDIA_LOCAL_PKGS=(nvidia-390xx-dkms nvidia-390xx-utils lib32-nvidia-390xx-utils) ;;
    esac
}
gpu_classify_nvidia_driver() {
    NVIDIA_DRIVER_FAMILY=none
    NVIDIA_REPO_PKGS=() NVIDIA_LOCAL_PKGS=()
    # A frozen branch that is already installed wins over the generation map.
    # Repair and re-provisioning must serve the install that exists: the
    # legacy edition boots on a proprietary branch the online repos do not
    # carry, and reclassifying it from scratch is how a repair ends up
    # replacing a working driver with the fresh-install pick.
    local _installed
    _installed="$(_gpu_installed_nvidia_branch)"
    if [[ -n "$_installed" ]]; then
        _gpu_frozen_family "$_installed"
        [[ "$NVIDIA_DRIVER_FAMILY" != none ]] && return 0
    fi
    case "$NVIDIA_GEN" in
        turing)
            NVIDIA_DRIVER_FAMILY=nvidia-open
            NVIDIA_REPO_PKGS=(nvidia-open nvidia-utils nvidia-settings lib32-nvidia-utils libva-nvidia-driver libva-utils) ;;
        maxwell)
            _gpu_frozen_family 580xx ;;
        kepler)
            _gpu_frozen_family 470xx ;;
        fermi)
            _gpu_frozen_family 390xx ;;
        prefermi|none)
            NVIDIA_DRIVER_FAMILY=nouveau
            NVIDIA_REPO_PKGS=(xf86-video-nouveau mesa lib32-mesa) ;;
    esac
}

# ── Write seams (caller sets these before sourcing; defaults suit chroot/root) ─
#   GPU_SUDO        '' (chroot/root/test) or 'sudo' (dots live) — prefixes /etc writes
#   KERNEL_CMDLINE  default /etc/kernel/cmdline   (point at a temp file in tests)
#   MKINITCPIO_CONF default /etc/mkinitcpio.conf
#   MODPROBE_DIR    default /etc/modprobe.d
# Write stdin to a file at its canonical path, honoring GPU_SUDO + creating dirs.
_gpu_write_file() {
    local dest="$1" mode="${2:-644}" tmp
    tmp="$(mktemp)"
    cat >"$tmp"
    ${GPU_SUDO:-} install -m "$mode" -D "$tmp" "$dest"
    rm -f "$tmp"
}

# ── gpu_base_cmdline_tokens <root_spec> [root_subvol] ───────────────────────
# Print the ONE canonical base kernel cmdline: Plymouth splash, zswap disabled,
# rd.udev.log_level=3, subvol normalized (leading slash stripped so /@ -> @).
# Caller word-splits the output into cmdline_upsert.
gpu_base_cmdline_tokens() {
    local root_spec="$1" subvol="${2:-@}"
    subvol="${subvol#/}"
    printf '%s rootflags=subvol=%s rw rootfstype=btrfs zswap.enabled=0 quiet splash rd.udev.log_level=3 vt.global_cursor_default=0 consoleblank=0 nowatchdog nmi_watchdog=0' \
        "$root_spec" "$subvol"
}

# ── cmdline_upsert <token>... ───────────────────────────────────────────────
# The ONE cmdline writer: per-key dedup upsert into $KERNEL_CMDLINE (single
# line). Seeds from the existing file, else /boot/limine.conf's cmdline:, else
# /proc/cmdline (stripping BOOT_IMAGE=/initrd=). limine regenerates limine.conf
# from /etc/kernel/cmdline, so this never writes limine.conf directly.
cmdline_upsert() {
    local kc="${KERNEL_CMDLINE:-/etc/kernel/cmdline}" current=""
    if [[ -f "$kc" ]]; then
        current="$(cat "$kc")"
    elif [[ -f /boot/limine.conf ]]; then
        current="$(awk -F': *' 'tolower($1) ~ /(kernel_)?cmdline$/ {print $2; exit}' /boot/limine.conf 2>/dev/null || true)"
    elif [[ -r /proc/cmdline ]]; then
        current="$(sed -E 's/\bBOOT_IMAGE=[^ ]*//g; s/\binitrd=[^ ]*//g' /proc/cmdline)"
    fi
    local -a toks=(); local t
    for t in $current; do toks+=("$t"); done
    local new key i found
    for new in "$@"; do
        key="${new%%=*}"; found=false
        for i in "${!toks[@]}"; do
            if [[ "${toks[$i]%%=*}" == "$key" ]]; then toks[$i]="$new"; found=true; break; fi
        done
        [[ $found == false ]] && toks+=("$new") || true
    done
    printf '%s\n' "${toks[*]}" | _gpu_write_file "$kc"
}

# ── write_modprobe_conf <nvidia|amd> ────────────────────────────────────────
# Always mkdir -p the dir first (fixes the archiso Kepler/Fermi missing-mkdir
# bug), then write the canonical per-vendor options file. One writer subsumes
# the 5 byte-identical heredocs across the two repos.
write_modprobe_conf() {
    local vendor="$1" dir="${MODPROBE_DIR:-/etc/modprobe.d}"
    ${GPU_SUDO:-} mkdir -p "$dir"
    case "$vendor" in
        nvidia)
            # fbdev=1 exists only since driver 545 (nvidia-open / 580xx); the
            # 470xx/390xx legacy branches reject the unknown param and fail to
            # load nvidia-drm, so emit it only for the modern branches.
            local fbdev=""
            case "${NVIDIA_GEN:-}" in turing|maxwell) fbdev=" fbdev=1" ;; esac
            # How a driver survives suspend is the driver's own business, and
            # since 595 mainline answers it differently from the legacy branches:
            # nvidia-utils ships nvidia-sleep.conf asking for kernel suspend
            # notifiers, where 580xx and older ask to preserve video memory.
            # Those are alternatives, not layers. This file is called nvidia.conf,
            # so it stacks on top of theirs instead of replacing it, and handing
            # the legacy answer to a driver that already gave the modern one
            # leaves both set at once. Say nothing to the branch that speaks for
            # itself.
            local sleep_opts=""
            case "${NVIDIA_GEN:-}" in
                turing) ;;
                *) sleep_opts=$'options nvidia NVreg_PreserveVideoMemoryAllocations=1\noptions nvidia NVreg_TemporaryFilePath=/var/tmp\n' ;;
            esac
            printf 'options nvidia-drm modeset=1%s\n%s' "$fbdev" "$sleep_opts" \
                | _gpu_write_file "$dir/nvidia.conf" ;;
        amd)
            printf 'options amdgpu si_support=1\noptions amdgpu cik_support=1\noptions radeon si_support=0\noptions radeon cik_support=0\n' \
                | _gpu_write_file "$dir/amdgpu.conf" ;;
    esac
}

# ── mkinitcpio_add_modules <mod>... ─────────────────────────────────────────
# Idempotent prepend into MODULES=() (guard scoped to the MODULES line). Each
# module is prepended right after "MODULES=(", so several in one call land
# reversed -- the existing behavior; modprobe resolves load order via deps.
mkinitcpio_add_modules() {
    local conf="${MKINITCPIO_CONF:-/etc/mkinitcpio.conf}" mod
    for mod in "$@"; do
        if ! grep -qE "\bMODULES=\([^)]*\b${mod}\b" "$conf"; then
            ${GPU_SUDO:-} sed -i "s/^MODULES=(/MODULES=(${mod} /" "$conf"
        fi
    done
}

# ── intel_kms_module ────────────────────────────────────────────────────────
# Which module the initramfs needs for Intel early KMS, read off the card rather
# than worked out from its generation. Whether i915 or xe claims a part is the
# kernel's call and it moves from one release to the next, so a table here would
# be a second opinion with nothing keeping it honest — and the generation tiers
# are no help either, since the one covering Xe spans parts on both sides of the
# split. Asking what is driving the card cannot disagree with the kernel, and
# follows it for free the release a default changes.
#
# i915 when nothing answers: it is what every Intel part predating the split
# uses, and it is what the initramfs named before any of this was asked.
intel_kms_module() {
    local addr drv=""
    addr="$(_gpu_lspci_d | grep -iE 'VGA compatible controller|3D controller|Display controller' \
            | grep -i 'Intel' | head -1 | awk '{print $1}' || true)"
    [[ -n "$addr" ]] && drv="$(_gpu_bound_driver "$addr")" || true
    case "$drv" in
        i915|xe) printf '%s\n' "$drv" ;;
        *)       printf 'i915\n' ;;
    esac
}

# ── mkinitcpio_remove_hook <hook> ───────────────────────────────────────────
# Idempotent removal of a HOOKS entry (scoped to the HOOKS line so MODULES and
# comments are untouched). No GPU path removes a hook today: NVIDIA used to drop
# kms, until it turned out that hook only ever collects in-kernel-tree drivers
# and so never held an NVIDIA module to begin with.
mkinitcpio_remove_hook() {
    local conf="${MKINITCPIO_CONF:-/etc/mkinitcpio.conf}" hook="$1"
    if grep -qE "^HOOKS=\([^)]*\b${hook}\b" "$conf"; then
        ${GPU_SUDO:-} sed -i -E "/^HOOKS=\(/ s/\b${hook}\b *//" "$conf"
    fi
}

# ── mkinitcpio_add_hook <hook> [<after>] ────────────────────────────────────
# Idempotent insert of a HOOKS entry: right after <after> when that hook is
# present, else before the closing paren. Scoped to the HOOKS line.
mkinitcpio_add_hook() {
    local conf="${MKINITCPIO_CONF:-/etc/mkinitcpio.conf}" hook="$1" after="${2:-}"
    grep -qE "^HOOKS=\([^)]*\b${hook}\b" "$conf" && return 0
    if [[ -n "$after" ]] && grep -qE "^HOOKS=\([^)]*\b${after}\b" "$conf"; then
        ${GPU_SUDO:-} sed -i -E "/^HOOKS=\(/ s/\b${after}\b/& ${hook}/" "$conf"
    else
        ${GPU_SUDO:-} sed -i -E "/^HOOKS=\(/ s/\)/ ${hook})/" "$conf"
    fi
}

# ── nvidia_strip_gsp_firmware ───────────────────────────────────────────────
# Pre-Turing NVIDIA cards (Maxwell/Pascal/Volta and older) never load the
# ~100 MB GSP firmware that nouveau — and the proprietary driver — declare, yet
# mkinitcpio bundles every firmware a loaded module lists, inflating the UKI
# until it no longer fits a small reused dual-boot ESP and the write ENOSPCs.
# Install a build hook that drops the GSP blobs from the initramfs (BUILDROOT
# only, so the on-disk firmware and package ownership are untouched and it keeps
# working across updates). No-op on Turing+ (which needs GSP) and with no NVIDIA.
nvidia_strip_gsp_firmware() {
    case "${NVIDIA_GEN:-none}" in
        maxwell|kepler|fermi|prefermi) ;;
        *) return 0 ;;
    esac
    local dir="${INITCPIO_INSTALL_DIR:-/etc/initcpio/install}"
    ${GPU_SUDO:-} mkdir -p "$dir"
    ${GPU_SUDO:-} tee "$dir/strip-nvidia-gsp" >/dev/null <<'HOOKEOF'
#!/bin/bash
build() {
    rm -f "$BUILDROOT"/usr/lib/firmware/nvidia/*/gsp_*.bin*
}
help() {
    echo "Drops the unused NVIDIA GSP firmware (Turing+ only) from the initramfs."
}
HOOKEOF
    mkinitcpio_add_hook strip-nvidia-gsp kms
}

# ── hypr_env_upsert <user_home> <key> <value> ───────────────────────────────
# Idempotent append of hl.env("KEY","VALUE") into <user_home>/.config/hypr/
# custom/env.lua. Skips (return 0) when the file is absent (pre-dotfiles). In
# the chroot the file is owned by MAIN_USER; the caller chowns afterward.
hypr_env_upsert() {
    local user_home="$1" key="$2" val="$3"
    local env_lua="$user_home/.config/hypr/custom/env.lua"
    [[ -f "$env_lua" ]] || return 0
    if ! grep -qE "hl\.env\(\"${key}\"" "$env_lua"; then
        printf 'hl.env("%s", "%s")\n' "$key" "$val" >> "$env_lua"
    fi
}

# ── hypr_config_upsert <user_home> <marker> <lua_line> ──────────────────────
# Idempotent append of an hl.config({...}) line into custom/general.lua, keyed on
# a unique marker so it lands at most once. No-op when the file is absent.
hypr_config_upsert() {
    local general_lua="$1/.config/hypr/custom/general.lua" marker="$2" line="$3"
    [[ -f "$general_lua" ]] || return 0
    grep -q "$marker" "$general_lua" || printf '%s\n' "$line" >> "$general_lua"
}

# ── hypr_env_retire <user_home> <key> ───────────────────────────────────────
# Delete an hl.env("<key>", ...) line an older install wrote into custom/env.lua.
# hypr_env_upsert only adds-if-absent, so retiring a dead/harmful key on an
# upgraded machine needs an explicit removal. No-op when file/line is absent.
hypr_env_retire() {
    local env_lua="$1/.config/hypr/custom/env.lua" key="$2"
    [[ -f "$env_lua" ]] || return 0
    sed -i "/hl\.env(\"${key}\"/d" "$env_lua"
}

# Extra probes/wrappers (overridable for testing).
_gpu_lspci_d()   { lspci -D 2>/dev/null || true; }
_gpu_systemctl() { ${GPU_SUDO:-} systemctl "$@"; }
# The module currently driving a card, straight from the kernel. Empty when
# nothing has claimed it.
_gpu_bound_driver() {
    local link="/sys/bus/pci/devices/$1/driver"
    [[ -e "$link" ]] || return 0
    basename "$(readlink -f "$link")" 2>/dev/null || true
}
_gpu_esp_mib() {
    if mountpoint -q /boot/efi 2>/dev/null; then
        echo $(( $(findmnt -bno SIZE /boot/efi 2>/dev/null || echo 0) / 1048576 ))
    else
        echo 0
    fi
}
# Whether a proprietary NVIDIA driver is actually installed. When a legacy card
# falls back to nouveau (its frozen branch was unavailable), forcing the
# proprietary nvidia config + GBM_BACKEND=nvidia env black-screens the Wayland
# session. The nvidia paths consult this and stay on nouveau when it returns 1.
_gpu_nvidia_has_driver() {
    local pkg
    for pkg in nvidia-utils nvidia-open nvidia-open-dkms nvidia-dkms \
               nvidia-580xx-utils nvidia-470xx-utils nvidia-390xx-utils; do
        _gpu_pacman_has "$pkg" && return 0
    done
    return 1
}
# One package per query: `pacman -Qq a b` exits 1 unless *every* name is
# installed, and these branches conflict with each other.
_gpu_pacman_has() { pacman -Qq "$1" >/dev/null 2>&1; }

# ── gpu_target_kernel ───────────────────────────────────────────────────────
# The kernel release the target will boot. Inside a chroot $(uname -r) names
# the build host's kernel, which is never the one being installed, so read the
# module trees instead and take the newest that carries a kernel image from the
# `linux` package: a headers-only upgrade leaves a bare build tree behind under
# a version nothing can boot.
_gpu_module_dirs() { printf '%s\n' /usr/lib/modules/*/; }
_gpu_uname_r()     { uname -r; }
gpu_target_kernel() {
    local d n running stock="" any=""
    running="$(_gpu_uname_r)"
    while IFS= read -r d; do
        [[ -f "$d/vmlinuz" ]] || continue
        n="$(basename "$d")"
        # Already running it, so there is nothing to work out. This can only
        # match on a live system: inside an installer the running kernel is the
        # installer's own and has no tree here.
        [[ "$n" == "$running" ]] && { printf '%s\n' "$n"; return 0; }
        any="$n"
        [[ -r "$d/pkgbase" && "$(<"$d/pkgbase")" == "linux" ]] && stock="$n"
    done < <(_gpu_module_dirs | sort -V)
    # The stock kernel by preference, since that is what an install lays down,
    # but never at the cost of returning nothing: a machine booting linux-lts or
    # linux-zen has a real kernel and a real driver, and answering "none" there
    # would strip the configuration off a card that works.
    printf '%s\n' "${stock:-$any}"
}

# ── nvidia_module_present [<kernel>] ────────────────────────────────────────
# Whether a loadable nvidia module exists for that kernel. Asking pacman is not
# enough and this is the difference that stranded a user: nvidia-open ships
# PREBUILT modules under one exact kernel's directory while depending on
# `linux` unversioned, so a kernel that moves on its own leaves the package
# installed and its module sitting where nothing will look for it. The card
# then reports no driver at all, has no DRM node, and drives no outputs.
_gpu_modinfo() { modinfo -k "$1" "$2" >/dev/null 2>&1; }
# modinfo answers out of depmod's index, and that index is rebuilt when a
# package touches a kernel's own directory rather than whenever one drops a
# module deeper inside it. A module file sitting in the tree is the same answer
# and cannot be missed by an index that has not caught up, so it is worth asking
# second: reading a stale index as "no driver" would strip the configuration off
# a card that works.
_gpu_module_file() {
    local k="$1"
    [[ -n "$(find "/usr/lib/modules/$k" -name 'nvidia.ko*' -print -quit 2>/dev/null)" ]]
}
nvidia_module_present() {
    local k="${1:-}"
    [[ -n "$k" ]] || k="$(gpu_target_kernel)"
    [[ -n "$k" ]] || return 1
    _gpu_modinfo "$k" nvidia || _gpu_module_file "$k"
}

# ── nvidia_write_qs_hint <user_home> ────────────────────────────────────────
# Ship the QS_DISABLE_DMABUF escape hatch as a commented, opt-in line. It cures
# the NVIDIA EGL dmabuf-import gray/blank Quickshell surface but forces the
# slower SHM path, so it stays off until a user with the symptom uncomments it.
nvidia_write_qs_hint() {
    local env_lua="$1/.config/hypr/custom/env.lua"
    [[ -f "$env_lua" ]] || return 0
    grep -q 'QS_DISABLE_DMABUF' "$env_lua" || cat >> "$env_lua" <<'HINT'
-- Gray/blank Quickshell on NVIDIA? Uncomment to force the SHM buffer path:
-- hl.env("QS_DISABLE_DMABUF", "1")
HINT
}

# ── nvidia_write_env <user_home> ────────────────────────────────────────────
# NVIDIA Wayland env + Hyprland conf. LIBVA/GBM always; NVD_BACKEND on
# turing/maxwell only. Cursors + GL anti-flicker go through Hyprland conf.
# __GLX_VENDOR_LIBRARY_NAME is NOT set (GLX-only; no effect on the native
# Wayland/Qt6 path and breaks XWayland windows/screenshare) and is retired from
# older installs; same for the dead wlroots-era WLR_NO_HARDWARE_CURSORS.
nvidia_write_env() {
    local uh="$1"
    hypr_env_retire "$uh" __GLX_VENDOR_LIBRARY_NAME
    hypr_env_retire "$uh" WLR_NO_HARDWARE_CURSORS
    hypr_env_upsert "$uh" LIBVA_DRIVER_NAME nvidia
    hypr_env_upsert "$uh" GBM_BACKEND nvidia-drm
    hypr_config_upsert "$uh" no_hardware_cursors 'hl.config({ cursor = { no_hardware_cursors = true } })'
    hypr_config_upsert "$uh" nvidia_anti_flicker 'hl.config({ opengl = { nvidia_anti_flicker = true } })'
    case "$NVIDIA_GEN" in
        turing|maxwell) hypr_env_upsert "$uh" NVD_BACKEND direct ;;
    esac
    case "$NVIDIA_GEN" in
        maxwell) nvidia_write_qs_hint "$uh" ;;
    esac
}

# ── nvidia_enable_services <enable_powerd:bool> [enable_sleep:bool] ─────────
# Enable suspend/hibernate/resume (tolerant of missing units); powerd only when
# enable_powerd. Dynamic Boost is Ampere+ notebook-only, so only the turing
# bucket (Turing and newer) can ever legitimately use it.
#
# The sleep units are opt-out because mainline stopped wanting them: from 595 the
# driver handles suspend through kernel notifiers, and nvidia-utils actively
# disables these three on upgrade for exactly that reason. Switching them back on
# is not a harmless belt-and-braces, it reinstates the handshake the driver no
# longer performs. The legacy branches still need them.
nvidia_enable_services() {
    local enable_powerd="${1:-false}" enable_sleep="${2:-true}" svc
    if [[ "$enable_sleep" == true ]]; then
        for svc in nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service; do
            _gpu_systemctl enable "$svc" >/dev/null 2>&1 || true
        done
    fi
    if [[ "$enable_powerd" == true ]]; then
        _gpu_systemctl enable nvidia-powerd.service >/dev/null 2>&1 || true
    fi
}

# ── hypridle_fix_nvidia <user_home> ─────────────────────────────────────────
# Prepend a short sleep before the Lua-form dpms-enable dispatch so the NVIDIA
# driver finishes resuming before the display is re-enabled. Idempotent (skips
# when a sleep is already present). Skips silently when hypridle.conf is absent.
hypridle_fix_nvidia() {
    local uh="$1"; local hf="$uh/.config/hypr/hypridle.conf"
    [[ -f "$hf" ]] || return 0
    if grep -qE 'after_sleep_cmd\s*=.*hyprctl dispatch.*dpms.*action.*enable' "$hf" \
        && ! grep -qE 'after_sleep_cmd\s*=.*sleep\s+[0-9].*&&.*hyprctl dispatch.*dpms.*action.*enable' "$hf"; then
        ${GPU_SUDO:-} sed -i '/after_sleep_cmd/s|hyprctl dispatch '"'"'hl.dsp.dpms({ action = "enable" })'"'"'|sleep 2 \&\& hyprctl dispatch '"'"'hl.dsp.dpms({ action = "enable" })'"'"'|' "$hf"
    fi
    if grep -qE 'on-resume\s*=.*hyprctl dispatch.*dpms.*action.*enable' "$hf" \
        && ! grep -qE 'on-resume\s*=.*sleep\s+[0-9].*&&.*hyprctl dispatch.*dpms.*action.*enable' "$hf"; then
        ${GPU_SUDO:-} sed -i '/on-resume/s|hyprctl dispatch '"'"'hl.dsp.dpms({ action = "enable" })'"'"'|sleep 1 \&\& hyprctl dispatch '"'"'hl.dsp.dpms({ action = "enable" })'"'"'|' "$hf"
    fi
}

# ── Failure breadcrumb ──────────────────────────────────────────────────────
# note_failure records a recoverable GPU failure; flush_failures writes them to
# a breadcrumb the desktop surfaces on first boot. Both paths stay exit-0.
GPU_FAILURES=()
note_failure() { GPU_FAILURES+=("$1"); printf 'GPU: %s\n' "$1" >&2; }
flush_failures() {
    local path="${1:-/var/lib/mainstream/gpu-install-failed.log}"
    [[ ${#GPU_FAILURES[@]} -gt 0 ]] || return 0
    ${GPU_SUDO:-} mkdir -p "$(dirname "$path")" 2>/dev/null || true
    # Added to rather than replacing what is there. The driver install writes
    # its own troubles to this same file earlier in an install, and the later
    # run of this has no business throwing those away: two GPU problems on one
    # machine are worth reading together, and the second is usually caused by
    # the first.
    { [[ -s "$path" ]] && cat "$path"
      printf 'gpu-config failures (%s):\n' "$(date -Is 2>/dev/null || echo unknown)"
      printf '  - %s\n' "${GPU_FAILURES[@]}"
    } | _gpu_write_file "$path"
}

_gpu_swap_partuuid() {
    blkid -t TYPE=swap -o export 2>/dev/null | awk -F= '/^PARTUUID=/{print $2; exit}' || true
}

# ── gpu_apply_autoconfig ────────────────────────────────────────────────────
# System-level GPU config from gpu_detect's results: per-vendor MODULES,
# modprobe.d, NVIDIA early-KMS + services, the GPU kernel cmdline flags, and
# resume= for hibernation. Mirrors dots setup_gpu_autoconfig. Does NOT rebuild
# the initramfs or write the base cmdline -- the caller owns those. NVIDIA is
# deliberately NOT early-loaded (early-loading breaks hibernation); KMS is kept
# by nvidia_drm.modeset=1.
#
# Small-ESP guard: explicit MODULES entries make the initramfs/UKI carry the
# full GPU module + firmware set (explicit modules bypass autodetect, so e.g.
# amdgpu pulls every ASIC generation's firmware). On a small reused ESP
# (Windows dual-boot: 100-260 MiB) that UKI no longer fits and the write
# ENOSPCs. When the mounted ESP is under GPU_EARLY_KMS_ESP_THRESHOLD MiB
# (default 512; 0 disables the guard), skip the explicit MODULES — the kms
# hook still early-loads the present card with autodetect-trimmed firmware.
gpu_apply_autoconfig() {
    local -a cmdline_args=()
    local esp_threshold="${GPU_EARLY_KMS_ESP_THRESHOLD:-512}" early_kms=true esp_mib
    esp_mib="$(_gpu_esp_mib)"
    if [[ "$esp_threshold" -gt 0 && "$esp_mib" -gt 0 && "$esp_mib" -lt "$esp_threshold" ]]; then
        early_kms=false
    fi
    # Intel first so its module precedes nvidia in MODULES.
    if [[ $HAS_INTEL == true ]]; then
        # No i915.modeset cmdline token: the param was deprecated in 6.12 (warns)
        # and KMS is already the -1 auto default; early KMS comes from MODULES.
        [[ $early_kms == true ]] && mkinitcpio_add_modules "$(intel_kms_module)" || true
    fi
    if [[ $HAS_AMD == true ]]; then
        if [[ $IS_OLD_AMD == true ]]; then
            write_modprobe_conf amd
            [[ $early_kms == true ]] && mkinitcpio_add_modules amdgpu radeon || true
            cmdline_args+=("amdgpu.si_support=1" "amdgpu.cik_support=1")
        else
            [[ $early_kms == true ]] && mkinitcpio_add_modules amdgpu || true
            cmdline_args+=("amdgpu.modeset=1")
            [[ $IS_RDNA4 == true ]] && cmdline_args+=("amdgpu.sg_display=0") || true
        fi
    fi
    if [[ $HAS_NVIDIA == true && $NVIDIA_PCI_DEC -ge 1728 ]] && _gpu_nvidia_has_driver; then
        # The userspace packages being present says nothing about whether a
        # module exists for the kernel about to boot. Dressing a driverless
        # kernel in modeset flags and suspend services hides the failure behind
        # config that reads as correct; say it instead.
        local _k; _k="$(gpu_target_kernel)"
        if nvidia_module_present "$_k"; then
            # No nvidia entries go into MODULES. Baking them into the initramfs
            # costs hibernation: the boot kernel freezes devices before anything
            # has written /proc/driver/nvidia/suspend, so the driver refuses the
            # freeze and the resume falls through into an ordinary boot. KMS is
            # kept by nvidia_drm.modeset=1 below, and udev loads the modules on
            # the real root where the handshake can happen. The cost is a visible
            # handoff from simpledrm once nvidia_drm probes.
            write_modprobe_conf nvidia
            cmdline_args+=("nvidia_drm.modeset=1")
            local _pw=false _sleep=true
            if [[ "$NVIDIA_GEN" == turing ]]; then _pw=true; _sleep=false; fi
            nvidia_enable_services "$_pw" "$_sleep"
        else
            note_failure "nvidia: driver installed but no module for kernel ${_k:-unknown}, so the GPU configuration was skipped"
        fi
    fi
    nvidia_strip_gsp_firmware
    # PRIME for hybrid.
    if [[ $IS_HYBRID == true && $early_kms == true ]]; then
        if [[ $HAS_NVIDIA == true && $HAS_INTEL == true ]]; then
            mkinitcpio_add_modules "$(intel_kms_module)"
        elif [[ $HAS_NVIDIA == true && $HAS_AMD == true ]]; then
            mkinitcpio_add_modules amdgpu
        fi
    fi
    # resume= for hibernation if a swap partition exists and none is set yet.
    local swap_partuuid; swap_partuuid="$(_gpu_swap_partuuid)"
    if [[ -n "$swap_partuuid" ]]; then
        local kc="${KERNEL_CMDLINE:-/etc/kernel/cmdline}" cur=""
        [[ -f "$kc" ]] && cur="$(cat "$kc")" || true
        if ! grep -Eq '(^|[[:space:]])resume=' <<<"$cur"; then
            cmdline_args+=("resume=PARTUUID=$swap_partuuid")
        fi
    fi
    if (( ${#cmdline_args[@]} > 0 )); then
        cmdline_upsert "${cmdline_args[@]}"
    fi
}

# ── gpu_apply_hypr_tweaks <user_home> ───────────────────────────────────────
# User-level Hyprland GPU config (run AFTER dotfiles deploy so env.lua/
# hypridle.conf exist): NVIDIA env + hypridle resume fix for Fermi+. Mirrors
# dots setup_gpu_hypr_tweaks.
#
# AQ_DRM_DEVICES is deliberately NOT written here. This library used to pin it
# to the NVIDIA card (and later to a joined NVIDIA+other-cards list) on hybrid
# setups, but on at least one confirmed hybrid Blackwell laptop (HP Omen Max
# 16, RTX 5080) both forms black-screened on boot, and the only fix that
# worked was removing the line entirely and letting Aquamarine autodetect.
# We intentionally do not retire a pre-existing AQ_DRM_DEVICES line either:
# a machine in this state can't boot to rerun the installer normally, so the
# realistic recovery path is a fresh install, which never writes the line in
# the first place. Anyone who wants Hyprland pinned to a specific GPU can
# still set AQ_DRM_DEVICES by hand per the Hyprland wiki.
gpu_apply_hypr_tweaks() {
    local uh="$1"
    # Resolve driver presence once (a pacman query) and reuse for both branches.
    local has_nv_drv=false
    if [[ $HAS_NVIDIA == true ]] && _gpu_nvidia_has_driver && nvidia_module_present; then has_nv_drv=true; fi
    if [[ $has_nv_drv == true && $NVIDIA_PCI_DEC -ge 1728 ]]; then
        nvidia_write_env "$uh"
        hypridle_fix_nvidia "$uh"
    fi
}
