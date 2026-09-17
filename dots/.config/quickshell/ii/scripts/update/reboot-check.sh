#!/usr/bin/env bash
# Whether an update leaves the running desktop needing a reboot.
#
#   reboot-check.sh session             the packages the running desktop has
#                                       loaded, one per line
#   reboot-check.sh predict             pending updates, from checkupdates when
#                                       it is installed, else the last sync
#   reboot-check.sh plan < names        package names on stdin, one per line
#   reboot-check.sh verdict SINCE [F]   what pacman.log says was installed since
#                                       SINCE (its own timestamp format), judged
#                                       against the session list in F
#
# Prints 0 or 1 on the first line, then the packages that decided it.
#
# What breaks after an update is a library or binary the session has already
# loaded being replaced on disk: the shell's next reload takes new modules
# into an old process, and the desktop comes back with dead controls that
# only a fresh session repairs. So the question is not which packages are
# "important" but which of the pending ones own a file the compositor or the
# shell currently has mapped. That is read straight from /proc. A short list
# of names covers what never shows up in a user process: the kernel, its
# firmware and microcode, the graphics drivers, out-of-tree modules and the
# display manager.
#
# TIMING IS THE WHOLE DIFFICULTY. Once a package is upgraded, the file the
# session still holds is gone from the disk AND from the package database,
# which now lists the new name. Most of what a desktop maps carries its
# version in the filename, so after the fact nothing can say which package
# owned it. The session list therefore has to be taken BEFORE the upgrade and
# handed to the verdict, which is what the caller does with `session`.
set -u

mode="${1:-}"; shift || true
me="$(id -un)"

# Packages that need a reboot whatever the session has loaded. Kernel modules
# and graphics drivers are here because they are loaded by the kernel rather
# than mapped into any process, so the scan below can never see them.
always_re='^(linux(-(lts|zen|hardened|rt|rt-lts|cachyos[a-z-]*|mainstream[a-z-]*))?|linux-firmware.*|linux-api-headers|amd-ucode|intel-ucode|systemd|systemd-libs|glibc|sddm|dbus|dbus-broker|mainstream-system|nvidia|nvidia-open|nvidia-lts|nvidia-.*-dkms|nvidia-open-dkms|nvidia-utils|lib32-nvidia-utils|nvidia-settings|.*-dkms|mesa|lib32-mesa|vulkan-.*|xf86-video-.*)$'

# One scan of the session's processes, reused by everything below. Prints
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

# Every package owning a file the compositor or a shell instance has mapped.
# Only paths that are still on disk can be attributed, which is exactly why
# this has to be taken before anything is replaced.
session_packages() {
    local files
    files="$(_session_maps | sed -n 's/^live //p')"
    [[ -n "$files" ]] || return 0
    printf '%s\n' "$files" | xargs -r pacman -Qoq 2>/dev/null | sort -u
}

# Whether anything the session loaded has already been replaced on disk. The
# packages behind it usually cannot be named any more, so this answers yes or
# no and leaves the naming to the caller's own list.
session_has_replaced() {
    _session_maps | grep -q '^gone '
}

# names on stdin -> the ones that matter, on stdout. $1 is a file holding the
# session package list; without one the session is read now, which is only
# right before an upgrade has run.
judge() {  # $1 = session list file, optional
    local names session
    names="$(grep -v '^[[:space:]]*$' | sort -u)"
    [[ -n "$names" ]] || return 0
    if [[ -n "${1:-}" && -r "$1" ]]; then
        session="$(sort -u < "$1")"
    else
        session="$(session_packages)"
    fi
    {
        printf '%s\n' "$names" | grep -E "$always_re" || true
        if [[ -n "$session" ]]; then
            comm -12 <(printf '%s\n' "$names") <(printf '%s\n' "$session")
        fi
    } | sort -u
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
    session)
        session_packages
        ;;
    predict)
        # checkupdates syncs a private copy of the databases, so its answer is
        # current; the fallback reads the last sync this machine did, which is
        # right until the repositories move again.
        if command -v checkupdates >/dev/null 2>&1; then
            checkupdates 2>/dev/null | awk '{print $1}'
        else
            pacman -Qu 2>/dev/null | grep -v '\[ignored\]' | awk '{print $1}'
        fi | judge | emit
        ;;
    plan)
        judge | emit
        ;;
    verdict)
        since="${1:-}"; session_file="${2:-}"
        {
            if [[ -n "$since" ]]; then
                awk -v since="$since" '
                    /\[ALPM\] (upgraded|installed|reinstalled) / {
                        ts = substr($1, 2, length($1) - 2)
                        if (ts >= since) print $4
                    }' /var/log/pacman.log 2>/dev/null | judge "$session_file"
            fi
            # Something the session loaded is already gone from disk. Whatever
            # did it, this session cannot be trusted to reload cleanly.
            session_has_replaced && echo "replaced-under-session"
        } | emit
        ;;
    *)
        echo "usage: reboot-check.sh session | predict | plan < names | verdict SINCE [session-file]" >&2
        exit 2
        ;;
esac
