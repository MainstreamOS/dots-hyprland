#!/usr/bin/env python3
# shake-zoom.py [FACTOR]
# Watches the pointer and, on a deliberate back-and-forth shake, bumps
# Hyprland's cursor:zoom_factor for a "where is my cursor" magnifier that
# eases back once movement settles. Polls cursorpos over the Hyprland IPC
# socket (cheap; no per-poll process spawn); only the infrequent zoom
# toggle shells out to hyprctl.
import fcntl
import glob
import json
import os
import signal
import socket
import subprocess
import sys
import time
from collections import deque

MODE = sys.argv[1] if len(sys.argv) > 1 else "zoom"
ZOOM_FACTOR = float(sys.argv[2]) if len(sys.argv) > 2 else 2.0
GROW_FACTOR = float(sys.argv[3]) if len(sys.argv) > 3 else 2.5
POLL = 1.0 / 60.0
WINDOW = 0.6          # seconds a reversal stays "recent"
MIN_SEG = 30          # px a swing must cover to count as a reversal
MIN_REVERSALS = 4     # reversals within WINDOW to trigger the zoom
HOLD = 1.0 if MODE == "grow" else 3.0   # seconds the effect holds after a shake (per mode)


def _sock_path():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    base = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid()), "hypr")
    if not sig:
        try:
            sig = sorted(os.listdir(base))[0]
        except Exception:
            return None
    return os.path.join(base, sig, ".socket.sock")


_PATH = None


def cursorpos(path=None):
    try:
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(0.2)
        s.connect(path or _PATH)
        s.sendall(b"cursorpos")
        r = s.recv(64).decode()
        s.close()
        x, y = r.strip().split(",")
        return int(x), int(y)
    except Exception:
        return None


# A hardware cursor only re-renders at a new size when it moves, so grow mode
# forces a software cursor (re-rendered every frame) while active, restoring
# the user's setting afterward.
_orig_nohw = 2


def _set_nohw(value):
    subprocess.run(["hyprctl", "eval", "hl.config({ cursor = { no_hardware_cursors = %d } })" % value], capture_output=True)


def set_zoom(factor):
    subprocess.run(
        ["hyprctl", "eval", "hl.config({ cursor = { zoom_factor = %g } })" % factor],
        capture_output=True,
    )


def _cursor_theme_size():
    def g(key, default):
        try:
            out = subprocess.run(
                ["gsettings", "get", "org.gnome.desktop.interface", key],
                capture_output=True, text=True).stdout.strip().strip("'")
            return out or default
        except Exception:
            return default
    theme = g("cursor-theme", "Bibata-Modern-Classic")
    try:
        size = int(g("cursor-size", "24"))
    except ValueError:
        size = 24
    return theme, size


_base_theme = "Bibata-Modern-Classic"
_base_size = 24


def activate():
    global _base_theme, _base_size
    if MODE == "grow":
        _base_theme, _base_size = _cursor_theme_size()
        _set_nohw(1)
        subprocess.run(["hyprctl", "setcursor", _base_theme, str(int(_base_size * GROW_FACTOR))], capture_output=True)
    else:
        set_zoom(ZOOM_FACTOR)


def deactivate():
    if MODE == "grow":
        subprocess.run(["hyprctl", "setcursor", _base_theme, str(_base_size)], capture_output=True)
        _set_nohw(_orig_nohw)
    else:
        set_zoom(1)


_KEY_LEFTSHIFT = 42
_KEY_RIGHTSHIFT = 54
_last_shift_check = 0.0
_shift_state = False


def _evio_getkey_req(length):
    return (2 << 30) | (length << 16) | (ord("E") << 8) | 0x18


def _shift_held():
    length = (0x2ff // 8) + 1
    req = _evio_getkey_req(length)
    for dev in glob.glob("/dev/input/event*"):
        try:
            fd = os.open(dev, os.O_RDONLY | os.O_NONBLOCK)
            try:
                buf = bytearray(length)
                fcntl.ioctl(fd, req, buf, True)
                for k in (_KEY_LEFTSHIFT, _KEY_RIGHTSHIFT):
                    if buf[k // 8] & (1 << (k % 8)):
                        return True
            finally:
                os.close(fd)
        except OSError:
            continue
    return False


def _shift_held_throttled(now):
    # Poll the live SHIFT key-state at ~12 Hz (not a keystroke stream) so
    # "hold SHIFT to keep the zoom" stays responsive without hammering evdev.
    global _last_shift_check, _shift_state
    if now - _last_shift_check >= 0.08:
        _shift_state = _shift_held()
        _last_shift_check = now
    return _shift_state


class ShakeDetector:
    # Direction-agnostic: a "reversal" is when the velocity vector flips more
    # than 90 degrees (dot product < 0) after covering MIN_SEG since the last
    # one, so a shake in any orientation (horizontal, vertical, diagonal)
    # counts equally.
    def __init__(self):
        self.prev_vec = None
        self.anchor = None
        self.reversals = deque()

    def feed(self, now, x, y, dx, dy):
        if dx * dx + dy * dy >= 4:
            vec = (dx, dy)
            if self.prev_vec is not None and (vec[0] * self.prev_vec[0] + vec[1] * self.prev_vec[1]) < 0:
                if self.anchor is None or (x - self.anchor[0]) ** 2 + (y - self.anchor[1]) ** 2 >= MIN_SEG * MIN_SEG:
                    self.reversals.append(now)
                    self.anchor = (x, y)
            elif self.anchor is None:
                self.anchor = (x, y)
            self.prev_vec = vec
        while self.reversals and now - self.reversals[0] > WINDOW:
            self.reversals.popleft()
        return len(self.reversals) >= MIN_REVERSALS


def main():
    global _PATH
    path = _sock_path()
    if not path:
        return
    _PATH = path

    def _cleanup(*_):
        deactivate()
        sys.exit(0)

    signal.signal(signal.SIGTERM, _cleanup)
    signal.signal(signal.SIGINT, _cleanup)

    global _base_theme, _base_size, _orig_nohw
    _base_theme, _base_size = _cursor_theme_size()
    try:
        _orig_nohw = json.loads(subprocess.run(
            ["hyprctl", "getoption", "cursor:no_hardware_cursors", "-j"],
            capture_output=True, text=True).stdout).get("int", 2)
    except Exception:
        _orig_nohw = 2

    det = ShakeDetector()
    prev = cursorpos(path)
    active = False
    active_until = 0.0
    while True:
        time.sleep(POLL)
        now = time.time()
        p = cursorpos(path)
        if p is None:
            continue
        if prev is None:
            prev = p
            continue
        dx = p[0] - prev[0]
        dy = p[1] - prev[1]
        prev = p
        if det.feed(now, p[0], p[1], dx, dy):
            if not active:
                activate()
                active = True
                active_until = now + HOLD
        if active and now > active_until:
            if MODE == "zoom" and _shift_held_throttled(now):
                pass  # keep the zoom up as long as SHIFT is held
            else:
                deactivate()
                active = False
                det.reversals.clear()


if __name__ == "__main__":
    main()
