#!/usr/bin/env python3
# =============================================================================
# session/restore.py
#
# Replays the snapshot written by session/snapshot.sh. For each captured
# window, spawns its command via Hyprland's Lua exec-with-rules dispatch:
#
#     hl.dsp.exec_cmd("cmd args", { workspace = "3 silent", float = true, ... })
#
# Hyprland registers the rules BEFORE the next window from this exec maps,
# so placement happens at window-creation time — no race with our own
# dispatcher. This is the same path the overview's drag-to-workspace uses
# (modules/ii/overview/Overview.qml:323), and it's far more reliable than
# the earlier "spawn, watch openwindow events, dispatch movetoworkspacesilent
# after the fact" approach which lost races against apps' own session-
# restore opening more windows than expected.
#
# Userspace stand-in for xdg-session-management-v1 — when Hyprland
# implements that protocol the per-window state restore handled here will
# move into the compositor; the snapshot/relaunch coordination stays
# useful because the protocol doesn't relaunch processes.
# =============================================================================
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "quickshell/sessions"
SNAPSHOT_PATH = STATE_DIR / "last.json"
LOG_PATH = STATE_DIR / "restore.log"
CONFIG_PATH = Path.home() / ".config/illogical-impulse/config.json"

SPAWN_STAGGER_MS = int(os.environ.get("SESSION_SPAWN_STAGGER_MS", "150"))


def log(msg: str) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    line = f"[{datetime.now(timezone.utc).astimezone().isoformat(timespec='seconds')}] {msg}\n"
    with LOG_PATH.open("a") as f:
        f.write(line)


def config_enabled() -> bool:
    if not CONFIG_PATH.is_file():
        return False
    try:
        with CONFIG_PATH.open() as f:
            cfg = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        log(f"config read failed: {e}")
        return False
    return bool(cfg.get("session", {}).get("restoreEnabled", False))


def hyprctl(*args: str, json_out: bool = False):
    cmd = ["hyprctl"]
    if json_out:
        cmd.append("-j")
    cmd.extend(args)
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired) as e:
        log(f"hyprctl {' '.join(args)} failed: {e}")
        return None
    if result.returncode != 0:
        log(f"hyprctl {' '.join(args)} exit {result.returncode}: {result.stderr.strip()}")
        return None
    if json_out:
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return None
    return result.stdout


def quote_arg(part: str) -> str:
    """Shell-quote a single argv element for joining into one command line."""
    if not part:
        return '""'
    # If it contains spaces, quotes, or shell metacharacters, wrap in double
    # quotes and escape internal quotes/backslashes.
    if any(c in part for c in ' \t\n"\\$`'):
        escaped = part.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    return part


def cmd_to_shell_string(parts: list[str]) -> str:
    return " ".join(quote_arg(p) for p in parts)


def lua_escape(s: str) -> str:
    """Escape backslashes first, then double-quotes — order matters."""
    return s.replace("\\", "\\\\").replace('"', '\\"')


def build_rules_table(window: dict) -> str:
    """Build the second argument to hl.dsp.exec_cmd — a Lua table literal."""
    rules: list[str] = []

    ws = window.get("workspaceId")
    # Normal workspace IDs are >= 1. Special workspaces have negative IDs
    # and aren't restored here — they need name-based dispatch.
    if isinstance(ws, int) and ws >= 1:
        rules.append(f'workspace = "{ws} silent"')

    if window.get("floating"):
        rules.append("float = true")
        at = window.get("at") or []
        size = window.get("size") or []
        if len(at) == 2:
            rules.append(f'move = "{int(at[0])} {int(at[1])}"')
        if len(size) == 2:
            rules.append(f'size = "{int(size[0])} {int(size[1])}"')

    if window.get("pinned"):
        rules.append("pin = true")

    # Hyprland fullscreen state: 0 none, 1 maximize, 2 fullscreen, 3 both.
    # The exec rule only exposes a bool — restore non-zero states as
    # fullscreen=true and let the user retoggle for the precise mode if it
    # matters. Worth revisiting once exec rules grow a fullscreenstate key.
    fs = window.get("fullscreen") or 0
    if isinstance(fs, int) and fs > 0:
        rules.append("fullscreen = true")

    return "{ " + ", ".join(rules) + " }" if rules else "{}"


def spawn_with_rules(window: dict) -> bool:
    cmdline = window.get("cmdline") or []
    if not cmdline:
        return False
    cmd_str = cmd_to_shell_string(cmdline)
    escaped = lua_escape(cmd_str)
    rules = build_rules_table(window)
    expr = f'hl.dsp.exec_cmd("{escaped}", {rules})'
    # `hyprctl dispatch <ARG>` evaluates ARG as Lua (Hyprland 0.55+). The
    # legacy hyprlang inline-rule form `[workspace N silent] cmd` was
    # removed when the Lua config landed.
    result = hyprctl("dispatch", expr)
    if result is None:
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="Replay session snapshot.")
    parser.add_argument("--force", action="store_true",
                        help="bypass Config.options.session.restoreEnabled gate")
    args = parser.parse_args()

    if not args.force and not config_enabled():
        log("session restore disabled — skipping")
        return 0

    if not SNAPSHOT_PATH.is_file():
        log(f"no snapshot at {SNAPSHOT_PATH}")
        return 0

    try:
        with SNAPSHOT_PATH.open() as f:
            snapshot = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        log(f"snapshot read failed: {e}")
        return 1

    # Skip classes that are already mapped — assume user is intentionally
    # resuming an existing session (e.g. mid-session compositor restart).
    existing = {c.get("class", "") for c in (hyprctl("clients", json_out=True) or [])}

    pending: list[dict] = []
    for w in snapshot.get("windows", []):
        cls = w.get("class", "")
        if not cls or not w.get("cmdline"):
            continue
        if cls in existing:
            log(f"skip {cls} — already mapped")
            continue
        pending.append(w)

    if not pending:
        log("nothing to restore (all classes already running)")
        return 0
    log(f"restoring {len(pending)} windows via hl.dsp.exec_cmd with attached rules")

    # Fire one exec per pending entry, each carrying its own workspace +
    # floating + size + pin + fullscreen rules. Unlike the previous
    # dedup-by-cmdline approach, multiple entries for the same app (e.g.
    # three Zen windows on different workspaces) each get their own exec
    # with the correct workspace. Apps that join an existing process may
    # still consolidate, but at minimum every distinct target workspace
    # gets one rule registered.
    stagger_s = SPAWN_STAGGER_MS / 1000.0
    dispatched = 0
    for w in pending:
        if spawn_with_rules(w):
            dispatched += 1
            ws = w.get("workspaceId", "?")
            log(f"dispatched {w['class']} → ws={ws}")
        else:
            log(f"dispatch failed for {w['class']}")
        time.sleep(stagger_s)

    log(f"restore complete: {dispatched}/{len(pending)} dispatched")
    return 0


if __name__ == "__main__":
    sys.exit(main())
