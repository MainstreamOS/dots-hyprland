#!/usr/bin/env python3
"""Bluetooth phone calls and iPhone alerts for the shell.

PipeWire: org.pipewire.Telephony (native Bluetooth hands-free calls).
oFono: org.ofono.VoiceCall (Bluetooth hands-free calls).
BlueZ: Apple Notification Center Service (iPhone alerts and call actions).
KDE Connect is handled by kdeconnect-bridge.py, not here.
"""
import collections
import json
import os
import re
import signal
import struct
import sys
import time
import uuid as uuid_module

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from phone_runtime import WorkQueue

from gi.repository import Gio, GLib, GLibUnix

SERVICE = "org.mainstream.PhoneCalls"
PATH = "/org/mainstream/PhoneCalls"
TELEPHONY = "org.pipewire.Telephony"
TELEPHONY_PATH = "/org/pipewire/Telephony"
ANCS_SOURCE = "9fbf120d-6301-42d9-8c58-25e699a21dbd"
ANCS_DATA = "22eac6e9-24d6-4bb5-be44-b36ace7c7bfb"
ANCS_CONTROL = "69d1d8f3-45e1-49a8-9821-9bbdfdaad9d9"
ANCS_DEADLINE = 8
DEVICE_STATE = {"Connected", "Paired", "ServicesResolved"}
LIVE_STATES = ("incoming", "waiting", "dialing", "alerting", "active", "held")
# A hands-free gateway can report a stale incoming call for a few seconds after
# it connects or the watcher starts, until the phone lists its real calls.
GATEWAY_SETTLE = 10


def unpack(value):
    if isinstance(value, GLib.Variant):
        return unpack(value.unpack())
    if isinstance(value, dict):
        return {k: unpack(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [unpack(v) for v in value]
    return value


ACTION_TIMEOUT = 5000  # ms for the phone to answer or hang up


def invoke(bus, service, path, interface, method, parameters=None, timeout=1500):
    return unpack(bus.call_sync(service, path, interface, method, parameters,
                               None, Gio.DBusCallFlags.NO_AUTO_START, timeout, None))


class AncsDecoder:
    """Decode fragmented Get Notification Attributes replies, bounded in size."""
    def __init__(self):
        self.buffer = bytearray()

    def feed(self, value):
        self.buffer.extend(value)
        if len(self.buffer) > 65536:
            self.buffer.clear()
            raise ValueError("ANCS reply exceeded the size limit")
        if len(self.buffer) < 5:
            return None
        if self.buffer[0] != 0:
            self.buffer.clear()
            raise ValueError("Unexpected ANCS command")
        uid = struct.unpack_from("<I", self.buffer, 1)[0]
        attributes = {}
        offset = 5
        while offset + 3 <= len(self.buffer):
            attribute, length = struct.unpack_from("<BH", self.buffer, offset)
            if offset + 3 + length > len(self.buffer):
                return None
            attributes[attribute] = bytes(self.buffer[offset + 3:offset + 3 + length]).decode("utf-8", "replace")
            offset += 3 + length
            if all(key in attributes for key in (0, 1, 3, 6, 7)):
                del self.buffer[:offset]
                return uid, attributes
        return None


class Watcher:
    def __init__(self):
        self.work = WorkQueue(workers=1, capacity=64, name="phone_calls")
        self.refresh_pending = False
        self.service_names = set()
        self.session = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.system = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        self.calls = {}
        self.call_targets = {}
        self.gateways = {}
        self.messages = collections.OrderedDict()
        self.notifications = collections.OrderedDict()
        self.devices = []
        self.ancs = {}
        self.ancs_paths = {}
        self.last_output = ""
        self.error = ""
        # Only device connection changes and ANCS characteristic values matter;
        # RSSI and media transport updates on the same signal are ignored.
        self.system.signal_subscribe("org.bluez", "org.freedesktop.DBus.Properties", "PropertiesChanged",
            None, "org.bluez.Device1", Gio.DBusSignalFlags.NONE, self.on_device_changed)
        self.system.signal_subscribe("org.bluez", "org.freedesktop.DBus.Properties", "PropertiesChanged",
            None, "org.bluez.GattCharacteristic1", Gio.DBusSignalFlags.NONE, self.on_characteristic_changed)
        self.system.signal_subscribe("org.ofono", "org.ofono.VoiceCall", "PropertyChanged",
            None, None, Gio.DBusSignalFlags.NONE, lambda *_: self.refresh())
        self.session.signal_subscribe(TELEPHONY, None, None,
            None, None, Gio.DBusSignalFlags.NONE, lambda *_: self.refresh())
        xml = f'''<node><interface name="{SERVICE}">
          <method name="Action"><arg type="s" direction="in"/><arg type="s" direction="in"/>
          <arg type="b" direction="out"/></method>
          </interface></node>'''
        info = Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0]
        # A method call is always answered: a full queue is a definite failure, not a caller timeout.
        self.session.register_object(PATH, info, lambda *args: self.dispatch(self.dbus_method, *args) or args[-1].return_dbus_error(
            SERVICE + ".Busy", "Phone calls are busy; try again"), None, None)
        result = invoke(self.session, "org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", "RequestName", GLib.Variant("(su)", (SERVICE, 4)))
        if result[0] != 1:
            raise RuntimeError("The phone call helper is already running")
        for bus in (self.session, self.system):
            bus.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
                "/org/freedesktop/DBus", None, Gio.DBusSignalFlags.NONE, self.owner_changed)
        self.system.signal_subscribe("org.bluez", "org.freedesktop.DBus.ObjectManager", None,
            None, None, Gio.DBusSignalFlags.NONE, lambda *_: self.refresh())
        self.system.signal_subscribe("org.ofono", "org.ofono.VoiceCallManager", None,
            None, None, Gio.DBusSignalFlags.NONE, lambda *_: self.refresh())
        GLib.timeout_add_seconds(15, self.refresh)
        self.refresh()

    def dispatch(self, function, *args, key=None):
        def work():
            try:
                function(*args)
            except Exception as error:
                self.error = "Phone update failed: " + str(error)
                self.emit()
        if not self.work.submit(key or (function.__name__, str(args)), work):
            # A full queue must not lose a call change; the next refresh reads it again.
            self.refresh()
            return False
        return True

    def owner_changed(self, connection, sender, path, interface, signal_name, parameters, *_):
        name = parameters.unpack()[0]
        if name not in (TELEPHONY, "org.ofono", "org.bluez"):
            return
        def reset():
            if name == "org.bluez":
                for device in list(self.ancs):
                    self.remove_ancs(device)
            self._refresh()
        self.dispatch(reset, key=("owner", name))

    def on_device_changed(self, connection, sender, path, interface, signal_name, parameters, *_):
        _, changed, invalidated = parameters.unpack()
        if DEVICE_STATE & (set(changed) | set(invalidated)):
            self.refresh()

    def on_characteristic_changed(self, *args):
        if args[2] in self.ancs_paths:
            self.dispatch(self.bluez_signal, *args)

    def emit(self):
        value = {"calls": list(self.calls.values()),
                 "messages": list(reversed(self.messages.values()))[:30],
                 "notifications": list(reversed(self.notifications.values()))[:30],
                 "devices": self.devices, "error": self.error}
        output = json.dumps(value, ensure_ascii=False)
        if output != self.last_output:
            GLib.idle_add(lambda: (print(output, flush=True), False)[1])
            self.last_output = output

    def refresh(self):
        if not self.refresh_pending:
            self.refresh_pending = True
            GLib.timeout_add(100, self.start_refresh)
        return True

    def start_refresh(self):
        self.refresh_pending = False
        self.dispatch(self._refresh, key="refresh")
        return False

    def _refresh(self):
        names = set()
        for bus in (self.session, self.system):
            try:
                names.update(invoke(bus, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListNames")[0])
            except GLib.Error:
                pass
        self.service_names = names
        self.devices = []
        self.refresh_pipewire()
        self.refresh_ofono()
        self.refresh_bluez()
        self.emit()

    def refresh_pipewire(self):
        if TELEPHONY not in self.service_names:
            self.clear_calls("pipewire:")
            self.gateways = {}
            return
        active = set()
        now = time.monotonic()
        try:
            objects = invoke(self.session, TELEPHONY, TELEPHONY_PATH,
                             "org.freedesktop.DBus.ObjectManager", "GetManagedObjects")[0]
            gateways = [path for path, interfaces in objects.items() if TELEPHONY + ".AudioGateway1" in interfaces]
            self.gateways = {path: self.gateways.get(path, now) for path in gateways}
            for path, interfaces in list(objects.items()):
                if TELEPHONY + ".AudioGateway1" in interfaces:
                    self.devices.append({"id": path, "backend": "PipeWire hands-free", "callAlerts": True})
                    # The root manager only lists gateways. Calls belong to
                    # each gateway's ObjectManager, not the root's tree.
                    try:
                        objects.update(invoke(self.session, TELEPHONY, path,
                            "org.freedesktop.DBus.ObjectManager", "GetManagedObjects")[0])
                    except GLib.Error:
                        continue
            for path, interfaces in objects.items():
                props = interfaces.get(TELEPHONY + ".Call1", {})
                state = props.get("State")
                if state not in LIVE_STATES:
                    continue
                identifier = "pipewire:" + path
                settled = now - self.gateways.get(path.rsplit("/", 1)[0], now) >= GATEWAY_SETTLE
                if state == "incoming" and not settled and identifier not in self.calls:
                    # Shown once the gateway has settled, if it is still ringing.
                    GLib.timeout_add_seconds(GATEWAY_SETTLE, lambda: (self.refresh(), False)[1])
                    continue
                active.add(identifier)
                self.call_targets[identifier] = ("pipewire", path)
                self.calls[identifier] = {"id": identifier, "backend": "PipeWire hands-free",
                    "name": props.get("Name", ""), "number": props.get("LineIdentification", ""),
                    "state": state, "picture": "", "canPositive": state == "incoming",
                    "canNegative": state != "held", "positiveLabel": "Accept" if state == "incoming" else "",
                    "negativeLabel": "Decline" if state in ("incoming", "waiting") else "End call"}
        except GLib.Error:
            return
        self.clear_calls("pipewire:", keep=active)

    def refresh_ofono(self):
        if "org.ofono" not in self.service_names:
            self.clear_calls("ofono:")
            return
        active = set()
        try:
            modems = invoke(self.system, "org.ofono", "/", "org.ofono.Manager", "GetModems")[0]
            for modem, properties in modems:
                if "org.ofono.VoiceCallManager" not in properties.get("Interfaces", []):
                    continue
                self.devices.append({"id": modem, "backend": "Bluetooth hands-free", "callAlerts": True})
                calls = invoke(self.system, "org.ofono", modem, "org.ofono.VoiceCallManager", "GetCalls")[0]
                for path, props in calls:
                    if props.get("State") not in LIVE_STATES:
                        continue
                    identifier = "ofono:" + path
                    active.add(identifier)
                    self.call_targets[identifier] = ("ofono", path)
                    incoming = props.get("State") in ("incoming", "waiting")
                    self.calls[identifier] = {"id": identifier, "backend": "Bluetooth hands-free",
                        "name": props.get("Name", ""), "number": props.get("LineIdentification", ""),
                        "state": props.get("State"), "picture": "", "canPositive": incoming,
                        "canNegative": True, "positiveLabel": "Answer" if incoming else "",
                        "negativeLabel": "Decline" if incoming else "End call"}
        except GLib.Error:
            return
        self.clear_calls("ofono:", keep=active)

    def refresh_bluez(self):
        if "org.bluez" not in self.service_names:
            return
        try:
            objects = invoke(self.system, "org.bluez", "/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects")[0]
        except GLib.Error:
            return
        connected = {path for path, interfaces in objects.items()
                     if interfaces.get("org.bluez.Device1", {}).get("Connected")
                     and interfaces.get("org.bluez.Device1", {}).get("Paired")
                     and interfaces.get("org.bluez.Device1", {}).get("ServicesResolved", True)}
        groups = {}
        for path, interfaces in objects.items():
            uuid = interfaces.get("org.bluez.GattCharacteristic1", {}).get("UUID", "").lower()
            if uuid not in (ANCS_SOURCE, ANCS_DATA, ANCS_CONTROL):
                continue
            device = next((d for d in connected if path.startswith(d + "/")), None)
            if device:
                groups.setdefault(device, {})[uuid] = path
        for device, chars in groups.items():
            if len(chars) != 3:
                continue
            if device not in self.ancs and not self.start_ancs(device, chars):
                continue
            self.devices.append({"id": device, "backend": "iPhone notification sharing", "callAlerts": True, "messageAlerts": True})
        for device in list(self.ancs):
            if len(groups.get(device, {})) != 3:
                self.remove_ancs(device)

    def start_ancs(self, device, chars):
        self.ancs[device] = {"decoder": AncsDecoder(), "pending": collections.deque(), "current": None,
                             "flags": {}, "session": uuid_module.uuid4().hex, "control": chars[ANCS_CONTROL], "started": time.time()}
        for uuid in (ANCS_DATA, ANCS_SOURCE):
            self.ancs_paths[chars[uuid]] = (device, uuid)
            try:
                invoke(self.system, "org.bluez", chars[uuid], "org.bluez.GattCharacteristic1", "StartNotify")
            except GLib.Error as error:
                self.error = "Enable Share System Notifications on the paired iPhone: " + error.message.split(":")[-1]
                self.remove_ancs(device)
                return False
        self.error = ""
        return True

    def clear_calls(self, prefix, keep=()):
        for identifier in list(self.calls):
            if identifier.startswith(prefix) and identifier not in keep:
                self.calls.pop(identifier, None)
                self.call_targets.pop(identifier, None)

    def remove_ancs(self, device):
        self.ancs.pop(device, None)
        paths = [p for p, value in self.ancs_paths.items() if value[0] == device]
        for path in paths:
            try:
                invoke(self.system, "org.bluez", path, "org.bluez.GattCharacteristic1", "StopNotify")
            except GLib.Error:
                pass
            self.ancs_paths.pop(path, None)
        prefix = "ancs:" + device + ":"
        self.clear_calls(prefix)
        for collection in (self.messages, self.notifications):
            for identifier in list(collection):
                if identifier.startswith(prefix):
                    collection.pop(identifier, None)

    def bluez_signal(self, bus, sender, path, interface, signal_name, parameters, *_):
        if path not in self.ancs_paths:
            return
        iface, properties, _ = unpack(parameters)
        if iface != "org.bluez.GattCharacteristic1" or "Value" not in properties:
            return
        device, uuid = self.ancs_paths[path]
        if device not in self.ancs:
            return
        state = self.ancs[device]
        data = bytes(properties["Value"])
        if uuid == ANCS_SOURCE:
            if len(data) != 8:
                return
            event, flags, category, count, uid = struct.unpack("<BBBBI", data)
            identifier = "ancs:" + device + ":" + state["session"] + ":" + str(uid)
            if event == 2:
                state["flags"].pop(uid, None)
                state["pending"] = collections.deque(v for v in state["pending"] if v != uid)
                self.calls.pop(identifier, None)
                self.messages.pop(identifier, None)
                self.notifications.pop(identifier, None)
                self.call_targets.pop(identifier, None)
                self.emit()
                return
            # Do not alert for historical notifications delivered on reconnect.
            if flags & 4 and category != 1:
                return
            state["flags"][uid] = (flags, category)
            if uid != state["current"] and uid not in state["pending"]:
                state["pending"].append(uid)
            while len(state["pending"]) > 30:
                state["flags"].pop(state["pending"].popleft(), None)
            self.request_ancs(device)
        elif uuid == ANCS_DATA:
            try:
                result = state["decoder"].feed(data)
                if result is None:
                    return
                uid, attributes = result
                if uid != state["current"]:
                    return
                flags_category = state["flags"].get(uid)
                if flags_category:
                    flags, category = flags_category
                    identifier = "ancs:" + device + ":" + state["session"] + ":" + str(uid)
                    value = {"id": identifier, "backend": "iPhone", "name": attributes.get(1, ""),
                             "appName": attributes.get(0, ""), "time": time.time() * 1000,
                             "number": "", "deviceId": device, "body": attributes.get(3, ""), "picture": "",
                             "positiveLabel": attributes.get(6, ""), "negativeLabel": attributes.get(7, ""),
                             "canPositive": bool(flags & 8), "canNegative": bool(flags & 16)}
                    if category == 1:
                        self.calls[identifier] = {**value, "state": "incoming"}
                        self.call_targets[identifier] = ("ancs", device, uid)
                    elif category == 4 and attributes.get(0) == "com.apple.MobileSMS":
                        self.messages[identifier] = {**value, "live": True}
                        while len(self.messages) > 30:
                            self.messages.popitem(last=False)
                    else:
                        self.notifications[identifier] = value
                        while len(self.notifications) > 30:
                            self.notifications.popitem(last=False)
                    self.emit()
                state["current"] = None
                self.request_ancs(device)
            except (ValueError, GLib.Error):
                state["current"] = None
                state["decoder"].buffer.clear()
                self.error = "iPhone notification read failed"
                self.emit()
                self.request_ancs(device)

    def expire_ancs(self):
        for device, state in list(self.ancs.items()):
            if state["current"] is None or time.time() - state["started"] <= ANCS_DEADLINE:
                continue
            state["flags"].pop(state["current"], None)
            state["current"] = None
            state["decoder"].buffer.clear()
            self.request_ancs(device)

    def request_ancs(self, device):
        state = self.ancs.get(device)
        if state is None or state["current"] is not None or not state["pending"]:
            return
        uid = state["pending"].popleft()
        state["current"] = uid
        state["started"] = time.time()
        GLib.timeout_add_seconds(ANCS_DEADLINE + 1, lambda: (self.dispatch(self.expire_ancs, key="ancs_deadlines"), False)[1])
        command = b"\0" + struct.pack("<I", uid) + b"\0\1" + struct.pack("<H", 256)
        command += b"\3" + struct.pack("<H", 2048) + b"\6\7"
        try:
            self.ancs_write(state["control"], command)
        except GLib.Error:
            state["current"] = None
            self.error = "iPhone notification permission is unavailable"
            self.emit()
            if state["pending"]:
                GLib.timeout_add(250, lambda: (self.dispatch(self.request_ancs, device), False)[1])

    def ancs_write(self, path, data):
        invoke(self.system, "org.bluez", path, "org.bluez.GattCharacteristic1", "WriteValue",
               GLib.Variant("(aya{sv})", (list(data), {"type": GLib.Variant("s", "request")})))

    def dbus_method(self, connection, sender, path, interface, method, parameters, invocation):
        identifier, action = parameters.unpack() if method == "Action" else ("", "")
        target = self.call_targets.get(identifier)
        value = self.calls.get(identifier, {})
        if action not in ("positive", "negative") or target is None \
                or not value.get("canPositive" if action == "positive" else "canNegative"):
            invocation.return_value(GLib.Variant("(b)", (False,)))
            return
        try:
            if target[0] == "pipewire":
                invoke(self.session, TELEPHONY, target[1], TELEPHONY + ".Call1",
                       "Answer" if action == "positive" else "Hangup", timeout=ACTION_TIMEOUT)
            elif target[0] == "ofono":
                invoke(self.system, "org.ofono", target[1], "org.ofono.VoiceCall",
                       "Answer" if action == "positive" else "Hangup", timeout=ACTION_TIMEOUT)
            else:
                state = self.ancs.get(target[1])
                if state is None:
                    raise ValueError("Phone disconnected")
                self.ancs_write(state["control"], b"\2" + struct.pack("<I", target[2])
                                + bytes([0 if action == "positive" else 1]))
            invocation.return_value(GLib.Variant("(b)", (True,)))
            GLib.timeout_add(300, lambda: (self.refresh(), False)[1])
        except Exception as error:
            self.error = "Phone action failed: " + str(error)
            self.emit()
            timed_out = isinstance(error, GLib.Error) and error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.TIMED_OUT)
            invocation.return_dbus_error(SERVICE + (".Timeout" if timed_out else ".Failed"), str(error))


def direct_dial(number):
    # Strip presentation separators, but do not turn arbitrary text into a
    # different dial string. HFP accepts an optional '+' and up to 80 digits.
    clean = re.sub(r"[\s().-]", "", str(number or ""))
    if not re.fullmatch(r"\+?[0-9*#]{1,80}", clean):
        raise ValueError("The contact does not have a valid phone number")

    # Discover first, then send exactly one Dial request. A timeout may mean
    # the phone accepted it; retrying through another backend can dial twice.
    session = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    gateways = []
    try:
        objects = invoke(session, TELEPHONY, TELEPHONY_PATH,
                         "org.freedesktop.DBus.ObjectManager", "GetManagedObjects")[0]
        gateways = [path for path, interfaces in objects.items()
                    if TELEPHONY + ".AudioGateway1" in interfaces]
    except GLib.Error:
        pass
    if gateways:
        if len(gateways) != 1:
            raise ValueError("More than one hands-free phone is connected")
        invoke(session, TELEPHONY, gateways[0], TELEPHONY + ".AudioGateway1",
               "Dial", GLib.Variant("(s)", (clean,)), timeout=15000)
        return

    system = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    try:
        modems = invoke(system, "org.ofono", "/", "org.ofono.Manager", "GetModems")[0]
    except GLib.Error:
        modems = []
    managers = [path for path, properties in modems
                if "org.ofono.VoiceCallManager" in properties.get("Interfaces", [])]
    if len(managers) != 1:
        raise ValueError("Connect one phone over Bluetooth for call controls")
    invoke(system, "org.ofono", managers[0], "org.ofono.VoiceCallManager",
           "Dial", GLib.Variant("(ss)", (clean, "default")), timeout=15000)


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "action":
        if len(sys.argv) != 4 or sys.argv[3] not in ("positive", "negative"):
            raise ValueError("Expected action ID positive|negative")
        bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        try:
            # Room for a queued action plus the phone's own ACTION_TIMEOUT; never sent twice.
            accepted = invoke(bus, SERVICE, PATH, SERVICE, "Action", GLib.Variant("(ss)", tuple(sys.argv[2:])),
                              timeout=ACTION_TIMEOUT + 3000)[0]
        except GLib.Error as error:
            if (error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.TIMED_OUT)
                    or Gio.DBusError.get_remote_error(error) == SERVICE + ".Timeout"):
                print(str(error), file=sys.stderr)
                sys.exit(2)  # no answer: the phone may still act on it
            raise
        if not accepted:
            raise ValueError("Phone action is no longer available")
        return
    if command == "dial":
        if len(sys.argv) != 3:
            raise ValueError("Expected dial NUMBER")
        direct_dial(sys.argv[2])
        return
    if command != "watch":
        raise ValueError("Expected watch, dial NUMBER or action ID positive|negative")
    watcher = Watcher()
    loop = GLib.MainLoop()
    parent_pid = os.getppid()
    def parent_alive():
        # A crashed shell can leave the helper holding its D-Bus name, blocking
        # the recovered shell's helper. Release it when our launcher exits.
        if os.getppid() != parent_pid:
            loop.quit()
            return False
        return True
    GLib.timeout_add_seconds(2, parent_alive)
    for sig in (signal.SIGINT, signal.SIGTERM):
        GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, sig, lambda: (loop.quit(), False)[1])
    try:
        loop.run()
    finally:
        watcher.work.close()
        try:
            invoke(watcher.session, "org.freedesktop.DBus", "/org/freedesktop/DBus",
                   "org.freedesktop.DBus", "ReleaseName", GLib.Variant("(s)", (SERVICE,)))
        except GLib.Error:
            pass


if __name__ == "__main__":
    try:
        main()
    except (GLib.Error, ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
