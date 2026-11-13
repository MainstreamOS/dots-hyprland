"""Exercise older-history paging and the sent-file check without a session bus or phone."""
import ast
import os
from pathlib import Path
import stat
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock


class BusError(Exception):
    def __init__(self, name):
        super().__init__(name)
        self.name = name


def bridge_functions(backend="rust-connect"):
    source = Path(__file__).resolve().parents[1] / "kdeconnect-bridge.py"
    names = {"older_thread", "finish_legacy_page", "on_message", "message_allowed",
             "stale_links", "sent_file_fingerprint"}
    tree = ast.parse(source.read_text())
    tree.body = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in names]
    glib = type("GLib", (), {"Variant": staticmethod(lambda sig, value: value), "Error": BusError,
                             "timeout_add_seconds": Mock()})
    gio = type("Gio", (), {"DBusError": type("DBusError", (), {
        "get_remote_error": staticmethod(lambda error: error.name)})})
    scope = {"os": os, "stat": stat, "threads": {}, "listed_threads": {}, "deleted_conversations": {},
             "loading_threads": set(), "legacy_pages": {}, "THREAD_PAGE_SIZE": 100, "backend": backend,
             "emit": Mock(), "save_threads_soon": Mock(), "call": Mock(), "background": Mock(),
             "device_path": lambda d: d, "CONVERSATIONS_IFACE": "conversations",
             "message": lambda d, m: m, "GLib": glib, "Gio": gio}
    exec(compile(tree, str(source), "exec"), scope)
    return scope


def row(uid, date, thread=7):
    return {"thread": thread, "uid": uid, "date": date, "type": 1}


class OlderHistoryTests(unittest.TestCase):
    def test_a_page_keeps_its_own_thread_up_to_the_boundary(self):
        bridge = bridge_functions()
        rows = [row(n, 1000 - n) for n in range(100)] + [row("other", 5, thread=8), row("newer", 2000)]
        bridge["call"].return_value = (rows,)
        bridge["older_thread"]("phone", 7, 1000, 100, {})
        event = bridge["emit"].call_args
        self.assertEqual(event.args, ("olderThread",))
        self.assertEqual([m["uid"] for m in event.kwargs["messages"]], list(range(100)))
        self.assertTrue(event.kwargs["more"])

    def test_a_short_page_is_the_last(self):
        bridge = bridge_functions()
        bridge["call"].return_value = ([row("first", 900), row("boundary", 1000)],)
        bridge["older_thread"]("phone", 7, 1000, 100, {})
        self.assertFalse(bridge["emit"].call_args.kwargs["more"])

    def test_kde_connect_pages_by_offset_and_collects_the_reported_messages(self):
        bridge = bridge_functions("KDE Connect")
        bridge["call"].side_effect = [BusError("org.freedesktop.DBus.Error.UnknownMethod"), None]
        fields = {"request": "r1", "device": "phone", "thread": 7}
        bridge["older_thread"]("phone", 7, 1000, 100, fields)
        self.assertEqual(bridge["call"].call_args.args[2:4], ("requestConversation", (7, 100, 200)))
        bridge["emit"].assert_not_called()
        for n in range(100):
            bridge["on_message"]("phone", Mock(unpack=lambda n=n: (row(n, 999 - n),)))
        page = next(call for call in bridge["emit"].call_args_list if call.args == ("olderThread",))
        self.assertEqual(page.kwargs["request"], "r1")
        self.assertEqual(len(page.kwargs["messages"]), 100)
        self.assertTrue(page.kwargs["more"])
        self.assertEqual(bridge["legacy_pages"], {})

    def test_other_bus_failures_are_reported(self):
        bridge = bridge_functions()
        bridge["call"].side_effect = BusError("org.freedesktop.DBus.Error.Failed")
        with self.assertRaises(BusError):
            bridge["older_thread"]("phone", 7, 1000, 100, {})
        self.assertEqual(bridge["call"].call_count, 1)


class SentLinkTests(unittest.TestCase):
    def setUp(self):
        self.bridge = bridge_functions()
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = os.path.join(self.directory.name, "Pasted image.png")
        Path(self.path).write_bytes(b"first picture")

    def link(self, **fields):
        return {"uid": "sent", "path": self.path, **fields}

    def test_a_fingerprint_follows_the_file_and_not_the_device_number(self):
        info = os.stat(self.path)
        fingerprint = self.bridge["sent_file_fingerprint"](info)
        fields = {name: getattr(info, name) for name in ("st_ino", "st_size", "st_mtime_ns", "st_ctime_ns")}
        rebooted = SimpleNamespace(st_dev=info.st_dev + 1, **fields)
        self.assertEqual(self.bridge["sent_file_fingerprint"](rebooted), fingerprint)
        self.assertEqual(self.bridge["stale_links"]([self.link(fingerprint=fingerprint)]), [])
        Path(self.path).write_bytes(b"second picture")
        self.assertEqual(self.bridge["stale_links"]([self.link(fingerprint=fingerprint)]), ["sent"])

    def test_links_without_a_fingerprint_go_by_the_send_time(self):
        modified = os.stat(self.path).st_mtime_ns // 1_000_000
        self.assertEqual(self.bridge["stale_links"]([self.link(since=modified + 5)]), [])
        self.assertEqual(self.bridge["stale_links"]([self.link(since=modified - 5)]), ["sent"])
        self.assertEqual(self.bridge["stale_links"]([self.link()]), [])

    def test_a_missing_file_is_stale(self):
        os.unlink(self.path)
        self.assertEqual(self.bridge["stale_links"]([self.link(since=1)]), ["sent"])


if __name__ == "__main__":
    unittest.main()
