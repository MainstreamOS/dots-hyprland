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

# Day/Night Themes picks the theme itself, and the Themes page holds its Apply
# buttons back while it does; a switch from here would be undone at the next
# boundary, and would leave the schedule believing its own pick was on.
SCHEDULE="$(jq -r '.appearance.themeSchedule.mode // "off"' "$XDG_CONFIG_HOME/illogical-impulse/config.json" 2>/dev/null || true)"
if [ -n "$SCHEDULE" ] && [ "$SCHEDULE" != "off" ]; then
    notify 'Day/Night Themes is choosing your theme. Turn it off in Settings to switch by hand.'
    exit 0
fi

# The index is a record of what was saved, not of what is there now: a theme
# folder removed any other way stays listed, and landing on it would stop the
# cycle there for good, since a failed apply never moves the marker on.
mapfile -t SLUGS < <(cd "$THEMES_DIR" 2>/dev/null && jq -r '.[].slug // empty' index.json 2>/dev/null \
    | while IFS= read -r s; do [ -n "$s" ] && [ -d "$s" ] && printf '%s\n' "$s"; done || true)
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
# Through the shell, which cancels an apply already running rather than
# queueing behind it, repaints once the colours land, and says so when a theme
# fails. Straight to the script only when no shell is there to ask.
qs -c "${qsConfig:-ii}" ipc call themes apply "$NEXT" >/dev/null 2>&1 \
    || exec bash "$SCRIPT_DIR/apply-theme.sh" "$NEXT"
