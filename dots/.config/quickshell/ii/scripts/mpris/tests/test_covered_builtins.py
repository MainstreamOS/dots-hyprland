"""covered-builtins.sh pairs a browser's built-in player with its own bridge, natively and in a
Flatpak, on a private bus with fake players."""
import importlib.util
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "covered-builtins.sh"
TOOLS = ("dbus-run-session", "gdbus", "xdg-dbus-proxy")
MPRIS = "org.mpris.MediaPlayer2."

# Owns a name on the given bus, then the next one in a child process (a bridge host is the
# browser's child), and holds them until stdin closes.
OWNER = r'''
import os, subprocess, sys
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib
address, name, rest = sys.argv[1], sys.argv[2].replace("{pid}", str(os.getpid())), sys.argv[3:]
conn = Gio.DBusConnection.new_for_address_sync(address,
    Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
try:
    reply = conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                           "RequestName", GLib.Variant("(su)", (name, 4)), GLib.VariantType("(u)"),
                           Gio.DBusCallFlags.NONE, -1, None).unpack()[0]
except GLib.Error:
    reply = 0
print(name if reply == 1 else "refused " + name, flush=True)
child = subprocess.Popen([sys.executable, "-I", __file__, address, *rest]) if rest else None
sys.stdin.read()
if child:
    child.wait()
'''


def read_lines(fd, count, timeout=10):
    data = b""
    deadline = time.monotonic() + timeout
    while data.count(b"\n") < count:
        left = deadline - time.monotonic()
        if left <= 0 or not select.select([fd], [], [], left)[0]:
            raise AssertionError("a fake process did not come up")
        chunk = os.read(fd, 4096)
        if not chunk:
            raise AssertionError("a fake process exited early")
        data += chunk
    return data.decode().splitlines()


@unittest.skipUnless(all(shutil.which(tool) for tool in TOOLS) and importlib.util.find_spec("gi"),
                     "needs dbus-run-session, gdbus, xdg-dbus-proxy and python-gobject")
class CoveredBuiltinsTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="covered-")
        self.addCleanup(shutil.rmtree, self.dir, True)
        runtime = os.path.join(self.dir, "run")
        os.mkdir(runtime, 0o700)
        self.owner = os.path.join(self.dir, "owner.py")
        self.proxies = 0
        Path(self.owner).write_text(OWNER)
        env = {k: v for k, v in os.environ.items() if k != "DBUS_SESSION_BUS_ADDRESS"}
        env["XDG_RUNTIME_DIR"] = runtime
        bus = subprocess.Popen(["dbus-run-session", "--", "sh", "-c",
                                'echo "$DBUS_SESSION_BUS_ADDRESS"; exec cat >/dev/null'],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env)
        self.addCleanup(self.stop, bus)
        self.address = read_lines(bus.stdout.fileno(), 1)[0]
        if not self.address or "/run/user/" in self.address \
                or self.address == os.environ.get("DBUS_SESSION_BUS_ADDRESS"):
            raise RuntimeError("refusing to run on a non-private bus: " + self.address)
        self.env = dict(env, DBUS_SESSION_BUS_ADDRESS=self.address)

    def stop(self, process):
        if process.stdin:
            process.stdin.close()
        else:
            process.terminate()
        try:
            process.wait(5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        if process.stdout:
            process.stdout.close()

    def own(self, address, *names):
        process = subprocess.Popen([sys.executable, "-I", self.owner, address, *names], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, env=self.env)
        self.addCleanup(self.stop, process)
        return read_lines(process.stdout.fileno(), len(names))

    def proxy(self, own):
        self.proxies += 1
        path = os.path.join(self.dir, f"p{self.proxies}.sock")
        process = subprocess.Popen(["xdg-dbus-proxy", self.address, path, "--filter", f"--own={own}"],
                                   env=self.env)
        self.addCleanup(self.stop, process)
        deadline = time.monotonic() + 10
        while not os.path.exists(path):
            if time.monotonic() > deadline or process.poll() is not None:
                raise AssertionError("xdg-dbus-proxy did not come up")
            time.sleep(0.05)
        return "unix:path=" + path, process.pid

    def connection_pid(self, name):
        out = subprocess.run(["gdbus", "call", "--session", "--dest", "org.freedesktop.DBus",
                              "--object-path", "/org/freedesktop/DBus", "--method",
                              "org.freedesktop.DBus.GetConnectionUnixProcessID", name],
                             env=self.env, capture_output=True, text=True, check=True).stdout
        return int(out.strip("()\n, ").split()[-1])

    def covered(self, *names):
        for name in names:
            self.assertFalse(name.startswith("refused"), name)
        result = subprocess.run(["bash", str(SCRIPT), *names], env=self.env, capture_output=True,
                                text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        return set(result.stdout.split())

    def test_native_brave_bridge_covers_its_own_browser(self):
        builtin, bridge = self.own(self.address, MPRIS + "brave.instance{pid}", MPRIS + "brave.instance{pid}_t1")
        self.assertEqual(self.covered(builtin, bridge), {builtin})

    def test_flatpak_brave_bridge_covers_its_own_browser(self):
        address, proxy_pid = self.proxy(MPRIS + "brave.*")
        builtin, bridge = self.own(address, MPRIS + "brave.instance2", MPRIS + "brave.instance{pid}_t1")
        self.assertEqual(self.connection_pid(builtin), proxy_pid)
        self.assertEqual(self.connection_pid(bridge), proxy_pid)
        self.assertEqual(self.covered(builtin, bridge), {builtin})
        self.assertEqual(self.own(address, MPRIS + "chromium.instance{pid}_t1")[0].split()[0], "refused")

    def test_native_chromium_family_is_unchanged(self):
        for builtin_name, bridge_name in (("chromium.instance{pid}", "chromium.instance{pid}_t3"),
                                          ("chrome.instance{pid}", "chromium.instance{pid}_t4"),
                                          ("firefox.instance_1_{pid}", "firefox.instance{pid}_t5")):
            with self.subTest(builtin_name):
                builtin, bridge = self.own(self.address, MPRIS + builtin_name, MPRIS + bridge_name)
                self.assertEqual(self.covered(builtin, bridge), {builtin})

    def test_brave_bridge_leaves_another_browsers_builtin(self):
        chromium, = self.own(self.address, MPRIS + "chromium.instance{pid}")
        brave, bridge = self.own(self.address, MPRIS + "brave.instance{pid}", MPRIS + "brave.instance{pid}_t1")
        self.assertEqual(self.covered(chromium, brave, bridge), {brave})
        self.assertEqual(self.covered(chromium, bridge), set())

    def test_separate_flatpak_apps_do_not_pair(self):
        brave_address, _ = self.proxy(MPRIS + "brave.*")
        chromium_address, _ = self.proxy(MPRIS + "chromium.*")
        brave, = self.own(brave_address, MPRIS + "brave.instance2")
        chromium, bridge = self.own(chromium_address, MPRIS + "chromium.instance2",
                                    MPRIS + "chromium.instance{pid}_t1")
        self.assertNotEqual(self.connection_pid(brave), self.connection_pid(bridge))
        self.assertEqual(self.covered(brave, chromium, bridge), {chromium})


if __name__ == "__main__":
    unittest.main()
