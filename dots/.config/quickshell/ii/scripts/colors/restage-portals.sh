#!/usr/bin/env bash
# Every GTK file dialog on the system — choose a wallpaper, import a theme, pick
# a login picture — is drawn by xdg-desktop-portal-gtk rather than by whatever
# asked for it, and it reads the palette once, when it starts. Restarting it is
# what hands its dialogs a new one.
#
# Restarted, and never merely stopped. The same process answers
# org.freedesktop.portal.Settings, which is how every running GTK application
# hears about interface changes, and it does not exit on its own — so a stop
# leaves them deaf to the icon theme, to light and dark, to all of it, until
# something starts it again. A restart is a sixty-millisecond gap they
# reconnect across. For the same reason nothing here may wait while the service
# is down: the length of that gap is the whole safety margin.

set -u

command -v systemctl >/dev/null 2>&1 || exit 0

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"

# One restart per burst of colour changes.
if command -v flock >/dev/null 2>&1 && { exec 7>"$RUNTIME_DIR/quickshell-restage-portals.lock"; } 2>/dev/null; then
    flock -n 7 || exit 0
fi

# Not while one of its own dialogs is open — the restart would take the dialog
# down with it, mid-pick. Matched on the window class, since a title can carry
# the same string for entirely unrelated reasons.
if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
    && hyprctl clients -j 2>/dev/null \
       | jq -e 'any(.[]; .class == "xdg-desktop-portal-gtk")' >/dev/null 2>&1; then
    exit 0
fi

systemctl --user restart xdg-desktop-portal-gtk.service 2>/dev/null || true
