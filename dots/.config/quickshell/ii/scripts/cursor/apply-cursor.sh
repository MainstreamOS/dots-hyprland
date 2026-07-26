#!/usr/bin/env bash
# Point the compositor at the cursor theme chosen in Settings.
#
#   apply-cursor.sh [size]
#
# The chosen theme is read from gsettings, which is also where GNOME's own
# settings panels write. Those can leave a name behind that this machine has no
# theme for — "default" is the stock value and is not a theme anyone ships — and
# hyprctl reports success whatever name it is handed, so an unusable name leaves
# the pointer on the compositor's built-in arrow with nothing to say why. Check
# the theme is really on disk and fall back to the one we ship if it isn't.
set -uo pipefail

FALLBACK="Bibata-Modern-Classic"
DEFAULT_SIZE=24

unquote() {
    local s="$1"
    s="${s#\'}"
    s="${s%\'}"
    printf '%s' "$s"
}

installed() {
    local name="$1" base
    [ -n "$name" ] || return 1
    for base in "$HOME/.local/share/icons" "$HOME/.icons" /usr/share/icons; do
        [ -d "$base/$name/cursors" ] && return 0
    done
    return 1
}

theme=$(unquote "$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null || true)")
installed "$theme" || theme="$FALLBACK"

size="${1:-}"
[ -n "$size" ] || size=$(unquote "$(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null || true)")
case "$size" in
    '' | *[!0-9]*) size=$DEFAULT_SIZE ;;
esac

hyprctl setcursor "$theme" "$size" >/dev/null 2>&1
