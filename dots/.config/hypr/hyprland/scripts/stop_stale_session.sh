#!/usr/bin/env bash
# Stops session targets left active by a Hyprland session that ended without
# its shutdown hook, so this login starts them, and the apps they pull in, again.

# Later in a session the old targets may have become its own.
[[ ${1:-} == --login ]] || { echo "Usage: ${0##*/} --login (for the Hyprland login in execs.lua only)" >&2; exit 2; }

targets=(hyprland-autostart.target xdg-desktop-autostart.target hyprland-session.target graphical-session.target)
runtime=${XDG_RUNTIME_DIR:-/run/user/$UID}

# The login waits on this script, so no query may hold it up for long.
bounded() { timeout 2 "$@" 2>/dev/null; }

is_hyprland() {
    local comm
    [[ $1 =~ ^[0-9]+$ ]] || return 1
    { read -r comm <"/proc/$1/comm"; } 2>/dev/null || return 1
    [[ ${comm,,} == hyprland ]]
}

own_lock=$runtime/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-none}/hyprland.lock
{ read -r own_pid <"$own_lock"; } 2>/dev/null
is_hyprland "$own_pid" || exit 0
started=$(stat -c %Y "$own_lock" 2>/dev/null) || exit 0

check_unit() {
    local id=$1 state=$2 entered=$3
    case $id in
        '') ;;
        gamescope-session-plus@*)
            # Gaming Mode is in use unless it is on its way out.
            case $state in inactive | failed) ;; deactivating) leaving=1 ;; *) exit 0 ;; esac
            ;;
        *)
            case $state in inactive | failed) return ;; esac
            # A target that came up after this Hyprland did is this session's own.
            [[ $entered =~ ^[0-9]+$ ]] && ((entered < started)) || exit 0
            stale=1
            ;;
    esac
}

scan() {
    local out key value id= state= entered=
    out=$(bounded systemctl --user show --timestamp=unix -p Id -p ActiveState -p ActiveEnterTimestamp \
        "${targets[@]}" 'gamescope-session-plus@*.service') || exit 0
    stale=0 leaving=0
    # A blank line ends each unit's block.
    while IFS='=' read -r key value; do
        case $key in
            Id) id=$value ;;
            ActiveState) state=$value ;;
            ActiveEnterTimestamp) [[ $value == @* ]] && entered=${value#@} ;;
            '') check_unit "$id" "$state" "$entered"; id= state= entered= ;;
        esac
    done <<<"$out"$'\n'
}

# The targets cannot start again until Gaming Mode has stopped, so it gets a
# few seconds to finish, and the targets are left alone if it takes longer.
for ((i = 0; i < 25; i++)); do
    scan
    ((stale && leaving)) || break
    sleep 0.2
done

# Gaming Mode blanks this to keep portals out of it and may not have put it
# back yet, which would leave this session's portal without its backends.
bounded systemctl --user unset-environment XDG_DESKTOP_PORTAL_DIR=
((stale && !leaving)) || exit 0

# A nested Hyprland belongs to the session it runs in. A read error (2) stops here too.
grep -qszE '^(WAYLAND_DISPLAY|DISPLAY)=' "/proc/$own_pid/environ"
(($? == 1)) || exit 0

for dir in "$runtime"/hypr/*/; do
    pid=
    { read -r pid <"${dir}hyprland.lock"; } 2>/dev/null
    [[ $pid != "$own_pid" ]] && is_hyprland "$pid" && exit 0
done

# Another graphical login of this user, a desktop on another VT or Gaming Mode,
# shares these targets. A session that is closing has already ended.
sessions=$(bounded loginctl show-user "$UID" -p Sessions --value) || exit 0
for s in $sessions; do
    [[ $s == "${XDG_SESSION_ID:-}" ]] && continue
    props=$(bounded loginctl show-session "$s" -p Type -p State) || exit 0
    [[ $props == *State=closing* ]] && continue
    case $props in *Type=wayland* | *Type=x11* | *Type=mir*) exit 0 ;; esac
done

echo "Stopping session targets left over from an earlier session" >&2
if ! timeout -k 1 3 systemctl --user stop "${targets[@]}" 2>/dev/null; then
    # Until these are down, this session's own start of the targets waits.
    bounded systemctl --user list-jobs --no-legend |
        awk '$3 == "stop" { print "Still stopping: " $2 }' >&2
fi
exit 0
