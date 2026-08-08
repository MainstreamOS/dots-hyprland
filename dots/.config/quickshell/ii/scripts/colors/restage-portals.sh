#!/usr/bin/env bash
# Every GTK file dialog on the system — choose a wallpaper, import a theme, pick
# a login picture — is drawn by xdg-desktop-portal-gtk rather than by whatever
# asked for it. The portal takes the palette, the widget theme, the icon theme
# and the interface fonts once, when it starts, and nothing tells it to look
# again, so stopping it is what discards the old look. It is D-Bus activated, so
# the next dialog starts a fresh one holding the current colours.

set -u

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"

command -v systemctl >/dev/null 2>&1 || exit 0

# Two wallpaper changes in quick succession — a slideshow tick landing on a
# theme apply — would otherwise each stop the portal, and the second could catch
# the first's replacement mid-start.
if command -v flock >/dev/null 2>&1 && exec 7>"$RUNTIME_DIR/quickshell-restage-portals.lock" 2>/dev/null; then
    flock -n 7 || exit 0
fi

# The folder icons are recolored by a job that detaches and outlives the apply,
# and it ends by flipping the icon theme away and back so open applications
# reload. A portal that comes up between those two writes holds the plain icon
# set. The job takes this lock before it starts, so waiting on it is exact —
# no guess about how long the rebuild runs.
if command -v flock >/dev/null 2>&1 && exec 6>"$RUNTIME_DIR/quickshell-icon-recolor.lock" 2>/dev/null; then
    flock -w 30 6 || true
fi

# Not while one of its own dialogs is open — stopping the portal would take the
# dialog down with it, mid-pick. Matched on the window class, since a title can
# carry the same string for entirely unrelated reasons.
if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
    && hyprctl clients -j 2>/dev/null \
       | jq -e 'any(.[]; .class == "xdg-desktop-portal-gtk")' >/dev/null 2>&1; then
    exit 0
fi

systemctl --user stop xdg-desktop-portal-gtk.service 2>/dev/null || true
