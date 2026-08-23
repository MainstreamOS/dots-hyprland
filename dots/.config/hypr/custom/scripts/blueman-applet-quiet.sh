#!/usr/bin/env bash
# Starts blueman-applet for the session, with its tray item switched off.

pgrep -x blueman-applet >/dev/null 2>&1 && exit 0

# Hide only the tray item — the agent and the rest of the applet stay. Left
# alone once the plugin list mentions StatusNotifierItem at all, in either
# direction: that is the user's own answer, given through blueman's plugin
# dialog, and it outranks ours.
if command -v gsettings >/dev/null 2>&1; then
    if ! gsettings get org.blueman.general plugin-list 2>/dev/null | grep -q "StatusNotifierItem"; then
        new=$(python3 - <<'PY'
import ast, subprocess
cur = subprocess.run(["gsettings", "get", "org.blueman.general", "plugin-list"],
                     capture_output=True, text=True).stdout.strip()
try:
    lst = ast.literal_eval(cur) if cur else []
except (ValueError, SyntaxError):
    lst = []
print(str(list(lst) + ["!StatusNotifierItem"]))
PY
        ) && gsettings set org.blueman.general plugin-list "$new" || true
    fi
fi

exec blueman-applet
