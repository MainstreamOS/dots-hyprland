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
#   AMD_DEC (int)         IS_OLD_AMD
#   INTEL_DEC (int)       IS_ARC  IS_OLD_INTEL
# Generation ladder (PCI device-id decimal): 7684 Turing+, 4928 Maxwell-Volta,
# 4032 Kepler, 1728 Fermi, below Fermi -> prefermi (nouveau).
# AMD "old" = pre-GCN: dec < 26112 AND NOT an APU (4864-5887 exemption), OR a
# pre-GCN name (HD 2xxx-6xxx / RV / RS / R[67]xx); RDNA4 (Navi 4x / RX 9xxx /
# gfx12) always forces modern.
# Returns 1 if no display device is found (lspci missing or none present).
gpu_detect() {
    HAS_NVIDIA=false HAS_AMD=false HAS_INTEL=false IS_HYBRID=false IS_VM=false
    NVIDIA_PCI_DEC=0 NVIDIA_GEN=none
    AMD_DEC=0 IS_OLD_AMD=false IS_RDNA4=false
    INTEL_DEC=0 IS_ARC=false IS_OLD_INTEL=false

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
        if   [[ $NVIDIA_PCI_DEC -ge 7684 ]]; then NVIDIA_GEN=turing
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
        if grep -iqE 'Navi 4[0-9]|RX 9[0-9]{3}|gfx12' <<<"$lspci_names"; then IS_RDNA4=true; IS_OLD_AMD=false; fi
    fi

    if [[ $HAS_INTEL == true ]]; then
        local intel_dev intel_id
        intel_dev="$(grep -iE 'Intel.*(Graphics|UHD|HD|Iris|Arc)' <<<"$lspci_names" | head -1 || true)"
        if grep -iqE 'Arc|Xe|A[3-7][0-9]{2}' <<<"$intel_dev"; then
            IS_ARC=true
        else
            intel_id="$(grep -iE 'Intel.*Graphics' <<<"$lspci_nn" | grep -oE '8086:[0-9a-fA-F]{4}' | head -1 | cut -d: -f2 || true)"
            INTEL_DEC=$((16#${intel_id:-ffff}))
            [[ $INTEL_DEC -lt 256 ]] && IS_OLD_INTEL=true || true
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
    printf '%s rootflags=subvol=%s rw rootfstype=btrfs zswap.enabled=0 quiet splash rd.udev.log_level=3 vt.global_cursor_default=0 consoleblank=0 nowatchdog nmi_watchdog=0 audit=0' \
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
            printf 'options nvidia-drm modeset=1 fbdev=1\noptions nvidia NVreg_PreserveVideoMemoryAllocations=1\noptions nvidia NVreg_TemporaryFilePath=/var/tmp\n' \
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

# ── nvidia_write_env <user_home> ────────────────────────────────────────────
# The NVIDIA Wayland env set. The four base keys always; NVD_BACKEND=direct only
# on turing/maxwell (newer-driver VA-API feature — the canonical gating).
nvidia_write_env() {
    local uh="$1"
    hypr_env_upsert "$uh" LIBVA_DRIVER_NAME nvidia
    hypr_env_upsert "$uh" GBM_BACKEND nvidia-drm
    hypr_env_upsert "$uh" __GLX_VENDOR_LIBRARY_NAME nvidia
    hypr_env_upsert "$uh" WLR_NO_HARDWARE_CURSORS 1
    case "$NVIDIA_GEN" in
        turing|maxwell) hypr_env_upsert "$uh" NVD_BACKEND direct ;;
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
# enable_powerd (turing/maxwell).
nvidia_enable_services() {
    local enable_powerd="${1:-false}" svc
    for svc in nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service; do
        _gpu_systemctl enable "$svc" >/dev/null 2>&1 || true
    done
    if [[ "$enable_powerd" == true ]]; then
        _gpu_systemctl enable nvidia-powerd.service >/dev/null 2>&1 || true
    fi
}

# ── nvidia_early_kms <remove_kms_hook:bool> [esp_threshold_mib] ──────────────
# Inject the nvidia early-KMS modules, optionally dropping the kms hook first.
# Skips injection when /boot/efi is a mounted FAT ESP smaller than the threshold
# (reused small Windows ESP — a ~170 MB UKI would overflow it). threshold 0
# disables the guard (the live dots path, which has no UKI/ESP constraint).
nvidia_early_kms() {
    local remove_kms="${1:-false}" threshold="${2:-512}" esp_mib
    esp_mib="$(_gpu_esp_mib)"
    if [[ "$threshold" -gt 0 && "$esp_mib" -gt 0 && "$esp_mib" -lt "$threshold" ]]; then
        return 0
    fi
    [[ "$remove_kms" == true ]] && mkinitcpio_remove_hook kms || true
    mkinitcpio_add_modules nvidia nvidia_modeset nvidia_uvm nvidia_drm
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
# the initramfs or write the base cmdline -- the caller owns those. Early-KMS
# behavior via GPU_EARLY_KMS_REMOVE_HOOK (default false = keep kms) and
# GPU_EARLY_KMS_ESP_THRESHOLD (default 0 = guard off; archiso sets true/512).
gpu_apply_autoconfig() {
    local -a cmdline_args=()
    # Intel first so i915 precedes nvidia in MODULES.
    if [[ $HAS_INTEL == true ]]; then
        if [[ $IS_ARC == true ]]; then
            mkinitcpio_add_modules xe
        else
            mkinitcpio_add_modules i915
            [[ $IS_HYBRID == true ]] || cmdline_args+=("i915.modeset=1")
        fi
    fi
    if [[ $HAS_AMD == true ]]; then
        if [[ $IS_OLD_AMD == true ]]; then
            write_modprobe_conf amd
            mkinitcpio_add_modules amdgpu radeon
            cmdline_args+=("amdgpu.si_support=1" "amdgpu.cik_support=1")
        else
            mkinitcpio_add_modules amdgpu
            cmdline_args+=("amdgpu.modeset=1")
            [[ $IS_RDNA4 == true ]] && cmdline_args+=("amdgpu.sg_display=0") || true
        fi
    fi
    if [[ $HAS_NVIDIA == true && $NVIDIA_PCI_DEC -ge 1728 ]] && _gpu_nvidia_has_driver; then
        nvidia_early_kms "${GPU_EARLY_KMS_REMOVE_HOOK:-false}" "${GPU_EARLY_KMS_ESP_THRESHOLD:-0}"
        write_modprobe_conf nvidia
        cmdline_args+=("nvidia_drm.modeset=1")
        local _pw=false
        [[ "$NVIDIA_GEN" == turing || "$NVIDIA_GEN" == maxwell ]] && _pw=true || true
        nvidia_enable_services "$_pw"
    fi
    # PRIME for hybrid.
    if [[ $IS_HYBRID == true ]]; then
        if [[ $HAS_NVIDIA == true && $HAS_INTEL == true ]]; then
            mkinitcpio_add_modules i915
            cmdline_args+=("i915.modeset=1")
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
