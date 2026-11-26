#!/usr/bin/env bash
# gpu-driver-install.sh: an NVIDIA module for every installed kernel, and the
# frozen 580xx branch GTX 900 to Titan V cards need, from the repositories.
#
# Sourced after gpu-config.sh, which stays free of package transactions and
# supplies the reads used here (gpu_installed_kernels, nvidia_module_present,
# note_failure). The prebuilt nvidia-open carries modules for Arch's `linux`
# only, so a machine with any other kernel runs the DKMS build of the driver
# for all of its kernels.
#
# Seams, as in gpu-config.sh:
#   GPU_SUDO        '' when already root (installer, gpu-drivers) or 'sudo' (./setup)
#   GPU_DB_REFRESH  'true' lets the ladder refresh the package database. Only
#                   for an installer: on a running system a refresh followed
#                   by a kernel and driver install is a partial upgrade.
#   GPU_LOG_DIR     where a failed build's log is kept (default /var/log/mainstream)
#   GPU_NVIDIA_PENDING  where a frozen branch left for the system update is
#                   noted (default /var/lib/mainstream/nvidia-driver-pending)
# and the functions below, which tests redefine to record calls.

_gpu_pacman() { ${GPU_SUDO:-} pacman "$@"; }
_gpu_dkms()   { ${GPU_SUDO:-} dkms "$@"; }
_gpu_pkg_in_repo() { pacman -Si -- "$1" >/dev/null 2>&1; }
# pacman -Q also answers for a package that only provides the name, and
# nvidia-open-dkms provides nvidia-open.
_gpu_pkg_installed() { [[ "$(pacman -Qq -- "$1" 2>/dev/null)" == "$1" ]]; }
# Headers of another version leave no build tree under this release, so the
# tree is asked for rather than the package.
_gpu_kernel_headers_present() { [[ -e "/usr/lib/modules/$1/build" ]]; }
# DKMS keeps the log of a failed build in its build directory, where the next
# build or the removal of the package deletes it. One copy per kernel is kept,
# replaced each time. Fails when there is no log to keep.
_gpu_dkms_make_log() { printf '%s\n' "/var/lib/dkms/nvidia/$1/build/make.log"; }
_gpu_dkms_log_kept() { printf '%s\n' "${GPU_LOG_DIR:-/var/log/mainstream}/nvidia-dkms-$1.log"; }
_gpu_keep_dkms_log() {
    ${GPU_SUDO:-} install -D -m644 "$(_gpu_dkms_make_log "$1")" "$(_gpu_dkms_log_kept "$2")" 2>/dev/null
}

# ── gpu_nvidia_kernel_toolchain ─────────────────────────────────────────────
# Headers for every installed kernel, and dkms. A kernel rides with its own
# headers: an unversioned headers upgrade fires the dkms remove hook for the
# installed kernel, and unless the kernel moves to the same version in the same
# transaction the working module is deleted and the build that follows is for a
# kernel that is not there. A kernel no repository carries cannot ride, so its
# headers are only taken when it has none.
gpu_nvidia_kernel_toolchain() {
    local rel base hdr g rc=0 groups=() all=()
    while read -r rel base; do
        [[ -n "$rel" ]] || continue
        hdr="$base-headers"
        if _gpu_pkg_in_repo "$base" && _gpu_pkg_in_repo "$hdr"; then
            g="$base $hdr"
        elif ! _gpu_pkg_in_repo "$base" && ! _gpu_pkg_installed "$hdr" && _gpu_pkg_in_repo "$hdr"; then
            g="$hdr"
        else
            continue
        fi
        [[ " ${all[*]} " == *" $hdr "* ]] && continue
        groups+=("$g")
        # shellcheck disable=SC2206
        all+=($g)
    done < <(gpu_installed_kernels)
    if _gpu_pacman -S --needed --noconfirm "${all[@]}" dkms; then
        return 0
    fi
    (( ${#groups[@]} > 0 )) || return 1
    # One kernel's headers failing must not cost the others theirs.
    for g in "${groups[@]}"; do
        # shellcheck disable=SC2086
        _gpu_pacman -S --needed --noconfirm $g || rc=1
    done
    _gpu_pacman -S --needed --noconfirm dkms || rc=1
    return "$rc"
}

# ── gpu_nvidia_ensure_modules ───────────────────────────────────────────────
# Leaves every installed kernel with a loadable nvidia module, or says which
# one has none and why. Reads NVIDIA_DRIVER_FAMILY (gpu_classify_nvidia_driver)
# and runs after the caller has installed that family's packages. Does nothing
# when every kernel already has a module. Returns 1 when a kernel is left
# without one.
gpu_nvidia_ensure_modules() {
    local _gdi_nohdr=() rc=0 entry rel base then_what
    _gpu_nvidia_ladder || rc=1
    (( ${#_gdi_nohdr[@]} > 0 )) || return "$rc"
    # With a DKMS driver installed, pacman's DKMS hook builds the module when
    # the headers arrive. The prebuilt driver builds nothing, so the swap has
    # to be asked for again.
    then_what="then run gpu-drivers again."
    case "${NVIDIA_DRIVER_FAMILY:-none}" in
        nvidia-open) if _gpu_pkg_installed nvidia-open-dkms; then then_what="the module is then built by itself."; fi ;;
        *) then_what="the module is then built by itself." ;;
    esac
    for entry in "${_gdi_nohdr[@]}"; do
        rel="${entry%% *}"; base="${entry#* }"
        note_failure "nvidia: kernel $rel has no headers, so no module can be built for it. Install the package $base-headers; $then_what"
    done
    return 1
}
# The steps themselves. Kernels left without headers go into the caller's
# _gdi_nohdr, since what to tell the person depends on how the run ends.
_gpu_nvidia_ladder() {
    local family="${NVIDIA_DRIVER_FAMILY:-none}" open=false dkms_pkg=""
    case "$family" in
        nvidia-open)
            open=true
            if _gpu_pkg_installed nvidia-open-dkms; then dkms_pkg=nvidia-open-dkms; fi ;;
        nvidia-580xx|nvidia-470xx|nvidia-390xx)
            dkms_pkg="$family-dkms"
            _gpu_pkg_installed "$dkms_pkg" || return 0 ;;
        *)
            return 0 ;;
    esac

    local rel base missing rc=0 swapped=false had_module=() kept=() note
    if [[ -z "$(gpu_installed_kernels)" ]]; then
        echo "nvidia: no installed kernel found, so the module is unverified."
        return 0
    fi
    missing="$(gpu_kernels_missing_nvidia)"
    [[ -n "$missing" ]] || return 0

    # The prebuilt driver's release moves every time Arch's kernel does, so a
    # missing module for that kernel is first answered by the build that
    # matches it. Where the caller allows a refresh that is the newest build;
    # otherwise it is the one the database already names. The kernel rides
    # along so the pair cannot end up a version apart again.
    if [[ $open == true && -z "$dkms_pkg" ]]; then
        local stock_rel="" stock=()
        while read -r rel base; do
            [[ "$base" == linux ]] && stock_rel="$rel"
        done <<<"$missing"
        if [[ -n "$stock_rel" ]]; then
            if [[ "${GPU_DB_REFRESH:-false}" == true ]]; then
                echo "nvidia: no module for kernel $stock_rel. Refreshing the database and taking the matching build."
                _gpu_pacman -Sy || echo "nvidia: database refresh failed."
            else
                echo "nvidia: no module for kernel $stock_rel. Taking the nvidia-open build the package database names."
            fi
            if _gpu_pkg_in_repo linux; then
                stock+=(linux)
                if _gpu_pkg_installed linux-headers && _gpu_pkg_in_repo linux-headers; then stock+=(linux-headers); fi
            fi
            _gpu_pacman -S --needed --noconfirm "${stock[@]}" nvidia-open \
                || echo "nvidia: nvidia-open update failed."
            missing="$(gpu_kernels_missing_nvidia)"
            [[ -n "$missing" ]] || return 0
        fi
    fi

    # No prebuilt module exists for what is left, so DKMS builds them. The
    # toolchain goes in first and on its own: a refused driver swap must not
    # also cost the headers a build needs.
    echo "nvidia: getting kernel headers and dkms so DKMS can build for every installed kernel."
    gpu_nvidia_kernel_toolchain || echo "nvidia: could not install all of the DKMS toolchain."
    missing="$(gpu_kernels_missing_nvidia)"
    [[ -n "$missing" ]] || return 0
    local buildable=0
    while read -r rel base; do
        if _gpu_kernel_headers_present "$rel"; then
            buildable=1
        else
            _gdi_nohdr+=("$rel $base")
            rc=1
        fi
    done <<<"$missing"

    if [[ $open == true && -z "$dkms_pkg" ]]; then
        if (( buildable == 0 )); then
            echo "nvidia: nothing can be built, so the installed driver stays as it is."
            return 1
        fi
        if ! _gpu_pkg_installed dkms; then
            note_failure "nvidia: dkms could not be installed, so the prebuilt driver stays in place."
            return 1
        fi
        # The swap takes the prebuilt module away from the kernel that has one.
        # Those kernels are remembered: none of them may come out without one.
        while read -r rel base; do
            nvidia_module_present "$rel" || continue
            if ! _gpu_kernel_headers_present "$rel"; then
                note_failure "nvidia: kernel $rel has a working module and no headers ($base-headers), so the prebuilt driver stays in place."
                return 1
            fi
            had_module+=("$rel")
        done < <(gpu_installed_kernels)
        # The DKMS driver conflicts with the prebuilt one and pacman's conflict
        # question answers itself with "no" when nothing may ask, so the swap is
        # spelled out. Fetch the replacement first: removing the prebuilt driver
        # and then failing to get its DKMS twin leaves no driver at all.
        echo "nvidia: switching to the DKMS driver, which builds for each kernel."
        if ! _gpu_pacman -Sw --noconfirm nvidia-open-dkms; then
            note=""
            while read -r rel base; do note+=" $rel"; done <<<"$missing"
            note_failure "nvidia: nvidia-open-dkms is not obtainable, so the prebuilt driver stays in place and kernel$note still has no module. Run gpu-drivers again once the computer is online."
            return 1
        fi
        local had_prebuilt=false
        if _gpu_pkg_installed nvidia-open; then
            had_prebuilt=true
            _gpu_pacman -Rdd --noconfirm nvidia-open \
                || echo "nvidia: could not remove the prebuilt driver before the swap."
        fi
        if ! _gpu_pacman -S --noconfirm nvidia-open-dkms; then
            echo "nvidia: nvidia-open-dkms install failed."
        fi
        if ! _gpu_pkg_installed nvidia-open-dkms; then
            if [[ $had_prebuilt == true ]] && ! _gpu_pkg_installed nvidia-open; then
                echo "nvidia: putting the prebuilt driver back."
                _gpu_pacman -S --noconfirm nvidia-open \
                    || note_failure "nvidia: no driver package is installed. Run: sudo pacman -S nvidia-open"
            fi
            note_failure "nvidia: nvidia-open-dkms could not be installed."
            return 1
        fi
        swapped=true
        missing="$(gpu_kernels_missing_nvidia)"
    fi

    # Installing the package only queues the build: pacman's DKMS hook builds
    # for the kernels it finds headers for at that moment. Ask for each kernel
    # still without a module by name before concluding there is none.
    if [[ -n "$missing" ]]; then
        local dkms_ver
        dkms_ver="$(_gpu_dkms status -m nvidia 2>/dev/null | head -1 | sed -n 's|^nvidia[/,][[:space:]]*\([^,:]*\).*|\1|p' || true)"
        if [[ -z "$dkms_ver" ]]; then
            echo "nvidia: could not read a DKMS version for nvidia."
        else
            while read -r rel base; do
                _gpu_kernel_headers_present "$rel" || continue
                echo "nvidia: asking DKMS for nvidia/$dkms_ver against kernel $rel."
                if ! _gpu_dkms install -m nvidia -v "$dkms_ver" -k "$rel"; then
                    echo "nvidia: DKMS build of nvidia/$dkms_ver for kernel $rel failed."
                    if _gpu_keep_dkms_log "$dkms_ver" "$rel"; then kept+=("$rel"); fi
                fi
            done <<<"$missing"
        fi
    fi

    # A swap made here must not cost a kernel the module it had. If DKMS could
    # not build for one of those, the prebuilt driver goes back. A machine that
    # was on the DKMS driver before this run is never moved.
    if [[ $swapped == true ]]; then
        local lost=() still=() never=()
        for rel in "${had_module[@]}"; do
            nvidia_module_present "$rel" || lost+=("$rel")
        done
        if (( ${#lost[@]} > 0 )); then
            note=""
            for rel in "${lost[@]}"; do
                if [[ " ${kept[*]} " == *" $rel "* ]]; then note+=" The build log is kept in $(_gpu_dkms_log_kept "$rel")."; fi
            done
            echo "nvidia: the DKMS build failed for kernel ${lost[*]}. Putting the prebuilt driver back."
            _gpu_pacman -Rdd --noconfirm nvidia-open-dkms \
                || echo "nvidia: could not remove nvidia-open-dkms."
            _gpu_pacman -S --noconfirm nvidia-open \
                || echo "nvidia: nvidia-open install failed."
            for rel in "${lost[@]}"; do
                nvidia_module_present "$rel" || still+=("$rel")
            done
            while read -r rel base; do
                if [[ -n "$rel" && " ${had_module[*]} " != *" $rel "* ]]; then never+=("$rel"); fi
            done < <(gpu_kernels_missing_nvidia)
            if (( ${#still[@]} > 0 )); then
                note_failure "nvidia: the DKMS build failed for kernel ${lost[*]} and the prebuilt driver could not be put back, so kernel ${still[*]} has no driver. Run: sudo pacman -Rdd nvidia-open-dkms; sudo pacman -S nvidia-open.$note"
            elif (( ${#never[@]} > 0 )); then
                note_failure "nvidia: the DKMS build failed for kernel ${lost[*]}, so the prebuilt driver was put back. Kernel ${never[*]} still has no module.$note"
            else
                note_failure "nvidia: the DKMS build failed for kernel ${lost[*]}, so the prebuilt driver was put back.$note"
            fi
            return 1
        fi
    fi

    while read -r rel base; do
        [[ -n "$rel" ]] || continue
        if nvidia_module_present "$rel"; then
            echo "nvidia: module present for kernel $rel."
        elif _gpu_kernel_headers_present "$rel"; then
            note=""
            if [[ " ${kept[*]} " == *" $rel "* ]]; then note=" The build log is kept in $(_gpu_dkms_log_kept "$rel")."; fi
            note_failure "nvidia: no loadable module for kernel $rel ($base), so the card has no driver on that kernel.$note"
            rc=1
        else
            rc=1
        fi
    done < <(gpu_installed_kernels)
    return "$rc"
}

# ── gpu_nvidia_modules_for_added_kernel <package> ───────────────────────────
# gpu_nvidia_ensure_modules after that kernel was added beside the others.
# Returns 1 when it is still without a module while another kernel has one:
# the caller takes it back out, so what the ladder noted is not reported.
# Otherwise the ladder's notes go to note_failure as usual.
gpu_nvidia_modules_for_added_kernel() {
    local kernel="$1" saved n notes=()
    saved="$(declare -f note_failure)"
    note_failure() { notes+=("$1"); }
    gpu_nvidia_ensure_modules
    unset -f note_failure
    [[ -z "$saved" ]] || eval "$saved"
    gpu_kernel_nvidia_ready "$kernel" || return 1
    for n in "${notes[@]}"; do note_failure "$n"; done
    return 0
}

# ── gpu_nvidia_remove_drivers [<family to keep>] ────────────────────────────
# Takes every NVIDIA driver package off but the named family's, by exact name.
# The branches conflict with each other and pacman's conflict question answers
# itself with no, so the driver being replaced goes before the next arrives.
# Without dependency checks: the branch that follows provides nvidia-utils.
gpu_nvidia_remove_drivers() {
    local keep="${1:-none}" b p all=() present=()
    all=(nvidia nvidia-open nvidia-dkms nvidia-open-dkms nvidia-utils lib32-nvidia-utils
         nvidia-settings libxnvctrl opencl-nvidia lib32-opencl-nvidia)
    for b in 580xx 470xx 390xx; do
        [[ "$keep" == "nvidia-$b" ]] && continue
        all+=("nvidia-$b-dkms" "nvidia-$b-utils" "lib32-nvidia-$b-utils" "nvidia-$b-settings"
              "libxnvctrl-$b" "opencl-nvidia-$b" "lib32-opencl-nvidia-$b")
    done
    for p in "${all[@]}"; do
        if _gpu_pkg_installed "$p"; then present+=("$p"); fi
    done
    (( ${#present[@]} > 0 )) || return 0
    echo "nvidia: removing ${present[*]}."
    _gpu_pacman -Rdd --noconfirm "${present[@]}"
}

# ── gpu_nvidia_legacy_offered ───────────────────────────────────────────────
# Whether the repositories offer the frozen branch NVIDIA_LOCAL_PKGS names: its
# dkms and utils packages. Its settings app comes along when it is offered too.
gpu_nvidia_legacy_offered() {
    local p
    (( ${#NVIDIA_LOCAL_PKGS[@]} > 0 )) || return 1
    for p in "${NVIDIA_LOCAL_PKGS[@]}"; do
        [[ "$p" == *-dkms || "$p" == *-utils ]] || continue
        _gpu_pkg_in_repo "$p" || return 1
    done
    return 0
}

# ── gpu_nvidia_legacy_due ───────────────────────────────────────────────────
# Whether a system set up before the repositories carried the 580xx branch should
# get it now: the card is one 580xx is the driver for, no NVIDIA kernel driver is
# installed, and the repositories offer it. Reads gpu_classify_nvidia_driver.
gpu_nvidia_legacy_due() {
    local p
    [[ "${NVIDIA_DRIVER_FAMILY:-none}" == nvidia-580xx ]] || return 1
    for p in nvidia nvidia-lts nvidia-dkms nvidia-open nvidia-open-lts nvidia-open-dkms \
             nvidia-580xx-dkms nvidia-470xx-dkms nvidia-390xx-dkms; do
        _gpu_pkg_installed "$p" && return 1
    done
    gpu_nvidia_legacy_offered
}

# ── gpu_nvidia_install_legacy ───────────────────────────────────────────────
# Installs the frozen branch gpu_classify_nvidia_driver picked (NVIDIA_LOCAL_PKGS)
# from the package repositories and has DKMS build it for every installed
# kernel. Returns:
#   0  it is installed and at least one kernel has its module
#   1  it was tried and no kernel can use it, so every NVIDIA driver is off the
#      machine, the card is left to nouveau and the family reads nouveau
#   2  the repositories do not offer it or it could not be downloaded, and
#      nothing was changed
gpu_nvidia_install_legacy() {
    local family="${NVIDIA_DRIVER_FAMILY:-none}" p rel base kernels pkgs=()
    if ! gpu_nvidia_legacy_offered; then
        echo "nvidia: the repositories do not offer $family, so it cannot be installed now."
        return 2
    fi
    for p in "${NVIDIA_LOCAL_PKGS[@]}"; do
        if _gpu_pkg_in_repo "$p"; then pkgs+=("$p"); fi
    done
    # Downloaded before anything comes off: a machine that cannot fetch the
    # branch keeps whatever driver it has.
    if ! _gpu_pacman -Sw --noconfirm "${pkgs[@]}"; then
        echo "nvidia: $family could not be downloaded."
        return 2
    fi
    gpu_nvidia_remove_drivers "$family" || echo "nvidia: could not remove the NVIDIA driver $family replaces."
    gpu_nvidia_kernel_toolchain || echo "nvidia: could not install all of the DKMS toolchain."
    if _gpu_pacman -S --needed --noconfirm "${pkgs[@]}" egl-wayland; then
        gpu_nvidia_ensure_modules || true
        kernels="$(gpu_installed_kernels)"
        if [[ -z "$kernels" ]]; then
            echo "nvidia: no installed kernel found, so the module is unverified."
            return 0
        fi
        while read -r rel base; do
            nvidia_module_present "$rel" && return 0
        done <<<"$kernels"
        note_failure "nvidia: $family did not build for any installed kernel, so it was removed and the card uses nouveau."
    else
        note_failure "nvidia: $family could not be installed, so the card uses nouveau."
    fi
    gpu_nvidia_remove_drivers none || echo "nvidia: could not remove $family."
    NVIDIA_DRIVER_FAMILY=nouveau NVIDIA_LOCAL_PKGS=() NVIDIA_REPO_PKGS=(xf86-video-nouveau mesa lib32-mesa)
    return 1
}

# ── the frozen branch left for the system update ───────────────────────────
# A branch the repositories could not offer when the system was set up, so the
# card runs on nouveau until the system update installs it.
gpu_nvidia_mark_pending() {
    printf '%s\n' "${NVIDIA_DRIVER_FAMILY:-none}" \
        | _gpu_write_file "${GPU_NVIDIA_PENDING:-/var/lib/mainstream/nvidia-driver-pending}"
}
gpu_nvidia_clear_pending() {
    ${GPU_SUDO:-} rm -f -- "${GPU_NVIDIA_PENDING:-/var/lib/mainstream/nvidia-driver-pending}"
}

# ── gpu_nvidia_setup_legacy ─────────────────────────────────────────────────
# A frozen branch's whole setup on a running system (./setup, gpu-drivers): the
# branch from the repositories, or the one already installed kept with its
# modules seen to, or nouveau. One the repositories could not offer is left for
# the system update. Returns 1 when the card is left without NVIDIA's driver.
gpu_nvidia_setup_legacy() {
    local rc
    gpu_nvidia_install_legacy; rc=$?
    case "$rc" in
        0) gpu_nvidia_clear_pending; return 0 ;;
        1) gpu_nvidia_clear_pending ;;
        *)
            if _gpu_pkg_installed "${NVIDIA_LOCAL_PKGS[0]:-}"; then
                echo "nvidia: keeping the installed $NVIDIA_DRIVER_FAMILY."
                gpu_nvidia_ensure_modules
                return
            fi
            gpu_nvidia_mark_pending
            note_failure "nvidia: $NVIDIA_DRIVER_FAMILY could not be downloaded, so the card uses nouveau. NVIDIA's driver installs with the next system update once the computer is online." ;;
    esac
    _gpu_pacman -S --needed --noconfirm xf86-video-nouveau mesa || true
    return 1
}

# ── gpu_driver_run_report [<path>] ──────────────────────────────────────────
# For a tool whose run is a complete repair: the breadcrumb then describes that
# run alone, and a run with nothing to report leaves none behind.
gpu_driver_run_report() {
    local path="${1:-/var/lib/mainstream/gpu-install-failed.log}"
    ${GPU_SUDO:-} rm -f -- "${path:?}" 2>/dev/null || true
    flush_failures "$path"
}
