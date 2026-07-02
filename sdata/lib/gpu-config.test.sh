#!/usr/bin/env bash
# gpu-config.test.sh — fixture harness for gpu-config.sh detection.
# Run: bash sdata/lib/gpu-config.test.sh   (exit 0 = all green)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gpu-config.sh
source "$DIR/gpu-config.sh"

# Drive detection from fixture globals instead of real hardware.
FIX_LSPCI=""; FIX_SYSVENDOR=""; FIX_ESP_MIB=0
_gpu_lspci_nn()   { printf '%s\n' "$FIX_LSPCI"; }
_gpu_lspci()      { printf '%s\n' "$FIX_LSPCI"; }
_gpu_sys_vendor() { printf '%s' "$FIX_SYSVENDOR"; }
_gpu_esp_mib()    { echo "$FIX_ESP_MIB"; }

FAILS=0; CASES=0
run() { FIX_SYSVENDOR="$2"; FIX_LSPCI="$3"; CASES=$((CASES + 1)); gpu_detect || true; }
chk() { local got="${!2}"; if [[ "$got" != "$3" ]]; then echo "  FAIL [$1] $2: got '$got' want '$3'"; FAILS=$((FAILS + 1)); fi; }
chk_str() { if [[ "$2" != "$3" ]]; then echo "  FAIL [$1]: got '$2' want '$3'"; FAILS=$((FAILS + 1)); fi; }
count() { grep -o "$1" <<<"$2" | wc -l | tr -d '[:space:]'; }

# 1. AMD RDNA2 — modern discrete
run amd-rdna2 "" "03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [Radeon RX 6700 XT] [1002:73df] (rev c1)"
chk amd-rdna2 HAS_AMD true; chk amd-rdna2 HAS_NVIDIA false; chk amd-rdna2 IS_HYBRID false
chk amd-rdna2 AMD_DEC 29663; chk amd-rdna2 IS_OLD_AMD false

# 2. AMD RDNA4 — name override forces modern
run amd-rdna4 "" "03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 [Radeon RX 9070 XT] [1002:7550] (rev c0)"
chk amd-rdna4 HAS_AMD true; chk amd-rdna4 AMD_DEC 30032; chk amd-rdna4 IS_OLD_AMD false

# 3. AMD pre-GCN — name regex marks old
run amd-pregcn "" "01:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Caicos [Radeon HD 6450] [1002:6760] (rev 81)"
chk amd-pregcn HAS_AMD true; chk amd-pregcn AMD_DEC 26464; chk amd-pregcn IS_OLD_AMD true

# 4. AMD APU (Renoir) — THE FIX: 4864-5887 exemption keeps it modern
run amd-apu "" "06:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Renoir [Radeon Vega Series / Radeon Vega Mobile Series] [1002:1636] (rev c8)"
chk amd-apu HAS_AMD true; chk amd-apu AMD_DEC 5686; chk amd-apu IS_OLD_AMD false

run amd-krackan "" "c5:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Krackan [Radeon 840M / 860M Graphics] [1002:1114] (rev c1)"
chk amd-krackan HAS_AMD true; chk amd-krackan AMD_DEC 4372; chk amd-krackan IS_OLD_AMD false

# 5-9. NVIDIA generation ladder
run nv-turing "" "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU104 [GeForce RTX 2080] [10de:1e87] (rev a1)"
chk nv-turing HAS_NVIDIA true; chk nv-turing NVIDIA_PCI_DEC 7815; chk nv-turing NVIDIA_GEN turing
run nv-maxwell "" "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GM204 [GeForce GTX 970] [10de:13c2] (rev a1)"
chk nv-maxwell NVIDIA_PCI_DEC 5058; chk nv-maxwell NVIDIA_GEN maxwell
run nv-kepler "" "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GK208B [GeForce GT 710] [10de:128b] (rev a1)"
chk nv-kepler NVIDIA_PCI_DEC 4747; chk nv-kepler NVIDIA_GEN kepler
run nv-fermi "" "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GF100 [GeForce GTX 480] [10de:06c0] (rev a3)"
chk nv-fermi NVIDIA_PCI_DEC 1728; chk nv-fermi NVIDIA_GEN fermi
run nv-prefermi "" "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation G92 [GeForce 8800 GT] [10de:0611] (rev a2)"
chk nv-prefermi NVIDIA_PCI_DEC 1553; chk nv-prefermi NVIDIA_GEN prefermi

# 10-12. Intel
run intel-arc "" "03:00.0 VGA compatible controller [0300]: Intel Corporation DG2 [Arc A770] [8086:56a0] (rev 08)"
chk intel-arc HAS_INTEL true
run intel-modern "" "00:02.0 VGA compatible controller [0300]: Intel Corporation AlderLake-S GT1 [UHD Graphics 770] [8086:4680] (rev 0c)"
chk intel-modern HAS_INTEL true
run intel-presb "" "00:02.0 VGA compatible controller [0300]: Intel Corporation Core Processor Integrated Graphics Controller [8086:0042] (rev 12)"
chk intel-presb HAS_INTEL true

# 13. Hybrid NVIDIA + Intel (laptop; dGPU shows as 3D controller)
run hybrid-nv-intel "" "00:02.0 VGA compatible controller [0300]: Intel Corporation TigerLake-H GT1 [UHD Graphics] [8086:9a60] (rev 01)
01:00.0 3D controller [0302]: NVIDIA Corporation GA106M [GeForce RTX 3060 Mobile] [10de:2503] (rev a1)"
chk hybrid-nv-intel HAS_NVIDIA true; chk hybrid-nv-intel HAS_INTEL true; chk hybrid-nv-intel HAS_AMD false
chk hybrid-nv-intel IS_HYBRID true; chk hybrid-nv-intel NVIDIA_GEN turing

# 14. Hybrid NVIDIA + AMD
run hybrid-nv-amd "" "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU106 [GeForce RTX 2070] [10de:1f02] (rev a1)
03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 23 [Radeon RX 6600] [1002:73ff] (rev c7)"
chk hybrid-nv-amd HAS_NVIDIA true; chk hybrid-nv-amd HAS_AMD true; chk hybrid-nv-amd IS_HYBRID true
chk hybrid-nv-amd NVIDIA_GEN turing; chk hybrid-nv-amd IS_OLD_AMD false

# 15. VM (QEMU std VGA — no recognized vendor, IS_VM via DMI)
run vm-qemu "QEMU Standard PC (Q35 + ICH9, 2009)" "00:01.0 VGA compatible controller [0300]: Device [1234:1111] (rev 02)"
chk vm-qemu IS_VM true; chk vm-qemu HAS_NVIDIA false; chk vm-qemu HAS_AMD false; chk vm-qemu HAS_INTEL false

# ── cmdline writer (canonical content + idempotency + key dedup) ────────────
export GPU_SUDO=""
CMDTMP="$(mktemp -d)"; export KERNEL_CMDLINE="$CMDTMP/cmdline"; : > "$KERNEL_CMDLINE"
EXP_BASE='root=PARTUUID=abc-123 rootflags=subvol=@ rw rootfstype=btrfs zswap.enabled=0 quiet splash rd.udev.log_level=3 vt.global_cursor_default=0 consoleblank=0 nowatchdog nmi_watchdog=0'
chk_str cmdline-base-tokens "$(gpu_base_cmdline_tokens 'root=PARTUUID=abc-123' '/@')" "$EXP_BASE"
cmdline_upsert $(gpu_base_cmdline_tokens 'root=PARTUUID=abc-123' '/@'); CASES=$((CASES + 1))
chk_str cmdline-seed "$(cat "$KERNEL_CMDLINE")" "$EXP_BASE"
cmdline_upsert $(gpu_base_cmdline_tokens 'root=PARTUUID=abc-123' '/@'); CASES=$((CASES + 1))
chk_str cmdline-idempotent "$(cat "$KERNEL_CMDLINE")" "$EXP_BASE"
cmdline_upsert amdgpu.modeset=1 quiet; CASES=$((CASES + 1)); g="$(cat "$KERNEL_CMDLINE")"
chk_str cmdline-quiet-once "$(count '\bquiet\b' "$g")" "1"
chk_str cmdline-amdgpu-added "$( [[ "$g" == *"amdgpu.modeset=1"* ]] && echo yes || echo no )" "yes"
cmdline_upsert rd.udev.log_level=0; CASES=$((CASES + 1)); g="$(cat "$KERNEL_CMDLINE")"
chk_str cmdline-key-once "$(count 'rd\.udev\.log_level=' "$g")" "1"
chk_str cmdline-new-value "$( [[ "$g" == *"rd.udev.log_level=0"* ]] && echo yes || echo no )" "yes"
rm -rf "$CMDTMP"

# ── modprobe / mkinitcpio MODULES + HOOKS / hypr env writers ────────────────
WTMP="$(mktemp -d)"; export MODPROBE_DIR="$WTMP/modprobe.d" MKINITCPIO_CONF="$WTMP/mkinitcpio.conf"
NVIDIA_GEN=turing; write_modprobe_conf nvidia; CASES=$((CASES + 1))
chk_str modprobe-nvidia "$(cat "$MODPROBE_DIR/nvidia.conf")" "$(printf 'options nvidia-drm modeset=1 fbdev=1\noptions nvidia NVreg_PreserveVideoMemoryAllocations=1\noptions nvidia NVreg_TemporaryFilePath=/var/tmp')"
NVIDIA_GEN=kepler; write_modprobe_conf nvidia; CASES=$((CASES + 1))
chk_str modprobe-nvidia-legacy "$(cat "$MODPROBE_DIR/nvidia.conf")" "$(printf 'options nvidia-drm modeset=1\noptions nvidia NVreg_PreserveVideoMemoryAllocations=1\noptions nvidia NVreg_TemporaryFilePath=/var/tmp')"
write_modprobe_conf amd; CASES=$((CASES + 1))
chk_str modprobe-amd "$(cat "$MODPROBE_DIR/amdgpu.conf")" "$(printf 'options amdgpu si_support=1\noptions amdgpu cik_support=1\noptions radeon si_support=0\noptions radeon cik_support=0')"

printf 'MODULES=()\nHOOKS=(base systemd plymouth autodetect kms keyboard block filesystems fsck)\n' > "$MKINITCPIO_CONF"
mkinitcpio_add_modules i915; CASES=$((CASES + 1))
mkinitcpio_add_modules nvidia nvidia_modeset nvidia_uvm nvidia_drm
mkinitcpio_add_modules i915   # idempotent — already present
MODLINE="$(grep '^MODULES=' "$MKINITCPIO_CONF")"
chk_str mkinitcpio-modules "$MODLINE" "MODULES=(nvidia_drm nvidia_uvm nvidia_modeset nvidia i915 )"
chk_str mkinitcpio-i915-once "$(count '\bi915\b' "$MODLINE")" "1"
mkinitcpio_remove_hook kms; CASES=$((CASES + 1))
HOOKLINE="$(grep '^HOOKS=' "$MKINITCPIO_CONF")"
chk_str mkinitcpio-kms-removed "$( [[ "$HOOKLINE" == *" kms "* ]] && echo present || echo gone )" "gone"
chk_str mkinitcpio-hooks-intact "$( [[ "$HOOKLINE" == *"plymouth"* && "$HOOKLINE" == *"filesystems"* ]] && echo yes || echo no )" "yes"

ENVHOME="$WTMP/home"; mkdir -p "$ENVHOME/.config/hypr/custom"; : > "$ENVHOME/.config/hypr/custom/env.lua"
hypr_env_upsert "$ENVHOME" LIBVA_DRIVER_NAME nvidia; CASES=$((CASES + 1))
hypr_env_upsert "$ENVHOME" LIBVA_DRIVER_NAME nvidia   # idempotent
chk_str env-line "$(cat "$ENVHOME/.config/hypr/custom/env.lua")" 'hl.env("LIBVA_DRIVER_NAME", "nvidia")'
hypr_env_upsert "$WTMP/nonexistent" KEY val; rc=$?; CASES=$((CASES + 1))
chk_str env-absent-skip "$rc" "0"

: > "$ENVHOME/.config/hypr/custom/general.lua"
CURSOR_LINE='hl.config({ cursor = { no_hardware_cursors = true } })'
hypr_config_upsert "$ENVHOME" no_hardware_cursors "$CURSOR_LINE"; CASES=$((CASES + 1))
hypr_config_upsert "$ENVHOME" no_hardware_cursors "$CURSOR_LINE"
chk_str cursor-line "$(grep -c 'no_hardware_cursors = true' "$ENVHOME/.config/hypr/custom/general.lua")" "1"
hypr_config_upsert "$WTMP/nonexistent" no_hardware_cursors "$CURSOR_LINE"; rc=$?; CASES=$((CASES + 1))
chk_str cursor-absent-skip "$rc" "0"
rm -rf "$WTMP"

# ── NVIDIA env / services / early-KMS / hypridle / breadcrumb ────────────────
NTMP="$(mktemp -d)"; export MKINITCPIO_CONF="$NTMP/mkinitcpio.conf"
NVHOME="$NTMP/home"; mkdir -p "$NVHOME/.config/hypr/custom"

NVIDIA_GEN=turing; : > "$NVHOME/.config/hypr/custom/env.lua"; : > "$NVHOME/.config/hypr/custom/general.lua"; nvidia_write_env "$NVHOME"; CASES=$((CASES + 1))
EL="$(cat "$NVHOME/.config/hypr/custom/env.lua")"
GL="$(cat "$NVHOME/.config/hypr/custom/general.lua")"
chk_str env-turing-nvd "$( [[ "$EL" == *'hl.env("NVD_BACKEND", "direct")'* ]] && echo yes || echo no )" "yes"
chk_str env-turing-libva "$( [[ "$EL" == *'hl.env("LIBVA_DRIVER_NAME", "nvidia")'* ]] && echo yes || echo no )" "yes"
chk_str env-no-wlr-cursor "$( [[ "$EL" == *'WLR_NO_HARDWARE_CURSORS'* ]] && echo present || echo absent )" "absent"
chk_str env-turing-no-glx "$( [[ "$EL" == *'__GLX_VENDOR_LIBRARY_NAME'* ]] && echo present || echo absent )" "absent"
chk_str env-turing-no-qs-hint "$( [[ "$EL" == *'QS_DISABLE_DMABUF'* ]] && echo present || echo absent )" "absent"
chk_str cursor-no-hw "$( [[ "$GL" == *'no_hardware_cursors = true'* ]] && echo yes || echo no )" "yes"
chk_str anti-flicker "$( [[ "$GL" == *'nvidia_anti_flicker = true'* ]] && echo yes || echo no )" "yes"
NVIDIA_GEN=kepler; : > "$NVHOME/.config/hypr/custom/env.lua"; : > "$NVHOME/.config/hypr/custom/general.lua"; nvidia_write_env "$NVHOME"; CASES=$((CASES + 1))
EL="$(cat "$NVHOME/.config/hypr/custom/env.lua")"
chk_str env-kepler-no-nvd "$( [[ "$EL" == *'NVD_BACKEND'* ]] && echo present || echo absent )" "absent"
chk_str env-kepler-no-glx "$( [[ "$EL" == *'__GLX_VENDOR_LIBRARY_NAME'* ]] && echo present || echo absent )" "absent"

NVIDIA_GEN=maxwell; : > "$NVHOME/.config/hypr/custom/env.lua"; : > "$NVHOME/.config/hypr/custom/general.lua"; nvidia_write_env "$NVHOME"; CASES=$((CASES + 1))
EL="$(cat "$NVHOME/.config/hypr/custom/env.lua")"
chk_str env-maxwell-nvd "$( [[ "$EL" == *'hl.env("NVD_BACKEND", "direct")'* ]] && echo yes || echo no )" "yes"
chk_str env-maxwell-qs-hint "$( [[ "$EL" == *'QS_DISABLE_DMABUF'* ]] && echo yes || echo no )" "yes"

printf 'hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")\nhl.env("WLR_NO_HARDWARE_CURSORS", "1")\n' > "$NVHOME/.config/hypr/custom/env.lua"
NVIDIA_GEN=turing; nvidia_write_env "$NVHOME"; CASES=$((CASES + 1))
EL="$(cat "$NVHOME/.config/hypr/custom/env.lua")"
chk_str retire-glx "$( [[ "$EL" == *'__GLX_VENDOR_LIBRARY_NAME'* ]] && echo present || echo absent )" "absent"
chk_str retire-wlr "$( [[ "$EL" == *'WLR_NO_HARDWARE_CURSORS'* ]] && echo present || echo absent )" "absent"

: > "$NVHOME/.config/hypr/custom/env.lua"
_gpu_lspci_d() { printf '%s\n' "0000:01:00.0 VGA compatible controller: NVIDIA Corporation TU104 [GeForce RTX 2080]"; }
nvidia_write_aq_drm "$NVHOME"; CASES=$((CASES + 1))
chk_str aq-drm "$(cat "$NVHOME/.config/hypr/custom/env.lua")" 'hl.env("AQ_DRM_DEVICES", "/dev/dri/by-path/pci-0000:01:00.0-card")'

ENABLED=""; _gpu_systemctl() { [[ "$1" == enable ]] && ENABLED="$ENABLED ${2%.service}"; return 0; }
nvidia_enable_services true; CASES=$((CASES + 1))
chk_str svc-powerd-on "$( [[ "$ENABLED" == *"nvidia-powerd"* ]] && echo yes || echo no )" "yes"
chk_str svc-resume "$( [[ "$ENABLED" == *"nvidia-resume"* ]] && echo yes || echo no )" "yes"
ENABLED=""; nvidia_enable_services false; CASES=$((CASES + 1))
chk_str svc-powerd-off "$( [[ "$ENABLED" == *"nvidia-powerd"* ]] && echo present || echo absent )" "absent"
chk_str svc-suspend-still "$( [[ "$ENABLED" == *"nvidia-suspend"* ]] && echo yes || echo no )" "yes"

printf 'MODULES=()\nHOOKS=(base systemd plymouth kms block filesystems)\n' > "$MKINITCPIO_CONF"
nvidia_defer_kms; CASES=$((CASES + 1))
chk_str defer-kms-no-nvidia "$(grep -c nvidia "$MKINITCPIO_CONF")" "0"
chk_str defer-kms-removes-kms "$( [[ "$(grep '^HOOKS=' "$MKINITCPIO_CONF")" == *" kms "* ]] && echo present || echo gone )" "gone"

HF="$NVHOME/.config/hypr/hypridle.conf"
printf "listener {\n    after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })' && hyprctl dispatch 'x'\n    on-resume = hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'\n}\n" > "$HF"
hypridle_fix_nvidia "$NVHOME"; hypridle_fix_nvidia "$NVHOME"; CASES=$((CASES + 1))
chk_str hypridle-aftersleep "$(count 'sleep 2 &&' "$(cat "$HF")")" "1"
chk_str hypridle-onresume "$(count 'sleep 1 &&' "$(cat "$HF")")" "1"

GPU_FAILURES=(); note_failure "driver X failed" 2>/dev/null; note_failure "driver Y failed" 2>/dev/null
flush_failures "$NTMP/breadcrumb"; CASES=$((CASES + 1))
BC="$(cat "$NTMP/breadcrumb")"
chk_str breadcrumb-x "$( [[ "$BC" == *"- driver X failed"* ]] && echo yes || echo no )" "yes"
chk_str breadcrumb-y "$( [[ "$BC" == *"- driver Y failed"* ]] && echo yes || echo no )" "yes"
rm -rf "$NTMP"

# ── orchestration: gpu_apply_autoconfig + gpu_apply_hypr_tweaks per card ─────
OTMP="$(mktemp -d)"; export MKINITCPIO_CONF="$OTMP/mkinitcpio.conf" KERNEL_CMDLINE="$OTMP/cmdline" MODPROBE_DIR="$OTMP/modprobe.d"
OHOME="$OTMP/home"; mkdir -p "$OHOME/.config/hypr/custom"; FIX_SYSVENDOR=""
_gpu_swap_partuuid() { echo ""; }
_gpu_systemctl() { [[ "$1" == enable ]] && ENABLED="$ENABLED ${2%.service}"; return 0; }
# Orchestration nvidia cases assume a proprietary driver is installed.
_gpu_nvidia_has_driver() { return 0; }
oreset() { printf 'MODULES=()\nHOOKS=(base systemd plymouth autodetect kms keyboard block filesystems fsck)\n' > "$MKINITCPIO_CONF"; : > "$KERNEL_CMDLINE"; rm -rf "$MODPROBE_DIR"; : > "$OHOME/.config/hypr/custom/env.lua"; : > "$OHOME/.config/hypr/custom/general.lua"; ENABLED=""; }

oreset; FIX_LSPCI="03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 [Radeon RX 9070 XT] [1002:7550] (rev c0)"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1)); CL="$(cat "$KERNEL_CMDLINE")"; ML="$(grep '^MODULES=' "$MKINITCPIO_CONF")"
chk_str rdna4-cmdline "$( [[ "$CL" == *"amdgpu.modeset=1"* && "$CL" == *"amdgpu.sg_display=0"* ]] && echo yes || echo no )" "yes"
chk_str rdna4-modules "$( [[ "$ML" == *"amdgpu"* && "$ML" != *"nvidia"* ]] && echo yes || echo no )" "yes"

oreset; FIX_LSPCI="01:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Caicos [Radeon HD 6450] [1002:6760] (rev 81)"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1)); CL="$(cat "$KERNEL_CMDLINE")"; ML="$(grep '^MODULES=' "$MKINITCPIO_CONF")"
chk_str pregcn-modprobe "$( [[ -f "$MODPROBE_DIR/amdgpu.conf" ]] && echo yes || echo no )" "yes"
chk_str pregcn-modules "$( [[ "$ML" == *"amdgpu"* && "$ML" == *"radeon"* ]] && echo yes || echo no )" "yes"
chk_str pregcn-cmdline "$( [[ "$CL" == *"amdgpu.si_support=1"* && "$CL" == *"amdgpu.cik_support=1"* ]] && echo yes || echo no )" "yes"

oreset; FIX_LSPCI="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU104 [GeForce RTX 2080] [10de:1e87] (rev a1)"
gpu_detect; gpu_apply_autoconfig; gpu_apply_hypr_tweaks "$OHOME"; CASES=$((CASES + 1))
CL="$(cat "$KERNEL_CMDLINE")"; ML="$(grep '^MODULES=' "$MKINITCPIO_CONF")"; EV="$(cat "$OHOME/.config/hypr/custom/env.lua")"; GV="$(cat "$OHOME/.config/hypr/custom/general.lua")"
chk_str turing-modprobe "$( [[ -f "$MODPROBE_DIR/nvidia.conf" ]] && echo yes || echo no )" "yes"
chk_str turing-no-early-nvidia "$( [[ "$ML" == *"nvidia"* ]] && echo present || echo absent )" "absent"
chk_str turing-kms-removed "$( [[ "$(grep '^HOOKS=' "$MKINITCPIO_CONF")" == *" kms "* ]] && echo present || echo gone )" "gone"
chk_str turing-cmdline "$( [[ "$CL" == *"nvidia_drm.modeset=1"* ]] && echo yes || echo no )" "yes"
chk_str turing-powerd "$( [[ "$ENABLED" == *"nvidia-powerd"* ]] && echo yes || echo no )" "yes"
chk_str turing-env "$( [[ "$EV" == *'NVD_BACKEND'* ]] && echo yes || echo no )" "yes"
chk_str turing-cursor "$( [[ "$GV" == *'no_hardware_cursors = true'* ]] && echo yes || echo no )" "yes"

oreset; FIX_LSPCI="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GK208B [GeForce GT 710] [10de:128b] (rev a1)"
gpu_detect; gpu_apply_autoconfig; gpu_apply_hypr_tweaks "$OHOME"; CASES=$((CASES + 1)); CL="$(cat "$KERNEL_CMDLINE")"; EV="$(cat "$OHOME/.config/hypr/custom/env.lua")"
chk_str kepler-cmdline "$( [[ "$CL" == *"nvidia_drm.modeset=1"* ]] && echo yes || echo no )" "yes"
chk_str kepler-powerd-off "$( [[ "$ENABLED" == *"nvidia-powerd"* ]] && echo present || echo absent )" "absent"
chk_str kepler-no-nvd "$( [[ "$EV" == *'NVD_BACKEND'* ]] && echo present || echo absent )" "absent"
chk_str kepler-no-fbdev "$(grep -c 'fbdev=1' "$MODPROBE_DIR/nvidia.conf")" "0"

oreset; FIX_LSPCI="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP106 [GeForce GTX 1060 6GB] [10de:1c03] (rev a1)"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1))
chk_str maxwell-gen "$NVIDIA_GEN" "maxwell"
chk_str maxwell-powerd-off "$( [[ "$ENABLED" == *"nvidia-powerd"* ]] && echo present || echo absent )" "absent"
chk_str maxwell-fbdev "$(grep -c 'fbdev=1' "$MODPROBE_DIR/nvidia.conf")" "1"

oreset; FIX_LSPCI="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation G92 [GeForce 8800 GT] [10de:0611] (rev a2)"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1)); ML="$(grep '^MODULES=' "$MKINITCPIO_CONF")"
chk_str prefermi-no-nvidia "$( [[ "$ML" == *"nvidia"* ]] && echo present || echo absent )" "absent"
chk_str prefermi-no-modprobe "$( [[ -f "$MODPROBE_DIR/nvidia.conf" ]] && echo present || echo absent )" "absent"

oreset; FIX_LSPCI="00:02.0 VGA compatible controller [0300]: Intel Corporation AlderLake-S GT1 [UHD Graphics 770] [8086:4680] (rev 0c)"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1)); CL="$(cat "$KERNEL_CMDLINE")"; ML="$(grep '^MODULES=' "$MKINITCPIO_CONF")"
chk_str intel-modules "$( [[ "$ML" == *"i915"* ]] && echo yes || echo no )" "yes"
chk_str intel-cmdline "$( [[ "$CL" == *"i915.modeset=1"* ]] && echo present || echo absent )" "absent"

oreset; FIX_LSPCI="03:00.0 VGA compatible controller [0300]: Intel Corporation DG2 [Arc A770] [8086:56a0] (rev 08)"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1)); ML="$(grep '^MODULES=' "$MKINITCPIO_CONF")"
chk_str arc-i915 "$( [[ "$ML" == *"i915"* ]] && echo yes || echo no )" "yes"
chk_str arc-no-xe "$( [[ "$ML" == *xe* ]] && echo present || echo absent )" "absent"

oreset; FIX_LSPCI="00:02.0 VGA compatible controller [0300]: Intel Corporation TigerLake-H GT1 [UHD Graphics] [8086:9a60] (rev 01)
01:00.0 3D controller [0302]: NVIDIA Corporation GA106M [GeForce RTX 3060 Mobile] [10de:2503] (rev a1)"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1)); CL="$(cat "$KERNEL_CMDLINE")"; ML="$(grep '^MODULES=' "$MKINITCPIO_CONF")"
chk_str hybrid-modules "$( [[ "$ML" == *"i915"* ]] && echo yes || echo no )" "yes"
chk_str hybrid-no-early-nvidia "$( [[ "$ML" == *"nvidia"* ]] && echo present || echo absent )" "absent"
chk_str hybrid-cmdline "$( [[ "$CL" == *"nvidia_drm.modeset=1"* ]] && echo yes || echo no )" "yes"
chk_str hybrid-no-i915-modeset "$(count 'i915\.modeset=1' "$CL")" "0"

# Legacy NVIDIA that fell back to nouveau (no proprietary driver) must NOT get
# the nvidia config/env — that would black-screen the session.
oreset; _gpu_nvidia_has_driver() { return 1; }
FIX_LSPCI="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GK208B [GeForce GT 710] [10de:128b] (rev a1)"
gpu_detect; gpu_apply_autoconfig; gpu_apply_hypr_tweaks "$OHOME"; CASES=$((CASES + 1))
CL="$(cat "$KERNEL_CMDLINE")"; EV="$(cat "$OHOME/.config/hypr/custom/env.lua")"; GV="$(cat "$OHOME/.config/hypr/custom/general.lua")"
chk_str nouveau-no-modprobe "$( [[ -f "$MODPROBE_DIR/nvidia.conf" ]] && echo present || echo absent )" "absent"
chk_str nouveau-no-modeset "$( [[ "$CL" == *"nvidia_drm.modeset=1"* ]] && echo present || echo absent )" "absent"
chk_str nouveau-no-env "$( [[ "$EV" == *'GBM_BACKEND'* ]] && echo present || echo absent )" "absent"
chk_str nouveau-no-cursor "$( [[ "$GV" == *'no_hardware_cursors'* ]] && echo present || echo absent )" "absent"
_gpu_nvidia_has_driver() { return 0; }

oreset; _gpu_swap_partuuid() { echo "1234-abcd"; }
FIX_LSPCI="03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [Radeon RX 6700 XT] [1002:73df] (rev c1)"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1)); CL="$(cat "$KERNEL_CMDLINE")"
chk_str resume-added "$( [[ "$CL" == *"resume=PARTUUID=1234-abcd"* ]] && echo yes || echo no )" "yes"
_gpu_swap_partuuid() { echo ""; }

# Small-ESP guard: explicit early-KMS MODULES are skipped when the mounted ESP
# is under the threshold; modprobe/cmdline config is unaffected. Threshold 0
# disables the guard.
oreset; FIX_ESP_MIB=100
FIX_LSPCI="03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [Radeon RX 6700 XT] [1002:73df] (rev c1)"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1)); CL="$(cat "$KERNEL_CMDLINE")"; ML="$(grep '^MODULES=' "$MKINITCPIO_CONF")"
chk_str smallesp-no-amdgpu "$( [[ "$ML" == *"amdgpu"* ]] && echo present || echo absent )" "absent"
chk_str smallesp-cmdline-kept "$( [[ "$CL" == *"amdgpu.modeset=1"* ]] && echo yes || echo no )" "yes"

oreset; FIX_ESP_MIB=100
FIX_LSPCI="00:02.0 VGA compatible controller [0300]: Intel Corporation AlderLake-S GT1 [UHD Graphics 770] [8086:4680] (rev 0c)"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1)); ML="$(grep '^MODULES=' "$MKINITCPIO_CONF")"
chk_str smallesp-no-i915 "$( [[ "$ML" == *"i915"* ]] && echo present || echo absent )" "absent"

oreset; FIX_ESP_MIB=1024
FIX_LSPCI="03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [Radeon RX 6700 XT] [1002:73df] (rev c1)"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1)); ML="$(grep '^MODULES=' "$MKINITCPIO_CONF")"
chk_str bigesp-amdgpu "$( [[ "$ML" == *"amdgpu"* ]] && echo yes || echo no )" "yes"

oreset; FIX_ESP_MIB=100; GPU_EARLY_KMS_ESP_THRESHOLD=0
FIX_LSPCI="03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [Radeon RX 6700 XT] [1002:73df] (rev c1)"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1)); ML="$(grep '^MODULES=' "$MKINITCPIO_CONF")"
chk_str guard-off-amdgpu "$( [[ "$ML" == *"amdgpu"* ]] && echo yes || echo no )" "yes"
unset GPU_EARLY_KMS_ESP_THRESHOLD; FIX_ESP_MIB=0
rm -rf "$OTMP"

echo "----"
if [[ $FAILS -eq 0 ]]; then echo "gpu_detect: all $CASES cases PASS"; exit 0
else echo "gpu_detect: $FAILS assertion(s) FAILED across $CASES cases"; exit 1; fi
