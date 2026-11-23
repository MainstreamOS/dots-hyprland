#!/usr/bin/env bash
# gpu-driver-install.test.sh: the per-kernel NVIDIA module steps against a fake
# system. Kernel trees live in a temp directory, and pacman and dkms are
# stand-ins that keep an installed set and record every call.
# Run: bash sdata/lib/gpu-driver-install.test.sh   (exit 0 = all green)
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gpu-config.sh
source "$DIR/gpu-config.sh"
# shellcheck source=gpu-driver-install.sh
source "$DIR/gpu-driver-install.sh"

FAILS=0; CASES=0
chk_str() { if [[ "$2" != "$3" ]]; then echo "  FAIL [$1]: got '$2' want '$3'"; FAILS=$((FAILS + 1)); fi; }
has()   { if [[ "$2" != *"$3"* ]]; then echo "  FAIL [$1]: '$3' not in: $2"; FAILS=$((FAILS + 1)); fi; }
lacks() { if [[ "$2" == *"$3"* ]]; then echo "  FAIL [$1]: '$3' found in: $2"; FAILS=$((FAILS + 1)); fi; }

TMP="$(mktemp -d)"; K="$TMP/modules"
trap 'rm -rf "$TMP"' EXIT

# Anything that reaches a real tool is a failed test, not a changed machine.
mkdir -p "$TMP/bin"
for _t in sudo dkms modinfo; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/escaped"\nexit 1\n' "$_t" "$TMP" > "$TMP/bin/$_t"
    chmod +x "$TMP/bin/$_t"
done
PATH="$TMP/bin:$PATH"

# ── the fake system ─────────────────────────────────────────────────────────
INSTALLED=" "; REPO=" "; CALLS=(); OUT=""; RC=0
NO_FETCH=""          # a package pacman -Sw cannot get
NO_INSTALL=""        # a package whose pacman -S fails
HOOK_SKIPS=" "       # kernels pacman's DKMS hook builds nothing for
DKMS_FAIL=" "        # kernels no DKMS build succeeds for
LEAVE_LOG=0          # 1: a failed build leaves DKMS's make.log behind
PREBUILT_STALE=0     # 1: the repo's nvidia-open is for a kernel that is not here
FAIL_COMBINED=0      # 1: a transaction naming more than one kernel fails

in_set() { [[ "$2" == *" $1 "* ]]; }
kernel() {  # kernel <release> <pkgbase> [module] [headers]
    mkdir -p "$K/$1"; : > "$K/$1/vmlinuz"; echo "$2" > "$K/$1/pkgbase"
    [[ " $* " == *" module "* ]] && : > "$K/$1/nvidia.ko"
    [[ " $* " == *" headers "* ]] && mkdir -p "$K/$1/build"
    return 0
}
tree_of() {
    local d
    for d in "$K"/*/; do
        [[ -f "$d/vmlinuz" && -r "$d/pkgbase" && "$(<"$d/pkgbase")" == "$1" ]] && basename "$d"
    done
    return 0
}
hook_build() {
    local d k
    in_set dkms "$INSTALLED" || return 0
    for d in "$K"/*/; do
        k="$(basename "$d")"
        [[ -d "$d/build" && -f "$d/vmlinuz" ]] || continue
        in_set "$k" "$HOOK_SKIPS" && continue
        in_set "$k" "$DKMS_FAIL" && continue
        : > "$d/nvidia.ko"
    done
}
reset() {
    rm -rf "$K"; mkdir -p "$K"
    INSTALLED=" "; REPO=" linux linux-headers linux-mainstream linux-mainstream-headers dkms nvidia-open nvidia-open-dkms nvidia-utils "
    CALLS=(); OUT=""; RC=0; GPU_FAILURES=()
    NO_FETCH=""; NO_INSTALL=""; HOOK_SKIPS=" "; DKMS_FAIL=" "; PREBUILT_STALE=0; FAIL_COMBINED=0
    LEAVE_LOG=0; unlink "$TMP/dkms/620.73.04/build/make.log" 2>/dev/null; unlink "$GPU_LOG_DIR/nvidia-dkms-$STOCK.log" 2>/dev/null
    unset GPU_SUDO GPU_DB_REFRESH
}

_gpu_module_dirs() { printf '%s\n' "$K"/*/; }
_gpu_modinfo() { return 1; }
_gpu_module_file() { [[ -e "$K/$1/nvidia.ko" ]]; }
_gpu_kernel_headers_present() { [[ -d "$K/$1/build" ]]; }
_gpu_dkms_make_log() { printf '%s\n' "$TMP/dkms/$1/build/make.log"; }
GPU_LOG_DIR="$TMP/log"; STOCK=7.3.5-arch1-1

# Queries only. nvidia-open-dkms provides nvidia-open, and pacman -Q answers a
# provided name with the provider, as the real one does.
pacman() {
    case "$1" in
        -Si) [[ "$2" == -- ]] && shift; in_set "$2" "$REPO" ;;
        -Q|-Qq)
            [[ "$2" == -- ]] && shift
            if in_set "$2" "$INSTALLED"; then echo "$2"
            elif [[ "$2" == nvidia-open ]] && in_set nvidia-open-dkms "$INSTALLED"; then echo nvidia-open-dkms
            else return 1; fi ;;
        *) echo "pacman $*" >> "$TMP/escaped"; return 1 ;;
    esac
}
_gpu_pacman() {
    CALLS+=("pacman $*")
    local op="$1" p t n=0; shift
    case "$op" in
        -Sy) return 0 ;;
        -Sw) shift; in_set "$1" "$REPO" && [[ "$1" != "$NO_FETCH" ]] ;;
        -Rdd)
            shift; in_set "$1" "$INSTALLED" || return 1
            INSTALLED="${INSTALLED/ $1 / }"
            # The prebuilt driver owns one kernel's module, the DKMS one all it built.
            case "$1" in
                nvidia-open) for t in $(tree_of linux); do unlink "${K:?}/${t:?}/nvidia.ko" 2>/dev/null; done ;;
                nvidia-*-dkms)
                    for t in "${K:?}"/*/nvidia.ko; do [[ -e "$t" ]] && unlink "$t"; done
                    unlink "$TMP/dkms/620.73.04/build/make.log" 2>/dev/null ;;
            esac
            return 0 ;;
        -S)
            local pkgs=()
            for p in "$@"; do [[ "$p" == -* ]] || pkgs+=("$p"); done
            for p in "${pkgs[@]}"; do
                in_set "$p" "$REPO" || return 1
                [[ "$p" == "$NO_INSTALL" ]] && return 1
                [[ -n "$(tree_of "$p")" ]] && n=$((n + 1))
            done
            (( FAIL_COMBINED == 1 && n > 1 )) && return 1
            # The conflict question answers itself with No.
            if [[ " ${pkgs[*]} " == *" nvidia-open-dkms "* ]] && in_set nvidia-open "$INSTALLED"; then return 1; fi
            if [[ " ${pkgs[*]} " == *" nvidia-open "* ]] && in_set nvidia-open-dkms "$INSTALLED"; then return 1; fi
            for p in "${pkgs[@]}"; do
                in_set "$p" "$INSTALLED" || INSTALLED+="$p "
                case "$p" in
                    *-headers) for t in $(tree_of "${p%-headers}"); do mkdir -p "$K/$t/build"; done ;;
                esac
            done
            for p in "${pkgs[@]}"; do
                case "$p" in
                    nvidia-open) (( PREBUILT_STALE == 1 )) || for t in $(tree_of linux); do : > "$K/$t/nvidia.ko"; done ;;
                    nvidia-*-dkms) hook_build ;;
                esac
            done
            return 0 ;;
        *) return 1 ;;
    esac
}
_gpu_dkms() {
    CALLS+=("dkms $*")
    case "$1" in
        status) [[ "$INSTALLED" == *"-dkms "* ]] && echo "nvidia/620.73.04, 7.3.5-arch1-1, x86_64: installed"; return 0 ;;
        install)
            local a="$*"; local k="${a##*-k }"
            [[ -d "$K/$k/build" ]] || return 1
            if in_set "$k" "$DKMS_FAIL"; then
                if (( LEAVE_LOG == 1 )); then
                    mkdir -p "$TMP/dkms/620.73.04/build"; echo "make: no rule for $k" > "$TMP/dkms/620.73.04/build/make.log"
                fi
                return 1
            fi
            : > "$K/$k/nvidia.ko" ;;
    esac
}
# Not in a subshell: the stand-ins keep their state in this shell's variables.
run_once() { CASES=$((CASES + 1)); CALLS=(); GPU_FAILURES=(); gpu_nvidia_ensure_modules > "$TMP/out" 2>&1; RC=$?; OUT="$(<"$TMP/out")"; }
calls() { local IFS='|'; printf '%s' "${CALLS[*]:-}"; }
MS=7.3.5-arch1-1-mainstream

# ── the reads ───────────────────────────────────────────────────────────────
reset
kernel $STOCK linux module; kernel $MS linux-mainstream
mkdir -p "$K/7.3.9-headers-only/build"; echo linux > "$K/7.3.9-headers-only/pkgbase"
mkdir -p "$K/7.0.0-no-pkgbase"; : > "$K/7.0.0-no-pkgbase/vmlinuz"
CASES=$((CASES + 2))
chk_str kernels-list "$(gpu_installed_kernels)" "$STOCK linux"$'\n'"$MS linux-mainstream"
chk_str kernels-missing "$(gpu_kernels_missing_nvidia)" "$MS linux-mainstream"

# ── classification names the package that is installed ──────────────────────
reset; NVIDIA_GEN=turing; CASES=$((CASES + 4))
gpu_classify_nvidia_driver
chk_str cls-fresh "${NVIDIA_REPO_PKGS[0]}" nvidia-open
INSTALLED=" nvidia-open nvidia-utils "; gpu_classify_nvidia_driver
chk_str cls-prebuilt "${NVIDIA_REPO_PKGS[0]}" nvidia-open
INSTALLED=" nvidia-open-dkms nvidia-utils dkms "; gpu_classify_nvidia_driver
chk_str cls-dkms-family "$NVIDIA_DRIVER_FAMILY" nvidia-open
chk_str cls-dkms-pkgs "${NVIDIA_REPO_PKGS[*]}" "nvidia-open-dkms nvidia-utils nvidia-settings lib32-nvidia-utils libva-nvidia-driver libva-utils"
NVIDIA_GEN=maxwell; gpu_classify_nvidia_driver
chk_str cls-dkms-not-for-legacy-card "$NVIDIA_DRIVER_FAMILY ${#NVIDIA_REPO_PKGS[@]}" "nvidia-580xx 0"
set -e; NVIDIA_GEN=turing; INSTALLED=" "; gpu_classify_nvidia_driver; set +e
chk_str cls-errexit-safe "${NVIDIA_REPO_PKGS[0]}" nvidia-open

NVIDIA_DRIVER_FAMILY=nvidia-open

# ── every kernel has a module: no package call at all ───────────────────────
reset; INSTALLED=" linux nvidia-open nvidia-utils "
kernel $STOCK linux module
run_once
chk_str stock-ok-rc "$RC" 0; chk_str stock-ok-calls "$(calls)" ""

reset; INSTALLED=" linux linux-mainstream nvidia-open-dkms dkms "
kernel $STOCK linux module headers; kernel $MS linux-mainstream module headers
run_once
chk_str dkms-ok-rc "$RC" 0; chk_str dkms-ok-calls "$(calls)" ""

# ── stock plus a second kernel without a module ─────────────────────────────
reset; INSTALLED=" linux linux-mainstream nvidia-open nvidia-utils "
kernel $STOCK linux module; kernel $MS linux-mainstream
HOOK_SKIPS=" $MS "
run_once
chk_str second-rc "$RC" 0
chk_str second-calls "$(calls)" "pacman -S --needed --noconfirm linux linux-headers linux-mainstream linux-mainstream-headers dkms|pacman -Sw --noconfirm nvidia-open-dkms|pacman -Rdd --noconfirm nvidia-open|pacman -S --noconfirm nvidia-open-dkms|dkms install -m nvidia -v 620.73.04 -k $MS"
chk_str second-swapped "$(in_set nvidia-open-dkms "$INSTALLED" && ! in_set nvidia-open "$INSTALLED" && echo yes)" yes
has second-verified-stock "$OUT" "module present for kernel $STOCK."
has second-verified-ms "$OUT" "module present for kernel $MS."
chk_str second-no-failure "${#GPU_FAILURES[@]}" 0
# A second run finds nothing to do.
run_once
chk_str second-again "$RC|$(calls)" "0|"

# The hook built both: nobody has to ask DKMS.
reset; INSTALLED=" linux linux-mainstream nvidia-open nvidia-utils "
kernel $STOCK linux module; kernel $MS linux-mainstream
run_once
chk_str second-hook-rc "$RC" 0
lacks second-hook-no-ask "$(calls)" "dkms install"

# Transactions and dkms go through GPU_SUDO.
CASES=$((CASES + 1))
chk_str seam-sudo "$(GPU_SUDO=echo; source "$DIR/gpu-driver-install.sh"; _gpu_pacman -Sy; _gpu_dkms status)" "pacman -Sy"$'\n'"dkms status"

# ── the DKMS package is already the driver ──────────────────────────────────
reset; INSTALLED=" linux linux-headers linux-mainstream nvidia-open-dkms dkms nvidia-utils "
kernel $STOCK linux module headers; kernel $MS linux-mainstream
run_once
chk_str dkms-installed-rc "$RC" 0
chk_str dkms-installed-calls "$(calls)" "pacman -S --needed --noconfirm linux linux-headers linux-mainstream linux-mainstream-headers dkms|dkms install -m nvidia -v 620.73.04 -k $MS"

# Never back to the prebuilt driver, even when it is Arch's kernel that lacks
# the module.
reset; INSTALLED=" linux linux-headers nvidia-open-dkms dkms nvidia-utils "
kernel $STOCK linux headers
run_once
chk_str dkms-stock-rc "$RC" 0
lacks dkms-stock-no-refresh "$(calls)" "pacman -Sy"
lacks dkms-stock-no-prebuilt "$(calls)" "nvidia-open"
has dkms-stock-asked "$(calls)" "dkms install -m nvidia -v 620.73.04 -k $STOCK"

# ── the DKMS package cannot be fetched ──────────────────────────────────────
reset; INSTALLED=" linux linux-mainstream nvidia-open nvidia-utils "
kernel $STOCK linux module; kernel $MS linux-mainstream
NO_FETCH=nvidia-open-dkms
run_once
chk_str nofetch-rc "$RC" 1
chk_str nofetch-last-call "${CALLS[-1]}" "pacman -Sw --noconfirm nvidia-open-dkms"
chk_str nofetch-prebuilt-kept "$(in_set nvidia-open "$INSTALLED" && echo yes)" yes
chk_str nofetch-stock-module "$(nvidia_module_present $STOCK && echo yes)" yes
chk_str nofetch-headers-kept "$(in_set linux-mainstream-headers "$INSTALLED" && echo yes)" yes
has nofetch-said "${GPU_FAILURES[*]}" "not obtainable"
has nofetch-names-kernel "${GPU_FAILURES[*]}" "kernel $MS still has no module"
lacks nofetch-not-the-served-kernel "${GPU_FAILURES[*]}" "$STOCK "
has nofetch-what-to-do "${GPU_FAILURES[*]}" "gpu-drivers again"
has nofetch-when "${GPU_FAILURES[*]}" "online"

# The install fails after the removal: the prebuilt driver goes back.
reset; INSTALLED=" linux linux-mainstream nvidia-open nvidia-utils "
kernel $STOCK linux module; kernel $MS linux-mainstream
NO_INSTALL=nvidia-open-dkms
run_once
chk_str noinstall-rc "$RC" 1
chk_str noinstall-prebuilt-back "$(in_set nvidia-open "$INSTALLED" && echo yes)" yes
chk_str noinstall-stock-module "$(nvidia_module_present $STOCK && echo yes)" yes
chk_str noinstall-last-call "${CALLS[-1]}" "pacman -S --noconfirm nvidia-open"

# dkms itself cannot be installed: nothing is removed.
reset; INSTALLED=" linux linux-headers linux-mainstream linux-mainstream-headers nvidia-open nvidia-utils "
kernel $STOCK linux module headers; kernel $MS linux-mainstream headers
REPO="${REPO/ dkms / }"
run_once
chk_str nodkms-rc "$RC" 1
lacks nodkms-no-removal "$(calls)" "-Rdd"
chk_str nodkms-prebuilt-kept "$(in_set nvidia-open "$INSTALLED" && echo yes)" yes

# ── headers neither installed nor obtainable ────────────────────────────────
# linux-custom is a local build in no repository, with no headers anywhere.
reset; INSTALLED=" linux linux-mainstream linux-custom nvidia-open nvidia-utils "
kernel $STOCK linux module; kernel $MS linux-mainstream; kernel 7.3.5-custom linux-custom
run_once
chk_str nohdr-rc "$RC" 1
lacks nohdr-not-in-transaction "$(calls)" "linux-custom"
has nohdr-named "${GPU_FAILURES[*]}" "kernel 7.3.5-custom has no headers"
has nohdr-package "${GPU_FAILURES[*]}" "linux-custom-headers"
# The swap went through, so the DKMS hook builds once the headers are there.
has nohdr-then-automatic "${GPU_FAILURES[*]}" "built by itself"
lacks nohdr-no-rerun "${GPU_FAILURES[*]}" "gpu-drivers again"
chk_str nohdr-others-served "$(nvidia_module_present $STOCK && nvidia_module_present $MS && echo yes)" yes
chk_str nohdr-custom-none "$(nvidia_module_present 7.3.5-custom && echo yes || echo no)" no
lacks nohdr-no-dkms-ask "$(calls)" "-k 7.3.5-custom"
chk_str nohdr-one-report "${#GPU_FAILURES[@]}" 1

# Nothing can be built, so the prebuilt driver stays: with it no hook builds
# anything, and the person is told to come back.
reset; INSTALLED=" linux linux-custom nvidia-open nvidia-utils "
kernel $STOCK linux module; kernel 7.3.5-custom linux-custom
run_once
chk_str nohdr-all-rc "$RC" 1
lacks nohdr-all-no-swap "$(calls)" "-Sw"
has nohdr-all-package "${GPU_FAILURES[*]}" "linux-custom-headers"
has nohdr-all-rerun "${GPU_FAILURES[*]}" "gpu-drivers again"
lacks nohdr-all-not-automatic "${GPU_FAILURES[*]}" "built by itself"
# Already on the DKMS driver: automatic.
reset; INSTALLED=" linux linux-headers linux-custom nvidia-open-dkms dkms nvidia-utils "
kernel $STOCK linux module headers; kernel 7.3.5-custom linux-custom
run_once
chk_str nohdr-dkms-rc "$RC" 1
has nohdr-dkms-automatic "${GPU_FAILURES[*]}" "linux-custom-headers; the module is then built by itself"

# The kernel that has the working prebuilt module cannot get headers: the swap
# would take its module away, so it does not happen.
reset; INSTALLED=" linux linux-mainstream nvidia-open nvidia-utils "
kernel $STOCK linux module; kernel $MS linux-mainstream
REPO="${REPO/ linux-headers / }"
run_once
chk_str stockhdr-rc "$RC" 1
lacks stockhdr-no-fetch "$(calls)" "-Sw"
lacks stockhdr-no-removal "$(calls)" "-Rdd"
chk_str stockhdr-stock-module "$(nvidia_module_present $STOCK && echo yes)" yes
lacks stockhdr-kernel-alone "$(calls)" "noconfirm linux linux-mainstream"

# ── a kernel that is in no repository ───────────────────────────────────────
# Its headers are obtainable: they are taken, the kernel is not.
reset; INSTALLED=" linux linux-local nvidia-open nvidia-utils "
REPO+="linux-local-headers "
kernel $STOCK linux module; kernel 7.3.5-local linux-local
run_once
chk_str norepo-rc "$RC" 0
chk_str norepo-toolchain "${CALLS[0]}" "pacman -S --needed --noconfirm linux linux-headers linux-local-headers dkms"
chk_str norepo-module "$(nvidia_module_present 7.3.5-local && echo yes)" yes
# Its headers are installed already: they are left alone.
reset; INSTALLED=" linux linux-local linux-local-headers nvidia-open nvidia-utils "
REPO+="linux-local-headers "
kernel $STOCK linux module; kernel 7.3.5-local linux-local headers
run_once
chk_str norepo-installed-rc "$RC" 0
chk_str norepo-installed-toolchain "${CALLS[0]}" "pacman -S --needed --noconfirm linux linux-headers dkms"

# One kernel's headers failing does not cost the others theirs.
reset; INSTALLED=" linux linux-mainstream nvidia-open nvidia-utils "
kernel $STOCK linux module; kernel $MS linux-mainstream
FAIL_COMBINED=1
run_once
chk_str split-rc "$RC" 0
chk_str split-calls "${CALLS[1]}|${CALLS[2]}|${CALLS[3]}" "pacman -S --needed --noconfirm linux linux-headers|pacman -S --needed --noconfirm linux-mainstream linux-mainstream-headers|pacman -S --needed --noconfirm dkms"

# ── Arch's kernel alone, stranded by a kernel that moved ────────────────────
reset; INSTALLED=" linux nvidia-open nvidia-utils "
kernel $STOCK linux
run_once
chk_str strand-rc "$RC" 0
chk_str strand-calls "$(calls)" "pacman -S --needed --noconfirm linux nvidia-open"
lacks strand-quiet-about-refresh "$OUT" "Refreshing"
# The installer allows the refresh.
reset; INSTALLED=" linux nvidia-open nvidia-utils "
kernel $STOCK linux
GPU_DB_REFRESH=true
run_once
chk_str strand-refresh-rc "$RC" 0
chk_str strand-refresh-calls "$(calls)" "pacman -Sy|pacman -S --needed --noconfirm linux nvidia-open"
has strand-refresh-said "$OUT" "Refreshing the database"
# Headers that are installed ride with the kernel.
reset; INSTALLED=" linux linux-headers nvidia-open nvidia-utils "
kernel $STOCK linux headers
run_once
chk_str strand-hdr-calls "$(calls)" "pacman -S --needed --noconfirm linux linux-headers nvidia-open"
# No matching prebuilt build is published: DKMS builds it.
reset; INSTALLED=" linux nvidia-open nvidia-utils "
kernel $STOCK linux
PREBUILT_STALE=1
run_once
chk_str strand-stale-rc "$RC" 0
chk_str strand-stale-calls "$(calls)" "pacman -S --needed --noconfirm linux nvidia-open|pacman -S --needed --noconfirm linux linux-headers dkms|pacman -Sw --noconfirm nvidia-open-dkms|pacman -Rdd --noconfirm nvidia-open|pacman -S --noconfirm nvidia-open-dkms"
chk_str strand-stale-module "$(nvidia_module_present $STOCK && echo yes)" yes
# A second kernel is the only one missing: no refresh, the prebuilt build cannot help it.
reset; INSTALLED=" linux linux-mainstream nvidia-open nvidia-utils "
kernel $STOCK linux module; kernel $MS linux-mainstream
run_once
lacks second-no-refresh "$(calls)" "pacman -Sy"

# ── a swap that would leave a kernel worse off is undone ────────────────────
# DKMS cannot build for Arch's kernel, which had the prebuilt module.
reset; INSTALLED=" linux linux-mainstream nvidia-open nvidia-utils "
kernel $STOCK linux module; kernel $MS linux-mainstream
DKMS_FAIL=" $STOCK "
run_once
chk_str rollback-rc "$RC" 1
chk_str rollback-calls "$(calls)" "pacman -S --needed --noconfirm linux linux-headers linux-mainstream linux-mainstream-headers dkms|pacman -Sw --noconfirm nvidia-open-dkms|pacman -Rdd --noconfirm nvidia-open|pacman -S --noconfirm nvidia-open-dkms|dkms install -m nvidia -v 620.73.04 -k $STOCK|pacman -Rdd --noconfirm nvidia-open-dkms|pacman -S --noconfirm nvidia-open"
chk_str rollback-packages "$(in_set nvidia-open "$INSTALLED" && ! in_set nvidia-open-dkms "$INSTALLED" && echo yes)" yes
chk_str rollback-stock-module "$(nvidia_module_present $STOCK && echo yes)" yes
chk_str rollback-ms-none "$(nvidia_module_present $MS && echo yes || echo no)" no
has rollback-said "${GPU_FAILURES[*]}" "the DKMS build failed for kernel $STOCK, so the prebuilt driver was put back. Kernel $MS still has no module."
chk_str rollback-one-report "${#GPU_FAILURES[@]}" 1
# DKMS left no log this time: nothing is named, and the rollback still ran.
lacks rollback-no-log-named "${GPU_FAILURES[*]}" "log"

# The failed build's log is kept before the package that owns it goes.
reset; INSTALLED=" linux linux-mainstream nvidia-open nvidia-utils "
kernel $STOCK linux module; kernel $MS linux-mainstream
DKMS_FAIL=" $STOCK "; LEAVE_LOG=1
run_once
chk_str keptlog-rc "$RC" 1
chk_str keptlog-rolled-back "$(in_set nvidia-open "$INSTALLED" && nvidia_module_present $STOCK && echo yes)" yes
chk_str keptlog-content "$(cat "$GPU_LOG_DIR/nvidia-dkms-$STOCK.log" 2>/dev/null)" "make: no rule for $STOCK"
chk_str keptlog-original-gone "$([[ -e "$TMP/dkms/620.73.04/build/make.log" ]] && echo there || echo gone)" gone
has keptlog-named "${GPU_FAILURES[*]}" "$GPU_LOG_DIR/nvidia-dkms-$STOCK.log"
# A second failure replaces the kept copy.
echo stale > "$GPU_LOG_DIR/nvidia-dkms-$STOCK.log"
DKMS_FAIL=" $STOCK "; LEAVE_LOG=1
run_once
chk_str keptlog-overwritten "$(cat "$GPU_LOG_DIR/nvidia-dkms-$STOCK.log" 2>/dev/null)" "make: no rule for $STOCK"

# The prebuilt driver cannot be put back either: said with the command to run.
reset; INSTALLED=" linux linux-mainstream nvidia-open nvidia-utils "
kernel $STOCK linux module; kernel $MS linux-mainstream
DKMS_FAIL=" $STOCK "; NO_INSTALL=nvidia-open
run_once
chk_str rollback-fail-rc "$RC" 1
has rollback-fail-said "${GPU_FAILURES[*]}" "could not be put back, so kernel $STOCK has no driver. Run: sudo pacman"

# A kernel that never had a module failing is no reason to undo a swap that
# gave another kernel one.
reset; INSTALLED=" linux linux-mainstream linux-mainstream-performance nvidia-open nvidia-utils "
REPO+="linux-mainstream-performance linux-mainstream-performance-headers "
PERF=7.3.5-1-mainstream-performance
kernel $STOCK linux module; kernel $MS linux-mainstream; kernel $PERF linux-mainstream-performance
DKMS_FAIL=" $PERF "
run_once
chk_str gained-rc "$RC" 1
lacks gained-no-rollback "$(calls)" "-Rdd --noconfirm nvidia-open-dkms"
chk_str gained-on-dkms "$(in_set nvidia-open-dkms "$INSTALLED" && echo yes)" yes
chk_str gained-modules "$(nvidia_module_present $STOCK && nvidia_module_present $MS && echo yes)" yes
has gained-named "${GPU_FAILURES[*]}" "no loadable module for kernel $PERF (linux-mainstream-performance)"

# A machine that was already on the DKMS driver is never moved back, whatever fails.
reset; INSTALLED=" linux linux-headers linux-mainstream linux-mainstream-headers nvidia-open-dkms dkms nvidia-utils "
kernel $STOCK linux headers; kernel $MS linux-mainstream module headers
DKMS_FAIL=" $STOCK "
run_once
chk_str ondkms-rc "$RC" 1
lacks ondkms-no-removal "$(calls)" "-Rdd"
lacks ondkms-no-prebuilt "$(calls)" "noconfirm nvidia-open"
chk_str ondkms-kept "$(in_set nvidia-open-dkms "$INSTALLED" && nvidia_module_present $MS && echo yes)" yes

# ── a frozen legacy branch with two kernels ─────────────────────────────────
reset; NVIDIA_DRIVER_FAMILY=nvidia-580xx
REPO+="nvidia-580xx-dkms "; INSTALLED=" linux linux-mainstream "
kernel $STOCK linux; kernel $MS linux-mainstream
CASES=$((CASES + 1))
gpu_nvidia_kernel_toolchain >/dev/null 2>&1
chk_str legacy-toolchain "$(calls)" "pacman -S --needed --noconfirm linux linux-headers linux-mainstream linux-mainstream-headers dkms"
# Before the branch is installed there is nothing to build.
run_once
chk_str legacy-absent "$RC|$(calls)" "0|"
HOOK_SKIPS=" $STOCK $MS "
_gpu_pacman -S --needed --noconfirm nvidia-580xx-dkms
run_once
chk_str legacy-rc "$RC" 0
chk_str legacy-calls "$(calls)" "pacman -S --needed --noconfirm linux linux-headers linux-mainstream linux-mainstream-headers dkms|dkms install -m nvidia -v 620.73.04 -k $STOCK|dkms install -m nvidia -v 620.73.04 -k $MS"
chk_str legacy-modules "$(nvidia_module_present $STOCK && nvidia_module_present $MS && echo yes)" yes
lacks legacy-no-open "$(calls)" "nvidia-open"

# A DKMS build that fails is said by kernel name.
reset; NVIDIA_DRIVER_FAMILY=nvidia-open
INSTALLED=" linux linux-headers linux-mainstream linux-mainstream-headers nvidia-open-dkms dkms "
kernel $STOCK linux module headers; kernel $MS linux-mainstream headers
_gpu_dkms() { CALLS+=("dkms $*"); [[ "$1" == status ]] && echo "nvidia/620.73.04: added"; [[ "$1" != install ]]; }
run_once
chk_str buildfail-rc "$RC" 1
has buildfail-named "${GPU_FAILURES[*]}" "no loadable module for kernel $MS (linux-mainstream)"

# A frozen branch is a DKMS driver too: headers arriving build the module.
reset; NVIDIA_DRIVER_FAMILY=nvidia-470xx
INSTALLED=" linux linux-headers linux-custom nvidia-470xx-dkms dkms "
kernel $STOCK linux module headers; kernel 7.3.5-custom linux-custom
run_once
chk_str legacy-nohdr-rc "$RC" 1
has legacy-nohdr-automatic "${GPU_FAILURES[*]}" "linux-custom-headers; the module is then built by itself"

# ── the breadcrumb of a complete repair run ─────────────────────────────────
reset; CASES=$((CASES + 2)); CRUMB="$TMP/state/gpu-install-failed.log"
mkdir -p "$TMP/state"; echo "  - a line from an older run" > "$CRUMB"
GPU_FAILURES=("nvidia: this run's trouble")
gpu_driver_run_report "$CRUMB"
has crumb-written "$(cat "$CRUMB" 2>/dev/null)" "this run's trouble"
lacks crumb-old-gone "$(cat "$CRUMB" 2>/dev/null)" "older run"
# A run with nothing to report leaves no breadcrumb behind.
GPU_FAILURES=()
gpu_driver_run_report "$CRUMB"
chk_str crumb-cleared "$([[ -e "$CRUMB" ]] && echo there || echo gone)" gone
gpu_driver_run_report "$CRUMB"
chk_str crumb-absent-ok "$?" 0

# Nouveau and unknown families are not this file's business.
reset; NVIDIA_DRIVER_FAMILY=nouveau; kernel $STOCK linux
run_once
chk_str nouveau-untouched "$RC|$(calls)" "0|"

# The file is safe to call from a script running under set -e.
reset; NVIDIA_DRIVER_FAMILY=nvidia-open; INSTALLED=" linux linux-mainstream nvidia-open nvidia-utils "
kernel $STOCK linux module; kernel $MS linux-mainstream
CASES=$((CASES + 1))
chk_str errexit "$(set -euo pipefail; gpu_nvidia_ensure_modules >/dev/null 2>&1; echo done)" done

CASES=$((CASES + 1))
chk_str nothing-escaped "$(cat "$TMP/escaped" 2>/dev/null)" ""

if [[ $FAILS -eq 0 ]]; then echo "gpu-driver-install: all $CASES cases PASS"; exit 0
else echo "gpu-driver-install: $FAILS assertion(s) FAILED across $CASES cases"; exit 1; fi
