"""Playback sign-in is opt-in, YouTube-only, and never exports cookies. A stream is only handed
to the player when the player can open it."""
import ast
import base64
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
                 and n.name in {"on_host", "normalize_url", "get_stream_url", "browser_profile",
                                "single_quality_playlist", "time_left"}]
    scope = dict(os=os, re=__import__("re"), urllib=__import__("urllib"), hashlib=hashlib, base64=base64,
                 configparser=configparser, subprocess=Mock(), sys=__import__("sys"),
                 MEDIA_DIR="/unused", YTDLP_FORMAT="best", YTDLP_MERGED_FORMAT="merged", DOWNLOAD_BYTES="1M",
                 time=Mock(), YOUTUBE_PLAYBACK_SECONDS=40,
                 cached_media=Mock(return_value=None), youtube_hls=Mock(return_value=None),
                 stream_answers=Mock(return_value=True), public_url=Mock(return_value=True))
    scope["time"].monotonic.return_value = 0
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
        r["youtube_hls"].return_value = "http://127.0.0.1:1/list.m3u8"
        self.assertEqual(r["get_stream_url"]("https://youtu.be/abcdefghijk", True)["status"], "ok")
        r["browser_profile"].assert_not_called()
        r["subprocess"].run.assert_not_called()

    def test_authenticated_retry_uses_default_clients_and_no_cookie_export(self):
        r = resolver()
        r["browser_profile"] = Mock(return_value="firefox:/profile")
        r["subprocess"].run.return_value = Mock(returncode=1)
        r["youtube_hls"].side_effect = [None, "http://127.0.0.1:1/list.m3u8"]
        self.assertEqual(r["get_stream_url"]("https://youtu.be/abcdefghijk", True)["status"], "ok")
        first, second = (call.args[1] for call in r["youtube_hls"].call_args_list)
        self.assertEqual(first, [])
        self.assertEqual(second, ["--cookies-from-browser", "firefox:/profile"])
        r["subprocess"].run.assert_not_called()

    def test_youtube_attempts_share_one_deadline(self):
        r = resolver()
        r["browser_profile"] = Mock(return_value="firefox:/profile")
        r["time"].monotonic.side_effect = [100, 112, 125, 129]
        r["subprocess"].run.return_value = Mock(returncode=1)
        self.assertEqual(r["get_stream_url"]("https://youtu.be/abcdefghijk", True)["status"], "error")
        self.assertEqual([call.args[3] for call in r["youtube_hls"].call_args_list], [140, 140])
        self.assertEqual(r["subprocess"].run.call_args.kwargs["timeout"], 11)

    def test_missing_profile_keeps_normal_fallback(self):
        r = resolver()
        r["browser_profile"] = Mock(return_value="")
        r["subprocess"].run.return_value = Mock(returncode=1)
        self.assertEqual(r["get_stream_url"]("https://youtu.be/abcdefghijk", True)["status"], "error")
        self.assertEqual(r["subprocess"].run.call_count, 1)

    def test_refused_address_is_not_handed_to_the_player(self):
        r = resolver()
        r["stream_answers"].return_value = False
        r["subprocess"].run.return_value = Mock(returncode=0, stdout="https://cdn.example/video\n")
        result = r["get_stream_url"]("https://example.org/video")
        self.assertEqual(result["stream_url"], "")
        # The direct lookup, then the download that takes over from it.
        self.assertEqual(r["subprocess"].run.call_count, 2)

    def test_playlist_keeps_one_h264_quality_and_the_original_audio(self):
        r = resolver()
        original = base64.urlsafe_b64encode(b"\n\x05acont\x12\x08original").decode().rstrip("=")
        master = "\n".join([
            "#EXTM3U",
            '#EXT-X-MEDIA:URI="https://m.example/audio-bn.m3u8",TYPE=AUDIO,GROUP-ID="234",NAME="bn - dubbed-auto",DEFAULT=NO',
            f'#EXT-X-MEDIA:URI="audio-en.m3u8",TYPE=AUDIO,GROUP-ID="234",NAME="English",YT-EXT-XTAGS="{original}",DEFAULT=NO',
            '#EXT-X-STREAM-INF:BANDWIDTH=800,CODECS="avc1.4D401E,mp4a.40.2",RESOLUTION=640x360,AUDIO="234"',
            "https://m.example/360.m3u8",
            '#EXT-X-STREAM-INF:BANDWIDTH=4000,CODECS="vp09.00.40.08,mp4a.40.2",RESOLUTION=1280x720,AUDIO="234"',
            "https://m.example/720-vp9.m3u8",
            '#EXT-X-STREAM-INF:BANDWIDTH=3700,CODECS="avc1.4D4020,mp4a.40.2",RESOLUTION=1280x720,AUDIO="234"',
            "720-avc.m3u8",
            '#EXT-X-STREAM-INF:BANDWIDTH=6200,CODECS="avc1.64002A,mp4a.40.2",RESOLUTION=1920x1080,AUDIO="234"',
            "https://m.example/1080.m3u8",
        ])
        playlist = r["single_quality_playlist"](master, "https://m.example/master.m3u8")
        self.assertEqual(playlist.count("#EXT-X-STREAM-INF"), 1)
        self.assertTrue(playlist.rstrip().endswith("https://m.example/720-avc.m3u8"))
        self.assertEqual(playlist.count("#EXT-X-MEDIA"), 1)
        self.assertIn('URI="https://m.example/audio-en.m3u8"', playlist)
        self.assertIn("DEFAULT=YES", playlist)
        r["public_url"].return_value = False
        self.assertIsNone(r["single_quality_playlist"](master, "https://m.example/master.m3u8"))

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
