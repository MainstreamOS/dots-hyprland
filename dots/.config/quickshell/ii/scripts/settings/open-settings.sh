#!/usr/bin/env bash
# Opens Settings at a page (by file) and section; a window already open takes them.
#   open-settings.sh [Page.qml [section]]
set -uo pipefail

page="${1:-}"
section="${2:-}"
settings="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/settings.qml"

# One request at a time, so two made at once cannot both start a window.
exec 9>>"${XDG_RUNTIME_DIR:-/tmp}/mainstream-settings-open.lock"
flock -w 45 9

# Asks again while a window restarts or loads; --newest reaches the one that stays.
# Longer than a restart's own 15 s wait, so a failed one is answered by the old window.
deadline=$((SECONDS + 25))
while ((SECONDS < deadline)); do
    answer=$(timeout 10 qs ipc --newest -p "$settings" call settings openPage "$page" "$section" 2>&1) || break
    grep -qx ok <<<"$answer" && exit 0
    # A Settings window from before openPage existed.
    grep -q "Function not found" <<<"$answer" && break
    sleep 0.2
done

env ${page:+"QS_SETTINGS_PAGE=$page"} ${section:+"QS_SETTINGS_SECTION=$section"} qs -p "$settings" 9>&- &
# The lock is kept until the new window can be asked, so the next request goes to it.
# Its lock file, written once IPC listens, is checked first: each qs list starts a quickshell.
lock_file="${XDG_RUNTIME_DIR:-/run/user/$UID}/quickshell/by-pid/$!/instance.lock"
for _ in $(seq 100); do
    [[ -s "$lock_file" ]] && qs list -j -p "$settings" 2>/dev/null | grep -qE "\"pid\": $!(,|$)" && break
    kill -0 $! 2>/dev/null || break
    sleep 0.05
done
