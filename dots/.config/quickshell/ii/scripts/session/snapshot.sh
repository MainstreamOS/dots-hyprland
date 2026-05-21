#!/usr/bin/env bash
# =============================================================================
# session/snapshot.sh
#
# Captures the current set of mapped Hyprland toplevels and writes a JSON
# snapshot at $XDG_STATE_HOME/quickshell/sessions/last.json. Read by
# session/restore.sh on next Hyprland start.
#
# Intended trigger: hl.on("hyprland.shutdown", ...) in hypr/custom/execs.lua,
# so the snapshot reflects the windows the user actually had open at logout.
#
# Userspace stand-in for xdg-session-management-v1 — that wayland-protocols
# staging protocol isn't implemented in Hyprland 0.55 yet. When upstream
# lands it, the per-window geometry portion of restore.sh can drop; this
# snapshot/relaunch still has value because the protocol doesn't relaunch
# apps, only re-applies state to apps that have already mapped a toplevel.
#
# Skips:
#   * windows whose class starts with Quickshell (the shell relaunches itself)
#   * windows whose /proc/<pid>/cmdline is empty/unreadable
#
# The script is idempotent and silent on the no-op path (config off).
# =============================================================================
set -uo pipefail

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
SNAPSHOT_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/sessions"
SNAPSHOT_PATH="$SNAPSHOT_DIR/last.json"
LOG="$SNAPSHOT_DIR/snapshot.log"

mkdir -p "$SNAPSHOT_DIR"
log() { printf '[%s] %s\n' "$(date -Iseconds)" "$*" >> "$LOG"; }

# Clean up orphan tmps from prior crashed runs (SIGKILL bypasses the trap
# below, so they accumulate otherwise). Anything older than 1 minute and
# not the current target is fair game.
find "$SNAPSHOT_DIR" -maxdepth 1 -type f -name 'last.json.*' -mmin +1 -delete 2>/dev/null || true

# Gate: only run when Config.options.session.restoreEnabled is true.
if [[ -f "$CONFIG_FILE" ]] && command -v jq >/dev/null 2>&1; then
    enabled=$(jq -r '.session.restoreEnabled // false' "$CONFIG_FILE" 2>/dev/null)
    if [[ "$enabled" != "true" ]]; then
        log "session restore disabled — skipping snapshot"
        exit 0
    fi
fi

if ! command -v hyprctl >/dev/null 2>&1; then
    log "hyprctl unavailable — skipping"
    exit 0
fi

# `hyprctl clients -j` returns the per-window array. We filter + reshape via
# jq, then enrich with /proc/<pid>/cmdline (jq can't read /proc so a small
# python loop handles that). Race-safe write: tmp + mv.
tmp=$(mktemp "$SNAPSHOT_DIR/last.json.XXXXXX")
trap 'rm -f "$tmp"' EXIT

if ! hyprctl clients -j 2>/dev/null \
    | jq '[
        .[]
        | select(.class != null and .class != "")
        | select(.class | test("^[Qq]uickshell") | not)
        | {
            class,
            title,
            pid,
            workspaceId: (.workspace.id // -1),
            workspaceName: (.workspace.name // ""),
            monitor: (.monitor | tostring),
            at,
            size,
            floating,
            fullscreen,
            pinned
        }
    ]' > "$tmp"; then
    log "hyprctl clients failed — aborting"
    exit 1
fi

# Enrich with cmdline pulled from /proc. Skip entries where the cmdline
# is empty (kernel threads, exited PIDs).
python3 - "$tmp" "$SNAPSHOT_PATH" <<'PY' || { log "enrich failed"; exit 1; }
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    rows = json.load(f)
out = []
for w in rows:
    try:
        with open(f'/proc/{w["pid"]}/cmdline', 'rb') as f:
            parts = [p.decode('utf-8', 'replace') for p in f.read().split(b'\0') if p]
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        parts = []
    if not parts:
        continue
    w['cmdline'] = parts
    out.append(w)
import datetime
payload = {
    'version': 1,
    'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'windows': out,
}
tmp_out = dst + '.tmp'
with open(tmp_out, 'w') as f:
    json.dump(payload, f, indent=2)
import os
os.replace(tmp_out, dst)
print(f'wrote {len(out)} windows', file=sys.stderr)
PY

log "snapshot OK ($(jq '.windows | length' "$SNAPSHOT_PATH") windows)"
