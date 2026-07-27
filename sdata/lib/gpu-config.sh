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
# pre-GCN name (HD 2xxx-6xxx / RV / RS / R[67]xx); RDNA4 (Navi 4x / RX 9xxx /
# gfx12) always forces modern.
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
        pci_line="$(grep -iE 'NVIDIA|GeForce|Quadro|Tesla' <<<"$lspci_nn" | head -1 || true)"
        pci_id="$(grep -oE '\[10de:[0-9a-fA-F]{4}\]' <<<"$pci_line" | tail -1 | grep -oE '[0-9a-fA-F]{4}' | tail -1 || true)"
        NVIDIA_PCI_DEC=$((16#${pci_id:-0}))
        if   [[ $NVIDIA_PCI_DEC -ge 7682 ]]; then NVIDIA_GEN=turing
        elif [[ $NVIDIA_PCI_DEC -ge 4928 ]]; then NVIDIA_GEN=maxwell
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
        if grep -iqE '\bRadeon [678][0-9]0M\b|Radeon Graphics' <<<"$lspci_names"; then IS_OLD_AMD=false; fi
        if grep -iqE 'Navi 4[0-9]|RX 9[0-9]{3}|gfx12' <<<"$lspci_names"; then IS_RDNA4=true; IS_OLD_AMD=false; fi
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
gpu_classify_nvidia_driver() {
    NVIDIA_DRIVER_FAMILY=none
    NVIDIA_REPO_PKGS=() NVIDIA_LOCAL_PKGS=()
    case "$NVIDIA_GEN" in
        turing)
            NVIDIA_DRIVER_FAMILY=nvidia-open
            NVIDIA_REPO_PKGS=(nvidia-open nvidia-utils nvidia-settings lib32-nvidia-utils libva-nvidia-driver libva-utils) ;;
        maxwell)
            NVIDIA_DRIVER_FAMILY=nvidia-580xx
            NVIDIA_LOCAL_PKGS=(nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils nvidia-580xx-settings libxnvctrl-580xx) ;;
        kepler)
            NVIDIA_DRIVER_FAMILY=nvidia-470xx
            NVIDIA_LOCAL_PKGS=(nvidia-470xx-dkms nvidia-470xx-utils lib32-nvidia-470xx-utils) ;;
        fermi)
            NVIDIA_DRIVER_FAMILY=nvidia-390xx
            NVIDIA_LOCAL_PKGS=(nvidia-390xx-dkms nvidia-390xx-utils lib32-nvidia-390xx-utils) ;;
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
            printf 'options nvidia-drm modeset=1%s\noptions nvidia NVreg_PreserveVideoMemoryAllocations=1\noptions nvidia NVreg_TemporaryFilePath=/var/tmp\n' "$fbdev" \
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

# ── mkinitcpio_remove_hook <hook> ───────────────────────────────────────────
# Idempotent removal of a HOOKS entry (scoped to the HOOKS line so MODULES and
# comments are untouched). Used to drop the kms hook before injecting nvidia
# modules; callers that keep kms simply never call it.
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
    pacman -Qq nvidia-utils nvidia-open nvidia-open-dkms nvidia-dkms \
        nvidia-580xx-utils nvidia-470xx-utils nvidia-390xx-utils >/dev/null 2>&1
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

# ── nvidia_write_aq_drm <user_home> ─────────────────────────────────────────
# Hybrid NVIDIA: pin Aquamarine's DRM device to the NVIDIA card via the stable
# by-path symlink (card0/card1 enumeration is non-deterministic).
nvidia_write_aq_drm() {
    local uh="$1" addr
    addr="$(_gpu_lspci_d | grep -iE 'NVIDIA|GeForce|Quadro|Tesla' | head -1 | awk '{print $1}' || true)"
    [[ -n "$addr" ]] || return 0
    hypr_env_upsert "$uh" AQ_DRM_DEVICES "/dev/dri/by-path/pci-${addr}-card"
}

# ── nvidia_enable_services <enable_powerd:bool> ─────────────────────────────
# Enable suspend/hibernate/resume (tolerant of missing units); powerd only when
# enable_powerd. Dynamic Boost is Ampere+ notebook-only, so only the turing
# bucket (Turing and newer) can ever legitimately use it.
nvidia_enable_services() {
    local enable_powerd="${1:-false}" svc
    for svc in nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service; do
        _gpu_systemctl enable "$svc" >/dev/null 2>&1 || true
    done
    if [[ "$enable_powerd" == true ]]; then
        _gpu_systemctl enable nvidia-powerd.service >/dev/null 2>&1 || true
    fi
}

# ── nvidia_defer_kms ────────────────────────────────────────────────────────
# Do NOT early-load the nvidia modules into the initramfs: baking them in breaks
# hibernation, because NVreg_PreserveVideoMemoryAllocations restores VRAM before
# the init hooks make the temp filesystem usable (ArchWiki). KMS/full-res is kept
# by nvidia_drm.modeset=1 on the cmdline; the modules load via udev on the real
# root, after which suspend/hibernate VRAM preservation works. Remove the kms
# hook so udev autodetect doesn't early-load nvidia_drm in its place. Dropping
# the in-initramfs nvidia modules also shrinks the UKI. AMD/Intel still get
# early KMS via their explicit MODULES entries, guarded by the small-ESP check
# in gpu_apply_autoconfig.
nvidia_defer_kms() {
    mkinitcpio_remove_hook kms
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
    { printf 'gpu-config failures (%s):\n' "$(date -Is 2>/dev/null || echo unknown)"
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
    # Intel first so i915 precedes nvidia in MODULES.
    if [[ $HAS_INTEL == true ]]; then
        # i915 is the kernel default for Alchemist/Iris-Xe and older; on the rare
        # Xe2 card (Battlemage/Lunar Lake) it is a harmless no-op and xe auto-loads.
        # No i915.modeset cmdline token: the param was deprecated in 6.12 (warns)
        # and KMS is already the -1 auto default; early KMS comes from MODULES.
        [[ $early_kms == true ]] && mkinitcpio_add_modules i915 || true
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
        nvidia_defer_kms
        write_modprobe_conf nvidia
        cmdline_args+=("nvidia_drm.modeset=1")
        local _pw=false
        [[ "$NVIDIA_GEN" == turing ]] && _pw=true || true
        nvidia_enable_services "$_pw"
    fi
    nvidia_strip_gsp_firmware
    # PRIME for hybrid.
    if [[ $IS_HYBRID == true && $early_kms == true ]]; then
        if [[ $HAS_NVIDIA == true && $HAS_INTEL == true ]]; then
            mkinitcpio_add_modules i915
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
# hypridle.conf exist): NVIDIA env + hypridle resume fix for Fermi+, and the
# hybrid AQ_DRM device pin. Mirrors dots setup_gpu_hypr_tweaks.
gpu_apply_hypr_tweaks() {
    local uh="$1"
    # Resolve driver presence once (a pacman query) and reuse for both branches.
    local has_nv_drv=false
    if [[ $HAS_NVIDIA == true ]] && _gpu_nvidia_has_driver; then has_nv_drv=true; fi
    if [[ $has_nv_drv == true && $NVIDIA_PCI_DEC -ge 1728 ]]; then
        nvidia_write_env "$uh"
        hypridle_fix_nvidia "$uh"
    fi
    if [[ $has_nv_drv == true && $IS_HYBRID == true ]]; then
        nvidia_write_aq_drm "$uh"
    fi
}
