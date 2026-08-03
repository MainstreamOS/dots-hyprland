#!/usr/bin/env python3
# =============================================================================
# session/session.py — window-state capture + restore engine
#
#   session.py watch [--force]
#       Resident capturer. Follows Hyprland's event socket and re-snapshots a
#       couple of seconds after anything changes, plus a slow periodic pass to
#       catch drag-moves and resizes (which emit no event). This is what makes
#       the session survive a crash, a power loss, or any exit that isn't the
#       power menu — see the note on hyprland.shutdown below.
#
#   session.py snapshot [--dry-run] [--allow-empty]
#       One-shot capture into $XDG_STATE_HOME/quickshell/sessions/last.json.
#       Called by Session.qml before a power action so the final state is
#       authoritative, and by the watcher on every change.
#
#   session.py restore [--force] [--dry-run]
#       Waits for the shell to PAINT (a quickshell:* layer surface exists),
#       then replays the snapshot. Windows are grouped by the process that
#       owned them: one launch per process, with placement rules attached so
#       Hyprland positions the window as it maps. Extra windows belonging to
#       the same process are moved into place once they appear, because only
#       the first window a process opens can carry an exec rule.
#
# Why a resident watcher rather than a shutdown hook: hl.on("hyprland.shutdown")
# fires on Hyprland's exit event, which is emitted only by the `exit`
# dispatcher. SIGTERM — what a logout, loginctl, or a crashing session actually
# delivers — goes straight to stopCompositor() without it, so a shutdown hook
# never runs. Capture has to happen while the session is still alive.
#
# All compositor traffic goes over Hyprland's sockets directly — no hyprctl
# forks, no jq. The .sh shims exist only to gate the disabled case without
# paying python startup.
# =============================================================================
from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import select
import socket
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "quickshell/sessions"
SNAPSHOT_PATH = STATE_DIR / "last.json"
LOG_PATH = STATE_DIR / "session.log"
LOCK_PATH = STATE_DIR / "watch.lock"
CONFIG_PATH = Path.home() / ".config/illogical-impulse/config.json"

SNAPSHOT_VERSION = 3

# Tunables. Env-only on purpose — not worth config-file surface.
STAGGER_MS = int(os.environ.get("QS_RESTORE_STAGGER_MS", "150"))
WAIT_TIMEOUT_S = float(os.environ.get("QS_RESTORE_WAIT_TIMEOUT", "20"))
SETTLE_MS = int(os.environ.get("QS_RESTORE_SETTLE_MS", "1200"))
# Prefix, not exact name: the bar layer is "quickshell:bar" in the default
# layout but other layouts (vertical bar) and surfaces (dock, background)
# differ — ANY quickshell:* layer means the shell finished loading QML and
# is creating windows, which is the readiness signal we need.
PAINT_PREFIX = os.environ.get("QS_RESTORE_PAINT_PREFIX", "quickshell")
# Watcher: settle time after a burst of events, and a periodic floor so a
# drag-move or resize (neither of which emits an event) still reaches disk.
WATCH_DEBOUNCE_S = float(os.environ.get("QS_WATCH_DEBOUNCE", "2"))
WATCH_PERIODIC_S = float(os.environ.get("QS_WATCH_PERIODIC", "120"))
# How long to wait for a multi-window process to reopen its other windows.
GROUP_SETTLE_S = float(os.environ.get("QS_RESTORE_GROUP_SETTLE", "8"))
GROUP_POLL_MS = int(os.environ.get("QS_RESTORE_GROUP_POLL_MS", "400"))
LOG_MAX_BYTES = 64 * 1024
LOG_KEEP_LINES = 200

# Events worth re-capturing for. Deliberately excludes activewindow* and
# workspace focus changes, which fire constantly and change nothing we store.
WATCH_EVENTS = {
    "openwindow", "closewindow", "movewindow", "windowtitle",
    "fullscreen", "changefloatingmode", "pin",
    "monitoradded", "monitorremoved",
}

# Flags that start an app in a background service mode with no window. Restoring
# one launches a D-Bus service and the user sees nothing, so they are stripped
# and the bare command is launched instead.
SERVICE_MODE_FLAGS = {"--gapplication-service"}


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

def _instance_dir() -> Path | None:
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        return None
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return Path(runtime) / "hypr" / sig


def _socket_path() -> Path | None:
    d = _instance_dir()
    if d is None:
        return None
    p = d / ".socket.sock"
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
    # Hyprland parses socket dispatch payloads as Lua (the config is Lua), so
    # everything goes through the hl.dsp.* API rather than the classic
    # "dispatch exec foo" form, which fails to parse.
    out = hypr_request(f"dispatch {expr}")
    if out is not None and out.strip() == "ok":
        return True
    log("ipc", f"dispatch reply {out!r} for: {expr[:160]}")
    return False


# ── capture ──────────────────────────────────────────────────────────────────

# App ids may contain hyphens (io.github.some-app), so the character class has
# to allow them. Without it the match fails and the caller falls back to the
# sandbox-internal /proc cmdline, which cannot be executed from the host.
_FLATPAK_SCOPE_RE = re.compile(r"app-flatpak-([A-Za-z0-9_.\-]+)-\d+\.scope")


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
    argv = [p.decode("utf-8", "replace") for p in parts]
    # Chromium/Electron rewrites argv into one space-joined block; restore
    # would exec that single element verbatim as a nonexistent "binary".
    # Recover by splitting when the lone element is not a real path.
    if len(argv) == 1 and " " in argv[0] and not os.path.exists(argv[0]):
        argv = [t for t in argv[0].split(" ") if t]
    # A service-mode launch opens no window at all; drop the flag so the
    # restored command actually shows something.
    return [a for a in argv if a not in SERVICE_MODE_FLAGS]


def workspace_selector(ws: dict) -> str:
    """The workspace as a rule string. Numbered workspaces go by id, special
    ones by their special:name, and named ones need the name: prefix — without
    it a named workspace is silently dropped and the window lands on whatever
    happens to be active."""
    wid = ws.get("id")
    name = (ws.get("name") or "").strip()
    if isinstance(wid, int) and wid >= 1:
        return str(wid)
    if name.startswith("special:"):
        return name
    if name:
        return f"name:{name}"
    return ""


def capture_windows() -> list[dict] | None:
    """The current desktop as restorable entries, or None if the compositor
    could not be queried — which must not be confused with an empty desktop."""
    clients = hypr_json("clients")
    if clients is None:
        return None

    mons = hypr_json("monitors", quiet=True) or []
    mon_name = {m.get("id"): m.get("name", "") for m in mons}
    mon_origin = {m.get("name", ""): (m.get("x", 0), m.get("y", 0)) for m in mons}

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
            log("snapshot", f"skip {cls} — no launch command for pid {pid}")
            continue

        name = mon_name.get(c.get("monitor"), "")
        at = list(c.get("at") or [])
        # Store monitor-relative coordinates: the move rule is applied relative
        # to the window's monitor, so a global coordinate would be offset twice
        # on any monitor that isn't at the origin.
        if len(at) == 2 and name in mon_origin:
            ox, oy = mon_origin[name]
            at = [at[0] - ox, at[1] - oy]

        windows.append({
            "class": cls,
            "title": c.get("title") or "",
            "workspace": workspace_selector(c.get("workspace") or {}),
            "monitor": name,
            "at": at,
            "size": c.get("size") or [],
            "floating": bool(c.get("floating")),
            "pinned": bool(c.get("pinned")),
            "fullscreen": c.get("fullscreen") or 0,
            "cmdline": cmdline,
            # Windows sharing a pid came from one process: it gets launched
            # once however many windows it had.
            "pid": pid,
        })
    return windows


def write_snapshot(windows: list[dict], allow_empty: bool = False) -> bool:
    if not windows and not allow_empty and SNAPSHOT_PATH.is_file():
        try:
            with SNAPSHOT_PATH.open() as f:
                previous = json.load(f).get("windows") or []
        except (OSError, json.JSONDecodeError):
            previous = []
        if previous:
            # A capture that comes back empty while the compositor is tearing
            # down would otherwise erase a perfectly good session.
            log("snapshot", f"refusing to replace {len(previous)} saved windows with an empty capture")
            return False

    payload = {
        "version": SNAPSHOT_VERSION,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "windows": windows,
    }
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = SNAPSHOT_PATH.with_name(SNAPSHOT_PATH.name + ".tmp")
    try:
        tmp.write_text(json.dumps(payload, indent=2))
        os.replace(tmp, SNAPSHOT_PATH)
    except OSError as e:
        log("snapshot", f"write failed: {e}")
        return False
    return True


def cmd_snapshot(args: argparse.Namespace) -> int:
    windows = capture_windows()
    if windows is None:
        log("snapshot", "clients query failed — keeping previous snapshot")
        return 1

    if args.dry_run:
        json.dump({"version": SNAPSHOT_VERSION, "windows": windows}, sys.stdout, indent=2)
        print()
        return 0

    if write_snapshot(windows, allow_empty=args.allow_empty):
        log("snapshot", f"captured {len(windows)} windows")
    return 0


# ── watch ────────────────────────────────────────────────────────────────────

def cmd_watch(args: argparse.Namespace) -> int:
    """Keep last.json close to the live session, so an ungraceful exit — which
    is most of them — still restores something current."""
    if not args.force and not config_enabled():
        log("watch", "disabled — not starting")
        return 0

    d = _instance_dir()
    if d is None or not (d / ".socket2.sock").is_socket():
        log("watch", "no Hyprland event socket — not starting")
        return 1

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    lock = LOCK_PATH.open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        log("watch", "another watcher already holds the lock — exiting")
        return 0

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(str(d / ".socket2.sock"))
    except OSError as e:
        log("watch", f"cannot connect to the event socket: {e}")
        return 1

    log("watch", f"watching (debounce {WATCH_DEBOUNCE_S:.0f}s, periodic {WATCH_PERIODIC_S:.0f}s)")
    buf = b""
    dirty = False
    due: float | None = None
    next_periodic = time.monotonic() + WATCH_PERIODIC_S
    saves = 0

    def save(reason: str) -> None:
        nonlocal saves
        windows = capture_windows()
        if windows is None:
            return
        if write_snapshot(windows):
            saves += 1
            # One line per burst of twenty keeps the log readable over a long
            # uptime while still showing the watcher is alive.
            if saves % 20 == 1:
                log("watch", f"snapshot #{saves}: {len(windows)} windows ({reason})")

    while True:
        now = time.monotonic()
        pending = [t for t in (due, next_periodic) if t is not None]
        timeout = max(0.0, min(pending) - now) if pending else None
        try:
            readable, _, _ = select.select([sock], [], [], timeout)
        except (OSError, InterruptedError):
            break

        if readable:
            try:
                chunk = sock.recv(8192)
            except OSError:
                chunk = b""
            if not chunk:
                # The compositor went away; so should we.
                log("watch", f"event socket closed after {saves} snapshots — exiting")
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                name = line.split(b">>", 1)[0].decode(errors="replace")
                # Hyprland emits both `movewindow` and `movewindowv2` for the
                # same change; treat them as one.
                if name in WATCH_EVENTS or name.removesuffix("v2") in WATCH_EVENTS:
                    dirty = True
                    due = time.monotonic() + WATCH_DEBOUNCE_S

        now = time.monotonic()
        if due is not None and now >= due:
            due = None
            if dirty:
                dirty = False
                save("event")
                next_periodic = now + WATCH_PERIODIC_S
        if now >= next_periodic:
            next_periodic = now + WATCH_PERIODIC_S
            # Catches drag-moves and resizes, which emit no event at all.
            save("periodic")

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

    ws = window.get("workspace") or ""
    if ws:
        # "silent" keeps the target workspace (special ones included) from
        # popping open over the fresh session.
        rules.append(f'workspace = "{lua_escape(ws)} silent"')

    mon = window.get("monitor") or ""
    if mon:
        rules.append(f'monitor = "{lua_escape(mon)}"')

    if window.get("floating"):
        rules.append("float = true")
        at, size = window.get("at") or [], window.get("size") or []
        if len(at) == 2:
            rules.append(f'move = "{int(at[0])} {int(at[1])}"')
        if len(size) == 2:
            rules.append(f'size = "{int(size[0])} {int(size[1])}"')

    if window.get("pinned"):
        rules.append("pin = true")

    # Hyprland fullscreen state: 0 none, 1 maximize, 2 fullscreen. The exec
    # rule key is fullscreen_state ("INTERNAL CLIENT"), which keeps maximize
    # and fullscreen distinct — the plain `fullscreen` bool would turn every
    # maximized window into a true fullscreen one. -1 leaves the client-side
    # state alone.
    fs = window.get("fullscreen") or 0
    if isinstance(fs, int) and fs == 1:
        rules.append('fullscreen_state = "1 -1"')
    elif isinstance(fs, int) and fs >= 2:
        rules.append('fullscreen_state = "2 -1"')

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


def group_windows(windows: list[dict]) -> list[list[dict]]:
    """Windows that shared a process at capture time, kept in saved order. Such
    a process is launched once however many windows it had: a browser or a GTK
    app reopens the rest itself, and only the first window to map can carry an
    exec rule anyway."""
    groups: dict[tuple, list[dict]] = {}
    order: list[tuple] = []
    for w in windows:
        if not w.get("class") or not w.get("cmdline"):
            if w.get("class"):
                log("restore", f"skip {w['class']} — no launch command saved")
            continue
        key = (w["class"], w.get("pid") or id(w))
        if key not in groups:
            groups[key] = []
            order.append(key)
        groups[key].append(w)
    return [groups[k] for k in order]


def place(addr: str, window: dict) -> None:
    """Move an already-mapped window to where it was saved."""
    sel = f"address:{addr}"
    ws = window.get("workspace") or ""
    if ws:
        # follow = false moves it silently, so the active workspace doesn't
        # flip under the user while the session is still coming up.
        hypr_dispatch(f'hl.dsp.window.move({{ workspace = "{lua_escape(ws)}", follow = false, window = "{sel}" }})')
    fs = window.get("fullscreen") or 0
    if isinstance(fs, int) and fs >= 1:
        internal = 1 if fs == 1 else 2
        # Both internal and client are required by this dispatcher.
        hypr_dispatch(f'hl.dsp.window.fullscreen_state({{ internal = {internal}, client = -1, window = "{sel}" }})')


def place_extra(group: list[dict], baseline: set[str]) -> None:
    """Place the windows a multi-window process reopened for itself, matched by
    title where possible and otherwise by saved order."""
    cls = group[0]["class"]
    deadline = time.monotonic() + GROUP_SETTLE_S
    seen: list[dict] = []
    while time.monotonic() < deadline:
        seen = [c for c in (hypr_json("clients", quiet=True) or [])
                if (c.get("class") or "") == cls and (c.get("address") or "") not in baseline]
        if len(seen) >= len(group):
            break
        time.sleep(GROUP_POLL_MS / 1000.0)

    if len(seen) <= 1:
        return

    # The first window carried the exec rule and is already in place; sort the
    # rest out by title, falling back to saved order.
    placed = 0
    used: set[str] = set()
    for entry in group[1:]:
        title = entry.get("title") or ""
        match = next((c for c in seen
                      if (c.get("address") or "") not in used
                      and title and (c.get("title") or "") == title), None)
        if match is None:
            match = next((c for c in seen if (c.get("address") or "") not in used), None)
        if match is None:
            break
        used.add(match.get("address") or "")
        place(match.get("address") or "", entry)
        placed += 1
    if placed:
        log("restore", f"{cls}: placed {placed} more window(s)")


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

    saved = snapshot.get("windows") or []
    try:
        age_h = (time.time() - SNAPSHOT_PATH.stat().st_mtime) / 3600
        log("restore", f"snapshot: {len(saved)} windows, {age_h:.1f}h old")
    except OSError:
        pass

    outcome = wait_for_shell()
    log("restore", f"shell wait: {outcome} (prefix={PAINT_PREFIX})")

    # Count what's already running AFTER the wait, so apps the user (or an
    # autostart) launched during the gate aren't double-spawned, and remember
    # the windows that predate the restore so group placement only touches new
    # ones. Counting per class rather than testing set membership means one
    # autostarted terminal no longer suppresses every other saved terminal.
    running: dict[str, int] = {}
    baseline: set[str] = set()
    for c in hypr_json("clients") or []:
        cls = c.get("class") or ""
        if cls:
            running[cls] = running.get(cls, 0) + 1
        addr = c.get("address") or ""
        if addr:
            baseline.add(addr)

    pending: list[list[dict]] = []
    for group in group_windows(saved):
        cls = group[0]["class"]
        have = running.get(cls, 0)
        if have > 0:
            # Each already-mapped window accounts for one saved one.
            running[cls] = max(0, have - len(group))
            log("restore", f"skip {cls} — {have} already mapped")
            continue
        pending.append(group)

    if not pending:
        log("restore", "nothing to restore")
        return 0

    total = sum(len(g) for g in pending)
    log("restore", f"restoring {total} windows from {len(pending)} process(es)")
    launched = 0
    for i, group in enumerate(pending):
        lead = group[0]
        expr = build_expr(lead)
        if args.dry_run:
            extra = f"   -- plus {len(group) - 1} placed after mapping" if len(group) > 1 else ""
            print(expr + extra)
            continue
        if hypr_dispatch(expr):
            launched += 1
            more = f" (+{len(group) - 1} more)" if len(group) > 1 else ""
            log("restore", f"launched {lead['class']} → ws={lead.get('workspace') or '?'}{more}")
            if len(group) > 1:
                place_extra(group, baseline)
        else:
            log("restore", f"launch failed for {lead['class']}")
        # Smooth the IO/CPU burst; no sleep after the last entry.
        if i + 1 < len(pending):
            time.sleep(STAGGER_MS / 1000.0)

    if not args.dry_run:
        log("restore", f"restore complete: {launched}/{len(pending)} launched")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Session window capture/restore.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_watch = sub.add_parser("watch", help="follow the compositor and keep last.json current")
    p_watch.add_argument("--force", action="store_true", help="bypass the config gate")
    p_watch.set_defaults(fn=cmd_watch)

    p_snap = sub.add_parser("snapshot", help="capture mapped windows to last.json")
    p_snap.add_argument("--dry-run", action="store_true", help="print instead of writing")
    p_snap.add_argument("--allow-empty", action="store_true",
                        help="permit replacing a saved session with an empty capture")
    p_snap.set_defaults(fn=cmd_snapshot)

    p_rest = sub.add_parser("restore", help="replay last.json after the shell paints")
    p_rest.add_argument("--force", action="store_true", help="bypass the config gate")
    p_rest.add_argument("--dry-run", action="store_true", help="print dispatch exprs instead of sending")
    p_rest.set_defaults(fn=cmd_restore)

    args = parser.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
