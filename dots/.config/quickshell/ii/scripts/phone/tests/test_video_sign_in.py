"""Playback sign-in is opt-in, YouTube-only, and never exports cookies."""
import ast
import configparser
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch
import urllib.parse


def resolver():
    source = Path(__file__).resolve().parents[1] / "link-preview.py"
    tree = ast.parse(source.read_text())
    tree.body = [n for n in tree.body if isinstance(n, ast.FunctionDef)
                 and n.name in {"on_host", "normalize_url", "get_stream_url", "browser_profile"}]
    scope = dict(os=os, re=__import__("re"), urllib=__import__("urllib"), hashlib=hashlib,
                 configparser=configparser, subprocess=Mock(), sys=__import__("sys"),
                 MEDIA_DIR="/unused", YTDLP_FORMAT="best", YTDLP_MERGED_FORMAT="merged",
                 cached_media=Mock(return_value=None))
    exec(compile(tree, str(source), "exec"), scope)
    return scope


class VideoSignInTests(unittest.TestCase):
    def test_disabled_or_non_youtube_never_reads_browser(self):
        for url, enabled in [("https://youtu.be/abcdefghijk", False),
                             ("https://example.org/video", True),
                             ("https://youtube.com.example.org/video", True)]:
            r = resolver()
            r["browser_profile"] = Mock()
            r["subprocess"].run.return_value = Mock(returncode=1)
            self.assertEqual(r["get_stream_url"](url, enabled)["status"], "error")
            r["browser_profile"].assert_not_called()

    def test_public_playback_never_needs_sign_in(self):
        r = resolver()
        r["browser_profile"] = Mock()
        r["subprocess"].run.return_value = Mock(returncode=0, stdout="https://cdn.example/video\n")
        self.assertEqual(r["get_stream_url"]("https://youtu.be/abcdefghijk", True)["status"], "ok")
        r["browser_profile"].assert_not_called()

    def test_authenticated_retry_uses_default_clients_and_no_cookie_export(self):
        r = resolver()
        r["browser_profile"] = Mock(return_value="firefox:/profile")
        r["subprocess"].run.side_effect = [Mock(returncode=1), Mock(returncode=1),
                                          Mock(returncode=0, stdout="https://cdn.example/video\n")]
        self.assertEqual(r["get_stream_url"]("https://youtu.be/abcdefghijk", True)["status"], "ok")
        calls = r["subprocess"].run.call_args_list
        self.assertNotIn("--cookies-from-browser", calls[0].args[0])
        command = calls[2].args[0]
        self.assertIn("--cookies-from-browser", command)
        self.assertIn("firefox:/profile", command)
        self.assertNotIn("--extractor-args", command)
        self.assertNotIn("--cookies", command)

    def test_missing_profile_keeps_normal_fallback(self):
        r = resolver()
        r["browser_profile"] = Mock(return_value="")
        r["subprocess"].run.return_value = Mock(returncode=1)
        self.assertEqual(r["get_stream_url"]("https://youtu.be/abcdefghijk", True)["status"], "error")
        self.assertEqual(r["subprocess"].run.call_count, 2)

    def test_install_default_wins_over_other_profile_default(self):
        r = resolver()
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, HOME=directory, XDG_CONFIG_HOME=directory):
            zen = Path(directory) / "zen"
            for name in ("active", "other"):
                (zen / name).mkdir(parents=True)
                (zen / name / "cookies.sqlite").touch()
            (zen / "profiles.ini").write_text("[Profile0]\nDefault=1\nPath=other\n[Install1]\nDefault=active\n")
            self.assertEqual(r["browser_profile"](), "firefox:" + str(zen / "active"))


if __name__ == "__main__":
    unittest.main()
