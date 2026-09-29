#!/usr/bin/env bash
# Mirror the shell's font choices into the GTK/Qt interface fonts so apps match
# the shell. Same mapping as the installer's setup_fonts(): font-name <- main
# (pango Medium + variable-font axes), document-font-name <- reading,
# monospace-font-name <- monospace, plus gtk-3.0/4.0 settings.ini gtk-font-name.
#
# Args: [MAIN] [MONO] [READING] font families. With no args, read them from the
# shell config.json (the settings UI passes its live values to dodge the
# config-write race; startup and theme-apply let it read from disk).
set -u

MAIN="${1:-}"; MONO="${2:-}"; READING="${3:-}"
if [ -z "$MAIN" ] && [ -z "$MONO" ] && [ -z "$READING" ]; then
    CFG="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
    [ -f "$CFG" ] || exit 0
    command -v jq >/dev/null 2>&1 || exit 0
    { IFS= read -r MAIN; IFS= read -r MONO; IFS= read -r READING; } < <(jq -r '.appearance.fonts
        | (.main, .monospace, .reading) | if . == null or . == false then "" else tostring | gsub("\n"; " ") end' "$CFG" 2>/dev/null)
fi

if command -v gsettings >/dev/null 2>&1; then
    # Only what differs is written: every write reaches dconf and each app
    # watching it, the same value included.
    IFACE_NOW=$(gsettings list-recursively org.gnome.desktop.interface 2>/dev/null)
    font_set() {
        case $'\n'"$IFACE_NOW"$'\n' in *$'\n'"org.gnome.desktop.interface $1 '$2'"$'\n'*) return 0 ;; esac
        gsettings set org.gnome.desktop.interface "$1" "$2" 2>/dev/null || true
    }
    [ -n "$MAIN" ]    && font_set font-name           "$MAIN Medium 11 @opsz=11,wght=500"
    [ -n "$READING" ] && font_set document-font-name  "$READING 11"
    [ -n "$MONO" ]    && font_set monospace-font-name "$MONO 11"
fi

# gtk-3.0 / gtk-4.0 settings.ini — only the gtk-font-name line is touched so the
# matugen-managed prefer-dark key and everything else stay intact.
if [ -n "$MAIN" ]; then
    GTKFONT="$MAIN Medium 11"
    for f in "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini"; do
        mkdir -p "$(dirname "$f")"
        if [ -f "$f" ] && grep -q '^\[Settings\]' "$f"; then
            if grep -qxF "gtk-font-name=$GTKFONT" "$f"; then
                :
            elif grep -q '^gtk-font-name=' "$f"; then
                sed -i "s|^gtk-font-name=.*|gtk-font-name=$GTKFONT|" "$f"
            else
                sed -i "/^\[Settings\]/a gtk-font-name=$GTKFONT" "$f"
            fi
        else
            printf '[Settings]\ngtk-font-name=%s\n' "$GTKFONT" > "$f"
        fi
    done
fi
exit 0
