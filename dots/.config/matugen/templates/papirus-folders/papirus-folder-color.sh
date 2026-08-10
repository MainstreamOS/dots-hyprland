#!/usr/bin/env bash
set -u

# Rebuilding the folder icons takes about two thirds of a second, and matugen
# waits for whatever it is told to run afterwards -- so this used to sit in the
# middle of every wallpaper change and every theme apply, ahead of the colours
# the desktop was waiting for. Nothing needs the icons to be ready before the
# rest of the change lands, so the first invocation hands the work to a detached
# copy of itself and returns. Descriptors 8 and 9 carry locks belonging to
# whoever started the chain; the copy closes them so it can't outlive its own
# run and stall the next one.
if [ -z "${PAPIRUS_FOLDER_DETACHED:-}" ] && command -v setsid >/dev/null 2>&1; then
    PAPIRUS_FOLDER_DETACHED=1 setsid bash "$0" >/dev/null 2>&1 </dev/null 8>&- 9>&- &
    exit 0
fi

folder_color="${PAPIRUS_FOLDER_COLOR:-}"
source_hex="${PAPIRUS_SOURCE_HEX:-}"
theme_name="${PAPIRUS_MATUGEN_THEME:-Papirus-Matugen}"
theme_dir="${XDG_DATA_HOME:-$HOME/.local/share}/icons/$theme_name"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/matugen"
state_file="$state_dir/papirus-folder-color"
pending_file="$state_file.pending"

mkdir -p "$state_dir"

[ -n "$source_hex" ] || source_hex="{{ colors.source_color.default.hex }}"
[ -n "$source_hex" ] || source_hex="{{ colors.primary.default.hex }}"

source_hex="${source_hex#\#}"
case "$source_hex" in
  ??????) ;;
  *)
    source_hex="5294e2"
    ;;
esac

if [ -z "$folder_color" ]; then
  if command -v python3 >/dev/null 2>&1; then
    folder_color="$(python3 - "$source_hex" <<'PY'
import colorsys
import sys

source = sys.argv[1]
palette = {
    "adwaita": "#3a87e5",
    "black": "#3f3f3f",
    "blue": "#4877b1",
    "bluegrey": "#4d646f",
    "breeze": "#147eb8",
    "brown": "#957552",
    "carmine": "#7a0002",
    "cyan": "#0096aa",
    "darkcyan": "#35818a",
    "deeporange": "#e95420",
    "green": "#60924b",
    "grey": "#727272",
    "indigo": "#3f51b5",
    "magenta": "#b259b8",
    "nordic": "#5e81ac",
    "orange": "#dd772f",
    "palebrown": "#bea389",
    "paleorange": "#c89e6b",
    "pink": "#ec407a",
    "red": "#bf4b4b",
    "teal": "#12806a",
    "violet": "#5d399b",
    "white": "#cccccc",
    "yaru": "#973552",
    "yellow": "#e19d00",
}

def rgb(hex_value):
    hex_value = hex_value.lstrip("#")
    return tuple(int(hex_value[index:index + 2], 16) / 255 for index in (0, 2, 4))

source_hsv = colorsys.rgb_to_hsv(*rgb(source))
if source_hsv[1] < 0.08:
    print("white" if source_hsv[2] > 0.70 else "grey" if source_hsv[2] > 0.35 else "black")
    raise SystemExit

def score(hex_value):
    hsv = colorsys.rgb_to_hsv(*rgb(hex_value))
    hue_distance = min(abs(source_hsv[0] - hsv[0]), 1 - abs(source_hsv[0] - hsv[0]))
    saturation_distance = abs(source_hsv[1] - hsv[1])
    value_distance = abs(source_hsv[2] - hsv[2])
    return hue_distance * 5 + saturation_distance * 0.75 + value_distance * 0.2

print(min(palette, key=lambda name: score(palette[name])))
PY
)"
  fi

  if [ -z "$folder_color" ]; then
    r=$((16#${source_hex:0:2}))
    g=$((16#${source_hex:2:2}))
    b=$((16#${source_hex:4:2}))
    best="blue"
    bestd=99999999

    while read -r name pr pg pb; do
      d=$(( (r - pr) * (r - pr) + (g - pg) * (g - pg) + (b - pb) * (b - pb) ))
      if [ "$d" -lt "$bestd" ]; then
        bestd="$d"
        best="$name"
      fi
    done <<'COLORS'
red 191 75 75
yellow 225 157 0
green 96 146 75
teal 18 128 106
cyan 0 150 170
blue 72 119 177
indigo 63 81 181
violet 93 57 155
magenta 178 89 184
pink 236 64 122
orange 221 119 47
deeporange 233 84 32
brown 149 117 82
grey 114 114 114
bluegrey 77 100 111
carmine 122 0 2
black 63 63 63
COLORS

    folder_color="$best"
  fi
fi

case "$folder_color" in
  adwaita|black|blue|bluegrey|breeze|brown|carmine|cyan|darkcyan|deeporange|green|grey|indigo|magenta|nordic|orange|palebrown|paleorange|pink|red|teal|violet|white|yaru|yellow) ;;
  *)
    folder_color="blue"
    ;;
esac

current_theme=""
if command -v gsettings >/dev/null 2>&1; then
  current_theme="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")"
fi

base_theme="${PAPIRUS_MATUGEN_BASE_THEME:-}"
if [ -z "$base_theme" ]; then
  case "$current_theme" in
    # A Papirus variant the user chose themselves is the base to layer on.
    Papirus-Dark|Papirus-Dark-Matugen) base_theme="Papirus-Dark" ;;
    Papirus-Light|Papirus-Light-Matugen) base_theme="Papirus-Light" ;;
    Papirus) base_theme="Papirus" ;;
    # Anything else, including this script's own generated theme, says nothing
    # about light or dark: only */places is overridden here, so the base decides
    # every other icon on the desktop and it has to follow the colour scheme.
    *)
      scheme=""
      if command -v gsettings >/dev/null 2>&1; then
        scheme="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")"
      fi
      case "$scheme" in
        prefer-light) base_theme="Papirus-Light" ;;
        *) base_theme="Papirus-Dark" ;;
      esac
      ;;
  esac
fi

if [ ! -d "/usr/share/icons/$base_theme" ]; then
  for candidate in Papirus-Dark Papirus Papirus-Light; do
    [ -d "/usr/share/icons/$candidate" ] && { base_theme="$candidate"; break; }
  done
fi

# Only */places is overridden here and everything else is inherited, so without
# a base on disk the published theme resolves to bare hicolor — every icon on
# the desktop, not just the folders. Nothing to layer on means nothing to
# publish, and the icon theme already in use is left alone.
if [ ! -d "/usr/share/icons/$base_theme" ]; then
  exit 0
fi

# The icon set depends only on which of the seventeen folder colours was
# picked and which Papirus variant it is layered over. Wallpapers that land on
# the same colour -- most of a light or dark theme's neighbours do -- would
# otherwise delete and relink four hundred icons to produce byte-identical
# output, and flip the icon theme away and back, making every open application
# reload its icons for nothing.
#
# What is on disk decides this, not what an earlier run said it was going to do.
# The note records an intention, and a run that died partway through leaves one
# it never carried out, along with the marker written across the rebuild; asking
# for the same colour again is exactly when nothing else would notice. -ef
# compares what the links resolve to and forks nothing, which matters because
# the no-op this guards is on the path of every wallpaper change.
#
# An alias is checked alongside folder.svg. The links are laid down one at a
# time, and nothing serialises two rebuilds, so a directory can hold the newer
# folder.svg over aliases from the older colour; sampling only folder.svg reads
# that as finished and it stays mixed for as long as the colour does.
icons_current=1
for size in 16x16 22x22 24x24 32x32 48x48 64x64; do
  source_dir="/usr/share/icons/$base_theme/$size/places"
  [ -d "$source_dir" ] || source_dir="/usr/share/icons/Papirus/$size/places"
  [ -e "$source_dir/folder-$folder_color.svg" ] || continue
  [ "$theme_dir/$size/places/folder.svg" -ef "$source_dir/folder-$folder_color.svg" ] || {
    icons_current=0
    break
  }
  if [ -e "$source_dir/folder-$folder_color-documents.svg" ] \
     && [ ! "$theme_dir/$size/places/folder-documents.svg" -ef "$source_dir/folder-$folder_color-documents.svg" ]; then
    icons_current=0
    break
  fi
done

if [ ! -e "$pending_file" ] \
   && [ "$icons_current" = "1" ] \
   && [ "$folder_color" = "$(cat "$state_file" 2>/dev/null)" ] \
   && [ "$base_theme" = "$(cat "$state_file.base" 2>/dev/null)" ] \
   && [ -f "$theme_dir/index.theme" ]; then
    exit 0
fi

mkdir -p "$theme_dir"
: > "$pending_file"

cat > "$theme_dir/index.theme" <<EOF
[Icon Theme]
Name=$theme_name
Comment=Papirus folder color overlay generated by matugen
Inherits=$base_theme,hicolor
Example=folder
FollowsColorScheme=true
Directories=16x16/places,22x22/places,24x24/places,32x32/places,48x48/places,64x64/places

[16x16/places]
Context=Places
Size=16
Type=Fixed

[22x22/places]
Context=Places
Size=22
Type=Fixed

[24x24/places]
Context=Places
Size=24
Type=Fixed

[32x32/places]
Context=Places
Size=32
Type=Fixed

[48x48/places]
Context=Places
Size=48
Type=Fixed

[64x64/places]
Context=Places
Size=64
Type=Fixed
EOF

for size in 16x16 22x22 24x24 32x32 48x48 64x64; do
  target_dir="$theme_dir/$size/places"
  source_dir="/usr/share/icons/$base_theme/$size/places"
  [ -d "$source_dir" ] || source_dir="/usr/share/icons/Papirus/$size/places"
  [ -d "$source_dir" ] || continue

  rm -rf "$target_dir"
  mkdir -p "$target_dir"

  for icon in "$source_dir"/folder-"$folder_color"*.svg; do
    [ -e "$icon" ] || continue
    name="$(basename "$icon")"
    case "$name" in
      folder-"$folder_color".svg) alias="folder.svg" ;;
      folder-"$folder_color"-*) alias="folder-${name#folder-$folder_color-}" ;;
      *) continue ;;
    esac
    ln -sf "$icon" "$target_dir/$alias"
  done

  for icon in "$source_dir"/user-"$folder_color"-*.svg; do
    [ -e "$icon" ] || continue
    name="$(basename "$icon")"
    ln -sf "$icon" "$target_dir/user-${name#user-$folder_color-}"
  done
done

# Recorded once the icon set on disk is the colour being recorded, so a run that
# dies partway through is never mistaken for a finished one.
printf '%s\n' "$folder_color" > "$state_file"
printf '%s\n' "$base_theme" > "$state_file.base"
rm -f "$pending_file"

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -f -t "$theme_dir" >/dev/null 2>&1 || true
fi

# Respect a manually chosen non-Papirus icon theme (Settings > Themes >
# System look): keep generating the recolored set, but don't switch to it.
apply_icon_theme=1
case "$current_theme" in
  ""|Papirus*|papirus*) ;;
  *) apply_icon_theme=0 ;;
esac

if [ "$apply_icon_theme" = "1" ] && command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface icon-theme "$base_theme" >/dev/null 2>&1 || true
  gsettings set org.gnome.desktop.interface icon-theme "$theme_name" >/dev/null 2>&1 || true
fi

if [ "$apply_icon_theme" = "1" ]; then
  for qtconf in "$HOME/.config/qt6ct/qt6ct.conf" "$HOME/.config/qt5ct/qt5ct.conf"; do
    [ -f "$qtconf" ] && sed -i "s/^icon_theme=.*/icon_theme=$theme_name/" "$qtconf" 2>/dev/null || true
  done
fi

if [ "$apply_icon_theme" = "1" ] && command -v kwriteconfig6 >/dev/null 2>&1; then
  kwriteconfig6 --file kdeglobals --group Icons --key Theme "$theme_name" >/dev/null 2>&1 || true
elif command -v kwriteconfig5 >/dev/null 2>&1; then
  kwriteconfig5 --file kdeglobals --group Icons --key Theme "$theme_name" >/dev/null 2>&1 || true
fi

if command -v qdbus6 >/dev/null 2>&1; then
  qdbus6 org.kde.KGlobalSettings /KGlobalSettings notifyChange 4 0 >/dev/null 2>&1 || true
elif command -v qdbus >/dev/null 2>&1; then
  qdbus org.kde.KGlobalSettings /KGlobalSettings notifyChange 4 0 >/dev/null 2>&1 || true
fi
