#!/usr/bin/env bash
# Whether the update a pid file describes is still running.
#
#   update-live.sh <pidfile>     exit 0 and print the pid when it is
#
# The file names the session leader and the tick it started at. The number on
# its own is not enough: a run killed outright, or lost to a power cut, leaves
# the file behind, and sooner or later the kernel hands that number to some
# other process. Checking the start tick means a stranger with the same number
# is never taken for the update, and never sent its signals.
set -u

line=$(cat "${1:?pid file}" 2>/dev/null) || exit 1
pid=${line%% *}
started=${line#* }
[[ "$started" == "$line" ]] && started=""
case "$pid" in ""|*[!0-9]*) exit 1 ;; esac
kill -0 "$pid" 2>/dev/null || exit 1

# Everything after the command name sits at a fixed position; the name itself
# is the one field that may contain spaces, so it is cut off first.
rest=$(sed 's/^[^)]*) //' "/proc/$pid/stat" 2>/dev/null) || exit 1
set -- $rest
# Field 4 here is the session id (6 in the file), 20 the start tick (22).
[[ "${4}" == "$pid" ]] || exit 1
if [[ -n "$started" && "${20}" != "$started" ]]; then exit 1; fi
echo "$pid"
