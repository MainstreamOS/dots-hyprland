#!/usr/bin/env bash
# Maps matugen's primary color to the nearest Papirus folder color.
set -eu
COLORS_JSON="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/colors.json"
THEME="Papirus-Dark"

command -v papirus-folders >/dev/null || exit 0
[ -f "$COLORS_JSON" ] || exit 0

hex=$(jq -r '.. | objects | .primary? // empty' "$COLORS_JSON" | head -n1 | tr -d '#')
[ -n "$hex" ] || exit 0

r=$((16#${hex:0:2})); g=$((16#${hex:2:2})); b=$((16#${hex:4:2}))

declare -A P=(
  [red]="229 57 53"       [pink]="216 27 96"       [violet]="142 36 170"
  [indigo]="57 73 171"    [blue]="30 136 229"      [cyan]="0 172 193"
  [teal]="0 137 123"      [green]="67 160 71"      [yellow]="253 216 53"
  [orange]="251 140 0"    [deeporange]="244 81 30" [brown]="109 76 65"
  [grey]="117 117 117"    [bluegrey]="84 110 122"  [black]="48 48 48"
  [nordic]="129 161 193"  [magenta]="211 47 103"
)

best="blue"; bestd=99999999
for name in "${!P[@]}"; do
  read -r pr pg pb <<<"${P[$name]}"
  d=$(( (r-pr)*(r-pr) + (g-pg)*(g-pg) + (b-pb)*(b-pb) ))
  (( d < bestd )) && bestd=$d && best=$name
done

papirus-folders -C "$best" -t "$THEME" >/dev/null 2>&1 || true
