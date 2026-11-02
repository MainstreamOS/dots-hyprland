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
    names = {"load_threads", "save_threads", "conversations", "refresh_conversation_list", "on_message"}
    tree = ast.parse(source.read_text())
    tree.body = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in names]
    scope = {"json": json, "os": __import__("os"), "threads": {}, "listed_threads": {},
             "known_reachable": set(), "emit": Mock(), "save_threads_soon": Mock(),
             "call": Mock(), "device_path": lambda d: d, "CONVERSATIONS_IFACE": "conversations",
             "load_active": Mock(return_value=[]), "dedup_addresses": lambda a: a,
             "resync_soon": Mock(),
             "loading_threads": set(), "started_ms": 1000, "message": lambda d, m: m}
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

    def test_online_list_does_not_restore_deleted_threads_from_history(self):
        self.bridge["known_reachable"] = {"phone"}
        self.bridge["load_active"].return_value = [self.kept]
        self.bridge["conversations"]("phone")
        self.assertEqual(self.listed(), [self.kept])
        self.assertIn(("phone", 1), self.bridge["threads"])
        self.bridge["call"].assert_called_once()

    def test_reset_can_be_empty_and_late_threads_still_arrive(self):
        self.bridge["refresh_conversation_list"]("phone")
        self.assertEqual(self.listed(), [])
        self.assertEqual(self.bridge["listed_threads"]["phone"], set())
        self.bridge["on_message"]("phone", Mock(unpack=lambda: (self.kept,)))
        self.assertEqual(self.bridge["listed_threads"]["phone"], {2})
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


if __name__ == "__main__":
    unittest.main()
