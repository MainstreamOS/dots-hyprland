#!/usr/bin/env python3
# =============================================================================
# session/session.py — window-state snapshot + restore engine
#
# Userspace stand-in for xdg-session-management-v1: the protocol sits in
# wayland-protocols/staging but Hyprland 0.55 has no implementation yet.
# When upstream lands it, the per-window state portion of `restore` moves
# into the compositor; snapshot/relaunch stays useful because the protocol
# re-applies state to mapped toplevels — it doesn't relaunch processes.
#
#   session.py snapshot [--dry-run]
#       Captures mapped toplevels (class, cmdline, workspace, geometry)
#       into $XDG_STATE_HOME/quickshell/sessions/last.json. Flatpak
#       windows are detected via their app-flatpak-*.scope cgroup and
#       stored as `flatpak run <app-id>` — the sandbox-internal cmdline
#       in /proc is not spawnable from the host.
#
#   session.py restore [--force] [--dry-run]
#       Waits for the shell to PAINT first: polls the Hyprland socket
#       until the quickshell:bar layer surface exists (it is only created
#       once the shell's QML has fully loaded), settles briefly, then
#       replays each window via hl.dsp.exec_cmd with attached rules —
#       Hyprland registers the rules before the spawned window maps, so
#       placement happens at creation time. Without the paint gate the
#       replayed apps cold-start in parallel with the shell and starve
#       its first load (the cold-boot-only "slow populate").
#
# All compositor traffic goes over Hyprland's IPC socket directly — no
# hyprctl forks, no jq. The .sh shims exist only to gate the disabled
# case without paying python startup.
# =============================================================================
from __future__ import annotations

import argparse
import json
import os
import re
import socket
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "quickshell/sessions"
SNAPSHOT_PATH = STATE_DIR / "last.json"
LOG_PATH = STATE_DIR / "session.log"
CONFIG_PATH = Path.home() / ".config/illogical-impulse/config.json"

# Tunables. Env-only on purpose — not worth config-file surface.
STAGGER_MS = int(os.environ.get("QS_RESTORE_STAGGER_MS", "150"))
WAIT_TIMEOUT_S = float(os.environ.get("QS_RESTORE_WAIT_TIMEOUT", "20"))
SETTLE_MS = int(os.environ.get("QS_RESTORE_SETTLE_MS", "1200"))
# Prefix, not exact name: the bar layer is "quickshell:bar" in the default
# layout but other layouts (vertical bar) and surfaces (dock, background)
# differ — ANY quickshell:* layer means the shell finished loading QML and
# is creating windows, which is the readiness signal we need.
PAINT_PREFIX = os.environ.get("QS_RESTORE_PAINT_PREFIX", "quickshell")
LOG_MAX_BYTES = 64 * 1024
LOG_KEEP_LINES = 200


_log_ready = False


def log(tag: str, msg: str) -> None:
    # mkdir + rotation once per process, not per call — the restore dispatch
    # loop logs per window and doesn't need a stat() each time.
    global _log_ready
    if not _log_ready:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        try:
            if LOG_PATH.is_file() and LOG_PATH.stat().st_size > LOG_MAX_BYTES:
                tail = LOG_PATH.read_text(errors="replace").splitlines()[-LOG_KEEP_LINES:]
                LOG_PATH.write_text("\n".join(tail) + "\n")
        except OSError:
            pass
        _log_ready = True
    stamp = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")
    try:
        with LOG_PATH.open("a") as f:
            f.write(f"[{stamp}] {tag}: {msg}\n")
    except OSError:
        pass


def config_enabled() -> bool:
    if not CONFIG_PATH.is_file():
        return False
    try:
        with CONFIG_PATH.open() as f:
            cfg = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        log("config", f"read failed: {e}")
        return False
    return bool(cfg.get("session", {}).get("restoreEnabled", False))


# ── Hyprland IPC ─────────────────────────────────────────────────────────────

def _socket_path() -> Path | None:
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        return None
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    p = Path(runtime) / "hypr" / sig / ".socket.sock"
    return p if p.is_socket() else None


def hypr_request(payload: str, quiet: bool = False) -> str | None:
    """One request/reply on Hyprland's command socket (one-shot per connect)."""
    path = _socket_path()
    if path is None:
        if not quiet:
            log("ipc", "Hyprland socket not found — not inside a Hyprland session?")
        return None
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(5)
            s.connect(str(path))
            s.sendall(payload.encode())
            chunks = []
            while True:
                b = s.recv(65536)
                if not b:
                    break
                chunks.append(b)
            return b"".join(chunks).decode(errors="replace")
    except OSError as e:
        if not quiet:
            log("ipc", f"request failed: {e}")
        return None


def hypr_json(cmd: str, quiet: bool = False):
    out = hypr_request(f"j/{cmd}", quiet=quiet)
    if not out:
        return None
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        log("ipc", f"non-JSON reply for {cmd}: {out[:120]!r}")
        return None


def hypr_dispatch(expr: str) -> bool:
    out = hypr_request(f"dispatch {expr}")
    if out is not None and out.strip() == "ok":
        return True
    log("ipc", f"dispatch reply {out!r} for: {expr[:160]}")
    return False


# ── snapshot ─────────────────────────────────────────────────────────────────

_FLATPAK_SCOPE_RE = re.compile(r"app-flatpak-([A-Za-z0-9_.]+)-\d+\.scope")


def flatpak_app_id(pid: int) -> str | None:
    try:
        cg = Path(f"/proc/{pid}/cgroup").read_text()
    except OSError:
        return None
    m = _FLATPAK_SCOPE_RE.search(cg)
    return m.group(1) if m else None


def read_cmdline(pid: int) -> list[str]:
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return []
    parts = raw.split(b"\0")
    # cmdline is NUL-terminated: drop only the final empty element so
    # legitimate interior/trailing empty-string args survive the round trip.
    if parts and parts[-1] == b"":
        parts.pop()
    return [p.decode("utf-8", "replace") for p in parts]


def cmd_snapshot(args: argparse.Namespace) -> int:
    # The hyprland.shutdown hook passes --skip-if-fresh: on QML-initiated
    # power actions Session.qml snapshots synchronously BEFORE
    # closeAllWindows(), then the shutdown hook fires after the windows are
    # gone — capturing again would overwrite the full snapshot with an
    # empty one. A fresh last.json means the authoritative capture already
    # happened; hook paths that bypass the QML (lid close, systemd
    # shutdown) find an old file and proceed normally.
    if args.skip_if_fresh > 0 and SNAPSHOT_PATH.is_file():
        try:
            age = time.time() - SNAPSHOT_PATH.stat().st_mtime
        except OSError:
            age = None
        if age is not None and age < args.skip_if_fresh:
            log("snapshot", f"skip — snapshot is {age:.0f}s old (< {args.skip_if_fresh:.0f}s)")
            return 0

    clients = hypr_json("clients")
    if clients is None:
        log("snapshot", "clients query failed — keeping previous snapshot")
        return 1

    windows = []
    for c in clients:
        cls = c.get("class") or ""
        # Skip the shell's own surfaces. Quickshell toplevels report their Qt
        # reverse-DNS app-id ("org.quickshell"), so match the substring -- a
        # startswith("quickshell") check misses the "org." form, captures the
        # shell, then blindly relaunches it on restore.
        if not cls or "quickshell" in cls.lower():
            continue
        pid = c.get("pid") or 0
        app_id = flatpak_app_id(pid)
        cmdline = ["flatpak", "run", app_id] if app_id else read_cmdline(pid)
        if not cmdline:
            continue
        ws = c.get("workspace") or {}
        windows.append({
            "class": cls,
            "title": c.get("title") or "",
            "workspaceId": ws.get("id", -1),
            "workspaceName": ws.get("name") or "",
            "at": c.get("at") or [],
            "size": c.get("size") or [],
            "floating": bool(c.get("floating")),
            "pinned": bool(c.get("pinned")),
            "fullscreen": c.get("fullscreen") or 0,
            "cmdline": cmdline,
        })

    payload = {
        "version": 2,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "windows": windows,
    }
    if args.dry_run:
        json.dump(payload, sys.stdout, indent=2)
        print()
        return 0

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = SNAPSHOT_PATH.with_name(SNAPSHOT_PATH.name + ".tmp")
    try:
        tmp.write_text(json.dumps(payload, indent=2))
        os.replace(tmp, SNAPSHOT_PATH)
    except OSError as e:
        log("snapshot", f"write failed: {e}")
        return 1
    log("snapshot", f"captured {len(windows)} windows")
    return 0


# ── restore ──────────────────────────────────────────────────────────────────

def quote_arg(part: str) -> str:
    """Shell-quote one argv element for joining into a single command line."""
    if not part:
        return '""'
    if any(c in part for c in " \t\n\r\"'\\$`;&|<>(){}*?[]~#"):
        escaped = part.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")
        return f'"{escaped}"'
    return part


def lua_escape(s: str) -> str:
    """Escape for embedding inside a double-quoted Lua string literal."""
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r")


def build_rules(window: dict) -> str:
    rules: list[str] = []

    ws_id = window.get("workspaceId")
    ws_name = window.get("workspaceName") or ""
    if isinstance(ws_id, int) and ws_id >= 1:
        rules.append(f'workspace = "{ws_id} silent"')
    elif isinstance(ws_id, int) and ws_id < 0 and ws_name.startswith("special:"):
        # Special workspaces are addressed by name; "silent" keeps the
        # special overlay from popping open over the fresh session.
        rules.append(f'workspace = "{lua_escape(ws_name)} silent"')

    if window.get("floating"):
        rules.append("float = true")
        at, size = window.get("at") or [], window.get("size") or []
        if len(at) == 2:
            rules.append(f'move = "{int(at[0])} {int(at[1])}"')
        if len(size) == 2:
            rules.append(f'size = "{int(size[0])} {int(size[1])}"')

    if window.get("pinned"):
        rules.append("pin = true")

    # Hyprland fullscreen state: 0 none, 1 maximize, 2 fullscreen, 3 both.
    # The exec rule only exposes a bool; non-zero restores as fullscreen.
    fs = window.get("fullscreen") or 0
    if isinstance(fs, int) and fs > 0:
        rules.append("fullscreen = true")

    return "{ " + ", ".join(rules) + " }" if rules else "{}"


def build_expr(window: dict) -> str:
    cmd_str = " ".join(quote_arg(p) for p in window["cmdline"])
    return f'hl.dsp.exec_cmd("{lua_escape(cmd_str)}", {build_rules(window)})'


def shell_painted() -> bool:
    layers = hypr_json("layers", quiet=True)
    if not isinstance(layers, dict):
        return False
    for mon in layers.values():
        for level in (mon.get("levels") or {}).values():
            for surf in level or []:
                if (surf.get("namespace") or "").startswith(PAINT_PREFIX):
                    return True
    return False


def wait_for_shell() -> str:
    """Block until the shell has painted (its bar layer exists), then settle.

    The quickshell:bar layer surface is only created after the shell's QML
    has fully loaded — compositor truth, not a guessed sleep. Returns the
    outcome string for the log; always eventually returns so a broken or
    disabled shell can't block restore forever.
    """
    if WAIT_TIMEOUT_S <= 0:
        return "gate disabled"
    if _socket_path() is None:
        return "no compositor socket"
    deadline = time.monotonic() + WAIT_TIMEOUT_S
    while time.monotonic() < deadline:
        if shell_painted():
            time.sleep(SETTLE_MS / 1000.0)
            return "painted"
        time.sleep(0.2)
    return f"timeout after {WAIT_TIMEOUT_S:.0f}s"


def cmd_restore(args: argparse.Namespace) -> int:
    if not args.force and not config_enabled():
        log("restore", "disabled — skipping")
        return 0

    if not SNAPSHOT_PATH.is_file():
        log("restore", f"no snapshot at {SNAPSHOT_PATH}")
        return 0
    try:
        with SNAPSHOT_PATH.open() as f:
            snapshot = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        log("restore", f"snapshot read failed: {e}")
        return 1

    outcome = wait_for_shell()
    log("restore", f"shell wait: {outcome} (prefix={PAINT_PREFIX})")

    # Compute what's already running AFTER the wait, so apps the user (or
    # an autostart) launched during the gate aren't double-spawned. A
    # mid-session compositor restart lands here too: everything still
    # mapped gets skipped.
    existing = {c.get("class", "") for c in (hypr_json("clients") or [])}
    pending = []
    for w in snapshot.get("windows", []):
        cls = w.get("class", "")
        if not cls or not w.get("cmdline"):
            continue
        if cls in existing:
            log("restore", f"skip {cls} — already mapped")
            continue
        pending.append(w)

    if not pending:
        log("restore", "nothing to restore")
        return 0

    log("restore", f"restoring {len(pending)} windows")
    dispatched = 0
    for i, w in enumerate(pending):
        expr = build_expr(w)
        if args.dry_run:
            print(expr)
            continue
        if hypr_dispatch(expr):
            dispatched += 1
            log("restore", f"dispatched {w['class']} → ws={w.get('workspaceId', '?')}")
        else:
            log("restore", f"dispatch failed for {w['class']}")
        # Smooth the IO/CPU burst; no sleep after the last entry.
        if i + 1 < len(pending):
            time.sleep(STAGGER_MS / 1000.0)

    if not args.dry_run:
        log("restore", f"restore complete: {dispatched}/{len(pending)} dispatched")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Session window snapshot/restore.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_snap = sub.add_parser("snapshot", help="capture mapped windows to last.json")
    p_snap.add_argument("--dry-run", action="store_true", help="print instead of writing")
    p_snap.add_argument("--skip-if-fresh", type=float, default=0, metavar="SECONDS",
                        help="no-op if last.json is younger than this (shutdown-hook guard)")
    p_snap.set_defaults(fn=cmd_snapshot)

    p_rest = sub.add_parser("restore", help="replay last.json after the shell paints")
    p_rest.add_argument("--force", action="store_true", help="bypass the config gate")
    p_rest.add_argument("--dry-run", action="store_true", help="print dispatch exprs instead of sending")
    p_rest.set_defaults(fn=cmd_restore)

    args = parser.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
