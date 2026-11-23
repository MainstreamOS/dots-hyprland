#!/usr/bin/env bash
# Keeps a window in view while the screens change.
#   window-in-view.sh <pid of the window's app>
#
# An output that is turned off, or starts duplicating another, hands its workspaces to a
# screen that goes on showing its own, so the window that asked for the change ends up on a
# workspace no screen shows. For a few seconds this shows that workspace again each time the
# set of screens changes. A window already in view is left alone, as focusing moves the pointer.
set -uo pipefail

pid="${1:?}"
screens_before=""
checks=0
for _ in $(seq 40); do
    sleep 0.2
    monitors=$(hyprctl monitors all -j 2>/dev/null) || continue
    screens=$(jq -c 'map([.name, .disabled, .mirrorOf])' <<<"$monitors" 2>/dev/null) || continue
    # Workspaces can move a moment after the screens do, so each change is followed for a second.
    if [[ "$screens" != "$screens_before" ]]; then
        screens_before=$screens
        checks=5
    fi
    ((checks-- > 0)) || continue
    # By name, as a special workspace has no id here.
    workspace=$(hyprctl clients -j 2>/dev/null \
        | jq -r --argjson pid "$pid" 'first(.[] | select(.pid == $pid) | .workspace.name // empty)' 2>/dev/null) || continue
    [[ -n "$workspace" ]] || continue
    jq -e --arg ws "$workspace" 'any(.[]; .disabled != true and (.mirrorOf // "none") == "none"
        and (.activeWorkspace.name == $ws or .specialWorkspace.name == $ws))' <<<"$monitors" >/dev/null 2>&1 && continue
    hyprctl dispatch "hl.dsp.focus({ window = \"pid:$pid\" })" >/dev/null 2>&1 || true
done
