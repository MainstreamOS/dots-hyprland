#!/usr/bin/env bash
# The layout that leads the login screen leads this session too. That is the
# pick made on the login screen, which the greeter's bridge records under /run,
# or otherwise the head of localed's list, which the last switch in the
# previous session left there. Runs once from the session's start hook.
set -uo pipefail

PICK=/run/mainstream-greeter/pick
X11_CONF=/etc/X11/xorg.conf.d/00-keyboard.conf
TOOL="$HOME/.config/quickshell/ii/scripts/keyboard/write-layouts.py"

# A pick belongs to the login screen that just ran. A session started by
# autologin, which is how Gaming Mode comes back to the desktop, had no login
# screen, so a pick older than the display manager's current start is stale.
dm_start=$(date -d "$(systemctl show sddm -p ActiveEnterTimestamp --value 2>/dev/null)" +%s 2>/dev/null || echo 0)
lead=""
if [[ -s "$PICK" ]] && (( $(stat -c %Y "$PICK" 2>/dev/null || echo 0) >= dm_start )); then
    IFS='|' read -r layout variant < "$PICK"
    lead="$layout:${variant:-}"
elif [[ -r "$X11_CONF" ]]; then
    layout=$(grep -oP 'Option\s+"XkbLayout"\s+"\K[^"]*' "$X11_CONF" | head -1 | cut -d, -f1)
    variant=$(grep -oP 'Option\s+"XkbVariant"\s+"\K[^"]*' "$X11_CONF" | head -1 | cut -d, -f1)
    [[ -n "$layout" ]] && lead="$layout:${variant:-}"
fi
[[ -n "$lead" ]] || exit 0
exec python3 "$TOOL" --from-hyprland --lead "$lead" --apply
