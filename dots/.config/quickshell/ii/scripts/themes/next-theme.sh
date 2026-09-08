#!/usr/bin/env bash
# next-theme.sh — apply the theme that follows the current one, wrapping round.
#
# The order is index.json's, which is the order the Themes page lists them in,
# so pressing the key walks the library the way the user sees it. apply-theme.sh
# is what records which theme is live, so its marker is what says where we are.
set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
THEMES_DIR="$XDG_CONFIG_HOME/mainstream/themes"
INDEX="$THEMES_DIR/index.json"
LAST_APPLIED="$THEMES_DIR/last-applied.txt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

notify() {
    command -v notify-send >/dev/null 2>&1 && notify-send 'Themes' "$1" -a 'Themes' || true
}

[ -r "$INDEX" ] || { notify 'No themes saved yet.'; exit 0; }

mapfile -t SLUGS < <(jq -r '.[].slug // empty' "$INDEX" 2>/dev/null || true)
COUNT=${#SLUGS[@]}
# One theme has nothing to switch to, and switching to itself would still cost
# a full re-apply.
[ "$COUNT" -gt 1 ] || { notify 'Save a second theme to switch between them.'; exit 0; }

CURRENT="$(cat "$LAST_APPLIED" 2>/dev/null || true)"
# A marker naming a theme that has since been deleted lands on the first one,
# which is also where a machine that has never applied one starts.
NEXT="${SLUGS[0]}"
for i in "${!SLUGS[@]}"; do
    if [ "${SLUGS[$i]}" = "$CURRENT" ]; then
        NEXT="${SLUGS[$(((i + 1) % COUNT))]}"
        break
    fi
done

NAME="$(jq -r --arg s "$NEXT" 'map(select(.slug == $s)) | .[0].name // $s' "$INDEX" 2>/dev/null || true)"
[ -n "$NAME" ] && [ "$NAME" != "null" ] || NAME="$NEXT"

notify "Switching to $NAME"
exec "$SCRIPT_DIR/apply-theme.sh" "$NEXT"
