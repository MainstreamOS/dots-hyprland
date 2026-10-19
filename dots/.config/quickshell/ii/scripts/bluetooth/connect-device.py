#!/usr/bin/env python3
"""Connect advertised Bluetooth services without forcing an audio codec/profile."""
import argparse
import json
import re
import sys
import time

from gi.repository import Gio, GLib

DEVICE = "org.bluez.Device1"
HFP_AG = "0000111f-0000-1000-8000-00805f9b34fb"
HSP_AG = "00001112-0000-1000-8000-00805f9b34fb"
A2DP_SINK = "0000110b-0000-1000-8000-00805f9b34fb"
A2DP_SOURCE = "0000110a-0000-1000-8000-00805f9b34fb"
HFP_HF = "0000111e-0000-1000-8000-00805f9b34fb"
HSP_HS = "00001108-0000-1000-8000-00805f9b34fb"
HID = "00001124-0000-1000-8000-00805f9b34fb"
HOGP = "00001812-0000-1000-8000-00805f9b34fb"
LE_AUDIO = {"0000184e-0000-1000-8000-00805f9b34fb", "00001850-0000-1000-8000-00805f9b34fb"}


def plan(properties):
    services = {uuid.lower() for uuid in properties.get("UUIDs", [])}
    icon = properties.get("Icon", "").lower()
    phone = icon == "phone" or ((int(properties.get("Class", 0)) >> 8) & 0x1f) == 2
    if phone or (HFP_AG in services and not services.intersection({A2DP_SINK, HFP_HF, HSP_HS})):
        # This is the REMOTE phone's Audio Gateway UUID. Requesting the
        # Hands-Free UUID here would ask the phone to behave as a headset.
        profile = HFP_AG if HFP_AG in services else HSP_AG if HSP_AG in services else ""
        return {"kind": "phone", "profile": profile, "automatic": bool(profile)}
    if services.intersection({HID, HOGP}):
        return {"kind": "input", "profile": "", "automatic": False}
    audio = services.intersection({A2DP_SINK, A2DP_SOURCE, HFP_HF, HSP_HS} | LE_AUDIO)
    return {"kind": "audio" if audio else "other", "profile": "", "automatic": bool(audio)}


def call(bus, path, interface, method, parameters=None):
    return bus.call_sync("org.bluez", path, interface, method, parameters,
                         None, Gio.DBusCallFlags.NONE, 20000, None)


def properties_for(bus, path):
    return call(bus, path, "org.freedesktop.DBus.Properties", "GetAll",
                GLib.Variant("(s)", (DEVICE,))).unpack()[0]


def connect(bus, path, automatic=False):
    properties = properties_for(bus, path)
    if properties.get("Connected") and not properties.get("ServicesResolved", True):
        deadline = time.monotonic() + 3
        while (properties.get("Connected") and not properties.get("ServicesResolved", True)
               and time.monotonic() < deadline):
            time.sleep(0.15)
            properties = properties_for(bus, path)
        if automatic and not properties.get("Connected"):
            return dict(plan(properties), skipped=True)
    selected = plan(properties)
    if automatic and (not selected["automatic"] or not properties.get("Paired")
                      or not properties.get("Trusted") or properties.get("Blocked")):
        return dict(selected, skipped=True)
    if properties.get("Blocked"):
        raise ValueError("Device is blocked")
    # Connect() is intentional even for an already-connected audio device:
    # a control-only link can still be missing its A2DP/HFP services. Let
    # BlueZ and WirePlumber negotiate codecs and honor saved audio preferences.
    if selected["profile"]:
        call(bus, path, DEVICE, "ConnectProfile", GLib.Variant("(s)", (selected["profile"],)))
    else:
        call(bus, path, DEVICE, "Connect")
        # A first manual connection can discover the phone's UUIDs. Complete
        # its call profile after that discovery rather than stopping at ACL.
        selected = plan(properties_for(bus, path))
        if selected["profile"]:
            call(bus, path, DEVICE, "ConnectProfile", GLib.Variant("(s)", (selected["profile"],)))
    return dict(selected, skipped=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device", help="BlueZ device object path")
    parser.add_argument("--automatic", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"/org/bluez/hci\d+/dev_(?:[0-9A-Fa-f]{2}_){5}[0-9A-Fa-f]{2}", args.device):
        parser.error("Invalid BlueZ device path")
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    try:
        result = connect(bus, args.device, args.automatic)
    except (GLib.Error, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print(json.dumps(result), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
