#!/usr/bin/env bash
# Mirror the shell's font choices into the GTK/Qt interface fonts so apps match
# the shell. Same mapping as the installer's setup_fonts(): font-name <- main
# (pango Medium + variable-font axes), document-font-name <- reading,
# monospace-font-name <- monospace, plus gtk-3.0/4.0 settings.ini gtk-font-name.
#
# Read the latest saved config after taking the lock, so queued Settings runs
# all apply the current values. Explicit arguments are supported for manual use.
set -u

MAIN="${1:-}"; MONO="${2:-}"; READING="${3:-}"; SCALE="${4:-}"
# One run at a time: two slider moves in flight would each read the Qt config before the other wrote it.
LOCK_DIR="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}"
mkdir -p -- "$LOCK_DIR" || exit 1
exec 9>>"$LOCK_DIR/mainstream-app-font.lock" || exit 1
# Never wait forever, and never write without the lock.
flock -w 12 9 || exit 1
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
if [ -z "$MAIN" ] && [ -z "$MONO" ] && [ -z "$READING" ] && [ -z "$SCALE" ]; then
    [ -f "$CFG" ] || exit 0
    command -v jq >/dev/null 2>&1 || exit 0
    values=$(jq -er '(.appearance.fonts
        | (.main, .monospace, .reading) | if . == null or . == false then "" else tostring | gsub("\n"; " ") end),
        (.appearance.appFontScale | if type == "number" then . else 1 end)' "$CFG" 2>/dev/null) || exit 1
    { IFS= read -r MAIN; IFS= read -r MONO; IFS= read -r READING; IFS= read -r SCALE; } <<<"$values"
fi
if [ -z "$SCALE" ] && [ -f "$CFG" ] && command -v jq >/dev/null 2>&1; then
    SCALE=$(jq -r '.appearance.appFontScale | if type == "number" then . else 1 end' "$CFG" 2>/dev/null)
fi
SCALE=$(awk -v s="${SCALE:-1}" 'BEGIN { s += 0; if (s < 0.8) s = 0.8; if (s > 2) s = 2; printf "%.2f", s }')

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
    # Text size for GTK apps, and for Firefox, which follows this key.
    NOW_SCALE=$(gsettings get org.gnome.desktop.interface text-scaling-factor 2>/dev/null)
    awk -v a="${NOW_SCALE:-1}" -v b="$SCALE" 'BEGIN { exit !((a - b) ^ 2 > 0.0001) }' \
        && gsettings set org.gnome.desktop.interface text-scaling-factor "$SCALE" 2>/dev/null || true
fi

# Qt apps read point sizes from qt6ct, with no factor of their own. Each size's base is kept beside
# the scale, and taken afresh only from a size set by hand, so moving the slider never drifts it.
# A size back at its base, as when setup puts the stock file back, gets the scale again.
QTCT="${XDG_CONFIG_HOME:-$HOME/.config}/qt6ct/qt6ct.conf"
QTMARK="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/qt-text-scale"
{ read -r PREV_SCALE PREV_BASES < "$QTMARK"; } 2>/dev/null
PREV_SCALE=${PREV_SCALE:-1.00}
# Written through a temp file of its own, and the marker only moves once the config it describes is on disk.
if [ -f "$QTCT" ] && QTTMP=$(mktemp "$QTCT.XXXXXX"); then
    BASES=$(awk -v prev="$PREV_SCALE" -v scale="$SCALE" -v known="${PREV_BASES:-}" -v out="$QTTMP" '
        BEGIN { n = split(known, kv, ","); for (i = 1; i <= n; i++) { split(kv[i], p, "="); base[p[1]] = p[2] } }
        /^\[/ { fonts = ($0 == "[Fonts]") }
        fonts && match($0, /^(general|fixed)="[^,]*,[0-9]+,/) {
            key = substr($0, 1, index($0, "=") - 1)
            n = split($0, parts, ",")
            size = parts[2] + 0
            b = (key in base && (int(base[key] * prev + 0.5) == size || base[key] == size)) ? base[key] : int(size / prev + 0.5)
            size = int(b * scale + 0.5); if (size < 6) size = 6
            parts[2] = size
            line = parts[1]; for (i = 2; i <= n; i++) line = line "," parts[i]
            print line > out
            kept = kept (kept == "" ? "" : ",") key "=" b
            next
        }
        { print > out }
        END { print kept }' "$QTCT") \
        && { cmp -s "$QTCT" "$QTTMP" || { chmod --reference="$QTCT" "$QTTMP" 2>/dev/null; mv -f "$QTTMP" "$QTCT"; }; } \
        && { [ "$PREV_SCALE ${PREV_BASES:-}" = "$SCALE $BASES" ] \
            || { mkdir -p "$(dirname "$QTMARK")" && printf '%s %s\n' "$SCALE" "$BASES" > "$QTMARK"; }; }
    rm -f "$QTTMP"
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

# Hyprtoolkit (hyprland-share-picker) — keep UI fonts in sync with shell fonts
HTCFG="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprtoolkit.conf"
if [ -f "$HTCFG" ]; then
    [ -n "$MAIN" ] && sed -i "s|^font_family =.*|font_family = $MAIN|" "$HTCFG"
    [ -n "$MONO" ] && sed -i "s|^font_family_monospace =.*|font_family_monospace = $MONO|" "$HTCFG"
fi

# Keep the matugen template in sync so wallpaper/color switches preserve the font
for tmpl in "${XDG_CONFIG_HOME:-$HOME/.config}/matugen/templates/hyprland/hyprtoolkit.conf"; do
    if [ -f "$tmpl" ]; then
        [ -n "$MAIN" ] && sed -i "s|^font_family =.*|font_family = $MAIN|" "$tmpl"
        [ -n "$MONO" ] && sed -i "s|^font_family_monospace =.*|font_family_monospace = $MONO|" "$tmpl"
    fi
done

exit 0
