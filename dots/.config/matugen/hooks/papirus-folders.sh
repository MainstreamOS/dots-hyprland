#!/usr/bin/env bash
set -u

generated="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/papirus-folder-color.sh"

if [ -f "$generated" ]; then
  bash "$generated"
  exit 0
fi

colors_json="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/colors.json"
if [ ! -f "$colors_json" ]; then
  exit 0
fi

hex=""
if command -v jq >/dev/null 2>&1; then
  hex="$(jq -r '.source_color // .primary // empty' "$colors_json" | tr -d '#')"
fi

case "$hex" in
  ??????) ;;
  *) exit 0 ;;
esac

r=$((16#${hex:0:2}))
g=$((16#${hex:2:2}))
b=$((16#${hex:4:2}))

best="blue"
bestd=99999999

while read -r name pr pg pb; do
  d=$(( (r - pr) * (r - pr) + (g - pg) * (g - pg) + (b - pb) * (b - pb) ))
  if [ "$d" -lt "$bestd" ]; then
    bestd="$d"
    best="$name"
  fi
done <<'COLORS'
red 226 82 82
yellow 249 189 48
green 135 177 88
teal 22 160 133
cyan 0 188 212
blue 82 148 226
indigo 92 107 192
violet 126 87 194
magenta 202 113 223
pink 240 98 146
orange 238 146 58
deeporange 235 102 55
brown 174 142 108
grey 142 142 142
bluegrey 96 125 139
carmine 163 0 2
black 79 79 79
COLORS

PAPIRUS_FOLDER_COLOR="$best" PAPIRUS_SOURCE_HEX="#$hex" bash "$HOME/.config/matugen/templates/papirus-folders/papirus-folder-color.sh"
