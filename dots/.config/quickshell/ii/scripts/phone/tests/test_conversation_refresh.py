"""Exercise the bridge's cache/list boundary without a session bus or phone."""
import ast
import contextlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock


def bridge_functions():
    source = Path(__file__).resolve().parents[1] / "kdeconnect-bridge.py"
    names = {"load_threads", "save_threads", "conversations", "refresh_conversation_list", "on_message",
             "message_allowed", "listed_messages", "apply_deletions", "publish_deletions", "delete_conversations"}
    tree = ast.parse(source.read_text())
    tree.body = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in names]
    scope = {"json": json, "os": __import__("os"), "threads": {}, "listed_threads": {}, "deleted_conversations": {},
             "known_reachable": set(), "emit": Mock(), "save_threads_soon": Mock(),
             "call": Mock(), "device_path": lambda d: d, "CONVERSATIONS_IFACE": "conversations",
             "load_active": Mock(return_value=[]), "dedup_addresses": lambda a: a,
             "resync_soon": Mock(),
             "loading_threads": set(), "started_ms": 1000, "message": lambda d, m: m,
             "sync_deletions": Mock(), "requested": set(), "forget_attachments": Mock(),
             "media_metadata": {}, "valid_device": lambda d: True, "valid_uid": lambda u: True,
             "GLib": type("GLib", (), {"Variant": staticmethod(lambda sig, value: value)})}
    exec(compile(tree, str(source), "exec"), scope)
    return scope


class ConversationRefreshTests(unittest.TestCase):
    def setUp(self):
        self.bridge = bridge_functions()
        self.old = {"thread": 1, "uid": "old", "date": 10, "type": 1}
        self.kept = {"thread": 2, "uid": "kept", "date": 20, "type": 1}
        self.bridge["threads"] = {("phone", 1): {"old": self.old}, ("phone", 2): {"kept": self.kept}}

    def listed(self):
        return next(call.kwargs["items"] for call in reversed(self.bridge["emit"].call_args_list)
                    if call.args == ("conversations",))

    def test_partial_online_list_keeps_the_previous_membership(self):
        self.bridge["known_reachable"] = {"phone"}
        self.bridge["load_active"].return_value = [self.kept]
        self.bridge["conversations"]("phone")
        self.assertEqual(self.listed(), [self.kept, self.old])
        self.assertIn(("phone", 1), self.bridge["threads"])
        self.bridge["call"].assert_called_once()

    def test_empty_or_partial_reset_never_collapses_the_visible_list(self):
        self.bridge["listed_threads"]["phone"] = {1, 2}
        self.bridge["refresh_conversation_list"]("phone")
        self.assertEqual(self.listed(), [self.kept, self.old])
        self.assertEqual(self.bridge["listed_threads"]["phone"], {1, 2})
        self.bridge["on_message"]("phone", Mock(unpack=lambda: (self.kept,)))
        self.assertEqual(self.bridge["listed_threads"]["phone"], {1, 2})
        self.assertEqual(self.bridge["emit"].call_args.kwargs["message"], self.kept)

    def test_offline_and_failed_reads_keep_the_last_list_without_resurrecting_old_history(self):
        self.bridge["listed_threads"]["phone"] = {2}
        self.bridge["conversations"]("phone")
        self.assertEqual(self.listed(), [self.kept])
        self.bridge["call"].assert_not_called()
        self.bridge["known_reachable"] = {"phone"}
        self.bridge["load_active"].side_effect = RuntimeError("bus timed out")
        self.bridge["conversations"]("phone")
        self.assertEqual(self.listed(), [self.kept])
        self.assertEqual(self.bridge["listed_threads"]["phone"], {2})

    def test_failed_reset_snapshot_keeps_the_list_and_retries(self):
        self.bridge["listed_threads"]["phone"] = {2}
        self.bridge["load_active"].side_effect = RuntimeError("bus timed out")
        self.bridge["refresh_conversation_list"]("phone")
        self.assertEqual(self.bridge["listed_threads"]["phone"], {2})
        self.bridge["emit"].assert_not_called()
        self.bridge["resync_soon"].assert_called_once_with("phone")

    def test_saved_list_survives_bridge_restart_and_keeps_history_separate(self):
        with tempfile.TemporaryDirectory() as directory:
            filename = str(Path(directory) / "threads.json")

            @contextlib.contextmanager
            def atomic_file(path, **_):
                with open(path, "w") as output:
                    yield output

            self.bridge.update(threads_cache_file=filename, atomic_file=atomic_file)
            self.bridge["listed_threads"]["phone"] = {2}
            self.bridge["save_threads"]()
            restarted = bridge_functions()
            restarted["threads_cache_file"] = filename
            restarted["load_threads"]()
            self.assertIn(("phone", 1), restarted["threads"])
            self.assertEqual(restarted["listed_threads"]["phone"], {2})
            restarted["conversations"]("phone")
            event = restarted["emit"].call_args_list[0]
            self.assertEqual(event.kwargs["items"], [self.kept])

    def test_cache_replay_is_not_a_new_incoming_message(self):
        replay = {"thread": 8, "uid": "replayed", "date": 2000, "type": 1}
        self.bridge["on_message"]("phone", Mock(unpack=lambda: (replay,)))
        self.assertFalse(self.bridge["emit"].call_args.kwargs["live"])
        self.bridge["on_message"]("phone", Mock(unpack=lambda: (replay,)), True)
        self.assertTrue(self.bridge["emit"].call_args.kwargs["live"])

    def test_deletion_blocks_replay_but_preserves_new_messages_and_other_devices(self):
        self.bridge["threads"][("other", 1)] = {"old": self.old}
        self.bridge["listed_threads"]["phone"] = {1, 2}
        self.bridge["apply_deletions"]("phone", {1: 1000})
        self.assertNotIn(("phone", 1), self.bridge["threads"])
        self.assertIn(("other", 1), self.bridge["threads"])
        self.bridge["on_message"]("phone", Mock(unpack=lambda: (self.old,)), True)
        self.bridge["emit"].assert_not_called()
        new = {"thread": 1, "uid": "new", "date": 1001, "type": 1}
        self.bridge["on_message"]("phone", Mock(unpack=lambda: (new,)), True)
        self.assertEqual(self.bridge["threads"][("phone", 1)], {"new": new})

    def test_deletion_survives_cache_reload_and_reconciles_before_the_list(self):
        with tempfile.TemporaryDirectory() as directory:
            filename = str(Path(directory) / "threads.json")
            @contextlib.contextmanager
            def atomic_file(path, **_):
                with open(path, "w") as output:
                    yield output
            self.bridge.update(threads_cache_file=filename, atomic_file=atomic_file)
            self.bridge["apply_deletions"]("phone", {1: 1000})
            self.bridge["save_threads"](strict=True)
            restarted = bridge_functions()
            restarted["threads_cache_file"] = filename
            restarted["load_threads"]()
            self.assertFalse(restarted["message_allowed"]("phone", self.old))
            restarted["publish_deletions"]("phone")
            self.assertEqual(restarted["emit"].call_args.kwargs, {"device":"phone", "threads":[1], "before":1000})

    def test_failed_backend_delete_does_not_modify_or_ack_local_history(self):
        self.bridge["call"].side_effect = RuntimeError("unsupported")
        with self.assertRaises(RuntimeError):
            self.bridge["delete_conversations"]("phone", [1])
        self.assertIn(("phone", 1), self.bridge["threads"])
        self.assertFalse(self.bridge["deleted_conversations"])
        self.bridge["emit"].assert_not_called()


if __name__ == "__main__":
    unittest.main()
