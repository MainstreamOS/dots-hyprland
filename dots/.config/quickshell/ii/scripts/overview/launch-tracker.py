"""Associate dropped apps, their child windows and portal pickers with a workspace."""

import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time


TOKEN = b"MAINSTREAM_LAUNCH_ID="
WRAPPERS = {"env", "sh", "bash", "zsh", "flatpak", "qs", "quickshell", "python", "python3"}
PICKERS = {"hyprland-share-picker", "hyprland-preview-share-picker"}


def emit(**message):
    print(json.dumps(message), flush=True)


def call(*args):
    return json.loads(subprocess.check_output(args, text=True, timeout=2, stderr=subprocess.DEVNULL))


def clients():
    return call("hyprctl", "-j", "clients")


def identity(pid):
    """Read only launch identity; never return the rest of a process's environment."""
    try:
        path = Path("/proc") / str(pid)
        token = next((value[len(TOKEN):].decode() for value in path.joinpath("environ").read_bytes().split(b"\0")
                      if value.startswith(TOKEN)), "")
        parent = int(path.joinpath("stat").read_text().rsplit(")", 1)[1].split()[1])
        return token, parent
    except (OSError, ValueError, UnicodeError):
        return "", 0


class Tracker:
    def __init__(self):
        self.launches = {}
        self.sessions = {}
        self.pickers = []

    def register(self, message):
        aliases = {str(message.get(key, "")).lower().removesuffix(".desktop") for key in ("id", "startupClass")}
        executable = Path(message.get("executable", "")).name.lower()
        if executable not in WRAPPERS:
            aliases.add(executable)
        # Generic runtimes identify many unrelated apps. Their launch token
        # distinguishes them, including two Quickshell apps dropped separately.
        aliases -= WRAPPERS | {"", "org.quickshell"}
        # An already running app may open its new window over D-Bus with its old
        # environment, so bind its current process IDs to this drop.
        try:
            pids = {window["pid"] for window in clients() if window.get("class", "").lower() in aliases}
        except (OSError, ValueError, subprocess.SubprocessError):
            pids = set()
        for launch in self.launches.values():
            launch["pids"] -= pids
        self.launches[message["token"]] = dict(workspace=message["workspace"], aliases=aliases,
                                              pids=pids, expires=time.monotonic() + 30)

    def process_launch(self, pid):
        seen = set()
        while pid > 1 and pid not in seen:
            seen.add(pid)
            token, parent = identity(pid)
            matched = [launch for launch in self.launches.values() if pid in launch["pids"]]
            if len(matched) == 1:
                return matched[0]
            if token in self.launches:
                return self.launches[token]
            pid = parent
        return None

    def class_launch(self, klass):
        matches = [launch for launch in self.launches.values() if klass.lower().removesuffix(".desktop") in launch["aliases"]]
        # Never choose arbitrarily between concurrent launches of the same app.
        return matches[0] if len(matches) == 1 else None

    def portal(self, message):
        if message.get("type") in ("method_return", "error"):
            # Restored/cancelled requests may finish without showing a picker.
            # Do not leave them ahead of the next app's interactive request.
            self.pickers = [request for request in self.pickers
                            if (request["sender"], request["cookie"])
                            != (message.get("destination"), message.get("reply_cookie"))]
            return
        data = message.get("payload", {}).get("data", [])
        if message.get("member") != "Start" or len(data) < 2:
            return
        if message.get("interface") == "org.freedesktop.portal.ScreenCast":
            reply = call("busctl", "--user", "--json=short", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
                         "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", message["sender"])
            pid = reply["data"][0]
            launch = self.process_launch(pid)
            owners = [window for window in clients() if window.get("pid") == pid and window.get("workspace", {}).get("id", 0) > 0]
            owners.sort(key=lambda window: window.get("focusHistoryID", 0))
            workspace = launch["workspace"] if launch else owners[0]["workspace"]["id"] if owners else 0
            self.sessions[data[0]] = dict(workspace=workspace, time=time.monotonic())
        elif message.get("interface") == "org.freedesktop.impl.portal.ScreenCast":
            # Backend ordering is picker ordering; the public request records
            # the actual caller PID even when the unsandboxed app_id is empty.
            request = self.sessions.pop(data[1], None)
            request = request or dict(workspace=0, time=time.monotonic())
            self.pickers.append(dict(request, sender=message["sender"], cookie=message["cookie"]))

    def window(self, address):
        window = None
        for _ in range(3):
            window = next((item for item in clients() if item["address"] == address), None)
            if window:
                break
            time.sleep(0.02)
        if not window:
            return 0, 0
        pid = window.get("pid", 0)
        launch = self.process_launch(pid) or self.class_launch(window.get("class", ""))
        if launch:
            launch["pids"].add(pid)
            return launch["workspace"], window["workspace"]["id"]
        if window.get("class") in PICKERS:
            # A picker is owned by the portal, not by OBS/browser. Only a
            # correlated request may redirect it; class alone is insufficient.
            _, parent = identity(pid)
            try:
                executable = Path((Path("/proc") / str(parent) / "cmdline").read_bytes().split(b"\0")[0].decode()).name
            except (OSError, UnicodeError):
                executable = ""
            if executable.startswith("xdg-desktop-portal") and self.pickers:
                return self.pickers.pop(0)["workspace"], window["workspace"]["id"]
        return 0, window["workspace"]["id"]

    def expire(self):
        now = time.monotonic()
        self.launches = {token: launch for token, launch in self.launches.items() if launch["expires"] > now}
        self.sessions = {session: request for session, request in self.sessions.items() if now - request["time"] < 120}
        self.pickers = [request for request in self.pickers if now - request["time"] < 120]


def main():
    stopping = False

    def stop(*_):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGTERM, stop)
    tracker = Tracker()
    selector = selectors.DefaultSelector()
    selector.register(sys.stdin, selectors.EVENT_READ, "input")
    monitor = subprocess.Popen(["busctl", "--user", "--json=short",
        "--match=type='method_call',interface='org.freedesktop.portal.ScreenCast',member='Start'",
        "--match=type='method_call',interface='org.freedesktop.impl.portal.ScreenCast',member='Start'",
        "--match=type='method_return',sender='org.freedesktop.impl.portal.desktop.hyprland'",
        "--match=type='error',sender='org.freedesktop.impl.portal.desktop.hyprland'", "monitor"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    selector.register(monitor.stdout, selectors.EVENT_READ, "portal")
    buffers = {"input": b"", "portal": b""}
    count = 0
    emit(event="ready")
    try:
        while not stopping:
            tracker.expire()
            if len(tracker.launches) != count:
                count = len(tracker.launches)
                emit(event="count", count=count)
            # Read portal requests before window arrivals when both are ready.
            for key, _ in sorted(selector.select(0.25), key=lambda item: item[0].data != "portal"):
                kind = key.data
                chunk = os.read(key.fd, 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    if kind == "input":
                        return
                    continue
                buffers[kind] += chunk
                while b"\n" in buffers[kind]:
                    line, buffers[kind] = buffers[kind].split(b"\n", 1)
                    if not line:
                        continue
                    try:
                        message = json.loads(line)
                    except ValueError:
                        continue
                    try:
                        if kind == "portal":
                            tracker.portal(message)
                        elif message["event"] == "launch":
                            tracker.register(message)
                            emit(event="registered", token=message["token"])
                        elif message["event"] == "window":
                            workspace, current = tracker.window(message["address"])
                            emit(event="window", address=message["address"], workspace=workspace, currentWorkspace=current)
                    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
                        if kind == "input" and message.get("event") == "window":
                            emit(event="window", address=message["address"], workspace=0, currentWorkspace=0)
    finally:
        monitor.terminate()
        monitor.wait(timeout=2)


if __name__ == "__main__":
    main()
