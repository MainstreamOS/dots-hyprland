#!/usr/bin/env python3
"""Synced lyrics for one song from LRCLIB (https://lrclib.net) or YouTube captions.

Usage: lyrics.py <title> <artist> <duration in seconds, 0 when unknown> [youtube_id]

Prints a single line:
    <time>§<text>§<time>§<text>§...§ok    the song's synced lyrics or captions
    not_found                             no synced lyrics or captions found
    no_info                               the title or the artist is missing
    offline                               the service could not be reached
    rate_limited§<seconds>                LRCLIB asked for no requests until then
"""
import email.utils
import html
import json
import math
import os
import re
import subprocess
import sys
import time
import urllib.parse
import xml.etree.ElementTree as ET

API = "https://lrclib.net/api"
HOMEPAGE = "https://mainstreamos.org"
TIMEOUT = 5
# Used when LRCLIB asks for a pause without saying how long.
DEFAULT_RETRY_AFTER = 60
YT_PLAYER_API = "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"
YT_USER_AGENT = "com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip"


class RateLimited(Exception):
    def __init__(self, seconds: int):
        super().__init__(seconds)
        self.seconds = seconds


class RequestFailure(OSError):
    pass


def _installed_version():
    # The markers the updater itself reads: the release an update last
    # applied, or the one the ISO was built from.
    clone = os.environ.get("MAINSTREAM_DOTFILES_DIR") or os.path.expanduser("~/.cache/dots-hyprland")
    for path in (os.path.join(clone, ".updatems-applied-tag"), "/etc/mainstream-dotfiles-tag"):
        try:
            with open(path, encoding="utf-8") as f:
                tag = f.read().strip()
        except OSError:
            continue
        if re.fullmatch(r"\d{1,2}\.\d+\.\d+", tag):
            return tag
    return None


def _user_agent() -> str:
    version = _installed_version()
    client = f"Mainstream OS Lyrics/{version}" if version else "Mainstream OS Lyrics"
    return f"{client} ({HOMEPAGE})"


def _retry_after(value) -> int:
    seconds = DEFAULT_RETRY_AFTER
    if value:
        value = value.strip()
        if value.isdigit():
            seconds = int(value)
        else:
            try:
                seconds = int(email.utils.parsedate_to_datetime(value).timestamp() - time.time())
            except (TypeError, ValueError, OverflowError):
                pass
    return min(max(seconds, 1), 24 * 60 * 60)


def _get(endpoint: str, params: dict, user_agent: str):
    """The decoded JSON answer, or None when LRCLIB has no such record."""
    query = urllib.parse.urlencode(params, quote_via=urllib.parse.quote)
    # curl races IPv4/IPv6 connections and negotiates HTTP/2. urllib tries
    # addresses serially, which can strand a lookup on a stalled network path.
    # Keep retries in the shared service so two lyric views never double them.
    response = subprocess.run(
        ["curl", "--silent", "--show-error", "--compressed",
         "--connect-timeout", "2", "--max-time", str(TIMEOUT),
         "--max-filesize", "2097152", "--proto", "=https",
         "--user-agent", user_agent, "--header", "Accept: application/json",
         "--write-out", "\n%{http_code}\n%header{retry-after}",
         f"{API}/{endpoint}?{query}"],
        capture_output=True, text=True, timeout=TIMEOUT + 1,
    )
    if response.returncode:
        raise RequestFailure(f"curl exited with status {response.returncode}")
    body, status, retry_after = response.stdout.rsplit("\n", 2)
    code = int(status)
    if code == 404:
        return None
    if code in (429, 503):
        raise RateLimited(_retry_after(retry_after))
    if code != 200:
        raise RequestFailure(f"HTTP {code}")
    return json.loads(body)


_TIMESTAMP = re.compile(r"\[(\d+):(\d+(?:[.:]\d+)?)\]")


def _parse_lrc(lrc_text: str) -> list:
    lines = []
    for raw in lrc_text.splitlines():
        raw = raw.strip()
        # A line can carry several timestamps when it is sung more than once.
        stamps = []
        while True:
            match = _TIMESTAMP.match(raw)
            if not match:
                break
            stamps.append(int(match.group(1)) * 60 + float(match.group(2).replace(":", ".")))
            raw = raw[match.end():]
        text = raw.strip()
        for stamp in stamps:
            lines.append({"time": stamp, "text": text})
    return sorted(lines, key=lambda line: line["time"])


def _is_match(record, title: str, artist: str) -> bool:
    if not isinstance(record, dict) or not record.get("syncedLyrics"):
        return False
    r_title = (record.get("trackName") or "").lower()
    r_artist = (record.get("artistName") or "").lower()
    t = title.lower()
    a = artist.lower()
    title_match = (t in r_title or r_title in t or
                   any(word in r_title for word in t.split() if len(word) > 3))
    artist_match = (a in r_artist or r_artist in a or
                    any(word in r_artist for word in a.split() if len(word) > 3))
    return title_match and artist_match


def fetch_lrclib(title: str, artist: str, duration: float) -> list:
    """Asks for the exact song first and searches once only if that fails.

    LRCLIB tells versions of a song apart by their length, so without one
    there is no exact song to ask for and the search is the only request.
    """
    user_agent = _user_agent()
    # Browser streams and long videos can report lengths outside LRCLIB's
    # accepted 1–3600 second range. Search still works without a duration.
    if math.isfinite(duration) and 1 <= round(duration) <= 3600:
        params = {"track_name": title, "artist_name": artist, "duration": round(duration)}
        record = _get("get", params, user_agent)
        if isinstance(record, dict) and record.get("instrumental"):
            return []
        if _is_match(record, title, artist):
            return _parse_lrc(record["syncedLyrics"])
    results = _get("search", {"track_name": title, "artist_name": artist}, user_agent)
    if isinstance(results, list):
        record = next((r for r in results if _is_match(r, title, artist)), None)
        if record:
            return _parse_lrc(record["syncedLyrics"])
    return []


def _yt_fetch(url: str, payload: str | None = None) -> str:
    """Fetches a YouTube endpoint via curl and returns its response body."""
    cmd = [
        "curl", "--silent", "--show-error", "--compressed",
        "--connect-timeout", "2", "--max-time", str(TIMEOUT),
        "--max-filesize", "2097152", "--proto", "=https",
        "--user-agent", YT_USER_AGENT,
    ]
    if payload is not None:
        cmd.extend(["--header", "Content-Type: application/json", "--data-raw", payload])
    cmd.extend(["--write-out", "\n%{http_code}", url])
    response = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT + 1)
    if response.returncode:
        raise RequestFailure(f"curl exited with status {response.returncode}")
    body, status = response.stdout.rsplit("\n", 1)
    code = int(status)
    if code != 200:
        raise RequestFailure(f"HTTP {code}")
    return body


def _preferred_lang() -> str:
    """Two-letter language prefix from LC_ALL/LANG, defaulting to 'en'."""
    locale = os.environ.get("LC_ALL") or os.environ.get("LANG") or ""
    base = locale.split(".", 1)[0].split("@", 1)[0].split("_", 1)[0].split("-", 1)[0].lower()
    if len(base) == 2 and base.isalpha():
        return base
    return "en"


def _pick_caption_track(tracks: list) -> dict:
    """Selects the best caption track matching the user's preferred language."""
    lang = _preferred_lang()

    def rank(track: dict) -> int:
        code = (track.get("languageCode") or "").lower()
        asr = track.get("kind") == "asr"
        if code == lang:
            return 2 if asr else 0
        if code.startswith(f"{lang}-") or code.startswith(f"{lang}_"):
            return 3 if asr else 1
        if code == "en":
            return 6 if asr else 4
        if code.startswith("en-") or code.startswith("en_"):
            return 7 if asr else 5
        return 8

    return min(tracks, key=rank)


def fetch_youtube_captions(video_id: str) -> list:
    """Fetches synced captions for a YouTube video ID via the player API."""
    payload = json.dumps({
        "context": {
            "client": {
                "clientName": "ANDROID",
                "clientVersion": "20.10.38",
                "hl": "en",
                "gl": "US",
            }
        },
        "videoId": video_id,
    })
    data = json.loads(_yt_fetch(YT_PLAYER_API, payload))
    captions = data.get("captions") if isinstance(data, dict) else None
    renderer = captions.get("playerCaptionsTracklistRenderer") if isinstance(captions, dict) else None
    raw_tracks = renderer.get("captionTracks") if isinstance(renderer, dict) else None
    tracks = [t for t in (raw_tracks or []) if isinstance(t, dict) and t.get("baseUrl")]
    if not tracks:
        return []

    chosen = _pick_caption_track(tracks)
    xml_body = _yt_fetch(chosen["baseUrl"])
    if not xml_body.strip():
        return []
    try:
        root = ET.fromstring(xml_body)
    except ET.ParseError as err:
        raise RequestFailure("Invalid caption XML") from err

    lines = []
    for p in root.iter("p"):
        if "t" not in p.attrib:
            continue
        stamp = round(int(p.attrib["t"]) / 1000.0, 2)
        raw_text = re.sub(r"(?:>{2,}|\u00bb+)", " ", html.unescape("".join(p.itertext())))
        text = " ".join(raw_text.split())
        if not text:
            continue
        if lines and lines[-1]["text"] == text and abs(lines[-1]["time"] - stamp) < 0.05:
            continue
        lines.append({"time": stamp, "text": text})
    return sorted(lines, key=lambda line: line["time"])


def main():
    youtube_id = sys.argv[4].strip() if len(sys.argv) >= 5 else ""
    if not youtube_id and (len(sys.argv) < 4 or not sys.argv[1] or not sys.argv[2]):
        print("no_info", flush=True)
        return
    title = sys.argv[1] if len(sys.argv) > 1 else ""
    artist = sys.argv[2] if len(sys.argv) > 2 else ""
    try:
        duration = float(sys.argv[3]) if len(sys.argv) > 3 else 0
    except ValueError:
        duration = 0
    try:
        lines = fetch_youtube_captions(youtube_id) if youtube_id else fetch_lrclib(title, artist, duration)
    except RateLimited as limit:
        print(f"rate_limited§{limit.seconds}", flush=True)
        return
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        # Unreachable, timed out, a server error or an answer that was not
        # JSON: nothing says the song has no lyrics.
        detail = str(error) if isinstance(error, RequestFailure) else type(error).__name__
        print(f"Lyrics lookup failed: {detail}", file=sys.stderr, flush=True)
        print("offline", flush=True)
        return
    if not lines:
        print("not_found", flush=True)
        return
    parts = []
    for line in lines:
        parts.append(str(line["time"]))
        parts.append(line["text"].replace("§", ""))
    parts.append("ok")
    print("§".join(parts), flush=True)


if __name__ == "__main__":
    main()
