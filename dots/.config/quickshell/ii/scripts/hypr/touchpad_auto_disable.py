# Keeps the internal touchpad off while an external mouse is in use, and puts
# it back to the user's own setting once no such mouse is left.
#
# libinput has this as a send-events mode ("disabled on external mouse"), but
# Hyprland only lets a device be enabled or disabled, so the rule is kept here,
# reading the devices the way libinput does (evdev.c, evdev-mt-touchpad.c):
#
#   - An internal touchpad is a node udev marks ID_INPUT_TOUCHPAD whose
#     ID_INTEGRATION (or ID_INPUT_TOUCHPAD_INTEGRATION) says internal; without
#     either, anything but Bluetooth or Logitech counts as internal.
#   - An external mouse is a node udev marks ID_INPUT_MOUSE or
#     ID_INPUT_POINTINGSTICK, on the USB or Bluetooth bus, and not handled as a
#     tablet, tablet pad or touchpad first. A pointing stick also counts when
#     ID_INTEGRATION says external.
#   - The touchpad only goes off once such a mouse has sent pointer input, so a
#     keyboard or receiver that merely exposes a mouse node never takes it away.
#     A mouse this process cannot read (reading /dev/input takes the input
#     group) is never counted, since it could be one of those.
#
# Stricter than libinput where a wrong answer would leave a laptop with no
# pointer at all: uinput devices (their sysfs path runs through
# /devices/virtual/input) never count, ID_INTEGRATION=internal outranks the
# bus, joysticks and touchscreens never count, a node the kernel names
# "... Consumer Control" or "... System Control" is a keyboard's media and power
# keys whatever udev made of it, and a mouse or TrackPoint on the same device as
# the internal touchpad (a keyboard cover's own) is part of that device.
#
#   touchpad_auto_disable.py touchpads        "internal<TAB>name" for each touchpad
#                                             watch acts on, or when there is none,
#                                             "other<TAB>name" for the first device
#                                             named like a touchpad; names as
#                                             Hyprland gives them
#   touchpad_auto_disable.py mice             the external mice present now
#   touchpad_auto_disable.py watch <env.lua>  keep the touchpads in step until
#                                             stdin closes or a signal arrives
#
# watch takes one command per line on stdin: "reload" once Hyprland has
# replayed its config, which puts every touchpad back to its saved setting, and
# "settings" once env.lua has changed. It exits 3 when there is no internal
# touchpad, which is the caller's cue not to start it again until one may have
# appeared. --root reads /sys, /run/udev and /dev/input from another tree.
import ctypes
import json
import os
import re
import select
import signal
import struct
import subprocess
import sys
import time

BUS_USB = 0x03
BUS_BLUETOOTH = 0x05
VENDOR_LOGITECH = 0x046D

KEYBOARD_NODE_SUFFIXES = (' Consumer Control', ' System Control')

EV_KEY = 0x01
EV_REL = 0x02
EV_ABS = 0x03
# Motion and wheel, hi-res wheel included, plus the mouse buttons. Anything
# else a node sends, a key on a combined keyboard and mouse node for one, is
# not the mouse being used.
POINTER_REL = {0x00, 0x01, 0x06, 0x08, 0x0B, 0x0C}
POINTER_ABS = {0x00, 0x01}
BTN_MOUSE_FIRST = 0x110
BTN_MOUSE_LAST = 0x117
INPUT_EVENT = struct.Struct('llHHi')

NO_TOUCHPAD = 3


def read_text(path):
    try:
        with open(path) as handle:
            return handle.read().strip()
    except (OSError, UnicodeDecodeError):
        return None


def udev_properties(root, device_id):
    text = read_text(os.path.join(root, 'run/udev/data', device_id))
    if text is None:
        return None
    props = {}
    for line in text.splitlines():
        if line.startswith('E:') and '=' in line:
            key, value = line[2:].split('=', 1)
            props[key] = value
    return props


def hex_attr(path):
    try:
        return int(read_text(path) or '', 16)
    except ValueError:
        return -1


class Node:
    def __init__(self, sysname, syspath, devnode, name, bus, vendor, props, parent_props):
        self.sysname = sysname
        self.syspath = syspath
        self.devnode = devnode
        self.name = name
        self.bus = bus
        self.vendor = vendor
        self.props = props
        self.parent_props = parent_props

    # libinput reads the ID_INPUT_* tags from the event node and from the input
    # device above it, so a tag set on either one counts.
    def tagged(self, key):
        return self.props.get(key) == '1' or self.parent_props.get(key) == '1'

    @property
    def virtual(self):
        return '/devices/virtual/input/' in self.syspath

    @property
    def ignored(self):
        if self.props.get('LIBINPUT_IGNORE_DEVICE', '0') != '0':
            return True
        seat = os.environ.get('XDG_SEAT') or 'seat0'
        return self.props.get('ID_SEAT', 'seat0') != seat


def input_nodes(root):
    base = os.path.join(root, 'sys/class/input')
    try:
        entries = os.listdir(base)
    except OSError:
        return None
    nodes = []
    for sysname in sorted(entries, key=lambda s: (len(s), s)):
        if not re.fullmatch(r'event\d+', sysname):
            continue
        link = os.path.join(base, sysname)
        devnum = read_text(os.path.join(link, 'dev'))
        # A node udev has not finished with has no database entry yet; its
        # "add" event follows once it has one.
        props = udev_properties(root, 'c' + devnum) if devnum else None
        if props is None:
            continue
        parent = os.path.realpath(os.path.join(link, 'device'))
        parent_props = udev_properties(root, '+input:' + os.path.basename(parent)) or {}
        nodes.append(Node(
            sysname=sysname,
            syspath=os.path.realpath(link),
            devnode=os.path.join(root, 'dev/input', sysname),
            name=read_text(os.path.join(parent, 'name')) or '',
            bus=hex_attr(os.path.join(parent, 'id/bustype')),
            vendor=hex_attr(os.path.join(parent, 'id/vendor')),
            props=props,
            parent_props=parent_props))
    return nodes


def is_external_mouse(node):
    if node.ignored or node.virtual:
        return False
    for tag in ('ID_INPUT_JOYSTICK', 'ID_INPUT_TABLET', 'ID_INPUT_TABLET_PAD',
                'ID_INPUT_TOUCHPAD', 'ID_INPUT_TOUCHSCREEN'):
        if node.tagged(tag):
            return False
    stick = node.tagged('ID_INPUT_POINTINGSTICK')
    if not (node.tagged('ID_INPUT_MOUSE') or stick):
        return False
    if node.name.endswith(KEYBOARD_NODE_SUFFIXES):
        return False
    integration = node.props.get('ID_INTEGRATION')
    if integration == 'internal':
        return False
    return node.bus in (BUS_USB, BUS_BLUETOOTH) or (stick and integration == 'external')


# systemd's hwdb calls the touchpad of some keyboard covers internal (the
# Surface Type Cover, the ThinkPad X1 Tablet keyboard) on the touchpad's node
# alone, so the same cover's mouse or TrackPoint node still reads as a removable
# USB or Bluetooth device. udev gives every node of one physical device the same
# LIBINPUT_DEVICE_GROUP, and nothing built into the touchpad's own device is an
# external mouse.
def external_mice(nodes):
    groups = {n.props.get('LIBINPUT_DEVICE_GROUP') for n in nodes if is_internal_touchpad(n)}
    groups.discard(None)
    groups.discard('')
    return [n for n in nodes
            if is_external_mouse(n) and n.props.get('LIBINPUT_DEVICE_GROUP') not in groups]


def is_internal_touchpad(node):
    if node.ignored or node.virtual or not node.tagged('ID_INPUT_TOUCHPAD'):
        return False
    # A tablet's touch surface is not a laptop's touchpad, whatever its port.
    if node.tagged('ID_INPUT_TABLET'):
        return False
    for key in ('ID_INTEGRATION', 'ID_INPUT_TOUCHPAD_INTEGRATION'):
        value = node.props.get(key)
        if value == 'internal':
            return True
        if value == 'external':
            return False
    return node.bus != BUS_BLUETOOTH and node.vendor != VENDOR_LOGITECH


# Hyprland's deviceNameToInternalString: spaces, newlines and commas become
# dashes and ASCII letters are lowered, byte by byte.
def hyprland_name(name):
    out = ''.join('-' if c in ' \n,' else (c.lower() if 'A' <= c <= 'Z' else c) for c in name)
    return out or 'unknown-device'


def hyprland_mice():
    try:
        result = subprocess.run(['hyprctl', 'devices', '-j'], capture_output=True, text=True, timeout=5)
        devices = json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    if not isinstance(devices, dict):
        return None
    return [m['name'] for m in devices.get('mice', []) if isinstance(m, dict) and isinstance(m.get('name'), str)]


# A name goes inside a quoted Lua string in hl.device(), so one carrying a quote
# or a backslash is never used.
def usable(name):
    return '"' not in name and '\\' not in name


def named_touchpad(mice):
    return [m for m in mice if 'touchpad' in m.lower() and usable(m)][:1]


def resolve_touchpads(nodes, mice):
    if nodes is None:
        return named_touchpad(mice)
    internal = [n for n in nodes if is_internal_touchpad(n)]
    # Hyprland numbers a second device of the same name "-1", "-2" and so on, so
    # a numbered name is this touchpad unless another device is called exactly that.
    taken = {hyprland_name(n.name) for n in nodes}
    names = []
    for node in internal:
        base = hyprland_name(node.name)
        numbered = re.compile(re.escape(base) + r'-\d+')
        for mouse in mice:
            if mouse == base or (numbered.fullmatch(mouse) and mouse not in taken):
                if usable(mouse) and mouse not in names:
                    names.append(mouse)
    if internal and not names:
        names = named_touchpad(mice)
    return names


BLOCK = re.compile(r'-- BEGIN touchpad-enable[^\n]*\n(.*?)-- END touchpad-enable', re.S)
STATEMENT = re.compile(r'^\s*hl\.device\(\s*\{\s*name\s*=\s*"([^"\\]*)"\s*,\s*enabled\s*=\s*(true|false)\s*\}\s*\)')


# The on/off each touchpad was given on the Mouse page. A touchpad with no
# statement there is on, as Hyprland has it.
def saved_settings(env_lua):
    text = read_text(env_lua) or ''
    settings = {}
    for block in BLOCK.findall(text):
        for line in block.splitlines():
            match = STATEMENT.match(line)
            if match:
                settings[match.group(1)] = match.group(2) == 'true'
    return settings


# Asks for SIGTERM when the parent goes, so a shell killed outright leaves no
# udevadm behind, and this script still puts the touchpad back.
def die_with_parent():
    try:
        ctypes.CDLL(None, use_errno=True).prctl(1, signal.SIGTERM)
    except (OSError, AttributeError):
        pass


class Stop(Exception):
    pass


class Mouse:
    def __init__(self, node):
        self.name = node.name
        self.devnode = node.devnode
        self.fd = None
        self.used = False
        self.unreadable = None
        try:
            self.fd = os.open(node.devnode, os.O_RDONLY | os.O_NONBLOCK | os.O_CLOEXEC)
        except OSError as error:
            # Being there is not enough: a receiver's or keyboard's idle mouse
            # node looks just like a mouse, and counting it would leave the
            # laptop with no pointer at all.
            self.unreadable = error.strerror or 'cannot open'

    def close(self):
        if self.fd is not None:
            try:
                os.close(self.fd)
            except OSError:
                pass
            self.fd = None

    # Reads what is waiting and stops listening at the first pointer event:
    # from then on the mouse counts as used until it is unplugged.
    def drain(self):
        while self.fd is not None:
            try:
                data = os.read(self.fd, INPUT_EVENT.size * 64)
            except BlockingIOError:
                return
            except OSError:
                self.close()
                return
            if not data:
                self.close()
                return
            whole = len(data) - len(data) % INPUT_EVENT.size
            for _, _, ev_type, code, value in INPUT_EVENT.iter_unpack(data[:whole]):
                if ((ev_type == EV_REL and code in POINTER_REL)
                        or (ev_type == EV_ABS and code in POINTER_ABS)
                        or (ev_type == EV_KEY and BTN_MOUSE_FIRST <= code <= BTN_MOUSE_LAST and value == 1)):
                    self.used = True
                    self.close()
                    return


class Watcher:
    DEBOUNCE = 0.3
    RETRY_FIRST = 1.0
    RETRY_MAX = 30.0

    def __init__(self, root, env_lua):
        self.root = root
        self.env_lua = env_lua
        self.touchpads = []
        self.saved = {}
        self.applied = {}
        self.mice = {}
        self.was_in_use = False
        self.monitor = None
        self.monitor_started = 0.0
        self.monitor_buffer = b''
        self.stdin_buffer = b''
        self.rescan_at = None
        self.settings_at = None
        self.monitor_at = None
        self.retry = self.RETRY_FIRST
        self.told_unreadable = False

    def say(self, text):
        try:
            print(text, flush=True)
        except OSError:
            pass

    def eval(self, touchpad, enabled):
        statement = 'hl.device({ name = "%s", enabled = %s })' % (touchpad, 'true' if enabled else 'false')
        try:
            return subprocess.run(['hyprctl', 'eval', statement], stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL, timeout=5).returncode == 0
        except (OSError, subprocess.SubprocessError):
            return False

    def in_use(self):
        return [m for m in self.mice.values() if m.used]

    # Only what differs from what this process last told Hyprland is sent,
    # unless forced: a config reload or Settings > Mouse may have moved the
    # touchpad without this process knowing.
    def apply(self, force=()):
        in_use = self.in_use()
        for touchpad in self.touchpads:
            want = self.saved.get(touchpad, True) and not in_use
            if touchpad not in force and self.applied.get(touchpad) == want:
                continue
            if self.eval(touchpad, want):
                self.applied[touchpad] = want
        if bool(in_use) != self.was_in_use:
            self.was_in_use = bool(in_use)
            if in_use:
                self.say('%s in use, touchpad off' % in_use[0].name)
            else:
                self.say('no external mouse in use, touchpad back to its setting')

    def refresh_touchpads(self, nodes):
        mice = hyprland_mice()
        if mice is None:
            return
        found = resolve_touchpads(nodes, mice)
        if found:
            self.touchpads = found

    def rescan(self):
        nodes = input_nodes(self.root)
        present = {n.syspath: n for n in external_mice(nodes or [])}
        for syspath in list(self.mice):
            if syspath not in present:
                self.mice.pop(syspath).close()
        for syspath, node in present.items():
            if syspath not in self.mice:
                mouse = self.mice[syspath] = Mouse(node)
                if mouse.unreadable and not self.told_unreadable:
                    self.told_unreadable = True
                    self.say('cannot read %s (%s), so %s is not counted; reading input devices '
                             'takes the input group' % (mouse.devnode, mouse.unreadable, mouse.name))
        self.refresh_touchpads(nodes)
        self.apply()

    def start_monitor(self):
        self.monitor_at = None
        try:
            self.monitor = subprocess.Popen(
                ['udevadm', 'monitor', '--udev', '--subsystem-match=input'],
                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                preexec_fn=die_with_parent)
        except OSError:
            self.monitor = None
            self.monitor_failed()
            return
        os.set_blocking(self.monitor.stdout.fileno(), False)
        self.monitor_started = time.monotonic()
        self.monitor_buffer = b''

    def monitor_failed(self):
        ran_long = False
        if self.monitor is not None:
            ran_long = time.monotonic() - self.monitor_started > 60
            try:
                self.monitor.stdout.close()
                self.monitor.kill()
                self.monitor.wait(timeout=2)
            except (OSError, subprocess.SubprocessError):
                pass
            self.monitor = None
        # Only a monitor that ran for a while starts the wait over. One that
        # could not be started at all keeps backing off, or a missing udevadm
        # would be retried, and the devices listed again, every second.
        if ran_long:
            self.retry = self.RETRY_FIRST
        self.say('input monitor stopped, restarting in %gs' % self.retry)
        self.monitor_at = time.monotonic() + self.retry
        self.retry = min(self.retry * 2, self.RETRY_MAX)

    def read_monitor(self):
        try:
            data = os.read(self.monitor.stdout.fileno(), 65536)
        except BlockingIOError:
            return
        except OSError:
            data = b''
        if not data:
            self.monitor_failed()
            return
        self.monitor_buffer += data
        *lines, self.monitor_buffer = self.monitor_buffer.split(b'\n')
        if any(line.startswith(b'UDEV') for line in lines):
            self.rescan_at = time.monotonic() + self.DEBOUNCE

    def read_stdin(self):
        try:
            data = os.read(0, 4096)
        except BlockingIOError:
            return
        except OSError:
            data = b''
        if not data:
            raise Stop()
        self.stdin_buffer += data
        *lines, self.stdin_buffer = self.stdin_buffer.split(b'\n')
        for line in lines:
            command = line.strip()
            if command == b'reload':
                self.saved = saved_settings(self.env_lua)
                self.refresh_touchpads(input_nodes(self.root))
                self.apply(force=set(self.touchpads))
            elif command == b'settings':
                self.settings_at = time.monotonic() + self.DEBOUNCE

    # Settings > Mouse applies the on/off itself, even when it picks the one
    # already saved, so while a mouse is in use the touchpad it may just have
    # switched on has to go off again. What env.lua says cannot tell whether
    # that happened, so every touchpad is set.
    def settings_changed(self):
        self.saved = saved_settings(self.env_lua)
        self.apply(force=set(self.touchpads))

    # Only a touchpad this process moved away from its saved setting is put
    # back, so one the user switched off stays off.
    def restore(self):
        saved = saved_settings(self.env_lua)
        for touchpad in self.touchpads:
            want = saved.get(touchpad, True)
            if touchpad in self.applied and self.applied[touchpad] != want:
                self.eval(touchpad, want)

    def loop(self):
        while True:
            poller = select.poll()
            poller.register(0, select.POLLIN)
            if self.monitor is not None:
                poller.register(self.monitor.stdout.fileno(), select.POLLIN)
            waiting = {m.fd: m for m in self.mice.values() if m.fd is not None}
            for fd in waiting:
                poller.register(fd, select.POLLIN)
            deadlines = [t for t in (self.rescan_at, self.settings_at, self.monitor_at) if t is not None]
            timeout = None
            if deadlines:
                timeout = max(0, int((min(deadlines) - time.monotonic()) * 1000) + 1)
            for fd, _ in poller.poll(timeout):
                if fd == 0:
                    self.read_stdin()
                elif self.monitor is not None and fd == self.monitor.stdout.fileno():
                    self.read_monitor()
                elif fd in waiting:
                    mouse = waiting[fd]
                    mouse.drain()
                    if mouse.used:
                        self.apply()
            now = time.monotonic()
            if self.monitor_at is not None and now >= self.monitor_at:
                self.start_monitor()
                # Whatever came or went while nothing was listening.
                if self.monitor is not None:
                    self.rescan_at = now
            if self.settings_at is not None and now >= self.settings_at:
                self.settings_at = None
                self.settings_changed()
            if self.rescan_at is not None and now >= self.rescan_at:
                self.rescan_at = None
                self.rescan()

    def run(self):
        mice = hyprland_mice()
        if mice is None:
            self.say('could not list input devices')
            return 1
        self.touchpads = resolve_touchpads(input_nodes(self.root), mice)
        if not self.touchpads:
            return NO_TOUCHPAD
        self.saved = saved_settings(self.env_lua)
        os.set_blocking(0, False)
        parent = os.getppid()
        die_with_parent()
        try:
            for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
                signal.signal(signum, self.stop)
            # A parent gone before the request was made sends no signal.
            if os.getppid() != parent:
                raise Stop()
            # Listening starts before the first look, so a mouse plugged in
            # between the two is not missed. Nothing has been applied yet, so
            # the first look sets every touchpad, which also undoes a watcher
            # that was killed with its touchpad off.
            self.start_monitor()
            self.rescan()
            self.loop()
        except Stop:
            pass
        finally:
            for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
                signal.signal(signum, signal.SIG_IGN)
            self.restore()
            for mouse in self.mice.values():
                mouse.close()
            if self.monitor is not None:
                self.monitor.terminate()
                try:
                    self.monitor.wait(timeout=2)
                except subprocess.SubprocessError:
                    self.monitor.kill()
        return 0

    def stop(self, signum, frame):
        raise Stop()


def main(argv):
    root = '/'
    if len(argv) > 2 and argv[1] == '--root':
        root = argv[2]
        argv = argv[:1] + argv[3:]
    command = argv[1] if len(argv) > 1 else ''
    if command == 'touchpads':
        mice = hyprland_mice()
        if mice is not None:
            internal = resolve_touchpads(input_nodes(root), mice)
            for name in internal:
                print('internal\t' + name)
            # The on/off row on the Mouse page also serves a touchpad the udev
            # rule leaves out, a USB or Bluetooth one for one.
            if not internal:
                for name in named_touchpad(mice):
                    print('other\t' + name)
        return 0
    if command == 'mice':
        for node in external_mice(input_nodes(root) or []):
            print('%s\t%s' % (node.sysname, node.name))
        return 0
    if command == 'watch' and len(argv) > 2:
        return Watcher(root, argv[2]).run()
    sys.stderr.write('usage: touchpad_auto_disable.py [--root DIR] touchpads | mice | watch <env.lua>\n')
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
