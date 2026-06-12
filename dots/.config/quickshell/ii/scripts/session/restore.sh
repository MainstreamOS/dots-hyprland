#!/usr/bin/env bash
# Thin gate for session/session.py restore. Exists so the config-disabled
# path costs one jq read instead of python startup, and so the file path
# called by hypr/custom/execs.lua stays stable across implementations.
# --force bypasses the gate (manual triggers).
set -uo pipefail

CONFIG="$HOME/.config/illogical-impulse/config.json"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/sessions"
log() { mkdir -p "$LOG_DIR"; printf '[%s] %s\n' "$(date -Iseconds)" "$*" >> "$LOG_DIR/session.log"; }

force=0
for arg in "$@"; do
    [[ "$arg" == "--force" ]] && force=1
done

if [[ $force -eq 0 ]] && [[ -f "$CONFIG" ]] && command -v jq >/dev/null 2>&1; then
    enabled=$(jq -r '.session.restoreEnabled // false' "$CONFIG" 2>/dev/null)
    if [[ "$enabled" != "true" ]]; then
        log "restore: disabled — skipping"
        exit 0
    fi
fi

if ! command -v python3 >/dev/null 2>&1; then
    log "restore: python3 missing — aborting"
    exit 1
fi

exec python3 "$DIR/session.py" restore "$@"
