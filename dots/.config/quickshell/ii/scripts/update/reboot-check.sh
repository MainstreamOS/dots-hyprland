#!/usr/bin/env bash
# Whether an update leaves the machine needing a reboot.
#
#   reboot-check.sh predict          pending updates, from checkupdates when it
#                                    is installed, else the last sync
#   reboot-check.sh plan < names     package names on stdin, one per line
#   reboot-check.sh verdict SINCE    what pacman.log says was installed since
#                                    SINCE (its own timestamp format)
#
# Prints 0 or 1 on the first line, then the packages that decided it.
#
# Only what the kernel holds asks for a reboot: the kernel, its firmware and
# microcode, out-of-tree modules, the NVIDIA driver and glibc. Anything else a
# running desktop has loaded is put right by logging in again, so the verdict
# leaves the Update page's relogin note when the session's code was replaced.
set -u

mode="${1:-}"; shift || true
me="$(id -un)"

# Removing a running kernel's modules or changing a driver's userspace API leaves
# the machine half working until it restarts.
always_re='^(linux(-(lts|zen|hardened|rt|rt-lts|cachyos[a-z-]*|mainstream[a-z-]*))?|linux-firmware.*|amd-ucode|intel-ucode|glibc|nvidia|nvidia-open|nvidia-lts|nvidia-.*-dkms|nvidia-open-dkms|nvidia-utils|lib32-nvidia-utils|nvidia-settings|.*-dkms)$'

# One scan of the session's processes. Prints
# "live <path>" and "gone <path>": a mapping whose file has been replaced
# under the process still names the old path, and awk splits the "(deleted)"
# suffix into its own field.
_session_maps() {
    local pids p
    pids="$(pgrep -u "$me" -x Hyprland; pgrep -u "$me" -x qs; pgrep -u "$me" -x quickshell)" || true
    [[ -n "$pids" ]] || return 0
    for p in $pids; do
        awk '$6 ~ /^\/usr\// { print ($7 == "(deleted)" ? "gone " : "live ") $6 }' \
            "/proc/$p/maps" 2>/dev/null
        readlink "/proc/$p/exe" 2>/dev/null | sed 's/^/live /'
    done | sort -u
}

# Whether anything the session loaded has already been replaced on disk.
# Only code counts. The session also maps icon caches, compiled schemas and
# fonts under /usr/share, which most updates regenerate, and a stale copy of
# those cannot break a reload the way a replaced library can.
session_has_replaced() {
    _session_maps | grep -qE '^gone /usr/(lib|lib64|bin)/'
}

# names on stdin -> the ones that require a reboot, on stdout.
judge() {
    local names
    names="$(grep -v '^[[:space:]]*$' | sort -u)"
    [[ -n "$names" ]] || return 0
    printf '%s\n' "$names" | grep -E "$always_re" | sort -u || true
}

emit() {  # reasons on stdin
    local reasons
    reasons="$(sort -u)"
    if [[ -n "$reasons" ]]; then
        echo 1
        printf '%s\n' "$reasons"
    else
        echo 0
    fi
}

case "$mode" in
    predict)
        # checkupdates syncs a private copy of the databases, so its answer is
        # current; the fallback reads the last sync this machine did, which is
        # right until the repositories move again.
        if command -v checkupdates >/dev/null 2>&1; then
            # A sync that could not reach the repositories knows nothing, and
            # saying 0 in that case would promise a reboot-free run it cannot
            # see. 2 is its way of saying nothing is pending.
            pending="$(checkupdates 2>/dev/null)"; rc=$?
            if [[ $rc -eq 1 ]]; then
                echo unknown
            else
                printf '%s\n' "$pending" | awk 'NF {print $1}' | judge | emit
            fi
        else
            pacman -Qu 2>/dev/null | grep -v '\[ignored\]' | awk '{print $1}' | judge | emit
        fi
        ;;
    plan)
        judge | emit
        ;;
    verdict)
        since="${1:-}"
        {
            if [[ -n "$since" ]]; then
                awk -v since="$since" '
                    /\[ALPM\] (upgraded|installed|reinstalled) / {
                        ts = substr($1, 2, length($1) - 2)
                        if (ts >= since) print $4
                    }' /var/log/pacman.log 2>/dev/null | judge
            fi
        } | emit
        if session_has_replaced; then
            mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/mainstream" 2>/dev/null || true
            touch "${XDG_STATE_HOME:-$HOME/.local/state}/mainstream/relogin-needed" 2>/dev/null || true
        fi
        ;;
    *)
        echo "usage: reboot-check.sh predict | plan < names | verdict SINCE" >&2
        exit 2
        ;;
esac
