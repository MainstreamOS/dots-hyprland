#!/usr/bin/env bash
# gpu-config.test.sh — fixture harness for gpu-config.sh detection.
# Run: bash sdata/lib/gpu-config.test.sh   (exit 0 = all green)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gpu-config.sh
source "$DIR/gpu-config.sh"

# Drive detection from fixture globals instead of real hardware.
FIX_LSPCI=""; FIX_SYSVENDOR=""; FIX_ESP_MIB=0; FIX_INSTALLED_BRANCH=""
_gpu_lspci_nn()   { printf '%s\n' "$FIX_LSPCI"; }
_gpu_lspci()      { printf '%s\n' "$FIX_LSPCI"; }
_gpu_sys_vendor() { printf '%s' "$FIX_SYSVENDOR"; }
_gpu_esp_mib()    { echo "$FIX_ESP_MIB"; }
_gpu_installed_nvidia_branch() { printf '%s' "$FIX_INSTALLED_BRANCH"; }

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

# Pre-GCN fusion APUs: ids sit above the 26112 ceiling and the HD 7xxx/8xxx
# names dodge the pre-GCN name regex, so only the id windows catch them.
run amd-llano "" "00:01.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Sumo [Radeon HD 6620G] [1002:9641]"
chk amd-llano HAS_AMD true; chk amd-llano AMD_DEC 38465; chk amd-llano IS_OLD_AMD true
run amd-wrestler "" "00:01.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Wrestler [Radeon HD 7340] [1002:9808]"
chk amd-wrestler AMD_DEC 38920; chk amd-wrestler IS_OLD_AMD true
run amd-trinity "" "00:01.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Trinity [Radeon HD 7660G] [1002:9900]"
chk amd-trinity AMD_DEC 39168; chk amd-trinity IS_OLD_AMD true
run amd-richland "" "00:01.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Richland [Radeon HD 8650G] [1002:990b]"
chk amd-richland AMD_DEC 39179; chk amd-richland IS_OLD_AMD true
run amd-trinity2 "" "00:01.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Trinity 2 [Radeon HD 7520G] [1002:9990]"
chk amd-trinity2 AMD_DEC 39312; chk amd-trinity2 IS_OLD_AMD true
run amd-richland2 "" "00:01.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Richland [Radeon HD 8550D] [1002:999d]"
chk amd-richland2 AMD_DEC 39325; chk amd-richland2 IS_OLD_AMD true

# GCN APUs on the same id pages must stay modern (amdgpu + RADV).
run amd-kaveri "" "00:01.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Kaveri [Radeon R7 Graphics] [1002:1309]"
chk amd-kaveri HAS_AMD true; chk amd-kaveri AMD_DEC 4873; chk amd-kaveri IS_OLD_AMD false
run amd-kabini "" "00:01.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Kabini [Radeon HD 8400 / R3 Series] [1002:9830]"
chk amd-kabini AMD_DEC 38960; chk amd-kabini IS_OLD_AMD false
run amd-mullins "" "00:01.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Mullins [Radeon R4/R5 Graphics] [1002:9851]"
chk amd-mullins AMD_DEC 38993; chk amd-mullins IS_OLD_AMD false
run amd-carrizo "" "00:01.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Wani [Radeon R5/R6/R7 Graphics] [1002:9874]"
chk amd-carrizo AMD_DEC 39028; chk amd-carrizo IS_OLD_AMD false
run amd-stoney "" "00:01.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Stoney [Radeon R2/R3/R4/R5 Graphics] [1002:98e4]"
chk amd-stoney AMD_DEC 39140; chk amd-stoney IS_OLD_AMD false

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
# Fermi parts whose IDs sit above GK107 (0x0FC0), and the Kepler parts around them.
run nv-fermi-gf110 "" "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GF110 [GeForce GTX 580] [10de:1080] (rev a1)"
chk nv-fermi-gf110 NVIDIA_GEN fermi
run nv-fermi-gf119 "" "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GF119 [GeForce GT 520] [10de:1040] (rev a1)"
chk nv-fermi-gf119 NVIDIA_GEN fermi
run nv-fermi-gf117 "" "01:00.0 3D controller [0302]: NVIDIA Corporation GF117M [GeForce 610M/710M/810M/820M / GT 620M/625M/630M/720M] [10de:1140] (rev a1)"
chk nv-fermi-gf117 NVIDIA_GEN fermi
run nv-fermi-gf116 "" "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GF116 [GeForce GTX 550 Ti] [10de:1244] (rev a1)"
chk nv-fermi-gf116 NVIDIA_GEN fermi
run nv-kepler-gk107 "" "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GK107 [GeForce GT 640] [10de:0fc1] (rev a1)"
chk nv-kepler-gk107 NVIDIA_GEN kepler
run nv-kepler-gk110 "" "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GK110 [GeForce GTX 780] [10de:1004] (rev a1)"
chk nv-kepler-gk110 NVIDIA_GEN kepler
run nv-kepler-gk104 "" "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GK104 [GeForce GTX 680] [10de:1180] (rev a1)"
chk nv-kepler-gk104 NVIDIA_GEN kepler
# The display ID must come from a display line even when another NVIDIA device lists first.
run nv-audio-first "" "00:1f.0 Audio device [0403]: NVIDIA Corporation GP107GL High Definition Audio Controller [10de:0fb9] (rev a1)
01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU116 [GeForce GTX 1660] [10de:2184] (rev a1)"
chk nv-audio-first NVIDIA_GEN turing

# 10-12. Intel generation ladder — xe (Gen12+), modern (Gen8-11), legacy (Gen4-7.5)
run intel-arc "" "03:00.0 VGA compatible controller [0300]: Intel Corporation DG2 [Arc A770] [8086:56a0] (rev 08)"
chk intel-arc HAS_INTEL true; chk intel-arc INTEL_GEN xe
run intel-alderlake "" "00:02.0 VGA compatible controller [0300]: Intel Corporation AlderLake-S GT1 [UHD Graphics 770] [8086:4680] (rev 0c)"
chk intel-alderlake HAS_INTEL true; chk intel-alderlake INTEL_GEN xe
run intel-presb "" "00:02.0 VGA compatible controller [0300]: Intel Corporation Core Processor Integrated Graphics Controller [8086:0042] (rev 12)"
chk intel-presb HAS_INTEL true; chk intel-presb INTEL_GEN legacy

run intel-tigerlake "" "00:02.0 VGA compatible controller [0300]: Intel Corporation TigerLake-LP GT2 [Iris Xe Graphics] [8086:9a49] (rev 01)"
chk intel-tigerlake INTEL_GEN xe
run intel-battlemage "" "03:00.0 VGA compatible controller [0300]: Intel Corporation Battlemage G21 [Arc B580] [8086:e20b] (rev 05)"
chk intel-battlemage INTEL_GEN xe
run intel-lunarlake "" "00:02.0 VGA compatible controller [0300]: Intel Corporation Lunar Lake [Intel Graphics] [8086:64a0] (rev 04)"
chk intel-lunarlake INTEL_GEN xe
run intel-dg1 "" "03:00.0 VGA compatible controller [0300]: Intel Corporation DG1 [Iris Xe MAX Graphics] [8086:4905]"
chk intel-dg1 INTEL_GEN xe

# Gen9/Gen11 stay 'modern': iHD VA-API, but no OpenCL (upstream legacy1 only).
run intel-skylake "" "00:02.0 VGA compatible controller [0300]: Intel Corporation HD Graphics 530 [8086:1912] (rev 06)"
chk intel-skylake INTEL_GEN modern
run intel-broadwell "" "00:02.0 VGA compatible controller [0300]: Intel Corporation HD Graphics 5500 [8086:1616] (rev 09)"
chk intel-broadwell INTEL_GEN modern
run intel-icelake "" "00:02.0 VGA compatible controller [0300]: Intel Corporation Iris Plus Graphics G7 [8086:8a52] (rev 07)"
chk intel-icelake INTEL_GEN modern
run intel-cherryview "" "00:02.0 VGA compatible controller [0300]: Intel Corporation Atom/Celeron/Pentium Processor Graphics [8086:22b0] (rev 21)"
chk intel-cherryview INTEL_GEN modern
run intel-cometlake "" "00:02.0 VGA compatible controller [0300]: Intel Corporation CometLake-U GT2 [UHD Graphics] [8086:9b41] (rev 02)"
chk intel-cometlake INTEL_GEN modern
run intel-elkhartlake "" "00:02.0 VGA compatible controller [0300]: Intel Corporation JasperLake [UHD Graphics] [8086:4e61] (rev 01)"
chk intel-elkhartlake INTEL_GEN modern
# Unrecognised id must fall to the safe middle tier, not to legacy.
run intel-unknown "" "00:02.0 VGA compatible controller [0300]: Intel Corporation Device [8086:ff01] (rev 01)"
chk intel-unknown INTEL_GEN modern

run intel-haswell "" "00:02.0 VGA compatible controller [0300]: Intel Corporation Haswell-ULT Integrated Graphics Controller [8086:0a16] (rev 09)"
chk intel-haswell INTEL_GEN legacy
run intel-sandybridge "" "00:02.0 VGA compatible controller [0300]: Intel Corporation 2nd Generation Core Processor Family Integrated Graphics Controller [8086:0116] (rev 09)"
chk intel-sandybridge INTEL_GEN legacy
run intel-g45 "" "00:02.0 VGA compatible controller [0300]: Intel Corporation 4 Series Chipset Integrated Graphics Controller [8086:2e32] (rev 03)"
chk intel-g45 INTEL_GEN legacy
run intel-gm965 "" "00:02.0 VGA compatible controller [0300]: Intel Corporation Mobile GM965/GL960 Integrated Graphics Controller [8086:2a02] (rev 0c)"
chk intel-gm965 INTEL_GEN legacy

# No Intel present -> INTEL_GEN stays 'none'.
run intel-absent "" "03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [Radeon RX 6700 XT] [1002:73df] (rev c1)"
chk intel-absent HAS_INTEL false; chk intel-absent INTEL_GEN none

# 13. Hybrid NVIDIA + Intel (laptop; dGPU shows as 3D controller)
run hybrid-nv-intel "" "00:02.0 VGA compatible controller [0300]: Intel Corporation TigerLake-H GT1 [UHD Graphics] [8086:9a60] (rev 01)
01:00.0 3D controller [0302]: NVIDIA Corporation GA106M [GeForce RTX 3060 Mobile] [10de:2503] (rev a1)"
chk hybrid-nv-intel HAS_NVIDIA true; chk hybrid-nv-intel HAS_INTEL true; chk hybrid-nv-intel HAS_AMD false
chk hybrid-nv-intel IS_HYBRID true; chk hybrid-nv-intel NVIDIA_GEN turing
chk hybrid-nv-intel INTEL_GEN xe

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
chk_str modprobe-nvidia "$(cat "$MODPROBE_DIR/nvidia.conf")" "$(printf 'options nvidia-drm modeset=1 fbdev=1')"
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

# AQ_DRM_DEVICES is no longer written: pinning Aquamarine to one card
# black-screened a hybrid laptop, and autodetect is what makes the outputs on
# both cards enumerable. Anyone who wants the pin sets it by hand.
chk_str aq-drm-retired "$(type -t nvidia_write_aq_drm || echo absent)" "absent"
chk_str defer-kms-retired "$(type -t nvidia_defer_kms || echo absent)" "absent"
CASES=$((CASES + 1))

# The initramfs names whichever module the kernel bound, not one worked out from
# the card's generation.
_gpu_lspci_d() { printf '%s\n' "0000:00:02.0 VGA compatible controller: Intel Corporation Arrow Lake-S [Intel Graphics]"; }
_gpu_bound_driver() { echo xe; };   chk_str intel-mod-xe "$(intel_kms_module)" "xe"
_gpu_bound_driver() { echo i915; }; chk_str intel-mod-i915 "$(intel_kms_module)" "i915"
_gpu_bound_driver() { return 0; };  chk_str intel-mod-fallback "$(intel_kms_module)" "i915"
CASES=$((CASES + 3))

ENABLED=""; _gpu_systemctl() { [[ "$1" == enable ]] && ENABLED="$ENABLED ${2%.service}"; return 0; }
nvidia_enable_services true; CASES=$((CASES + 1))
chk_str svc-powerd-on "$( [[ "$ENABLED" == *"nvidia-powerd"* ]] && echo yes || echo no )" "yes"
chk_str svc-resume "$( [[ "$ENABLED" == *"nvidia-resume"* ]] && echo yes || echo no )" "yes"
ENABLED=""; nvidia_enable_services false; CASES=$((CASES + 1))
chk_str svc-powerd-off "$( [[ "$ENABLED" == *"nvidia-powerd"* ]] && echo present || echo absent )" "absent"
chk_str svc-suspend-still "$( [[ "$ENABLED" == *"nvidia-suspend"* ]] && echo yes || echo no )" "yes"
ENABLED=""; nvidia_enable_services true false; CASES=$((CASES + 1))
chk_str svc-sleep-optout "$( [[ "$ENABLED" == *nvidia-suspend* || "$ENABLED" == *nvidia-hibernate* || "$ENABLED" == *nvidia-resume* ]] && echo present || echo absent )" "absent"
chk_str svc-powerd-kept "$( [[ "$ENABLED" == *"nvidia-powerd"* ]] && echo yes || echo no )" "yes"

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

# ── _gpu_nvidia_has_driver: any-of, not all-of ──────────────────────────────
# Drives every NVIDIA branch in both orchestrators, so an all-of query silently
# disables them all. Fixtured at the pacman seam so the real loop is exercised.
INSTALLED=""
_gpu_pacman_has() { [[ " $INSTALLED " == *" $1 "* ]]; }
has_drv() { _gpu_nvidia_has_driver && echo yes || echo no; }
CASES=$((CASES + 1))
INSTALLED="nvidia-580xx-utils"; chk_str hasdrv-580xx "$(has_drv)" "yes"
INSTALLED="nvidia-390xx-utils"; chk_str hasdrv-390xx "$(has_drv)" "yes"
INSTALLED="nvidia-utils nvidia-open"; chk_str hasdrv-open "$(has_drv)" "yes"
INSTALLED="mesa vulkan-radeon"; chk_str hasdrv-none "$(has_drv)" "no"

# ── orchestration: gpu_apply_autoconfig + gpu_apply_hypr_tweaks per card ─────
OTMP="$(mktemp -d)"; export MKINITCPIO_CONF="$OTMP/mkinitcpio.conf" KERNEL_CMDLINE="$OTMP/cmdline" MODPROBE_DIR="$OTMP/modprobe.d" INITCPIO_INSTALL_DIR="$OTMP/initcpio"
OHOME="$OTMP/home"; mkdir -p "$OHOME/.config/hypr/custom"; FIX_SYSVENDOR=""
_gpu_swap_partuuid() { echo ""; }
_gpu_systemctl() { [[ "$1" == enable ]] && ENABLED="$ENABLED ${2%.service}"; return 0; }
# Orchestration nvidia cases assume a proprietary driver is installed AND that
# its module exists for the kernel about to boot. The stranded-module case gets
# its own fixture further down.
_gpu_nvidia_has_driver() { return 0; }
nvidia_module_present() { return 0; }
oreset() { printf 'MODULES=()\nHOOKS=(base systemd plymouth autodetect kms keyboard block filesystems fsck)\n' > "$MKINITCPIO_CONF"; : > "$KERNEL_CMDLINE"; rm -rf "$MODPROBE_DIR" "$INITCPIO_INSTALL_DIR"; : > "$OHOME/.config/hypr/custom/env.lua"; : > "$OHOME/.config/hypr/custom/general.lua"; ENABLED=""; }

oreset; FIX_LSPCI="03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 48 [Radeon RX 9070 XT] [1002:7550] (rev c0)"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1)); CL="$(cat "$KERNEL_CMDLINE")"; ML="$(grep '^MODULES=' "$MKINITCPIO_CONF")"
chk_str rdna4-cmdline "$( [[ "$CL" == *"amdgpu.modeset=1"* && "$CL" == *"amdgpu.sg_display=0"* ]] && echo yes || echo no )" "yes"
chk_str rdna4-modules "$( [[ "$ML" == *"amdgpu"* && "$ML" != *"nvidia"* ]] && echo yes || echo no )" "yes"

oreset; FIX_LSPCI="01:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Caicos [Radeon HD 6450] [1002:6760] (rev 81)"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1)); CL="$(cat "$KERNEL_CMDLINE")"; ML="$(grep '^MODULES=' "$MKINITCPIO_CONF")"
chk_str pregcn-modprobe "$( [[ -f "$MODPROBE_DIR/amdgpu.conf" ]] && echo yes || echo no )" "yes"
chk_str pregcn-modules "$( [[ "$ML" == *"amdgpu"* && "$ML" == *"radeon"* ]] && echo yes || echo no )" "yes"
chk_str pregcn-cmdline "$( [[ "$CL" == *"amdgpu.si_support=1"* && "$CL" == *"amdgpu.cik_support=1"* ]] && echo yes || echo no )" "yes"

oreset; FIX_LSPCI="00:01.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Trinity [Radeon HD 7660G] [1002:9900]"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1)); CL="$(cat "$KERNEL_CMDLINE")"; ML="$(grep '^MODULES=' "$MKINITCPIO_CONF")"
chk_str terascale-apu-radeon "$( [[ "$ML" == *"radeon"* ]] && echo yes || echo no )" "yes"
chk_str terascale-apu-no-modeset "$( [[ "$CL" == *"amdgpu.modeset=1"* ]] && echo present || echo absent )" "absent"
chk_str terascale-apu-modprobe "$( [[ -f "$MODPROBE_DIR/amdgpu.conf" ]] && echo yes || echo no )" "yes"

oreset; FIX_LSPCI="00:01.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Wani [Radeon R5/R6/R7 Graphics] [1002:9874]"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1)); CL="$(cat "$KERNEL_CMDLINE")"; ML="$(grep '^MODULES=' "$MKINITCPIO_CONF")"
chk_str carrizo-no-radeon "$( [[ "$ML" == *"radeon"* ]] && echo present || echo absent )" "absent"
chk_str carrizo-modeset "$( [[ "$CL" == *"amdgpu.modeset=1"* ]] && echo yes || echo no )" "yes"

oreset; FIX_LSPCI="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU104 [GeForce RTX 2080] [10de:1e87] (rev a1)"
gpu_detect; gpu_apply_autoconfig; gpu_apply_hypr_tweaks "$OHOME"; CASES=$((CASES + 1))
CL="$(cat "$KERNEL_CMDLINE")"; ML="$(grep '^MODULES=' "$MKINITCPIO_CONF")"; EV="$(cat "$OHOME/.config/hypr/custom/env.lua")"; GV="$(cat "$OHOME/.config/hypr/custom/general.lua")"
chk_str turing-modprobe "$( [[ -f "$MODPROBE_DIR/nvidia.conf" ]] && echo yes || echo no )" "yes"
chk_str turing-no-early-nvidia "$( [[ "$ML" == *"nvidia"* ]] && echo present || echo absent )" "absent"
chk_str turing-kms-kept "$( [[ "$(grep '^HOOKS=' "$MKINITCPIO_CONF")" == *" kms "* ]] && echo present || echo gone )" "present"
chk_str turing-modprobe-body "$(cat "$MODPROBE_DIR/nvidia.conf")" "options nvidia-drm modeset=1 fbdev=1"
chk_str turing-modprobe-bytes "$(wc -c < "$MODPROBE_DIR/nvidia.conf" | tr -d ' ')" "37"
chk_str turing-no-sleep-svc "$( [[ "$ENABLED" == *nvidia-suspend* || "$ENABLED" == *nvidia-hibernate* || "$ENABLED" == *nvidia-resume* ]] && echo present || echo absent )" "absent"
chk_str turing-cmdline "$( [[ "$CL" == *"nvidia_drm.modeset=1"* ]] && echo yes || echo no )" "yes"
chk_str turing-powerd "$( [[ "$ENABLED" == *"nvidia-powerd"* ]] && echo yes || echo no )" "yes"
chk_str turing-env "$( [[ "$EV" == *'NVD_BACKEND'* ]] && echo yes || echo no )" "yes"
chk_str turing-cursor "$( [[ "$GV" == *'no_hardware_cursors = true'* ]] && echo yes || echo no )" "yes"
chk_str turing-no-gsp-hook "$( [[ -f "$INITCPIO_INSTALL_DIR/strip-nvidia-gsp" ]] && echo present || echo absent )" "absent"

oreset; FIX_LSPCI="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GK208B [GeForce GT 710] [10de:128b] (rev a1)"
gpu_detect; gpu_apply_autoconfig; gpu_apply_hypr_tweaks "$OHOME"; CASES=$((CASES + 1)); CL="$(cat "$KERNEL_CMDLINE")"; EV="$(cat "$OHOME/.config/hypr/custom/env.lua")"
chk_str kepler-cmdline "$( [[ "$CL" == *"nvidia_drm.modeset=1"* ]] && echo yes || echo no )" "yes"
chk_str kepler-powerd-off "$( [[ "$ENABLED" == *"nvidia-powerd"* ]] && echo present || echo absent )" "absent"
chk_str kepler-no-nvd "$( [[ "$EV" == *'NVD_BACKEND'* ]] && echo present || echo absent )" "absent"
chk_str kepler-no-fbdev "$(grep -c 'fbdev=1' "$MODPROBE_DIR/nvidia.conf")" "0"
chk_str kepler-sleep-svc "$( [[ "$ENABLED" == *nvidia-suspend* && "$ENABLED" == *nvidia-hibernate* && "$ENABLED" == *nvidia-resume* ]] && echo yes || echo no )" "yes"
chk_str kepler-sleep-opts "$(grep -c NVreg_PreserveVideoMemoryAllocations "$MODPROBE_DIR/nvidia.conf")" "1"

oreset; FIX_LSPCI="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP106 [GeForce GTX 1060 6GB] [10de:1c03] (rev a1)"
gpu_detect; gpu_apply_autoconfig; CASES=$((CASES + 1))
chk_str maxwell-gen "$NVIDIA_GEN" "maxwell"
chk_str maxwell-powerd-off "$( [[ "$ENABLED" == *"nvidia-powerd"* ]] && echo present || echo absent )" "absent"
chk_str maxwell-gsp-hook "$( [[ -f "$INITCPIO_INSTALL_DIR/strip-nvidia-gsp" && "$(grep '^HOOKS=' "$MKINITCPIO_CONF")" == *"strip-nvidia-gsp"* ]] && echo yes || echo no )" "yes"
chk_str maxwell-fbdev "$(grep -c 'fbdev=1' "$MODPROBE_DIR/nvidia.conf")" "1"
chk_str maxwell-sleep-opts "$(grep -c NVreg_PreserveVideoMemoryAllocations "$MODPROBE_DIR/nvidia.conf")" "1"
chk_str maxwell-sleep-svc "$( [[ "$ENABLED" == *nvidia-suspend* ]] && echo yes || echo no )" "yes"

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

# THE FIELD BUG (Alienware M17 R3, 2026-08-24): the packages are installed but
# the kernel moved on its own, so nvidia-open's prebuilt module sits under a
# kernel directory nothing will look in. Dressing that kernel in modeset flags
# and suspend services hid the failure behind config that read as correct.
oreset; nvidia_module_present() { return 1; }
FIX_LSPCI="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU106M [GeForce RTX 2060 Mobile] [10de:1f15] (rev a1)"
GPU_FAILURES=()
gpu_detect; gpu_apply_autoconfig; gpu_apply_hypr_tweaks "$OHOME"; CASES=$((CASES + 1))
CL="$(cat "$KERNEL_CMDLINE")"; EV="$(cat "$OHOME/.config/hypr/custom/env.lua")"
chk_str stranded-no-modeset "$( [[ "$CL" == *"nvidia_drm.modeset=1"* ]] && echo present || echo absent )" "absent"
chk_str stranded-no-modprobe "$( [[ -f "$MODPROBE_DIR/nvidia.conf" ]] && echo present || echo absent )" "absent"
chk_str stranded-no-env "$( [[ "$EV" == *'GBM_BACKEND'* ]] && echo present || echo absent )" "absent"
chk_str stranded-no-services "$( [[ "$ENABLED" == *nvidia-suspend* ]] && echo present || echo absent )" "absent"
chk_str stranded-recorded "$( [[ "${GPU_FAILURES[*]:-}" == *"no module for kernel"* ]] && echo yes || echo no )" "yes"
nvidia_module_present() { return 0; }

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
# ── target kernel + the stranded-module probe ───────────────────────────────
# A package query cannot see a module built for a kernel that has since moved.
# The orchestration section above stubs these probes so its own fixtures stay
# honest; re-source to get the real ones back before testing them directly.
source "$DIR/gpu-config.sh"
KDIR="$(mktemp -d)"
mkdir -p "$KDIR/6.17.1-arch1-1" "$KDIR/6.17.4-arch1-1" "$KDIR/6.17.9-headers-only"
for k in 6.17.1-arch1-1 6.17.4-arch1-1; do : > "$KDIR/$k/vmlinuz"; echo linux > "$KDIR/$k/pkgbase"; done
echo linux > "$KDIR/6.17.9-headers-only/pkgbase"   # headers left a bare tree, no vmlinuz
_gpu_module_dirs() { printf '%s\n' "$KDIR"/*/; }
_gpu_uname_r() { echo "not-a-tree-here"; }   # the installer case: nothing matches

chk_str tk-newest-bootable "$(gpu_target_kernel)" "6.17.4-arch1-1"; CASES=$((CASES + 1))

# On a live system the running kernel is the answer, even when an older or a
# stock-named tree also qualifies.
_gpu_uname_r() { echo "6.17.1-arch1-1"; }
chk_str tk-running-wins "$(gpu_target_kernel)" "6.17.1-arch1-1"; CASES=$((CASES + 1))
_gpu_uname_r() { echo "not-a-tree-here"; }

# A machine booting linux-lts or linux-zen has a real kernel and a real driver.
# Answering "none" here would strip the config off a card that works.
LTS="$(mktemp -d)"; mkdir -p "$LTS/6.12.40-1-lts"
: > "$LTS/6.12.40-1-lts/vmlinuz"; echo linux-lts > "$LTS/6.12.40-1-lts/pkgbase"
_gpu_module_dirs() { printf '%s\n' "$LTS"/*/; }
chk_str tk-nonstock-fallback "$(gpu_target_kernel)" "6.12.40-1-lts"; CASES=$((CASES + 1))
_gpu_modinfo() { [[ "$1" == "6.12.40-1-lts" ]]; }
chk_str tk-nonstock-configured "$(nvidia_module_present && echo yes || echo no)" "yes"; CASES=$((CASES + 1))
rm -rf "$LTS"
_gpu_module_dirs() { printf '%s\n' "$KDIR"/*/; }

# a tree with no kernel image must never be chosen, however new it sorts
: > "$KDIR/6.17.9-headers-only/pkgbase"; echo linux > "$KDIR/6.17.9-headers-only/pkgbase"
chk_str tk-skips-headers-only "$(gpu_target_kernel)" "6.17.4-arch1-1"; CASES=$((CASES + 1))

# module present for the booting kernel -> true
_gpu_modinfo() { [[ "$1" == "6.17.4-arch1-1" && "$2" == nvidia ]]; }
chk_str mod-present "$(nvidia_module_present && echo yes || echo no)" "yes"; CASES=$((CASES + 1))

# An index that has not caught up must not read as "no driver": the file in the
# tree is the same answer. Proven necessary, modinfo finds nothing until depmod
# has run even with the module sitting on disk.
_gpu_modinfo() { return 1; }
_gpu_module_file() { [[ "$1" == "6.17.4-arch1-1" ]]; }
chk_str mod-file-fallback "$(nvidia_module_present && echo yes || echo no)" "yes"; CASES=$((CASES + 1))
_gpu_module_file() { return 1; }
chk_str mod-neither "$(nvidia_module_present && echo yes || echo no)" "no"; CASES=$((CASES + 1))

# THE FIELD BUG: module exists only for the kernel that was replaced
_gpu_modinfo() { [[ "$1" == "6.17.1-arch1-1" && "$2" == nvidia ]]; }
chk_str mod-stranded "$(nvidia_module_present && echo yes || echo no)" "no"; CASES=$((CASES + 1))
chk_str mod-stranded-explicit "$(nvidia_module_present 6.17.1-arch1-1 && echo yes || echo no)" "yes"; CASES=$((CASES + 1))

# no bootable tree at all -> false, never a crash
_gpu_module_dirs() { printf '%s\n' /nonexistent-xyz/*/; }
chk_str tk-none "$(gpu_target_kernel)" ""; CASES=$((CASES + 1))
chk_str mod-none "$(nvidia_module_present && echo yes || echo no)" "no"; CASES=$((CASES + 1))
rm -rf "$KDIR"

# ── gpu_classify_nvidia_driver: generation map + installed-branch override ──
# The write-seam sections above re-source the lib, which restores the real
# pacman probe; pin the fixture again so these cases stay hermetic.
_gpu_installed_nvidia_branch() { printf '%s' "$FIX_INSTALLED_BRANCH"; }
classify() { NVIDIA_GEN="$1"; FIX_INSTALLED_BRANCH="$2"; CASES=$((CASES + 1)); gpu_classify_nvidia_driver; }

# Fresh systems: nothing installed, the generation decides.
classify turing "";   chk cls-turing NVIDIA_DRIVER_FAMILY nvidia-open
chk_str cls-turing-repo "${NVIDIA_REPO_PKGS[0]}" nvidia-open
classify maxwell "";  chk cls-maxwell NVIDIA_DRIVER_FAMILY nvidia-580xx
chk_str cls-maxwell-local "${NVIDIA_LOCAL_PKGS[0]}" nvidia-580xx-dkms
classify kepler "";   chk cls-kepler NVIDIA_DRIVER_FAMILY nvidia-470xx
classify fermi "";    chk cls-fermi NVIDIA_DRIVER_FAMILY nvidia-390xx
classify prefermi ""; chk cls-prefermi NVIDIA_DRIVER_FAMILY nouveau
classify none "";     chk cls-none NVIDIA_DRIVER_FAMILY nouveau

# THE REPAIR CASE: a legacy edition runs 580xx that the online repos do not
# carry. The installed branch must win over every generation verdict so a
# re-provision keeps the driver that is working instead of migrating it.
classify maxwell 580xx; chk cls-installed-match NVIDIA_DRIVER_FAMILY nvidia-580xx
classify turing 580xx;  chk cls-installed-over-turing NVIDIA_DRIVER_FAMILY nvidia-580xx
chk_str cls-installed-no-repo "${#NVIDIA_REPO_PKGS[@]}" 0
classify kepler 470xx;  chk cls-installed-470 NVIDIA_DRIVER_FAMILY nvidia-470xx
classify fermi 390xx;   chk cls-installed-390 NVIDIA_DRIVER_FAMILY nvidia-390xx

# An unrecognized probe answer must not zero the result; the map still runs.
classify maxwell bogus; chk cls-installed-bogus NVIDIA_DRIVER_FAMILY nvidia-580xx
FIX_INSTALLED_BRANCH=""

if [[ $FAILS -eq 0 ]]; then echo "gpu_detect: all $CASES cases PASS"; exit 0
else echo "gpu_detect: $FAILS assertion(s) FAILED across $CASES cases"; exit 1; fi
