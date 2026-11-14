#!/usr/bin/env bash
# Prints the bus names of browser built-in MPRIS players whose browser also
# runs a per-window bridge, one per line. Arguments: every player bus name.
#
# The bridge host embeds its OWN pid in its bus name, and the browser names
# its built-in player after its D-Bus connection or its pid depending on
# version — so no name-level linkage exists between the two. What does hold
# natively: the bridge host is a direct child of the browser process that
# owns the built-in's connection. Resolve both connections to processes and
# match the built-in's pid against the bridges' parent pids. A Flatpak app
# reaches the bus through one xdg-dbus-proxy, which the bus reports as the pid
# of every connection from it, so a built-in sharing a bridge's pid counts too.
set -u

pid_of() {
    # Output form is "(uint32 4341,)" — take the last number, not every digit.
    gdbus call --session --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.GetConnectionUnixProcessID "$1" 2>/dev/null \
        | grep -o '[0-9]\+' | tail -n1
}
ppid_of() { awk '/^PPid:/{print $2}' "/proc/$1/status" 2>/dev/null; }

declare -A covering=()
builtins=()
for name in "$@"; do
    case "$name" in
        *.firefox.instance*_t*|*.chromium.instance*_t*|*.brave.instance*_t*)
            pid=$(pid_of "$name") || continue
            [ -n "$pid" ] || continue
            covering[$pid]=1
            pp=$(ppid_of "$pid")
            [ -n "$pp" ] && covering[$pp]=1
            ;;
        *.firefox.instance*|*.chromium.instance*|*.chrome.instance*|*.brave.instance*)
            builtins+=("$name")
            ;;
    esac
done

[ ${#builtins[@]} -eq 0 ] && exit 0
[ ${#covering[@]} -eq 0 ] && exit 0
for name in "${builtins[@]}"; do
    pid=$(pid_of "$name")
    [ -n "$pid" ] || continue
    [ -n "${covering[$pid]:-}" ] && printf '%s\n' "$name"
done
exit 0
