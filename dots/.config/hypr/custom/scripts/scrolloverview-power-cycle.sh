#!/usr/bin/env bash
# Hyprland 0.55 layer-shell input-dispatch workaround.
# Plugin-loading at config-parse time is async since the lua-config
# migration; PLUGIN_INIT can land mid-layer-shell-setup and wedge dock
# pointer dispatch. Unloading + reloading via hyprctl AFTER quickshell
# has registered its layers clears the wedge for the rest of the
# session. Log goes to ~/.local/state/scrolloverview-power-cycle.log.

set -uo pipefail

PLUGIN_PATH="$HOME/.local/share/hyprland/plugins/scrolloverview.so"
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/scrolloverview-power-cycle.log"
mkdir -p "$(dirname "$LOG")"

{
    echo "=== scrolloverview-power-cycle @ $(date -Is) ==="

    if [[ ! -f "$PLUGIN_PATH" ]]; then
        echo "plugin not found at $PLUGIN_PATH — exiting"
        exit 0
    fi

    # Poll up to 10 s at 50 ms intervals for any quickshell layer
    # namespace. We need to cycle AFTER the dock layer registers,
    # otherwise the wedge state just re-arms for it.
    deadline_ns=$(( $(date +%s%N) + 10000000000 ))
    detected=0
    while (( $(date +%s%N) < deadline_ns )); do
        if hyprctl layers 2>/dev/null \
            | grep -qiE 'namespace:[[:space:]]*(quickshell|qs[-_]|ii[-_])'
        then
            echo "[$(date +%T)] quickshell layer detected"
            detected=1
            break
        fi
        sleep 0.05
    done
    (( detected == 0 )) && echo "[$(date +%T)] WARN: no quickshell layer seen in 10s — cycling anyway"

    # Brief settle so a second layer registering in the same tick still
    # lands before we yank the plugin.
    sleep 0.2

    echo "[$(date +%T)] unloading $PLUGIN_PATH"
    hyprctl plugin unload "$PLUGIN_PATH" 2>&1 || echo "[$(date +%T)] WARN: unload non-zero"
    sleep 0.1
    echo "[$(date +%T)] loading $PLUGIN_PATH"
    hyprctl plugin load "$PLUGIN_PATH" 2>&1 || echo "[$(date +%T)] ERROR: load non-zero"

    echo "=== done @ $(date -Is) ==="
} >> "$LOG" 2>&1
