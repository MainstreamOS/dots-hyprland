#!/usr/bin/env bash
# =============================================================================
# session/restore.sh
#
# Thin shim around session/restore.py. Two reasons it exists as bash:
#
#   1. Fast-path the config-disabled case so we don't pay python startup
#      cost (~30ms) on every Hyprland start for users who haven't opted in.
#   2. Preserves the file path that hypr/custom/execs.lua and
#      Session.qml's snapshotProc call — no churn there when we switched
#      the implementation from socat-bash to python.
#
# All arguments are forwarded to restore.py (notably --force, used by
# manual triggers that should bypass the config gate).
# =============================================================================
set -uo pipefail

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/sessions"
LOG="$SNAPSHOT_DIR/restore.log"

mkdir -p "$SNAPSHOT_DIR"

# --force bypasses the config gate; otherwise read it and short-circuit.
force=0
for arg in "$@"; do
    [[ "$arg" == "--force" ]] && force=1
done

if [[ $force -eq 0 ]] && [[ -f "$CONFIG_FILE" ]] && command -v jq >/dev/null 2>&1; then
    enabled=$(jq -r '.session.restoreEnabled // false' "$CONFIG_FILE" 2>/dev/null)
    if [[ "$enabled" != "true" ]]; then
        printf '[%s] session restore disabled — skipping\n' "$(date -Iseconds)" >> "$LOG"
        exit 0
    fi
fi

if ! command -v python3 >/dev/null 2>&1; then
    printf '[%s] python3 missing — aborting\n' "$(date -Iseconds)" >> "$LOG"
    exit 1
fi

exec python3 "$SCRIPT_DIR/restore.py" "$@"
