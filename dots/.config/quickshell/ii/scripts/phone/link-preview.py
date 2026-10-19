#!/usr/bin/env python3
"""
link-preview.py - Extract rich embed metadata and media previews for links
(YouTube, TikTok, Instagram, Facebook, Twitter/X, Spotify, and general websites).

Usage:
  link-preview.py batch <url1> <url2> ...
  link-preview.py stream <url>
"""

import sys
import os
import re
import json
import hashlib
import fcntl
import ipaddress
import socket
import time
import http.client
import struct
import urllib.error
import urllib.request
import urllib.parse
import subprocess
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from phone_runtime import LINK_PREVIEWS, atomic_file, image_extension

CACHE_DIR = str(LINK_PREVIEWS)
THUMBS_DIR = os.path.join(CACHE_DIR, "thumbs")
MEDIA_DIR = os.path.join(CACHE_DIR, "media")
INDEX_FILE = os.path.join(CACHE_DIR, "index.json")

os.makedirs(THUMBS_DIR, exist_ok=True)
os.makedirs(MEDIA_DIR, exist_ok=True)

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
PAGE_BYTES = 2 << 20
JSON_BYTES = 1 << 20
IMAGE_BYTES = 8 << 20
RETRY_SECONDS = 600
MEDIA_EXTS = (".mp4", ".webm", ".mkv", ".mov", ".m4a", ".mp3")


def on_host(url, *domains):
    host = (urllib.parse.urlparse(url).hostname or "").lower()
    return any(host == d or host.endswith("." + d) for d in domains)


def public_url(url):
    """Links in received messages are fetched without asking, so never on this
    computer or its local network."""
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        return False
    try:
        addresses = {info[4][0] for info in socket.getaddrinfo(parsed.hostname, parsed.port or 443)}
    except (OSError, UnicodeError):
        return False
    return all(ipaddress.ip_address(a.split("%")[0]).is_global for a in addresses)


class PublicRedirects(urllib.request.HTTPRedirectHandler):
    """Follows a redirect only to another public address."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not public_url(newurl):
            raise urllib.error.URLError("redirect to a non-public address")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def check_peer(sock):
    """The address actually connected to must be public too, whatever DNS answers after public_url checked it."""
    address = sock.getpeername()[0].split("%")[0]
    if not ipaddress.ip_address(address).is_global:
        sock.close()
        raise OSError("connected to a non-public address")


class PublicHTTPConnection(http.client.HTTPConnection):
    def connect(self):
        super().connect()
        check_peer(self.sock)


class PublicHTTPSConnection(http.client.HTTPSConnection):
    def connect(self):
        super().connect()
        check_peer(self.sock)


def proxied(req):
    """Whether this request goes through a proxy, which resolves the name itself and is the peer."""
    return bool(getattr(req, "_tunnel_host", None)) or req.has_proxy()


class PublicHTTPHandler(urllib.request.HTTPHandler):
    def http_open(self, req):
        return self.do_open(http.client.HTTPConnection if proxied(req) else PublicHTTPConnection, req)


class PublicHTTPSHandler(urllib.request.HTTPSHandler):
    def https_open(self, req):
        connection = http.client.HTTPSConnection if proxied(req) else PublicHTTPSConnection
        return self.do_open(connection, req, context=self._context)


# Every direct connection is checked, a host the proxy settings exempt included.
urllib.request.install_opener(urllib.request.build_opener(PublicRedirects, PublicHTTPHandler, PublicHTTPSHandler))

FETCH_SECONDS = 15
IMAGE_PIXELS = 40_000_000


def read_body(resp, limit):
    """At most limit + 1 bytes; a body still arriving after FETCH_SECONDS is abandoned."""
    deadline = time.monotonic() + FETCH_SECONDS
    chunks, size = [], 0
    while size <= limit:
        if time.monotonic() > deadline:
            raise TimeoutError("response took too long")
        chunk = getattr(resp, "read1", resp.read)(min(1 << 16, limit + 1 - size))  # read1: what has arrived
        if not chunk:
            break
        chunks.append(chunk)
        size += len(chunk)
    return b"".join(chunks)


def image_pixels(data):
    """Width times height from a PNG, GIF, JPEG or WebP header, or 0 when it cannot be read."""
    try:
        if data[:8] == b"\x89PNG\r\n\x1a\n":
            w, h = struct.unpack(">II", data[16:24])
        elif data[:6] in (b"GIF87a", b"GIF89a"):
            w, h = struct.unpack("<HH", data[6:10])
        elif data[:4] == b"RIFF" and data[8:12] == b"WEBP":
            if data[12:16] == b"VP8X":
                w, h = int.from_bytes(data[24:27], "little") + 1, int.from_bytes(data[27:30], "little") + 1
            elif data[12:16] == b"VP8L":
                bits = int.from_bytes(data[21:25], "little")
                w, h = (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1
            else:
                w, h = struct.unpack("<HH", data[26:30])
                w, h = w & 0x3FFF, h & 0x3FFF
        elif data[:2] == b"\xff\xd8":
            i = 2
            while i + 9 < len(data):
                if data[i] != 0xFF:
                    return 0
                marker, length = data[i + 1], struct.unpack(">H", data[i + 2:i + 4])[0]
                if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                    h, w = struct.unpack(">HH", data[i + 5:i + 9])
                    break
                i += 2 + length
            else:
                return 0
        else:
            return 0
        return w * h
    except struct.error:
        return 0


def cached_media(*hashes):
    """A finished download for one of these URL hashes; yt-dlp's partial files do not count."""
    for name in os.listdir(MEDIA_DIR):
        path = os.path.join(MEDIA_DIR, name)
        if (name.split(".", 1)[0] in hashes and name.endswith(MEDIA_EXTS) and name.count(".") == 1
                and os.path.getsize(path) > 1000):
            return {"stream_url": f"file://{path}", "status": "ok"}
    return None

def load_index():
    if os.path.exists(INDEX_FILE):
        try:
            with open(INDEX_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}

def save_index_batch(entries):
    if not entries:
        return
    try:
        with open(INDEX_FILE + ".lock", "a+") as lock:
            os.chmod(lock.name, 0o600)
            fcntl.flock(lock, fcntl.LOCK_EX)
            index = load_index()
            index.update(entries)
            with atomic_file(INDEX_FILE, prefix="index-") as output:
                json.dump(index, output, separators=(",", ":"))
    except OSError as error:
        print(f"Error saving link preview index: {error}", file=sys.stderr)


def fetch_and_cache_thumb(img_url, key):
    if not img_url:
        return ""
    img_url = img_url.replace("&amp;", "&")
    for ext in ("jpg", "png", "webp", "gif"):
        local_path = os.path.join(THUMBS_DIR, f"{key}.{ext}")
        if os.path.exists(local_path) and os.path.getsize(local_path) > 0:
            return local_path
    try:
        req = urllib.request.Request(
            img_url,
            headers={
                "User-Agent": USER_AGENT,
                "Referer": "https://www.google.com/"
            }
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = read_body(resp, IMAGE_BYTES)
        # Larger than the cap is never kept as a cut copy; huge dimensions would be costly to decode.
        ext = image_extension(data) if len(data) <= IMAGE_BYTES and image_pixels(data) <= IMAGE_PIXELS else ""
        if ext:
            local_path = os.path.join(THUMBS_DIR, f"{key}.{ext}")
            with atomic_file(local_path, "wb", "thumb-") as output:
                output.write(data)
            return local_path
    except Exception as e:
        if getattr(e, "code", None) != 404:  # a missing YouTube resolution is expected
            print(f"Failed to cache thumbnail {img_url}: {e}", file=sys.stderr)
    return ""

def extract_youtube_id(url):
    m = re.search(r'(?:v=|\/|youtu\.be\/|shorts\/|embed\/)([a-zA-Z0-9_-]{11})', url)
    return m.group(1) if m else ""

def resolve_youtube(url):
    vid = extract_youtube_id(url)
    url_hash = hashlib.sha256(url.encode()).hexdigest()[:16]
    is_shorts = "/shorts/" in url
    oembed_url = f"https://www.youtube.com/oembed?url={urllib.parse.quote(url)}&format=json"
    title = ""
    author = ""
    candidates = [f"https://i.ytimg.com/vi/{vid}/{q}" for q in ("maxresdefault.jpg", "mqdefault.jpg")] if vid else []
    try:
        req = urllib.request.Request(oembed_url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=4) as resp:
            d = json.loads(read_body(resp, JSON_BYTES)[:JSON_BYTES].decode("utf-8"))
            title = d.get("title", "")
            author = d.get("author_name", "")
            if d.get("thumbnail_url"):
                candidates.append(d["thumbnail_url"])
    except Exception as e:
        print(f"YouTube oEmbed failed for {url}: {e}", file=sys.stderr)

    local_thumb = next((path for path in (fetch_and_cache_thumb(c, f"{url_hash}_yt") for c in candidates) if path), "")
    return {
        "url": url,
        "provider": "YouTube",
        "domain": "youtube.com",
        "title": title or "YouTube Video",
        "author": author,
        "description": author,
        "thumbnail": local_thumb,
        "media_type": "video",
        "playable": True,
        "aspect_ratio": (9 / 16) if is_shorts else (16 / 9)
    }

def resolve_tiktok(url):
    url_hash = hashlib.sha256(url.encode()).hexdigest()[:16]
    oembed_url = f"https://www.tiktok.com/oembed?url={urllib.parse.quote(url)}"
    title = ""
    author = ""
    thumb_url = ""
    try:
        req = urllib.request.Request(oembed_url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=4) as resp:
            d = json.loads(read_body(resp, JSON_BYTES)[:JSON_BYTES].decode("utf-8"))
            title = d.get("title", "")
            author = d.get("author_name", "")
            thumb_url = d.get("thumbnail_url", "")
    except Exception as e:
        print(f"TikTok oEmbed failed for {url}: {e}", file=sys.stderr)

    local_thumb = fetch_and_cache_thumb(thumb_url, f"{url_hash}_tt") if thumb_url else ""
    return {
        "url": url,
        "provider": "TikTok",
        "domain": "tiktok.com",
        "title": title or "TikTok Video",
        "author": author,
        "description": author,
        "thumbnail": local_thumb,
        "media_type": "video",
        "playable": True,
        "aspect_ratio": 9 / 16
    }

def resolve_instagram(url):
    url_hash = hashlib.sha256(url.encode()).hexdigest()[:16]
    is_reel = "/reel/" in url
    is_post = "/p/" in url
    shortcode = ""
    m = re.search(r'/(?:reel|p)/([A-Za-z0-9_-]+)', url)
    if m:
        shortcode = m.group(1)

    clean_url = url.split("?")[0]
    title = "Instagram Reel" if is_reel else "Instagram Post" if is_post else "Instagram"
    author = f"Post {shortcode}" if shortcode else "Instagram"
    description = "Watch Reel on Instagram" if is_reel else "View Post on Instagram"
    thumb_url = ""
    aspect = 9 / 16 if is_reel else 1.0
    duration = 0

    if is_reel or is_post:
        try:
            cmd = ["yt-dlp", "--dump-json", "--skip-download", "--no-warnings", clean_url]
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=8)
            if res.returncode == 0 and res.stdout.strip():
                d = json.loads(res.stdout.strip())
                title = d.get("fulltitle") or d.get("title") or title
                author = d.get("uploader") or author
                description = f"@{d.get('uploader')}" if d.get('uploader') else description
                thumb_url = d.get("thumbnail") or ""
                duration = d.get("duration") or 0
                if d.get("aspect_ratio"):
                    aspect = d.get("aspect_ratio")
        except Exception as e:
            print(f"yt-dlp instagram resolve failed for {url}: {e}", file=sys.stderr)

    local_thumb = fetch_and_cache_thumb(thumb_url, f"{url_hash}_ig") if thumb_url else ""
    return {
        "url": url,
        "provider": "Instagram",
        "domain": "instagram.com",
        "title": title,
        "author": author,
        "description": description,
        "thumbnail": local_thumb,
        "media_type": "video" if is_reel else ("image" if is_post else "link"),
        "playable": bool(is_reel or is_post),
        "aspect_ratio": aspect,
        "duration": duration
    }

def resolve_facebook(url):
    path = urllib.parse.urlparse(url).path
    is_reel = bool(re.search(r"/(?:reel|share/r)/", path))
    is_video = (is_reel or on_host(url, "fb.watch")
                or bool(re.search(r"/(?:videos|watch|share/v)(?:/|$)|/video\.php$", path)))
    if is_video:
        try:
            # Shared Facebook links often return a login page to the generic
            # preview fetch. The video extractor follows them to the public reel.
            cmd = ["yt-dlp", "--dump-single-json", "--skip-download", "--no-playlist",
                   "--no-warnings", "--socket-timeout", "8", "--retries", "0", url]
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
            if res.returncode == 0 and res.stdout.strip():
                d = json.loads(res.stdout)
                url_hash = hashlib.sha256(url.encode()).hexdigest()[:16]
                return {
                    "url": url,
                    "provider": "Facebook",
                    "resolver": "facebook",
                    "domain": "facebook.com",
                    "title": d.get("title") or "Facebook Video",
                    "author": d.get("uploader") or "",
                    "description": d.get("description") or "",
                    "thumbnail": fetch_and_cache_thumb(d.get("thumbnail"), f"{url_hash}_fb"),
                    "media_type": "video",
                    "playable": True,
                    "aspect_ratio": d.get("aspect_ratio") or (9 / 16 if is_reel else 16 / 9),
                    "duration": d.get("duration") or 0
                }
        except Exception as e:
            print(f"Facebook video resolve failed for {url}: {e}", file=sys.stderr)

    result = resolve_generic_og(url)
    result.update(provider="Facebook", resolver="facebook")
    if is_video:
        # Keep a play/browser fallback for restricted or temporarily unavailable
        # videos, and retry metadata later rather than caching the login page.
        result.update(media_type="video", playable=True, retryAfter=time.time() + RETRY_SECONDS,
                      aspect_ratio=9 / 16 if is_reel else 16 / 9)
    return result


def resolve_twitter(url):
    url_hash = hashlib.sha256(url.encode()).hexdigest()[:16]
    clean_url = url.split("?")[0]
    api_url = re.sub(r'https?://(?:twitter|x)\.com/', 'https://api.vxtwitter.com/', clean_url)
    try:
        req = urllib.request.Request(api_url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=4) as resp:
            d = json.loads(read_body(resp, JSON_BYTES)[:JSON_BYTES].decode("utf-8"))
            text = d.get("text", "")
            user_name = d.get("user_name", "")
            screen_name = d.get("user_screen_name", "")
            media_urls = d.get("mediaURLs", [])
            thumb_url = media_urls[0] if media_urls else d.get("user_profile_image_url", "")
            local_thumb = fetch_and_cache_thumb(thumb_url, f"{url_hash}_x") if thumb_url else ""
            has_video = d.get("hasMedia") and "video" in (d.get("media_extended") or [{}])[0].get("type", "")
            return {
                "url": url,
                "provider": "X (Twitter)",
                "domain": "x.com",
                "title": f"{user_name} (@{screen_name})",
                "author": user_name,
                "description": text[:140] if text else "View post on X",
                "thumbnail": local_thumb,
                "media_type": "video" if has_video else ("image" if media_urls else "link"),
                "playable": bool(has_video),
                "aspect_ratio": 16 / 9
            }
    except Exception as e:
        print(f"Twitter resolve failed: {e}", file=sys.stderr)

    return {
        "url": url,
        "provider": "X (Twitter)",
        "domain": "x.com",
        "title": "Post on X",
        "author": "X",
        "description": "View post on X",
        "thumbnail": "",
        "media_type": "link",
        "playable": False,
        "aspect_ratio": 1.0
    }

def resolve_spotify(url):
    url_hash = hashlib.sha256(url.encode()).hexdigest()[:16]
    oembed_url = f"https://open.spotify.com/oembed?url={urllib.parse.quote(url)}"
    try:
        req = urllib.request.Request(oembed_url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=4) as resp:
            d = json.loads(read_body(resp, JSON_BYTES)[:JSON_BYTES].decode("utf-8"))
            title = d.get("title", "")
            thumb_url = d.get("thumbnail_url", "")
            local_thumb = fetch_and_cache_thumb(thumb_url, f"{url_hash}_spot") if thumb_url else ""
            return {
                "url": url,
                "provider": "Spotify",
                "domain": "spotify.com",
                "title": title or "Spotify Track",
                "author": "Spotify",
                "description": "Listen on Spotify",
                "thumbnail": local_thumb,
                "media_type": "audio",
                "playable": False,
                "aspect_ratio": 1.0
            }
    except Exception as e:
        print(f"Spotify resolve failed: {e}", file=sys.stderr)

    return None

def resolve_generic_og(url):
    url_hash = hashlib.sha256(url.encode()).hexdigest()[:16]
    try:
        if not public_url(url):
            raise ValueError("not a public address")
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=4) as resp:
            html = read_body(resp, PAGE_BYTES)[:PAGE_BYTES].decode("utf-8", errors="ignore")

        def get_meta(prop):
            m = re.search(r'<meta\s+(?:property|name)=["\']' + re.escape(prop) + r'["\']\s+content=["\']([^"\']+)["\']', html, re.I)
            if not m:
                m = re.search(r'<meta\s+content=["\']([^"\']+)["\']\s+(?:property|name)=["\']' + re.escape(prop) + r'["\']', html, re.I)
            return m.group(1).strip() if m else ""

        title = get_meta("og:title") or get_meta("twitter:title")
        if not title:
            t = re.search(r'<title[^>]*>(.*?)</title>', html, re.I | re.S)
            title = t.group(1).strip() if t else ""
        title = re.sub(r'\s+', ' ', title)

        image = get_meta("og:image") or get_meta("twitter:image")
        img_url = urllib.parse.urljoin(url, image) if image else ""
        if img_url and not public_url(img_url):
            img_url = ""

        desc = get_meta("og:description") or get_meta("description")
        desc = re.sub(r'\s+', ' ', desc)

        site = get_meta("og:site_name") or urllib.parse.urlparse(url).netloc
        domain = urllib.parse.urlparse(url).netloc or site

        is_video = "video" in (get_meta("og:type") or "")
        local_thumb = fetch_and_cache_thumb(img_url, f"{url_hash}_og") if img_url else ""

        return {
            "url": url,
            "provider": site,
            "domain": domain,
            "title": title or domain,
            "author": site,
            "description": desc or title or domain,
            "thumbnail": local_thumb,
            "media_type": "video" if is_video else ("image" if local_thumb else "link"),
            "playable": is_video,
            "aspect_ratio": 16 / 9 if is_video else 1.33
        }
    except Exception as e:
        print(f"Generic OG resolve failed for {url}: {e}", file=sys.stderr)
        domain = urllib.parse.urlparse(url).netloc or url
        return {
            "url": url,
            "provider": domain,
            "domain": domain,
            "title": domain,
            "author": domain,
            "description": url,
            "thumbnail": "",
            "media_type": "link",
            "playable": False,
            "aspect_ratio": 1.0,
            # A page that could not be read is tried again later, unlike one with no artwork.
            "retryAfter": time.time() + RETRY_SECONDS
        }

def normalize_url(url):
    clean = url.strip()
    if not clean.startswith("http://") and not clean.startswith("https://"):
        clean = "https://" + clean
    p = urllib.parse.urlparse(clean)
    if on_host(clean, "instagram.com", "tiktok.com", "youtu.be", "youtube.com"):
        query_params = urllib.parse.parse_qs(p.query)
        filtered = {}
        for k in ["v", "t"]:
            if k in query_params:
                filtered[k] = query_params[k]
        new_query = urllib.parse.urlencode(filtered, doseq=True)
        clean = urllib.parse.urlunparse((p.scheme, p.netloc, p.path, p.params, new_query, ""))
    return clean

def resolve_url(url, index):
    clean = normalize_url(url)
    for check_key in [url, clean]:
        if check_key in index:
            cached = index[check_key]
            if on_host(clean, "facebook.com", "fb.watch") and cached.get("resolver") != "facebook":
                continue
            if cached.get("retryAfter", float("inf")) <= time.time():
                continue
            thumb = cached.get("thumbnail", "")
            # A cached entry counts while its thumbnail is still on disk, and a
            # failed fetch only until its retry time.
            if thumb and os.path.exists(thumb):
                return cached
            if cached.get("media_type") == "link" and not thumb and cached.get("retryAfter", float("inf")) > time.time():
                return cached

    res = None
    if on_host(clean, "youtube.com", "youtu.be"):
        res = resolve_youtube(clean)
    elif on_host(clean, "tiktok.com"):
        res = resolve_tiktok(clean)
    elif on_host(clean, "instagram.com"):
        res = resolve_instagram(clean)
    elif on_host(clean, "facebook.com", "fb.watch"):
        res = resolve_facebook(clean)
    elif on_host(clean, "twitter.com", "x.com"):
        res = resolve_twitter(clean)
    elif on_host(clean, "open.spotify.com"):
        res = resolve_spotify(clean)

    if not res:
        res = resolve_generic_og(clean)
    return res

YTDLP_FORMAT = "best[height<=720][ext=mp4]/best[ext=mp4]/best"
# YouTube often serves only separate video and audio; a download can merge them (H.264 for the player).
YTDLP_MERGED_FORMAT = "bv*[height<=720][vcodec^=avc1]+ba[ext=m4a]/" + YTDLP_FORMAT


def get_stream_url(url):
    clean = normalize_url(url)
    url_hash = hashlib.sha256(url.encode()).hexdigest()[:16]
    clean_hash = hashlib.sha256(clean.encode()).hexdigest()[:16]

    cached = cached_media(url_hash, clean_hash)
    if cached:
        return {"url": url, **cached}

    is_tiktok = on_host(clean, "tiktok.com")
    is_instagram = on_host(clean, "instagram.com")
    is_youtube = on_host(clean, "youtube.com", "youtu.be")

    target_template = os.path.join(MEDIA_DIR, f"{url_hash}.%(ext)s")

    def download():
        try:
            cmd = ["yt-dlp", "-f", YTDLP_MERGED_FORMAT, "--merge-output-format", "mp4", "--no-playlist", "--no-warnings",
                   "-o", target_template, clean]
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            cached = cached_media(url_hash) if res.returncode == 0 else None
            return {"url": url, **cached} if cached else None
        except Exception as e:
            print(f"Failed to cache stream media for {url}: {e}", file=sys.stderr)
            return None

    def direct():
        try:
            cmd = ["yt-dlp", "-g", "-f", YTDLP_FORMAT, "--no-playlist", "--no-warnings", clean]
            if is_youtube:
                # YouTube's web clients no longer offer video and audio in one stream; its mobile site still does.
                cmd[1:1] = ["--extractor-args", "youtube:player_client=mweb"]
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=14)
            if res.returncode == 0:
                lines = [l.strip() for l in res.stdout.splitlines() if l.strip().startswith("http")]
                if lines:
                    return {"url": url, "stream_url": lines[0], "status": "ok"}
        except Exception as e:
            print(f"Failed to get stream url for {url}: {e}", file=sys.stderr)
        return None

    # TikTok and Instagram CDN URLs refuse playback without the site's referer, so their media is downloaded
    # first; for other sites a stream that cannot be played directly is downloaded instead.
    for attempt in (download, direct) if is_tiktok or is_instagram else (direct, download):
        result = attempt()
        if result:
            return result
    return {"url": url, "stream_url": "", "status": "error"}

def main():
    if len(sys.argv) < 2:
        print("Usage: link-preview.py [batch|stream] <urls...>", file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1].lower()
    if cmd == "stream":
        if len(sys.argv) < 3:
            sys.exit(1)
        url = sys.argv[2]
        res = get_stream_url(url)
        print(json.dumps(res))
    elif cmd == "batch":
        urls = sys.argv[2:]
        if not urls:
            print("{}")
            return
        results = {}
        index = load_index()
        with ThreadPoolExecutor(max_workers=min(8, len(urls))) as pool:
            future_to_url = {pool.submit(resolve_url, u, index): u for u in urls}
            for fut in future_to_url:
                u = future_to_url[fut]
                try:
                    results[u] = fut.result()
                except Exception as e:
                    print(f"Error resolving {u}: {e}", file=sys.stderr)
        save_index_batch({key: value for url, value in results.items() for key in (url, normalize_url(url))})
        print(json.dumps(results))
    else:
        sys.exit("Use batch or stream")

if __name__ == "__main__":
    main()
