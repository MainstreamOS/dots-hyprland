#!/usr/bin/env bash
# Thin gate for session/session.py snapshot. Stable path for the
# hyprland.shutdown hook in hypr/custom/execs.lua and Session.qml's
# synchronous pre-power-action snapshotProc.
set -uo pipefail

CONFIG="$HOME/.config/illogical-impulse/config.json"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/sessions"
log() { mkdir -p "$LOG_DIR"; printf '[%s] %s\n' "$(date -Iseconds)" "$*" >> "$LOG_DIR/session.log"; }

if [[ -f "$CONFIG" ]] && command -v jq >/dev/null 2>&1; then
    enabled=$(jq -r '.session.restoreEnabled // false' "$CONFIG" 2>/dev/null)
    if [[ "$enabled" != "true" ]]; then
        log "snapshot: disabled — skipping"
        exit 0
    fi
fi

if ! command -v python3 >/dev/null 2>&1; then
    log "snapshot: python3 missing — aborting"
    exit 1
fi

exec python3 "$DIR/session.py" snapshot "$@"
