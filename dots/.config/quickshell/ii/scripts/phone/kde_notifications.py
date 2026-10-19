"""KDE Connect notification lookups and device-scoped actions for the phone bridge."""

import html
import hashlib
import json
import re
import time

from phone_runtime import valid_device
from gi.repository import Gio, GLib

BUS = "org.kde.kdeconnect"
ROOT = "/modules/kdeconnect"
IFACE = "org.kde.kdeconnect.device.notifications"
ITEM = IFACE + ".notification"


def plain(value):
    return " ".join(html.unescape(re.sub(r"<[^>]*>", " ", str(value or ""))).split()).casefold()


def identity(item):
    fields = [item.get(key, "") for key in ("device", "internalId", "replyId", "appName", "title", "text")]
    return hashlib.sha256(json.dumps(fields, ensure_ascii=False).encode()).hexdigest()


class NotificationIndex:
    def __init__(self, bus):
        self.bus = bus
        self.items = []
        self.revision = 0
        self.snapshot_revision = -1
        self.updated = 0

    def invalidate(self, *_):
        self.revision += 1

    def call(self, path, interface, method, args=None):
        result = self.bus.call_sync(BUS, path, interface, method, args, None,
                                    Gio.DBusCallFlags.NO_AUTO_START, 2000, None)
        return result.unpack() if result is not None else ()

    def properties(self, path, interface):
        return self.call(path, "org.freedesktop.DBus.Properties", "GetAll", GLib.Variant("(s)", (interface,)))[0]

    def snapshot(self, fresh=False):
        revision = self.revision
        if not fresh and self.snapshot_revision == revision and time.monotonic() - self.updated < 10:
            return self.items
        devices = self.call(ROOT, "org.kde.kdeconnect.daemon", "devices", GLib.Variant("(bb)", (True, True)))[0]
        items = []
        for device in devices:
            path = ROOT + "/devices/" + device
            try:
                name = self.properties(path, "org.kde.kdeconnect.device").get("name", "")
                keys = self.call(path + "/notifications", IFACE, "activeNotifications")[0]
            except GLib.Error:
                continue
            for key in keys:
                item_path = path + "/notifications/" + str(key)
                try:
                    props = self.properties(item_path, ITEM)
                except GLib.Error:
                    continue
                items.append({"device": device, "deviceName": name, "key": str(key), "path": item_path,
                              **{k: str(props.get(k, "")) for k in ("internalId", "replyId", "appName", "title", "text", "ticker")},
                              "dismissable": bool(props.get("dismissable", False))})
        self.items = items
        self.snapshot_revision = revision
        self.updated = time.monotonic()
        return items

    def inspect(self, request, items):
        # This only discovers metadata for a live desktop notification. An
        # ambiguous match must never become permission to act on a conversation.
        source = request.get("source", "")
        app = plain(request.get("app"))
        title = plain(request.get("summary"))
        body = plain(request.get("body"))
        matches = []
        for item, item_app, item_title, texts in items:
            if source and source not in (item["device"], item["deviceName"]):
                continue
            if app == item_app and title == item_title and body and body in texts:
                matches.append(item)
        if len(matches) != 1:
            return {}
        return {**{key: matches[0][key] for key in ("device", "internalId", "replyId", "appName", "key", "dismissable")}, "identity": identity(matches[0])}

    def execute(self, request):
        kind = request.get("cmd")
        if kind == "inspect":
            items = [(item, plain(item["appName"]), plain(item["title"]), (plain(item["text"]), plain(item["ticker"])))
                     for item in self.snapshot()]
            return [{"notificationId": r["notificationId"], "info": self.inspect(r, items)}
                    for r in request.get("items", [])[:64]]
        device = request.get("device", "")
        internal = request.get("internalId", "")
        if not valid_device(device) or not internal:
            raise ValueError("This phone notification has no verified identity")
        # Always revalidate actions against the active objects. A saved replyId
        # alone must not authorize a reply to an expired or replaced notification.
        matches = [i for i in self.snapshot(fresh=True) if i["device"] == device and i["internalId"] == internal]
        if len(matches) != 1:
            raise ValueError("This notification is no longer available on the phone")
        item = matches[0]
        if request.get("identity") != identity(item):
            raise ValueError("This notification changed on the phone; review it before trying again")
        if kind == "reply":
            if not item["replyId"] or item["replyId"] != request.get("replyId") or not request.get("text", "").strip():
                raise ValueError("This notification no longer accepts replies")
            self.call(item["path"], ITEM, "sendReply", GLib.Variant("(s)", (request["text"],)))
        elif kind == "action":
            label = request.get("label", "")
            props = self.properties(item["path"], ITEM)
            if not label or ("actions" in props and label not in props["actions"]):
                raise ValueError("This action is no longer available on the phone")
            self.call(ROOT + "/devices/" + device + "/notifications", IFACE, "sendAction", GLib.Variant("(ss)", (internal, label)))
        elif kind == "dismiss" and item["dismissable"]:
            self.call(item["path"], ITEM, "dismiss")
        else:
            raise ValueError("Unsupported phone notification action")
        self.invalidate()
        return {}
