#!/usr/bin/env python3
"""The shell's only client of the KDE Connect D-Bus API (KDE Connect or rust-connect).

Commands arrive as JSON lines on stdin and events leave as JSON lines on
stdout, so the shell never parses D-Bus text output itself. Commands are
listed in handle_command.
"""
import base64
import hashlib
import itertools
import json
import os
import re
import shutil
import threading
import subprocess
import sys
import tempfile
import time

SCRIPTS_PHONE_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPTS_PHONE_DIR not in sys.path:
    sys.path.insert(0, SCRIPTS_PHONE_DIR)
from contacts import ContactRegistry
from attachments import attachment_file, remember_attachment, copy_phone_file
from phone_runtime import (PHONE_CACHE, WorkQueue, atomic_file, image_extension, jpeg_exif_thumbnail, render,
                           sweep_caches, valid_device, valid_uid)
from kde_notifications import NotificationIndex

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BUS = "org.kde.kdeconnect"
ROOT = "/modules/kdeconnect"
DEVICE_IFACE = "org.kde.kdeconnect.device"
CONVERSATIONS_IFACE = "org.kde.kdeconnect.device.conversations"
SFTP_IFACE = "org.kde.kdeconnect.device.sftp"
CALL_TIMEOUT = 2000
MOUNT_TIMEOUT = 30000
MMS_MAX_BYTES = 800 * 1024
MMS_TARGET_BYTES = 700 * 1024
MMS_PASSTHROUGH_BYTES = 750 * 1024
VIDEO_EXTS = (".mp4", ".mov", ".webm", ".mkv", ".3gp", ".avi", ".m4v")
IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp", ".bmp", ".heic", ".heif", ".avif")

conn = None
# Messages by thread and message id, for every thread a request has loaded.
threads = {}
# Threads the tab asked for; loading the thread list reports every other one too.
requested = set()
loading_threads = set()
subscribed = set()
pairing_watched = set()
watch_lock = threading.Lock()
# Each phone's last listed entry, kept when a later look at it times out.
last_entries = {}
cache_dir = str(PHONE_CACHE)
data_home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
config_home = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
duration_cache_file = os.path.join(cache_dir, "durations.json")
threads_cache_file = os.path.join(cache_dir, "threads.json")
durations = {}
media_metadata = {}
probed_empty = set()
pending_saves = set()
job_ids = itertools.count()
# Room for a phone's whole conversation list arriving at once after a reconnect.
io_queue = WorkQueue(workers=1, capacity=1024, name="phone_bus")
# Device refreshes never wait behind a mount, a file copy or a message burst.
device_queue = WorkQueue(workers=1, capacity=4, name="phone_devices")
media_queue = WorkQueue(workers=2, capacity=16, name="phone_media")
# Thumbnails wait on the phone's network round trips, which a few overlap well.
thumb_queue = WorkQueue(workers=3, capacity=64, name="phone_thumb")
preview_queue = WorkQueue(workers=1, capacity=2, name="phone_preview")
# Notification lookups read every phone notification object; keep them off the message queue.
notify_queue = WorkQueue(workers=1, capacity=16, name="phone_notifications")
notification_index = None
started_ms = time.time() * 1000
backend = "KDE Connect"
named_generation = -1
request_context = threading.local()
cache_lock = threading.RLock()
backend_generation = 0
thumbnail_generation = 0
preview_generation = 0
known_reachable = set()


def request_fields(cmd):
    """The fields of a command that its reply or failure carries back to QML."""
    return {key: cmd[key] for key in ("request", "device", "uid", "thread") if key in cmd}


def background(function, *args, key=None, queue=None):
    job_key = key or (function.__name__, next(job_ids))
    def work():
        request_context.fields = {}
        try:
            return function(*args)
        except Exception as error:
            fail(function.__name__, error)
        finally:
            request_context.fields = {}
    return (queue or io_queue).submit(job_key, work)



def dedup_addresses(raw_addresses):
    seen = set()
    result = []
    for addr in (raw_addresses or []):
        s = str(addr or "").strip()
        if not s:
            continue
        digits = re.sub(r"\D", "", s)
        key = digits if re.fullmatch(r"\+?[\d ()\-.]+", s) else s.casefold()
        if key in seen:
            continue
        seen.add(key)
        result.append(s)
    return result


def load_durations():
    global durations
    if os.path.isfile(duration_cache_file):
        try:
            with open(duration_cache_file, "r") as f:
                durations = json.load(f)
        except Exception:
            durations = {}


def save_durations():
    with cache_lock:
        data = dict(durations)
    try:
        with atomic_file(duration_cache_file, prefix="durations-") as output:
            json.dump(data, output)
    except OSError:
        pass


def load_threads():
    global threads
    if not os.path.isfile(threads_cache_file):
        return
    try:
        with open(threads_cache_file, "r") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            return
        for key_str, msgs in data.items():
            if ":" not in key_str or not isinstance(msgs, list):
                continue
            dev, tid_str = key_str.split(":", 1)
            tid = int(tid_str)
            bucket = threads.setdefault((dev, tid), {})
            for m in msgs:
                if isinstance(m, dict) and "uid" in m:
                    if "addresses" in m:
                        m["addresses"] = dedup_addresses(m.get("addresses"))
                    bucket[m["uid"]] = m
    except Exception:
        pass


def save_threads():
    try:
        payload = {f"{dev}:{tid}": sorted(bucket.values(), key=lambda m: m.get("date", 0))[-100:]
                   for (dev, tid), bucket in list(threads.items()) if bucket}
        with atomic_file(threads_cache_file, prefix="threads-") as output:
            json.dump(payload, output, separators=(",", ":"))
    except Exception:
        pass


def save_soon(save):
    """One write for a burst of changes."""
    if save.__name__ in pending_saves:
        return
    pending_saves.add(save.__name__)

    def run():
        pending_saves.discard(save.__name__)
        if not background(save, key=save.__name__):
            save_soon(save)
        return False

    GLib.timeout_add(400, run)


def save_threads_soon():
    save_soon(save_threads)


def file_key(path, length=64):
    stat = os.stat(path)
    return hashlib.sha256(f"{os.path.abspath(path)}:{stat.st_size}:{stat.st_mtime_ns}".encode()).hexdigest()[:length]


def with_extension(file_path, ext):
    """A link to the file under a name with its image extension, or the file itself."""
    link = f"{file_path}.{ext}"
    if not os.path.exists(link):
        try:
            os.symlink(file_path, link)
        except OSError:
            return file_path
    return link


def ensure_supported_image(file_path):
    if not file_path or not os.path.isfile(file_path):
        return file_path

    for ext in (".jpg", ".jpeg", ".png", ".gif", ".webp"):
        if file_path.lower().endswith(ext):
            return file_path
        candidate = f"{file_path}{ext}"
        if os.path.isfile(candidate) and os.path.getsize(candidate) > 0:
            return candidate

    try:
        with open(file_path, "rb") as f:
            head = f.read(64)
    except OSError:
        return file_path

    ext = image_extension(head)
    if ext:
        return with_extension(file_path, ext)

    is_heif = False
    if len(head) >= 12 and head[4:8] == b"ftyp":
        brand = head[8:12]
        if brand in (b"heic", b"heix", b"heim", b"heis", b"hevc", b"hevx", b"mif1", b"msf1", b"avif", b"avis"):
            is_heif = True
        elif any(b in head[:64] for b in (b"heic", b"heix", b"mif1", b"msf1", b"hevc")):
            is_heif = True

    if is_heif:
        jpg_file = f"{file_path}.jpg"
        if not os.path.exists(jpg_file) or os.path.getsize(jpg_file) == 0:
            try:
                render(["magick", file_path, jpg_file], jpg_file, 15)
            except Exception:
                try:
                    render(["ffmpeg", "-y", "-i", file_path, jpg_file], jpg_file, 15)
                except Exception:
                    pass
        if os.path.isfile(jpg_file) and os.path.getsize(jpg_file) > 0:
            return jpg_file

    return file_path


def probe_duration(path):
    if not path or not os.path.isfile(path):
        return 0
    key = file_key(path)
    if durations.get(key, 0) > 0:
        return durations[key]
    if key in probed_empty:
        return 0
    try:
        out = subprocess.check_output(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", path],
            timeout=3, text=True, stderr=subprocess.DEVNULL
        ).strip()
        val = float(out)
        if val > 0:
            ms = round(val * 1000)
            with cache_lock:
                durations[key] = ms
            save_soon(save_durations)
            return ms
    except Exception:
        pass
    probed_empty.add(key)
    return 0


NOT_VIDEO_BRANDS = (b"M4A ", b"M4B ", b"M4P ", b"heic", b"heix", b"mif1", b"msf1", b"avif", b"avis")


def is_video_file(path, mime=None):
    if not path or not os.path.isfile(path):
        return False
    if mime and mime.startswith("video/"):
        return True
    ext = os.path.splitext(path)[1].lower()
    if ext in VIDEO_EXTS:
        return True
    try:
        with open(path, "rb") as f:
            head = f.read(32)
        # The ftyp brand tells MP4 video from M4A audio and HEIF/AVIF stills, which share the box.
        if len(head) >= 12 and head[4:8] == b"ftyp" and head[8:12] in NOT_VIDEO_BRANDS:
            return False
        if len(head) >= 8 and head[4:8] in (b"ftyp", b"moov", b"mdat"):
            return True
        if head[:4] in (b"\x1a\x45\xdf\xa3", b"FLV\x01"):
            return True
        if len(head) >= 12 and head[:4] == b"RIFF" and head[8:12] == b"AVI ":
            return True
    except Exception:
        pass
    return False


def video_thumbnail(path, mime=None):
    if not is_video_file(path, mime):
        return ""
    try:
        key = file_key(path, 24)
        thumb_dir = os.path.join(cache_dir, "thumbs")
        os.makedirs(thumb_dir, exist_ok=True)
        out_path = os.path.join(thumb_dir, f"{key}.jpg")
        if os.path.isfile(out_path) and os.path.getsize(out_path) > 0:
            return out_path
        render(["ffmpeg", "-y", "-ss", "0.1", "-i", path, "-frames:v", "1",
                "-vf", "scale='min(480,iw)':-2", "-q:v", "4", out_path], out_path, 5)
        if os.path.isfile(out_path) and os.path.getsize(out_path) > 0:
            return out_path
    except Exception:
        pass
    return ""


def generate_thumbnail(path):
    if not path or not os.path.exists(path):
        return ""
    try:
        key = file_key(path, 16)
        thumb_dir = os.path.join(cache_dir, "thumbs")
        os.makedirs(thumb_dir, exist_ok=True)
        out_path = os.path.join(thumb_dir, f"{key}.jpg")
        if os.path.isfile(out_path) and os.path.getsize(out_path) > 0:
            return out_path

        ext = os.path.splitext(path)[1].lower()
        if ext in IMAGE_EXTS:
            try:
                jpeg = ext in (".jpg", ".jpeg")
                # The phone's files cross the network slowly: read each one once, and for a
                # camera photo only its first bytes, which hold the thumbnail the camera made.
                with open(path, "rb") as source:
                    head = source.read(128 * 1024)
                    embedded = jpeg_exif_thumbnail(head) if jpeg else None
                    if embedded:
                        with atomic_file(out_path, "wb") as output:
                            output.write(embedded)
                        return out_path
                    data = head + source.read()
                # libjpeg decodes at a fraction of full size, enough for a 320 px tile.
                hint = ["-define", "jpeg:size=640x640"] if jpeg else []
                render(["magick", *hint, "-", "-thumbnail", "320x320>", out_path], out_path, 8, input=data)
                if os.path.isfile(out_path) and os.path.getsize(out_path) > 0:
                    return out_path
            except Exception:
                pass

        if ext in VIDEO_EXTS:
            return video_thumbnail(path)
    except Exception:
        pass
    return ""


def request_thumbnails(paths, generation):
    global thumbnail_generation
    owner_generation = backend_generation
    thumbnail_generation = generation
    thumb_queue.cancel_pending()
    for path in paths[:48]:
        def work(p=path):
            if generation != thumbnail_generation:
                return ""
            return generate_thumbnail(p)
        # A finished thumbnail is sent even after a newer request: it is still that file's.
        def done(thumb, error, p=path):
            if thumb and owner_generation == backend_generation:
                emit("thumbnail", path=p, thumb=thumb)
        if not thumb_queue.submit((generation, path), work, done):
            break


def prepare_mms_attachment(file_path):
    """Ensures video and image attachments fit carrier MMS size/codec limits (<800 KB)."""
    if not file_path or not os.path.isfile(file_path):
        return file_path
    try:
        stat = os.stat(file_path)
        file_size = stat.st_size
        if file_size <= 0:
            return file_path
        ext = os.path.splitext(file_path)[1].lower()

        def output(suffix):
            mms_dir = os.path.join(cache_dir, "mms_out")
            os.makedirs(mms_dir, exist_ok=True)
            return os.path.join(mms_dir, f"mms_{file_key(file_path, 16)}.{suffix}")

        if ext in VIDEO_EXTS:
            out_path = output("mp4")
            if os.path.isfile(out_path) and 0 < os.path.getsize(out_path) <= MMS_MAX_BYTES:
                return out_path

            duration = 10.0
            v_codec = ""
            pix_fmt = ""
            level = 99
            width = 0
            height = 0
            has_audio = False
            try:
                probe_out = subprocess.check_output(
                    ["ffprobe", "-v", "error", "-show_format", "-show_streams", "-of", "json", file_path],
                    timeout=5, text=True, stderr=subprocess.DEVNULL
                )
                info = json.loads(probe_out)
                fmt_dur = float((info.get("format") or {}).get("duration") or 0)
                if fmt_dur > 0:
                    duration = fmt_dur
                for st in (info.get("streams") or []):
                    ctype = st.get("codec_type")
                    if ctype == "video" and not v_codec:
                        v_codec = str(st.get("codec_name") or "")
                        pix_fmt = str(st.get("pix_fmt") or "")
                        level = int(st.get("level") or 99)
                        width = int(st.get("width") or 0)
                        height = int(st.get("height") or 0)
                    elif ctype == "audio":
                        has_audio = True
            except Exception:
                pass

            if (ext == ".mp4" and file_size <= MMS_PASSTHROUGH_BYTES and v_codec == "h264"
                    and pix_fmt == "yuv420p" and 0 < level <= 41 and max(width, height) <= 1280):
                return file_path

            dur = max(1.0, duration)
            total_bps = int((MMS_TARGET_BYTES * 8 * 0.90) / dur)
            audio_bps = 48000 if has_audio else 0
            video_bps = max(64000, min(1200000, total_bps - audio_bps))
            if video_bps >= 350000:
                max_dim, fps = 640, 24
            elif video_bps >= 180000:
                max_dim, fps = 480, 20
            else:
                max_dim, fps = 360, 15

            for attempt in range(2):
                cmd = [
                    "ffmpeg", "-y", "-i", file_path,
                    "-vf", f"scale='min({max_dim},iw)':-2,fps={fps},format=yuv420p",
                    "-c:v", "libx264", "-profile:v", "main", "-level:v", "3.1",
                    "-preset", "veryfast",
                    "-b:v", str(video_bps),
                    "-maxrate", str(int(video_bps * 1.15)),
                    "-bufsize", str(int(video_bps * 2)),
                ]
                if has_audio:
                    cmd += ["-c:a", "aac", "-b:a", "48k", "-ac", "1", "-ar", "44100"]
                else:
                    cmd += ["-an"]
                cmd += ["-movflags", "+faststart", out_path]
                render(cmd, out_path, 45)
                if os.path.isfile(out_path):
                    out_size = os.path.getsize(out_path)
                    if 0 < out_size <= MMS_MAX_BYTES or attempt == 1:
                        return out_path if out_size > 0 else file_path
                    video_bps = max(50000, int(video_bps * (MMS_TARGET_BYTES * 0.92) / out_size))
                    max_dim = min(max_dim, 480)
                    fps = min(fps, 20)
            return file_path

        if ext in IMAGE_EXTS:
            if ext in (".jpg", ".jpeg", ".png") and file_size <= MMS_MAX_BYTES:
                return file_path
            out_path = output("jpg")
            if os.path.isfile(out_path) and 0 < os.path.getsize(out_path) <= MMS_MAX_BYTES:
                return out_path
            for max_dim, qual in ((1600, "82"), (1280, "70"), (960, "60")):
                try:
                    render(["magick", file_path, "-auto-orient", "-strip",
                            "-resize", f"{max_dim}x{max_dim}>", "-quality", qual, out_path], out_path, 15)
                except Exception:
                    try:
                        render(["ffmpeg", "-y", "-i", file_path,
                                "-vf", f"scale='min({max_dim},iw)':-2", "-q:v", "5", out_path], out_path, 15)
                    except Exception:
                        break
                if os.path.isfile(out_path) and 0 < os.path.getsize(out_path) <= MMS_MAX_BYTES:
                    return out_path
            if os.path.isfile(out_path) and os.path.getsize(out_path) > 0:
                return out_path
    except Exception:
        pass
    return file_path


def attachment_metadata(device, uid, path):
    key = device + ":" + str(uid)
    def work():
        supported = ensure_supported_image(path)
        remember_attachment(device, str(uid), supported)
        try:
            with open(supported, "rb") as f:
                still = image_extension(f.read(16)) in ("png", "jpg")
        except OSError:
            still = False
        if still:  # nothing to probe in a still image
            return {"path": supported, "duration": 0, "thumb": ""}
        return {"path": supported, "duration": probe_duration(supported), "thumb": video_thumbnail(supported)}
    generation = backend_generation
    def done(result, error):
        if generation != backend_generation:
            return
        if error:
            fail("attachment", error, device=device, uid=str(uid))
        else:
            media_metadata[key] = result
            emit("attachment", device=device, uid=str(uid), **result)
    if not media_queue.submit(("attachment", key), work, done):
        fail("attachment", "Media queue is busy; try again", device=device, uid=str(uid))


def on_attachment_received(device, arg1, arg2):
    first, second = str(arg1 or ""), str(arg2 or "")
    path, uid = (first, second) if first.startswith("/") else (second, first)
    if not path or not os.path.isfile(path):
        fail("attachment", "The phone returned an unavailable attachment", device=device, uid=uid)
        return
    remember_attachment(device, uid, path)
    attachment_metadata(device, uid, path)


def emit(event, **fields):
    context = getattr(request_context, "fields", {})
    line = json.dumps({"generation": backend_generation, **context, **fields, "event": event}, separators=(",", ":")) + "\n"

    def write():
        sys.stdout.write(line)
        sys.stdout.flush()
        return False
    if threading.current_thread() is threading.main_thread():
        write()
    else:
        GLib.idle_add(write)


def error_text(error):
    """The daemon's own words, without the GDBus.Error:name: prefix."""
    message = error.message if isinstance(error, GLib.Error) else str(error)
    return re.sub(r"^GDBus\.Error:[\w.]+:\s*", "", message)


last_sent = {}


def emit_changed(event, **fields):
    """Emits only when the event differs from the last one of its kind; True when it did."""
    text = json.dumps(fields, sort_keys=True)
    if last_sent.get(event) == text:
        return False
    last_sent[event] = text
    emit(event, **fields)
    return True


def fail(context, error, **fields):
    message = error_text(error)
    emit("error", context=context, message=message, **fields)


def device_path(device):
    if not valid_device(device):
        raise ValueError("bad device id")
    return f"{ROOT}/devices/{device}"


def call(path, iface, method, args=None, reply=None, timeout=CALL_TIMEOUT):
    result = conn.call_sync(BUS, path, iface, method, args, GLib.VariantType(reply) if reply else None,
                            Gio.DBusCallFlags.NO_AUTO_START, timeout, None)
    return result.unpack() if result is not None else ()


def plain(value):
    """A GVariant (or nested variant) as plain Python data."""
    while isinstance(value, GLib.Variant):
        value = value.unpack()
    return value


# ConversationMessage: (event, body, addresses, date, type, read, threadID, uID,
# subID, attachments); an attachment is (partID, mimeType, base64 thumbnail, uniqueIdentifier).
def message(device, raw):
    fields = plain(raw)
    if not isinstance(fields, (tuple, list)) or len(fields) < 9:
        return None
    event, body, addresses, date, kind, read, thread, uid, sub = fields[:9]
    attachments = []
    for part in (fields[9] if len(fields) > 9 else []):
        part = plain(part)
        if not isinstance(part, (tuple, list)) or len(part) < 4:
            continue
        part_id, mime, encoded, unique = part[:4]
        att = {"part": part_id, "mime": mime, "uid": unique, "thumb": thumbnail(device, unique, mime, encoded)}
        if unique:
            local_file = attachment_file(device, str(unique))
            if local_file:
                att["path"] = local_file
                metadata = media_metadata.get(device + ":" + str(unique))
                if metadata and metadata["path"] == local_file:
                    att.update(metadata)
                elif mime and (mime.startswith("audio/") or mime.startswith("video/")):
                    attachment_metadata(device, unique, local_file)
        attachments.append(att)
    return {
        "event": event, "body": body, "addresses": dedup_addresses([address(a) for a in addresses]),
        "date": date, "type": kind, "read": read, "thread": thread, "uid": uid, "sub": sub, "attachments": attachments,
    }


def address(raw):
    """A ConversationAddress is a struct holding one string."""
    value = plain(raw)
    return str(value[0] if isinstance(value, (tuple, list)) and value else value)


def thumbnail(device, unique, mime, encoded):
    """Writes an attachment's thumbnail once and returns its path, or ""."""
    if not encoded or not valid_uid(unique):
        return ""
    try:
        raw = base64.b64decode(encoded)
    except (TypeError, ValueError):
        return ""
    if not raw:
        return ""
    ext = image_extension(raw) or {"image/png": "png", "image/gif": "gif", "image/webp": "webp"}.get(mime, "jpg")
    folder = os.path.join(cache_dir, device)
    path = os.path.join(folder, f"{unique}.{ext}")
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        try:
            with atomic_file(path, "wb") as f:
                f.write(raw)
        except OSError:
            return ""
    return path


def start_backend():
    """Starts the phone daemon through D-Bus activation when the shell wants the phone. Calls never start it
    (NO_AUTO_START), and a daemon that is only activatable, not started at login, would otherwise stay down."""
    def done(connection, result):
        try:
            connection.call_finish(result)
        except GLib.Error as error:
            print(f"Could not start {BUS}: {error_text(error)}", file=sys.stderr)
    conn.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "StartServiceByName",
              GLib.Variant("(su)", (BUS, 0)), GLib.VariantType("(u)"), Gio.DBusCallFlags.NONE, 30000, None, done)


def has_paired_phone():
    """Whether rust-connect or KDE Connect has a phone paired, read from their own files."""
    try:
        with open(os.path.join(data_home, "rust-connect", "paired.json"), encoding="utf-8") as f:
            if json.load(f):
                return True
    except (OSError, ValueError):
        pass
    try:
        return os.path.getsize(os.path.join(config_home, "kdeconnect", "trusted_devices")) > 0
    except OSError:
        return False


def backend_name():
    """Which daemon owns the KDE Connect bus name, for the shell's labels."""
    try:
        bus = ("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus")
        owner = conn.call_sync(*bus, "GetNameOwner", GLib.Variant("(s)", (BUS,)), GLib.VariantType("(s)"),
                               Gio.DBusCallFlags.NONE, CALL_TIMEOUT, None).unpack()[0]
        pid = conn.call_sync(*bus, "GetConnectionUnixProcessID", GLib.Variant("(s)", (owner,)), GLib.VariantType("(u)"),
                             Gio.DBusCallFlags.NONE, CALL_TIMEOUT, None).unpack()[0]
        return "rust-connect" if "rust-connect" in os.path.basename(os.readlink(f"/proc/{pid}/exe")) else "KDE Connect"
    except (GLib.Error, OSError):
        return "KDE Connect"


def devices():
    global known_reachable, backend, named_generation, last_entries
    try:
        ids = call(ROOT, "org.kde.kdeconnect.daemon", "devices", GLib.Variant("(bb)", (False, True)), "(as)")[0]
    except GLib.Error as error:
        if error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.TIMED_OUT):
            # A busy daemon is not a missing one: keep what the shell shows and look again.
            GLib.timeout_add(1000, lambda: (devices_soon(), False)[1])
            return
        known_reachable = set()
        # QML marks every phone unreachable on this, so the next healthy list must be sent even if unchanged.
        last_sent.pop("devices", None)
        if emit_changed("backend", available=False):
            fail("daemon.devices", error)
        return
    if named_generation != backend_generation:
        named_generation = backend_generation
        backend = backend_name()
    emit_changed("backend", available=True, name=backend)
    out = []
    reachable = set()
    for device in ids:
        path = device_path(device)
        try:
            props = call(path, "org.freedesktop.DBus.Properties", "GetAll", GLib.Variant("(s)", (DEVICE_IFACE,)), "(a{sv})")[0]
            plugins = list(call(path, DEVICE_IFACE, "loadedPlugins", None, "(as)")[0])
        except GLib.Error:
            # A late answer keeps the phone as it was rather than dropping it from the list.
            if device in last_entries:
                out.append(last_entries[device])
                if last_entries[device]["reachable"]:
                    reachable.add(device)
            continue
        entry = {"id": device, "name": props.get("name", device), "type": props.get("type", "phone"),
                 "reachable": bool(props.get("isReachable", False)), "plugins": plugins, "charge": -1, "charging": False}
        if "kdeconnect_battery" in plugins:
            try:
                battery = call(path + "/battery", "org.freedesktop.DBus.Properties", "GetAll",
                               GLib.Variant("(s)", ("org.kde.kdeconnect.device.battery",)), "(a{sv})")[0]
                entry.update(charge=battery.get("charge", -1), charging=battery.get("isCharging", False))
            except GLib.Error:
                pass
        if entry["reachable"]:
            reachable.add(device)
        out.append(entry)
        watch(device)
    known_reachable = reachable
    last_entries = {entry["id"]: entry for entry in out}
    emit_changed("devices", devices=out)
    pair_requests(ids)


def pair_requests(paired):
    """Phones that asked to pair, with the code both screens show."""
    try:
        nearby = call(ROOT, "org.kde.kdeconnect.daemon", "devices", GLib.Variant("(bb)", (False, False)), "(as)")[0]
    except GLib.Error:
        nearby = []
    requests = []
    for device in nearby:
        if device in paired:
            continue
        watch_pairing(device)
        try:
            props = call(device_path(device), "org.freedesktop.DBus.Properties", "GetAll",
                         GLib.Variant("(s)", (DEVICE_IFACE,)), "(a{sv})")[0]
        except GLib.Error:
            continue
        # KDE Connect's pair states: 2 is a request from the phone.
        if props.get("pairState") == 2:
            requests.append({"id": device, "name": props.get("name", device), "key": props.get("verificationKey", "")})
    if emit_changed("pairRequests", requests=requests) and requests:
        # A request lapses after about 25 s with no signal; look again then.
        GLib.timeout_add_seconds(26, lambda: (devices_soon(), False)[1])


def watch_pairing(device):
    """A phone that is not paired yet: only its pairing state matters."""
    with watch_lock:
        if device in pairing_watched:
            return
        pairing_watched.add(device)
    conn.signal_subscribe(BUS, DEVICE_IFACE, "pairStateChanged", device_path(device), None,
                          Gio.DBusSignalFlags.NONE, lambda *a: devices_soon())


refresh_pending = False


def devices_soon():
    """One device refresh for a burst of changes."""
    global refresh_pending
    if refresh_pending:
        return

    def run():
        global refresh_pending
        refresh_pending = False
        background(devices, key="devices", queue=device_queue)
        return False

    refresh_pending = True
    GLib.timeout_add(300, run)


def watch(device):
    with watch_lock:
        if device in subscribed:
            return
        subscribed.add(device)
    path = device_path(device)
    for signal in ("conversationCreated", "conversationUpdated"):
        conn.signal_subscribe(BUS, CONVERSATIONS_IFACE, signal, path, None, Gio.DBusSignalFlags.NONE,
                              lambda *a, d=device: background(on_message, d, a[5]) or resync_soon(d))
    conn.signal_subscribe(BUS, CONVERSATIONS_IFACE, "conversationLoaded", path, None, Gio.DBusSignalFlags.NONE,
                          lambda *a, d=device: admit(on_loaded, d, a[5], on_drop=lambda: resync_soon(d)))
    conn.signal_subscribe(BUS, CONVERSATIONS_IFACE, "conversationRemoved", path, None, Gio.DBusSignalFlags.NONE,
                          lambda *a, d=device: admit(remove_thread, d, a[5].unpack()[0], on_drop=lambda: resync_soon(d)))
    # The full file of an attachment; its name is the attachment's unique id.
    conn.signal_subscribe(BUS, CONVERSATIONS_IFACE, "attachmentReceived", path, None, Gio.DBusSignalFlags.NONE,
                          lambda *a, d=device: attachment_received(d, a[5].unpack()))
    # rust-connect extensions; KDE Connect simply never emits these signals.
    conn.signal_subscribe(BUS, CONVERSATIONS_IFACE, "attachmentFailed", path, None, Gio.DBusSignalFlags.NONE,
                          lambda *a, d=device: fail("attachment", a[5].unpack()[1], device=d, uid=str(a[5].unpack()[0])))
    conn.signal_subscribe(BUS, CONVERSATIONS_IFACE, "conversationError", path, None, Gio.DBusSignalFlags.NONE,
                          lambda *a, d=device: fail("thread", a[5].unpack()[1], device=d, thread=a[5].unpack()[0]))
    # Reachability and battery changes refresh the device list.
    conn.signal_subscribe(BUS, "org.freedesktop.DBus.Properties", "PropertiesChanged", path, None,
                          Gio.DBusSignalFlags.NONE, lambda *a: devices_soon())
    conn.signal_subscribe(BUS, "org.kde.kdeconnect.device.battery", "refreshed", path + "/battery", None,
                          Gio.DBusSignalFlags.NONE, lambda *a: devices_soon())
    conn.signal_subscribe(BUS, "org.kde.kdeconnect.device.contacts", "localCacheSynchronized", path + "/contacts",
                          None, Gio.DBusSignalFlags.NONE, lambda *a, d=device: background(contacts, d, key=("contacts", d)))

    conn.signal_subscribe(BUS, "org.kde.kdeconnect.device.telephony", "callReceived", path + "/telephony", None,
                          Gio.DBusSignalFlags.NONE, lambda *a, d=device: on_call(d, *a[5].unpack()))
    conn.signal_subscribe(BUS, "org.kde.kdeconnect.device.share", "transferFailed", path + "/share", None,
                          Gio.DBusSignalFlags.NONE, lambda *a, d=device: fail("share", a[5].unpack()[0], device=d))
    conn.signal_subscribe(BUS, SFTP_IFACE, "mounted", path + "/sftp", None, Gio.DBusSignalFlags.NONE,
                          lambda *a, d=device: background(on_sftp_mounted, d))
    conn.signal_subscribe(BUS, SFTP_IFACE, "unmounted", path + "/sftp", None, Gio.DBusSignalFlags.NONE,
                          lambda *a, d=device: emit("mount", device=d, mounted=False, mountPoint="", places=[], error=""))


def mount_state(device):
    path = device_path(device) + "/sftp"
    folders = call(path, SFTP_IFACE, "getDirectories", None, "(a{sv})")[0]
    return {"mountPoint": call(path, SFTP_IFACE, "mountPoint", None, "(s)")[0],
            "places": [{"path": k, "name": plain(v)} for k, v in folders.items()]}


def on_sftp_mounted(device):
    try:
        emit("mount", device=device, mounted=True, error="", **mount_state(device))
    except Exception as e:
        emit("mount", device=device, mounted=False, mountPoint="", places=[], error=str(e))


def on_call(device, event, number, name):
    if event == "callReceived":
        emit("call", device=device, number=str(number), name=str(name), time=time.time() * 1000)


resyncing = set()


def admit(function, *args, tries=5, on_drop=None):
    """Queues a signal's work; while the queue is full it tries again every 2 s, then calls on_drop."""
    if background(function, *args):
        return
    if tries <= 1:
        if on_drop:
            on_drop()
        return
    GLib.timeout_add(2000, lambda: admit(function, *args, tries=tries - 1, on_drop=on_drop))


def attachment_received(device, args):
    """An attachment someone is waiting for gets a definite failure if its work cannot be queued."""
    first, second = (str(value or "") for value in args)
    uid = second if first.startswith("/") else first
    admit(on_attachment_received, device, *args,
          on_drop=lambda: fail("attachment", "Phone queue is busy; try again", device=device, uid=uid))


def resync_soon(device):
    """A conversation signal the full queue could not take: ask for the threads again."""
    if device in resyncing:
        return
    resyncing.add(device)

    def run():
        resyncing.discard(device)
        if not background(conversations, device, key=("conversations", device)):
            resync_soon(device)
        return False

    GLib.timeout_add(2000, run)


def remove_thread(device, tid):
    threads.pop((device, int(tid)), None)
    requested.discard((device, int(tid)))
    loading_threads.discard((device, int(tid)))
    save_threads_soon()
    emit("removed", device=device, thread=int(tid))


def on_message(device, params):
    msg = message(device, params.unpack()[0])
    if msg is None:
        return
    tid = int(msg["thread"])
    bucket = threads.setdefault((device, tid), {})
    prev_max_date = max((m.get("date", 0) for m in bucket.values()), default=0)
    is_new = msg["uid"] not in bucket
    bucket[msg["uid"]] = msg
    save_threads_soon()
    if (device, tid) not in loading_threads or is_new or msg.get("date", 0) >= prev_max_date:
        # Live: an incoming message the phone received while this bridge was running.
        live = is_new and msg["type"] == 1 and msg.get("date", 0) >= started_ms
        emit("message", device=device, message=msg, live=live)


def on_loaded(device, params):
    tid, count = params.unpack()
    tid = int(tid)
    loading_threads.discard((device, tid))
    save_threads_soon()
    if (device, tid) not in requested:
        return
    msgs = sorted(threads.get((device, tid), {}).values(), key=lambda m: m["date"])
    emit("thread", device=device, thread=tid, messages=msgs, loaded=count)


def remember_message(device, m):
    threads.setdefault((device, int(m["thread"])), {})[m["uid"]] = m


def load_active(device):
    latest = call(device_path(device), CONVERSATIONS_IFACE, "activeConversations", None, "(av)")[0]
    items = [m for m in (message(device, raw) for raw in latest) if m is not None]
    for m in items:
        remember_message(device, m)
    return items


def conversations(device):
    path = device_path(device)
    try:
        items = load_active(device)
    except Exception:
        items = []

    # activeConversations can be empty or partial after a restart; the thread cache fills it in.
    thread_map = {}
    for (d, tid), bucket in threads.items():
        if d == device and bucket:
            thread_map[tid] = max(bucket.values(), key=lambda m: m.get("date", 0))
    for m in items:
        tid = int(m["thread"])
        if tid not in thread_map or m.get("date", 0) >= thread_map[tid].get("date", 0):
            thread_map[tid] = m
    sorted_items = sorted(thread_map.values(), key=lambda m: m.get("date", 0), reverse=True)
    emit("conversations", device=device, items=sorted_items)

    # Push any cached thread histories immediately so opening a thread is instant.
    for m in sorted_items[:20]:
        tid = int(m["thread"])
        existing = threads.get((device, tid), {})
        if len(existing) > 1:
            msgs = sorted(existing.values(), key=lambda x: x["date"])[-100:]
            emit("thread", device=device, thread=tid, messages=msgs, loaded=len(msgs), cached=True)

    # Asks the phone for anything newer; it arrives as message events.
    call(path, CONVERSATIONS_IFACE, "requestAllConversationThreads")


def thread(device, thread_id, count):
    tid = int(thread_id)
    count = max(1, min(int(count or 50), 500))
    requested.add((device, tid))
    existing = threads.get((device, tid), {})
    if existing:
        msgs = sorted(existing.values(), key=lambda m: m["date"])[-count:]
        emit("thread", device=device, thread=tid, messages=msgs, loaded=len(msgs), cached=True)
    loading_threads.add((device, tid))
    # A thread that never finishes loading must not hold back live messages.
    GLib.timeout_add(2000, lambda d=device, t=tid: loading_threads.discard((d, t)) or False)
    # The messages arrive as message events, then a thread event once loaded.
    call(device_path(device), CONVERSATIONS_IFACE, "requestConversation",
         GLib.Variant("(xii)", (tid, 0, count)))


def attachment_files(paths):
    """Files to send by MMS. KDE Connect opens each as a plain path, not a URL."""
    out = []
    for p in (paths or []):
        if isinstance(p, str) and os.path.isabs(p) and os.path.isfile(p):
            prepared = prepare_mms_attachment(p)
            if prepared and os.path.isfile(prepared):
                out.append(prepared)
    return out


def thread_addresses(device, tid):
    if not threads.get((device, tid)):
        try:
            load_active(device)
        except Exception:
            pass
    # The newest message sent from this side names every recipient of a group.
    ordered = sorted(threads.get((device, tid), {}).values(), key=lambda m: (m.get("type") != 2, -m.get("date", 0)))
    return next((m["addresses"] for m in ordered if m.get("addresses")), [])


def files_variant(paths):
    return [GLib.Variant("s", p) for p in (paths or [])]


def send_to_addresses(device, addresses, text, paths):
    call(device_path(device), CONVERSATIONS_IFACE, "sendWithoutConversation",
         GLib.Variant("(avsav)", ([GLib.Variant("(s)", (a,)) for a in addresses], str(text), files_variant(paths))))


def reply(device, thread_id, text, paths):
    tid = int(thread_id)
    addrs = thread_addresses(device, tid)
    if addrs:
        send_to_addresses(device, addrs, text, paths)
    else:
        call(device_path(device), CONVERSATIONS_IFACE, "replyToConversation",
             GLib.Variant("(xsav)", (tid, str(text), files_variant(paths))))
    emit("sent", device=device, thread=tid)


def send(device, addresses, text, paths):
    addrs = dedup_addresses(addresses)
    if not addrs:
        raise ValueError("no recipient")
    send_to_addresses(device, addrs, text, paths)
    emit("sent", device=device, thread=-1)


def share(device, paths):
    urls = [GLib.filename_to_uri(p, None) for p in paths if os.path.isfile(p)]
    if not urls:
        raise ValueError("no files")
    call(device_path(device) + "/share", "org.kde.kdeconnect.device.share", "shareUrls",
         GLib.Variant("(as)", (urls,)))
    emit("shared", device=device, count=len(urls))


def mount(device):
    path = device_path(device) + "/sftp"
    iface = SFTP_IFACE
    generation = backend_generation

    # A mount left behind by a dropped connection makes the new mount fail.
    try:
        mp = call(path, iface, "mountPoint", None, "(s)")[0]
        if mp and os.path.exists(mp):
            try:
                os.listdir(mp)
            except OSError as err:
                if err.errno in (107, 112):  # ENOTCONN, EHOSTDOWN
                    subprocess.run(["fusermount", "-u", "-z", mp], check=False)
    except Exception:
        pass

    # Mounts run on the media queue, so waiting here keeps the bus queue free
    # and preserves the request/generation attached to the eventual result.
    try:
        ok = call(path, iface, "mountAndWait", reply="(b)", timeout=MOUNT_TIMEOUT)[0]
        if generation != backend_generation:
            return
        if ok:
            emit("mount", device=device, mounted=True, error="", **mount_state(device))
        else:
            emit("mount", device=device, mounted=False, mountPoint=call(path, iface, "mountPoint", None, "(s)")[0],
                 places=[], error=call(path, iface, "getMountError", None, "(s)")[0], sshfsMissing=not shutil.which("sshfs"))
    except GLib.Error as error:
        if generation == backend_generation:
            emit("mount", device=device, mounted=False, mountPoint="", places=[], error=error.message,
                 sshfsMissing=not shutil.which("sshfs"))


def attachment(device, part, unique, fresh=False):
    """fresh skips our cached copy and asks the daemon to drop its own (rust-connect's refreshAttachmentFile),
    for a file that failed to decode. KDE Connect has no such method and may return its cached copy again."""
    if not valid_uid(str(unique)):
        raise ValueError("bad attachment id")
    local_file = "" if fresh else attachment_file(device, str(unique))
    if local_file:
        attachment_metadata(device, str(unique), local_file)
        return
    args = lambda: GLib.Variant("(xs)", (int(part), str(unique)))
    if fresh:
        try:
            call(device_path(device), CONVERSATIONS_IFACE, "refreshAttachmentFile", args())
            return
        except GLib.Error as error:
            if Gio.DBusError.get_remote_error(error) != "org.freedesktop.DBus.Error.UnknownMethod":
                raise
    call(device_path(device), CONVERSATIONS_IFACE, "requestAttachmentFile", args())


contact_registry = ContactRegistry()


def contacts(device):
    """Names and photos by phone number, from the vCards KDE Connect keeps for the device."""
    contact_registry.refresh(device=device)
    emit("contacts", device=device, records=contact_registry.records)


def notification(job):
    """inspect, action or reply on the phone's notification objects, answered by job id."""
    def done(result, error):
        emit("notification", id=job.get("id"), ok=error is None, result=result,
             error=error_text(error) if error else "")
    if not notify_queue.submit(("notification", job.get("id")), lambda: notification_index.execute(job), done):
        emit("notification", id=job.get("id"), ok=False, result=None, error="Phone notification queue is busy; try again")


def handle_command(cmd):
    request_context.fields = {"generation": cmd["_generation"], **request_fields(cmd)}
    try:
        kind = cmd.get("cmd")
        device = cmd.get("device", "")
        if device:
            device_path(device)
            watch(device)
        if kind == "devices":
            last_sent.clear()
            devices()
        elif kind == "start":
            start_backend()
        elif kind == "conversations":
            conversations(device)
        elif kind == "thread":
            thread(device, cmd["thread"], cmd.get("count", 50))
        elif kind in ("reply", "send"):
            if device not in known_reachable:
                raise ValueError("The phone is not reachable; your message was kept for retry")
            if kind == "reply":
                reply(device, cmd["thread"], cmd["text"], cmd.get("attachments"))
            else:
                send(device, cmd.get("addresses", []), cmd["text"], cmd.get("attachments"))
        elif kind == "share":
            share(device, cmd.get("paths", []))
        elif kind == "mount":
            mount(device)
        elif kind == "attachment":
            attachment(device, cmd["part"], cmd["uid"], bool(cmd.get("fresh")))
        elif kind == "contacts":
            contacts(device)
            call(device_path(device) + "/contacts", "org.kde.kdeconnect.device.contacts", "synchronizeRemoteWithLocal")
        elif kind == "thumbnails":
            request_thumbnails(cmd.get("paths", []), cmd.get("thumbnailGeneration", 0))
        elif kind in ("open", "preview"):
            cancelled = (lambda: cmd.get("_previewGeneration") != preview_generation
                         or cmd.get("_generation") != backend_generation) if kind == "preview" else None
            local = copy_phone_file(device, cmd["path"], cmd["mount"], cancelled=cancelled)
            emit("filePreview" if kind == "preview" else "file", path=local)
        elif kind == "probe":
            path, uid = cmd.get("path", ""), cmd.get("uid", "")
            emit("duration", uid=uid, path=path, duration=probe_duration(path), thumb=video_thumbnail(path))
        elif kind == "notification":
            notification(cmd.get("job") or {})
        elif kind in ("acceptPairing", "declinePairing"):
            call(device_path(device), DEVICE_IFACE, "acceptPairing" if kind == "acceptPairing" else "cancelPairing")
            devices_soon()
        else:
            raise ValueError("Unknown phone command")
    except Exception as error:
        fail(str(cmd.get("cmd", "")), error)
    finally:
        request_context.fields = {}


def handle(line):
    global preview_generation
    try:
        cmd = json.loads(line)
        if not isinstance(cmd, dict):
            raise ValueError("Expected a phone command")
    except (ValueError, TypeError) as error:
        fail("parse", error)
        return
    kind = cmd.get("cmd")
    if kind in ("preview", "cancelPreview"):
        preview_generation += 1
        preview_queue.cancel_pending()
        if kind == "cancelPreview":
            return
        thumb_queue.cancel_pending()
        cmd["_previewGeneration"] = preview_generation
    # Repeated sync requests collapse into the one already waiting.
    key = ((kind, cmd.get("device", "")) if kind in ("devices", "conversations", "contacts")
           else (kind, cmd.get("device", ""), cmd.get("request") or cmd.get("uid") or cmd.get("thread", "")))
    generation = backend_generation
    cmd["_generation"] = generation
    def execute():
        if generation != backend_generation:
            fail(kind, "Phone backend restarted; try again", **request_fields(cmd))
            return
        handle_command(cmd)
    if kind in ("reply", "send") and cmd.get("attachments"):
        def prepare():
            return attachment_files(cmd["attachments"])
        def prepared(paths, error):
            if error:
                fail(kind, error, **request_fields(cmd))
            else:
                cmd["attachments"] = paths
                if not io_queue.submit(key, execute):
                    fail(kind, "Phone queue is busy; try again", **request_fields(cmd))
        accepted = media_queue.submit(key, prepare, prepared)
    elif kind == "preview":
        accepted = preview_queue.submit(key, execute)
    elif kind in ("probe", "open", "mount"):
        accepted = media_queue.submit(key, execute)
    elif kind == "devices":
        accepted = device_queue.submit(key, execute)
    else:
        accepted = io_queue.submit(key, execute)
    if not accepted:
        fail(str(kind), "Phone queue is busy; try again", **request_fields(cmd))


def owner_changed(connection, sender, path, interface, name, parameters, *_):
    global backend_generation, known_reachable
    _, old, new = parameters.unpack()
    backend_generation += 1
    known_reachable = set()
    notification_index.invalidate()
    last_sent.clear()
    emit("backend", available=bool(new), reset=True)
    if new:
        devices_soon()


def on_stdin(channel, condition):
    if condition & (GLib.IO_HUP | GLib.IO_ERR):
        loop.quit()
        return False
    line = channel.readline()
    if not line:
        loop.quit()
        return False
    if line.strip():
        handle(line)
    return True


def main():
    global conn, loop, notification_index
    load_durations()
    load_threads()
    media_queue.submit("sweep", sweep_caches)
    try:
        conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    except GLib.Error as error:
        fail("bus", error)
        return 1
    loop = GLib.MainLoop()
    notification_index = NotificationIndex(conn)
    conn.signal_subscribe(BUS, "org.kde.kdeconnect.device.notifications", None, None, None,
                          Gio.DBusSignalFlags.NONE, notification_index.invalidate)
    conn.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
                          "/org/freedesktop/DBus", BUS, Gio.DBusSignalFlags.NONE, owner_changed)
    for signal in ("deviceAdded", "deviceRemoved", "deviceVisibilityChanged", "deviceListChanged"):
        conn.signal_subscribe(BUS, "org.kde.kdeconnect.daemon", signal, ROOT, None, Gio.DBusSignalFlags.NONE,
                              lambda *a: devices_soon())
    GLib.timeout_add_seconds(15, lambda: (devices_soon(), True)[1])
    # A phone user's daemon starts with the shell; a first pairing starts it from the tab.
    if has_paired_phone():
        start_backend()
    channel = GLib.IOChannel.unix_new(sys.stdin.fileno())
    GLib.io_add_watch(channel, GLib.PRIORITY_DEFAULT, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_stdin)
    try:
        loop.run()
    finally:
        io_queue.close()
        media_queue.close()
        thumb_queue.close()
        preview_queue.close()
        notify_queue.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
