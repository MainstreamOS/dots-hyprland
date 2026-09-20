#!/usr/bin/env bash
# Starts the system update in a session of its own and records everything it
# says, so the Settings window is only ever a viewer of it.
#
#   run-detached.sh <state dir> <command...>
#
# The password for `sudo -S` is read from this script's stdin and handed on
# through a pipe; it never appears on a command line or in the environment.
#
# Why detached: the window that starts the update is a Quickshell instance,
# and Quickshell kills a child process when the object that owns it goes away.
# A reload of that window, or the user closing it, used to take the running
# update with it, part way through pacman. Here the window only launches, and
# the update carries on under its own session leader whatever the window does.
#
# What is left in the state dir, for the page to pick up at any point:
#   update.log   everything the helper printed, ending in the sentinel line
#                "@@MAINSTREAM-UPDATE-EXIT <code>" once it has finished
#   update.exit  the exit code, present only once the run is over
#   update.pid   the session leader and its start tick while it runs, for
#                the Stop button and the page's liveness check
set -u

dir="$1"; shift
[[ $# -gt 0 ]] || { echo "run-detached: no command given" >&2; exit 2; }
mkdir -p "$dir" || exit 2
log="$dir/update.log"; exitf="$dir/update.exit"; pidf="$dir/update.pid"
rm -f "$exitf" "$pidf" "$dir/update.seen"
: > "$log" || exit 2

# Waiting for the whole line is what keeps this from racing the page: the
# password is only forwarded once it has actually arrived.
IFS= read -r pw || { echo "run-detached: no password on stdin" >&2; exit 2; }

# The helper runs in the foreground of the new session, so its stdin is the
# pipe carrying the password and a TERM aimed at it is not deferred by a
# waiting shell. The Stop button signals the child of the recorded pid.
printf '%s\n' "$pw" | setsid -f bash -c '
    log="$1"; exitf="$2"; pidf="$3"; shift 3
    # The tick this session started at goes in beside the pid, so the page can
    # tell the run from whatever later inherits its number.
    echo "$$ $(sed "s/^[^)]*) //" /proc/$$/stat | awk "{print \$20}")" > "$pidf"
    "$@" >> "$log" 2>&1
    rc=$?
    printf "\n@@MAINSTREAM-UPDATE-EXIT %s\n" "$rc" >> "$log"
    echo "$rc" > "$exitf"
    rm -f "$pidf"
' bash "$log" "$exitf" "$pidf" "$@"
unset pw
exit 0
