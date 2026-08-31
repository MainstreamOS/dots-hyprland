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
SUPERVISE = 1.0       # seconds between "is anyone still watching us" checks
TAKEOVER = 3.0        # seconds to wait for an older watcher to step aside
DEAD_AFTER = 5.0      # seconds of unanswered polls before the compositor counts as gone
# Seconds the detector stays deaf after an effect ends. Finding the pointer is
# what the shake is for, so the moment it ends the hand is usually still moving
# over the thing it went looking for, and that movement is exactly the shape the
# detector is watching for. Without a pause the second trigger costs a fraction
# of the effort the first one did.
REARM = 1.2


def _runtime_dir():
    return os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())


def _instance():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    base = os.path.join(_runtime_dir(), "hypr")
    if not sig:
        try:
            sig = sorted(os.listdir(base))[0]
        except Exception:
            return None, None
    return os.path.join(base, sig, ".socket.sock"), sig


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


def _hyprctl(*args):
    # Bounded, because these also run on the way out: a wedged compositor
    # must not be able to hold the exit path open.
    try:
        subprocess.run(["hyprctl", *args], capture_output=True, timeout=2)
    except (OSError, subprocess.SubprocessError):
        pass


def _set_nohw(value):
    _hyprctl("eval", "hl.config({ cursor = { no_hardware_cursors = %d } })" % value)


def set_zoom(factor):
    _hyprctl("eval", "hl.config({ cursor = { zoom_factor = %g } })" % factor)


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


def _marker_path():
    return os.path.join(_runtime_dir(), "shake-zoom.active")


def _set_marker(on):
    # A file rather than a message, because the readers are separate processes
    # that come and go: one that starts while the effect is up still sees it.
    try:
        if on:
            with open(_marker_path(), "w") as f:
                f.write(MODE)
        else:
            os.unlink(_marker_path())
    except OSError:
        pass


def activate():
    global _base_theme, _base_size
    if MODE == "grow":
        _base_theme, _base_size = _cursor_theme_size()
        _set_nohw(1)
        _hyprctl("setcursor", _base_theme, str(int(_base_size * GROW_FACTOR)))
    else:
        set_zoom(ZOOM_FACTOR)
    _set_marker(True)


def deactivate():
    if MODE == "grow":
        _hyprctl("setcursor", _base_theme, str(_base_size))
        _set_nohw(_orig_nohw)
    else:
        set_zoom(1)
    _set_marker(False)


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
        self.reset()

    def reset(self):
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


_active = False


def _cleanup(*_):
    # Only undo what we actually did: an idle watcher that restored the cursor
    # here would stomp settings a newer watcher is legitimately holding.
    if _active:
        deactivate()
    sys.exit(0)


def _is_watcher(pid):
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as f:
            return b"shake-zoom.py" in f.read()
    except OSError:
        return False


def _claim(sig):
    # One watcher per compositor. The shell restarts this on every mode or
    # factor change, and a crashed shell leaves its old watcher orphaned, so a
    # new invocation takes the previous one's place instead of stacking a
    # second 60 Hz poller onto the same socket.
    fd = os.open(os.path.join(_runtime_dir(), "shake-zoom.%s.lock" % sig), os.O_RDWR | os.O_CREAT, 0o600)
    deadline = time.time() + TAKEOVER
    asked = set()
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            os.ftruncate(fd, 0)
            os.lseek(fd, 0, os.SEEK_SET)  # a failed read below leaves the offset past 0
            os.write(fd, str(os.getpid()).encode())
            return fd
        except OSError:
            pass
        try:
            os.lseek(fd, 0, os.SEEK_SET)
            holder = int(os.read(fd, 32) or 0)
        except (OSError, ValueError):
            holder = 0
        # The pid check keeps a recycled pid from taking the signal.
        if holder and holder != os.getpid() and holder not in asked and _is_watcher(holder):
            asked.add(holder)
            try:
                os.kill(holder, signal.SIGTERM)
            except OSError:
                pass
        if time.time() >= deadline:
            os.close(fd)
            return None
        time.sleep(0.05)


def main():
    global _PATH
    path, sig = _instance()
    if not path:
        return
    _PATH = path

    signal.signal(signal.SIGTERM, _cleanup)
    signal.signal(signal.SIGINT, _cleanup)

    # Claim before reading the baseline below, so an outgoing watcher has
    # already restored the real values by the time we sample them.
    lock = _claim(sig)
    if lock is None:
        return

    global _base_theme, _base_size, _orig_nohw, _active
    _base_theme, _base_size = _cursor_theme_size()
    try:
        _orig_nohw = json.loads(subprocess.run(
            ["hyprctl", "getoption", "cursor:no_hardware_cursors", "-j"],
            capture_output=True, text=True, timeout=2).stdout).get("int", 2)
    except Exception:
        _orig_nohw = 2

    det = ShakeDetector()
    prev = cursorpos(path)
    parent = os.getppid()
    active_until = 0.0
    rearm_at = 0.0
    answered = time.time()
    supervised = 0.0
    while True:
        time.sleep(POLL)
        now = time.time()
        # Nothing sends us a signal when the shell dies of anything other than
        # a clean shutdown, so notice that we've been orphaned and leave.
        if now - supervised >= SUPERVISE:
            supervised = now
            if os.getppid() != parent:
                _cleanup()
        p = cursorpos(path)
        if p is None:
            if now - answered > DEAD_AFTER:
                _cleanup()  # compositor gone
            continue
        answered = now
        if prev is None:
            prev = p
            continue
        dx = p[0] - prev[0]
        dy = p[1] - prev[1]
        prev = p
        shaking = det.feed(now, p[0], p[1], dx, dy)
        if now < rearm_at:
            # Still deaf: keep reading so the detector stays in step with where
            # the pointer is, but let nothing it sees count yet.
            det.reset()
            shaking = False
        if shaking:
            if not _active:
                activate()
                _active = True
                active_until = now + HOLD
        if _active and now > active_until:
            if MODE == "zoom" and _shift_held_throttled(now):
                pass  # keep the zoom up as long as SHIFT is held
            else:
                deactivate()
                _active = False
                # The swing that ended the effect leaves an anchor and a
                # direction behind it, so clearing only the timestamps lets the
                # next flick start from halfway there.
                det.reset()
                rearm_at = now + REARM


if __name__ == "__main__":
    main()
