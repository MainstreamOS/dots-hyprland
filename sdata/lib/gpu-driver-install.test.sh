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
        -Sw)
            for p in "$@"; do
                [[ "$p" == -* ]] && continue
                in_set "$p" "$REPO" && [[ "$p" != "$NO_FETCH" ]] || return 1
            done ;;
        -Rdd)
            for p in "$@"; do [[ "$p" == -* ]] || in_set "$p" "$INSTALLED" || return 1; done
            for p in "$@"; do
                [[ "$p" == -* ]] && continue
                INSTALLED="${INSTALLED/ $p / }"
                # The prebuilt driver owns one kernel's module, the DKMS one all it built.
                case "$p" in
                    nvidia-open) for t in $(tree_of linux); do unlink "${K:?}/${t:?}/nvidia.ko" 2>/dev/null; done ;;
                    nvidia-*-dkms)
                        for t in "${K:?}"/*/nvidia.ko; do [[ -e "$t" ]] && unlink "$t"; done
                        unlink "$TMP/dkms/620.73.04/build/make.log" 2>/dev/null ;;
                esac
            done
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
            # A frozen branch conflicts with the mainline driver and with the other branches.
            for p in "${pkgs[@]}"; do
                [[ "$p" =~ ^(lib32-)?nvidia-([0-9]{3}xx)- ]] || continue
                for t in $INSTALLED; do
                    case "$t" in
                        nvidia-open|nvidia-open-dkms|nvidia-utils|lib32-nvidia-utils) return 1 ;;
                        *nvidia-[0-9][0-9][0-9]xx-*) [[ "$t" == *"-${BASH_REMATCH[2]}-"* ]] || return 1 ;;
                    esac
                done
            done
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
ORIG_DKMS="$(declare -f _gpu_dkms)"
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

# ── whether a kernel can be started without losing the driver ───────────────
reset; CASES=$((CASES + 6))
kernel $STOCK linux module; kernel $MS linux-mainstream
chk_str ready-other-has-one "$(gpu_kernel_nvidia_ready linux-mainstream && echo yes || echo no)" no
chk_str ready-stock "$(gpu_kernel_nvidia_ready linux && echo yes || echo no)" yes
chk_str ready-not-installed "$(gpu_kernel_nvidia_ready linux-mainstream-performance && echo yes || echo no)" no
: > "$K/$MS/nvidia.ko"
chk_str ready-both "$(gpu_kernel_nvidia_ready linux-mainstream && echo yes || echo no)" yes
reset; kernel $STOCK linux; kernel $MS linux-mainstream
chk_str ready-none-has-one "$(gpu_kernel_nvidia_ready linux-mainstream && echo yes || echo no)" yes
reset; kernel $STOCK linux; kernel $MS linux-mainstream module
chk_str ready-only-new-has-one "$(gpu_kernel_nvidia_ready linux-mainstream && echo yes || echo no)" yes

# ── a kernel just added beside Arch's ───────────────────────────────────────
added_once() { CASES=$((CASES + 1)); CALLS=(); GPU_FAILURES=(); gpu_nvidia_modules_for_added_kernel linux-mainstream > "$TMP/out" 2>&1; RC=$?; OUT="$(<"$TMP/out")"; }
NVIDIA_DRIVER_FAMILY=nvidia-open
# Two kernels, both get a module: the second through the DKMS swap.
reset; INSTALLED=" linux linux-mainstream linux-mainstream-headers nvidia-open nvidia-utils "
kernel $STOCK linux module; kernel $MS linux-mainstream headers
added_once
chk_str added-ok-rc "$RC" 0
chk_str added-ok-both "$(gpu_kernels_missing_nvidia)" ""
chk_str added-ok-swapped "$(in_set nvidia-open-dkms "$INSTALLED" && echo yes)" yes
chk_str added-ok-no-notes "${#GPU_FAILURES[@]}" 0
# Offline: the DKMS driver cannot be fetched, so the new kernel has none while
# Arch's keeps its prebuilt one. The caller removes the kernel; no notes.
reset; INSTALLED=" linux linux-mainstream linux-mainstream-headers nvidia-open nvidia-utils "
kernel $STOCK linux module; kernel $MS linux-mainstream headers
NO_FETCH=nvidia-open-dkms
added_once
chk_str added-offline-rc "$RC" 1
chk_str added-offline-notes-dropped "${#GPU_FAILURES[@]}" 0
chk_str added-offline-stock-kept "$(in_set nvidia-open "$INSTALLED" && [[ -e "$K/$STOCK/nvidia.ko" ]] && echo yes)" yes
# The build fails for the new kernel: the prebuilt driver comes back for Arch's.
reset; INSTALLED=" linux linux-mainstream linux-mainstream-headers nvidia-open nvidia-utils "
kernel $STOCK linux module; kernel $MS linux-mainstream headers
DKMS_FAIL=" $MS "
added_once
chk_str added-buildfail-rc "$RC" 1
chk_str added-buildfail-notes-dropped "${#GPU_FAILURES[@]}" 0
chk_str added-buildfail-stock-kept "$([[ -e "$K/$STOCK/nvidia.ko" ]] && echo yes)" yes
# The ladder's notes still reach note_failure when the kernel stays: here no
# kernel ends up with a module, so starting the new one loses nothing.
reset; INSTALLED=" linux linux-mainstream linux-mainstream-headers nvidia-open nvidia-utils "
kernel $STOCK linux; kernel $MS linux-mainstream headers
PREBUILT_STALE=1; NO_FETCH=nvidia-open-dkms
added_once
chk_str added-none-rc "$RC" 0
has added-none-noted "${GPU_FAILURES[*]:-}" "nvidia-open-dkms is not obtainable"
chk_str added-note-failure-restored "$(declare -f note_failure | head -1)" "note_failure () "
NVIDIA_DRIVER_FAMILY=nvidia-open

# ── a frozen branch from the package repositories ───────────────────────────
# The image's state: the open DKMS driver and its userspace, built for the
# image's kernel, which is all an older card finds on a fresh install.
SET580="nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils nvidia-580xx-settings libxnvctrl-580xx"
GPU_NVIDIA_PENDING="$TMP/state/nvidia-driver-pending"; mkdir -p "$TMP/state"
GPU_NVIDIA_OFFERED="$TMP/state/nvidia-580xx-offered"
# The stand-in a case above replaced with one whose builds always fail.
eval "$ORIG_DKMS"
legacy_reset() {  # legacy_reset <generation> [offered|missing|<package left out>]
    local p
    reset
    REPO+="egl-wayland xf86-video-nouveau mesa "
    if [[ "${2:-offered}" != missing ]]; then
        for p in $SET580; do [[ "$p" == "${2:-}" ]] || REPO+="$p "; done
    fi
    INSTALLED=" linux-mainstream linux-mainstream-headers dkms nvidia-open-dkms nvidia-utils "
    kernel $MS linux-mainstream module headers
    NVIDIA_GEN="$1"; gpu_classify_nvidia_driver
    unlink "${GPU_NVIDIA_PENDING:?}" 2>/dev/null
    unlink "${GPU_NVIDIA_OFFERED:?}" 2>/dev/null
    return 0
}
legacy_once() { CASES=$((CASES + 1)); CALLS=(); GPU_FAILURES=(); gpu_nvidia_install_legacy > "$TMP/out" 2>&1; RC=$?; OUT="$(<"$TMP/out")"; }
setup_once() { CASES=$((CASES + 1)); CALLS=(); GPU_FAILURES=(); gpu_nvidia_setup_legacy > "$TMP/out" 2>&1; RC=$?; OUT="$(<"$TMP/out")"; }
all_in() { local p; for p in $1; do in_set "$p" "$INSTALLED" || return 1; done; }
none_in() { local p; for p in $1; do in_set "$p" "$INSTALLED" && return 1; done; return 0; }
pending() { [[ -e "$GPU_NVIDIA_PENDING" ]] && echo there || echo none; }
PERF=7.3.5-1-mainstream-performance
add_perf() {  # a second kernel beside the image's
    REPO+="linux-mainstream-performance linux-mainstream-performance-headers "
    INSTALLED+="linux-mainstream-performance "; kernel $PERF linux-mainstream-performance
}

# The set comes in place of the image's driver and builds for its kernel.
legacy_reset maxwell
legacy_once
chk_str repo-580xx-rc "$RC" 0
chk_str repo-580xx-calls "$(calls)" "pacman -Sw --noconfirm $SET580|pacman -Rdd --noconfirm nvidia-open-dkms nvidia-utils|pacman -S --needed --noconfirm linux-mainstream linux-mainstream-headers dkms|pacman -S --needed --noconfirm $SET580 egl-wayland"
chk_str repo-580xx-installed "$(all_in "$SET580" && echo yes)" yes
chk_str repo-580xx-mainline-gone "$(none_in "nvidia-open-dkms nvidia-utils" && echo yes)" yes
chk_str repo-580xx-module "$(nvidia_module_present $MS && echo yes)" yes
chk_str repo-580xx-family "$NVIDIA_DRIVER_FAMILY" nvidia-580xx
chk_str repo-580xx-no-failure "${#GPU_FAILURES[@]}" 0
# Kepler and Fermi stay on nouveau: no branch to install, nothing touched.
for _g in kepler fermi; do
    legacy_reset "$_g"
    legacy_once
    chk_str "repo-$_g-nouveau" "$NVIDIA_DRIVER_FAMILY $RC $(calls)" "nouveau 2 "
    chk_str "repo-$_g-image-kept" "$(all_in "nvidia-open-dkms nvidia-utils" && echo yes)" yes
done
# The settings app is not offered: the driver comes without it.
legacy_reset maxwell nvidia-580xx-settings
legacy_once
chk_str optional-missing-rc "$RC" 0
chk_str optional-missing-calls "${CALLS[0]}" "pacman -Sw --noconfirm nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils libxnvctrl-580xx"
chk_str optional-missing-installed "$(all_in "nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils" && none_in nvidia-580xx-settings && echo yes)" yes
# The 32-bit driver is required: without it nothing is changed.
legacy_reset maxwell lib32-nvidia-580xx-utils
legacy_once
chk_str required-missing-rc "$RC|$(calls)" "2|"
chk_str required-missing-image-kept "$(all_in "nvidia-open-dkms nvidia-utils" && echo yes)" yes

# Every installed kernel gets the module; one the hook missed is asked for by name.
legacy_reset maxwell; add_perf
HOOK_SKIPS=" $PERF "
legacy_once
chk_str repo-two-kernels-rc "$RC" 0
has repo-two-kernels-asked "$(calls)" "dkms install -m nvidia -v 620.73.04 -k $PERF"
chk_str repo-two-kernels-modules "$(nvidia_module_present $MS && nvidia_module_present $PERF && echo yes)" yes

# Offline: the repositories do not offer it. Nothing changes.
legacy_reset maxwell missing
legacy_once
chk_str offline-rc "$RC" 2
chk_str offline-no-calls "$(calls)" ""
chk_str offline-image-kept "$(all_in "nvidia-open-dkms nvidia-utils" && echo yes)" yes
# Offered, but the download fails: the driver it would replace stays.
legacy_reset maxwell; NO_FETCH=nvidia-580xx-utils
legacy_once
chk_str nodownload-rc "$RC" 2
chk_str nodownload-calls "$(calls)" "pacman -Sw --noconfirm $SET580"
chk_str nodownload-image-kept "$(all_in "nvidia-open-dkms nvidia-utils" && echo yes)" yes

# The module builds for no kernel: every NVIDIA driver comes off and the card
# is left to nouveau, which nothing blacklists any more.
legacy_reset maxwell; DKMS_FAIL=" $MS "
legacy_once
chk_str dkmsfail-rc "$RC" 1
chk_str dkmsfail-nothing-left "$(none_in "$SET580 nvidia-open-dkms nvidia-utils" && echo yes)" yes
chk_str dkmsfail-last-call "${CALLS[-1]}" "pacman -Rdd --noconfirm $SET580"
chk_str dkmsfail-family "$NVIDIA_DRIVER_FAMILY ${#NVIDIA_LOCAL_PKGS[@]}" "nouveau 0"
has dkmsfail-said "${GPU_FAILURES[*]}" "nvidia-580xx did not build for any installed kernel, so it was removed and the card uses nouveau"
# Then nothing is left for the module steps to do.
CALLS=(); gpu_nvidia_ensure_modules >/dev/null 2>&1; CASES=$((CASES + 1))
chk_str dkmsfail-ladder-quiet "$?|$(calls)" "0|"

# One kernel of two fails: the branch stays for the other, and the failure is named.
legacy_reset maxwell; add_perf
DKMS_FAIL=" $PERF "
legacy_once
chk_str onefail-rc "$RC" 0
chk_str onefail-kept "$(all_in "$SET580" && echo yes)" yes
has onefail-named "${GPU_FAILURES[*]}" "no loadable module for kernel $PERF"

# The install itself fails after the image's driver came off: nouveau.
legacy_reset maxwell; NO_INSTALL=nvidia-580xx-settings
legacy_once
chk_str noinstall-legacy-rc "$RC" 1
chk_str noinstall-legacy-nothing-left "$(none_in "$SET580 nvidia-open-dkms nvidia-utils" && echo yes)" yes
has noinstall-legacy-said "${GPU_FAILURES[*]}" "nvidia-580xx could not be installed, so the card uses nouveau"

# The legacy edition: the branch is already the driver and stays in place.
legacy_reset maxwell
INSTALLED=" linux-mainstream linux-mainstream-headers dkms $SET580 "
gpu_classify_nvidia_driver
legacy_once
chk_str edition-rc "$RC" 0
lacks edition-no-removal "$(calls)" "-Rdd"
chk_str edition-kept "$(all_in "$SET580" && echo yes)" yes

# ── the whole setup on a running system (./setup, gpu-drivers) ──────────────
# Offline with nothing installed: nouveau now, and a note for the system update.
legacy_reset maxwell missing
setup_once
chk_str setup-offline-rc "$RC" 1
chk_str setup-offline-pending "$(cat "$GPU_NVIDIA_PENDING" 2>/dev/null)" nvidia-580xx
has setup-offline-nouveau "$(calls)" "pacman -S --needed --noconfirm xf86-video-nouveau mesa"
has setup-offline-said "${GPU_FAILURES[*]}" "installs with the next system update once the computer is online"
# Offline with the branch installed: it is kept and its modules seen to.
legacy_reset maxwell missing
INSTALLED=" linux-mainstream linux-mainstream-headers dkms $SET580 "
gpu_classify_nvidia_driver
setup_once
chk_str setup-keep-rc "$RC" 0
has setup-keep-said "$OUT" "keeping the installed nvidia-580xx"
chk_str setup-keep-no-pending "$(pending)" none
lacks setup-keep-no-nouveau "$(calls)" "xf86-video-nouveau"
# Online: installed, and an older note cleared.
legacy_reset maxwell; echo nvidia-580xx > "$GPU_NVIDIA_PENDING"
setup_once
chk_str setup-online-rc "$RC" 0
chk_str setup-online-pending-cleared "$(pending)" none
# A build that fails leaves nouveau.
legacy_reset maxwell; echo nvidia-580xx > "$GPU_NVIDIA_PENDING"; DKMS_FAIL=" $MS "
setup_once
chk_str setup-dkmsfail-rc "$RC" 1
has setup-dkmsfail-nouveau "$(calls)" "xf86-video-nouveau mesa"

# ── the system update installs a branch an offline install left behind ──────
# updatems-system's step, lifted out and run against this fake system. The step
# sources the libraries itself, so stand-ins sourced after them stay in charge.
UPD="$TMP/repo"; mkdir -p "$UPD/sdata/lib"
NV_970="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GM204 [GeForce GTX 970] [10de:13c2] (rev a1)"
FIX_LSPCI="$NV_970"
_gpu_lspci_nn() { printf '%s\n' "$FIX_LSPCI"; }
_gpu_lspci() { printf '%s\n' "$FIX_LSPCI"; }
_gpu_sys_vendor() { :; }
flush_failures() { FLUSHED+=("${GPU_FAILURES[@]}"); }
gpu_apply_nvidia_autoconfig() { APPLIED+=(autoconfig); }
declare -f _gpu_pacman _gpu_dkms _gpu_module_dirs _gpu_modinfo _gpu_module_file _gpu_kernel_headers_present \
    _gpu_dkms_make_log _gpu_lspci_nn _gpu_lspci _gpu_sys_vendor flush_failures \
    gpu_apply_nvidia_autoconfig > "$TMP/fakes.sh"
printf 'source %q\nsource %q\n' "$DIR/gpu-config.sh" "$TMP/fakes.sh" > "$UPD/sdata/lib/gpu-config.sh"
printf 'source %q\nsource %q\n' "$DIR/gpu-driver-install.sh" "$TMP/fakes.sh" > "$UPD/sdata/lib/gpu-driver-install.sh"
# The Kernel page's helper: Limine's recorded entry, its pick of another kernel,
# and the change, written to a file since the step runs it in a subshell.
cat > "$TMP/kernels-helper" <<'HELPER'
read_last_entry() { ENTRY="/Mainstream OS/$FAKE_NEXT"; [[ -n "$FAKE_NEXT" ]]; }
entry_is_installed_kernel() { :; }
fallback_kernel() {
    local rel base
    while read -r rel base; do
        [[ "$base" != "$1" ]] && nvidia_module_present "$rel" && { printf '%s' "$base"; return 0; }
    done < <(gpu_installed_kernels)
    return 1
}
cmd_next() { echo "next $1" >> "$HELPER_LOG"; [[ -z "$FAKE_NEXT_FAILS" ]]; }
HELPER
export HELPER_LOG="$TMP/helper.log"
UPDATE_STEP="$(awk '/^GPU_INSTALL_LIB_SRC=/,/^# ── Wi-Fi country/' "$DIR/../update/updatems-system" | sed '$d')"
ME="$(id -un)"; MY_HOME="$(getent passwd "$ME" | cut -d: -f6)"
update_once() {
    CASES=$((CASES + 1)); CALLS=(); APPLIED=(); FLUSHED=(); SAID=(); PACMAN_NEEDED=(); RUNUSER=()
    : > "$HELPER_LOG"
    unset _NVIDIA_REBUILD_PENDING
    REPO_DIR="$UPD"; GPU_LIB_SRC="$UPD/sdata/lib/gpu-config.sh"; UMS_PERSON="$ME"; RC=0
    MAINSTREAM_KERNELS_HELPER="$TMP/kernels-helper"
    _src_ok() { [[ -f "$1" ]]; }
    t() { printf '%s' "$1"; }
    tf() { local fmt="$1"; shift; printf -- "$fmt" "$@"; }
    say() { SAID+=("say $*"); }; ok() { SAID+=("ok $*"); }; warn() { SAID+=("warn $*"); }
    _pacman_needed() { PACMAN_NEEDED+=("$*"); }
    runuser() { RUNUSER+=("$*"); }
    eval "$UPDATE_STEP" > "$TMP/out" 2>&1
    URC="$RC"; OUT="$(<"$TMP/out")"
}
said() { local IFS='|'; printf '%s' "${SAID[*]:-}"; }
helper() { tr '\n' '|' < "$HELPER_LOG"; }
FAKE_NEXT=linux-mainstream; FAKE_NEXT_FAILS=""
# No note: an older card that is on nouveau for another reason is left there.
legacy_reset maxwell
update_once
chk_str update-no-note "$(calls)|$(said)" "|"
# Still offline: the note stays and the next update tries again.
legacy_reset maxwell missing; echo nvidia-580xx > "$GPU_NVIDIA_PENDING"
update_once
chk_str update-offline-pending "$(cat "$GPU_NVIDIA_PENDING" 2>/dev/null)" nvidia-580xx
chk_str update-offline-image-kept "$(all_in "nvidia-open-dkms nvidia-utils" && echo yes)" yes
has update-offline-said "$(said)" "could not be downloaded yet; the next update tries again"
chk_str update-offline-rc "$URC" 0
# Online, on the nouveau an offline install left, every kernel gets the module:
# installed, configured, the person's own files written as them, the note gone
# and the boot images due a rebuild. The boot menu is left alone.
legacy_reset maxwell; echo nvidia-580xx > "$GPU_NVIDIA_PENDING"; add_perf
INSTALLED="${INSTALLED/ nvidia-open-dkms nvidia-utils / }"; unlink "${K:?}/${MS:?}/nvidia.ko"
update_once
chk_str update-online-installed "$(all_in "$SET580" && nvidia_module_present $MS && nvidia_module_present $PERF && echo yes)" yes
chk_str update-online-configured "${APPLIED[*]:-}" "autoconfig"
has update-online-as-person "${RUNUSER[*]:-}" "-u $ME -- bash -c"
has update-online-person-home "${RUNUSER[*]:-}" "$UPD/sdata/lib/gpu-config.sh $MY_HOME"
chk_str update-online-vaapi "${PACMAN_NEEDED[*]:-}" "libva-nvidia-driver libva-utils"
chk_str update-online-pending-gone "$(pending)" none
chk_str update-online-rebuild "${_NVIDIA_REBUILD_PENDING:-unset}" 1
chk_str update-online-menu-untouched "$(helper)" ""
has update-online-said "$(said)" "takes over from nouveau at the next restart"
chk_str update-online-rc "$URC" 0
# The kernel the computer starts gets no module while another does: the boot
# menu starts that one from now on.
legacy_reset maxwell; echo nvidia-580xx > "$GPU_NVIDIA_PENDING"; add_perf
DKMS_FAIL=" $PERF "; FAKE_NEXT=linux-mainstream-performance
update_once
chk_str update-start-lacks-next "$(helper)" "next linux-mainstream|"
has update-start-lacks-said "$(said)" "linux-mainstream-performance has no NVIDIA driver, so the computer starts linux-mainstream from now on"
chk_str update-start-lacks-installed "$(all_in "$SET580" && echo yes)|$(pending)|${_NVIDIA_REBUILD_PENDING:-unset}" "yes|none|1"
chk_str update-start-lacks-rc "$URC" 0
# The same, and the boot menu cannot be changed: said, and the update reports it.
legacy_reset maxwell; echo nvidia-580xx > "$GPU_NVIDIA_PENDING"; add_perf
DKMS_FAIL=" $PERF "; FAKE_NEXT=linux-mainstream-performance; FAKE_NEXT_FAILS=1
update_once
has update-start-stuck-said "$(said)" "choose another one in the boot menu"
chk_str update-start-stuck-rc "$URC" 1
FAKE_NEXT_FAILS=""
# The kernel it starts has the module, another does not: nothing to change.
legacy_reset maxwell; echo nvidia-580xx > "$GPU_NVIDIA_PENDING"; add_perf
DKMS_FAIL=" $PERF "; FAKE_NEXT=linux-mainstream
update_once
chk_str update-start-has-it "$(helper)|$URC" "|0"
# No kernel gets the module: nouveau again, the note kept for a later try, and no
# boot image rebuilt with NVIDIA's blacklist of nouveau.
legacy_reset maxwell; echo nvidia-580xx > "$GPU_NVIDIA_PENDING"; DKMS_FAIL=" $MS "
update_once
chk_str update-dkmsfail-nothing-left "$(none_in "$SET580 nvidia-open-dkms nvidia-utils" && echo yes)" yes
chk_str update-dkmsfail-pending-kept "$(pending)" there
chk_str update-dkmsfail-no-rebuild "${_NVIDIA_REBUILD_PENDING:-unset}" unset
chk_str update-dkmsfail-rc "$URC" 1
chk_str update-dkmsfail-no-config "${APPLIED[*]:-none} ${RUNUSER[*]:-none}" "none none"
has update-dkmsfail-flushed "${FLUSHED[*]:-}" "did not build for any installed kernel"
has update-dkmsfail-said "$(said)" "until the next update tries again"
# The branch got installed some other way since: only the note goes.
legacy_reset maxwell; echo nvidia-580xx > "$GPU_NVIDIA_PENDING"
INSTALLED=" linux-mainstream linux-mainstream-headers dkms $SET580 "
update_once
chk_str update-already-calls "$(calls)" ""
chk_str update-already-pending-gone "$(pending)" none
# A Kepler card's note, from before Kepler stayed on nouveau: it goes, nothing installed.
legacy_reset kepler; echo nvidia-470xx > "$GPU_NVIDIA_PENDING"
FIX_LSPCI="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GK208B [GeForce GT 710] [10de:128b] (rev a1)"
update_once
chk_str update-kepler "$(calls)|$(pending)" "|none"

# ── systems set up before the repository carried the branch ─────────────────
# The standard image left a GTX 900 to Titan V card on nouveau with no note. The
# update writes the note once and the same steps install the driver.
nouveau_install() {
    INSTALLED=" linux-mainstream linux-mainstream-headers dkms mesa "
    unlink "${K:?}/${MS:?}/nvidia.ko" 2>/dev/null
    return 0
}
offered() { [[ -e "$GPU_NVIDIA_OFFERED" ]] && echo there || echo none; }
NV_1060="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP106 [GeForce GTX 1060 6GB] [10de:1c03] (rev a1)"
FAKE_NEXT=linux-mainstream
legacy_reset maxwell; nouveau_install; FIX_LSPCI="$NV_1060"
update_once
chk_str adopt-pascal "$(all_in "$SET580" && nvidia_module_present $MS && echo yes)|$(pending)|$(offered)|${_NVIDIA_REBUILD_PENDING:-unset}" "yes|none|there|1"
has adopt-pascal-said "$(said)" "takes over from nouveau at the next restart"
update_once
chk_str adopt-pascal-once "$(calls)" ""
# A hybrid laptop's GTX 1050 gets it as at install; its session stays on the Intel GPU.
legacy_reset maxwell; nouveau_install
FIX_LSPCI="00:02.0 VGA compatible controller [0300]: Intel Corporation HD Graphics 630 [8086:591b] (rev 04)
01:00.0 3D controller [0302]: NVIDIA Corporation GP107M [GeForce GTX 1050 Mobile] [10de:1c8d] (rev a1)"
update_once
chk_str adopt-hybrid "$(all_in "$SET580" && echo yes)|$(pending)" "yes|none"
# It builds for no kernel: nouveau again, and from here the note decides, as for
# an offline install: the next update tries again.
legacy_reset maxwell; nouveau_install; FIX_LSPCI="$NV_1060"; DKMS_FAIL=" $MS "
update_once
chk_str adopt-buildfail "$(none_in "$SET580" && echo yes)|$(pending)|$(offered)|${_NVIDIA_REBUILD_PENDING:-unset}|$URC" "yes|there|there|unset|1"
DKMS_FAIL=" "
update_once
chk_str adopt-buildfail-retry "$(all_in "$SET580" && echo yes)|$(pending)" "yes|none"
# Tried once already: nothing more without a note.
legacy_reset maxwell; nouveau_install; FIX_LSPCI="$NV_1060"; : > "$GPU_NVIDIA_OFFERED"
update_once
chk_str adopt-once-only "$(calls)|$(pending)" "|none"
# Not for these, and nothing is noted, so a repository that offers the set later still counts.
not_due() {  # not_due <name> <lspci>; the fake system is set up beforehand
    FIX_LSPCI="$2"
    update_once
    chk_str "adopt-not-$1" "$(calls)|$(pending)|$(offered)" "|none|none"
}
legacy_reset maxwell; nouveau_install
not_due kepler "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GK208B [GeForce GT 710] [10de:128b] (rev a1)"
not_due fermi "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GF110 [GeForce GTX 580] [10de:1080] (rev a1)"
not_due turing "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU104 [GeForce RTX 2080] [10de:1e87] (rev a1)"
not_due amd "03:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 22 [Radeon RX 6700 XT] [1002:73df] (rev c1)"
legacy_reset maxwell
not_due already-nvidia "$NV_1060"
legacy_reset maxwell; INSTALLED=" linux-mainstream linux-mainstream-headers dkms nvidia-470xx-dkms nvidia-470xx-utils "
not_due 470xx-installed "$NV_1060"
legacy_reset maxwell; INSTALLED=" linux-mainstream linux-mainstream-headers dkms nvidia-dkms "
not_due nvidia-dkms-installed "$NV_1060"
legacy_reset maxwell missing; nouveau_install
not_due repo-without-set "$NV_1060"
legacy_reset maxwell lib32-nvidia-580xx-utils; nouveau_install
not_due repo-without-lib32 "$NV_1060"

CASES=$((CASES + 1))
chk_str nothing-escaped "$(cat "$TMP/escaped" 2>/dev/null)" ""

if [[ $FAILS -eq 0 ]]; then echo "gpu-driver-install: all $CASES cases PASS"; exit 0
else echo "gpu-driver-install: $FAILS assertion(s) FAILED across $CASES cases"; exit 1; fi
