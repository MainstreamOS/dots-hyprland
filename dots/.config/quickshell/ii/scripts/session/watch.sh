#!/usr/bin/env bash
# Thin gate for session/session.py watch — the resident capturer that keeps
# last.json current so an ungraceful exit still restores. Exists so the
# config-disabled path costs one jq read instead of a python process that
# would sit resident doing nothing.
set -uo pipefail

CONFIG="$HOME/.config/illogical-impulse/config.json"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/sessions"
log() { mkdir -p "$LOG_DIR"; printf '[%s] %s\n' "$(date -Iseconds)" "$*" >> "$LOG_DIR/session.log"; }

if [[ -f "$CONFIG" ]] && command -v jq >/dev/null 2>&1; then
    enabled=$(jq -r '.session.restoreEnabled // false' "$CONFIG" 2>/dev/null)
    if [[ "$enabled" != "true" ]]; then
        log "watch: disabled — skipping"
        exit 0
    fi
fi

if ! command -v python3 >/dev/null 2>&1; then
    log "watch: python3 missing — aborting"
    exit 1
fi

exec python3 "$DIR/session.py" watch "$@"
