"""Shared pieces of the phone helpers: bounded background work, atomic writes and file checks."""

from concurrent.futures import ThreadPoolExecutor
import contextlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import threading
import time


CACHE_HOME = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
PHONE_CACHE = CACHE_HOME / "quickshell/phone"
VOICE_NOTES = CACHE_HOME / "quickshell/phone-voice-notes"
LINK_PREVIEWS = CACHE_HOME / "quickshell/link_previews"
DAY = 86400
# Folder, days an entry is kept, and an optional size budget in bytes.
CACHE_LIMITS = (
    (PHONE_CACHE / "open", 1, 0),
    (PHONE_CACHE / "mms_out", 1, 0),
    (PHONE_CACHE / "thumbs", 30, 0),
    (PHONE_CACHE / "gifs", 7, 0),  # Directories.phoneGifs
    (VOICE_NOTES, 7, 0),
    (LINK_PREVIEWS / "thumbs", 30, 0),
    (LINK_PREVIEWS / "media", 30, 300 << 20),
)


def sweep_caches():
    """Drops cached copies past their age, then the oldest past a size budget."""
    now = time.time()
    for folder, days, budget in CACHE_LIMITS:
        try:
            entries = sorted(((e.stat().st_mtime, e.stat().st_size if e.is_file() else 0, e)
                              for e in os.scandir(folder)), key=lambda item: item[0], reverse=True)
        except OSError:
            continue
        used = 0
        for modified, size, entry in entries:
            used += size
            if now - modified > days * DAY or (budget and used > budget):
                try:
                    shutil.rmtree(entry.path) if entry.is_dir(follow_symlinks=False) else os.unlink(entry.path)
                except OSError:
                    pass
IMAGE_MAGIC = ((b"\x89PNG\r\n\x1a\n", "png"), (b"\xff\xd8\xff", "jpg"), (b"GIF87a", "gif"), (b"GIF89a", "gif"))


def image_extension(head):
    """The image type that a file's first bytes show, or ""."""
    for magic, ext in IMAGE_MAGIC:
        if head.startswith(magic):
            return ext
    return "webp" if head.startswith(b"RIFF") and head[8:12] == b"WEBP" else ""


def jpeg_exif_thumbnail(head):
    """The thumbnail a camera stores in a JPEG's EXIF block, from the file's first bytes, or None."""
    if head[:2] != b"\xff\xd8":
        return None
    i = 2
    while i + 4 <= len(head) and head[i] == 0xFF:
        marker, length = head[i + 1], int.from_bytes(head[i + 2:i + 4], "big")
        if marker == 0xDA:
            return None
        if marker == 0xE1 and head[i + 4:i + 10] == b"Exif\0\0":
            return _ifd1_thumbnail(head[i + 10:i + 2 + length])
        i += 2 + length
    return None


def _ifd1_thumbnail(tiff):
    order = {b"II": "little", b"MM": "big"}.get(tiff[:2])
    if order is None:
        return None
    def number(offset, size):
        return int.from_bytes(tiff[offset:offset + size], order) if offset + size <= len(tiff) else None
    ifd0 = number(4, 4)
    count = number(ifd0, 2) if ifd0 else None
    ifd1 = number(ifd0 + 2 + 12 * count, 4) if count is not None else None
    entries = number(ifd1, 2) if ifd1 else None
    if entries is None:
        return None
    start = size = None
    for k in range(entries):
        entry = ifd1 + 2 + 12 * k
        tag = number(entry, 2)
        if tag == 0x0201:
            start = number(entry + 8, 4)
        elif tag == 0x0202:
            size = number(entry + 8, 4)
    if not start or not size or start + size > len(tiff):
        return None
    data = tiff[start:start + size]
    return data if data[:2] == b"\xff\xd8" else None


def valid_device(device):
    return bool(re.fullmatch(r"[A-Za-z0-9_]+", device or ""))


def valid_uid(uid):
    return bool(re.fullmatch(r"[A-Za-z0-9_.-]{1,255}", uid or "")) and uid not in (".", "..")


@contextlib.contextmanager
def atomic_file(destination, mode="w", prefix="tmp-"):
    """A private temporary file that replaces destination only when the block succeeds."""
    directory = os.path.dirname(os.fspath(destination))
    os.makedirs(directory, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(dir=directory, prefix=prefix)
    try:
        with os.fdopen(fd, mode) as output:
            yield output
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def render(cmd, destination, timeout, input=None):
    """Runs a converter whose output argument is destination through a temporary name beside it, so a timeout or
    a killed process never leaves a partial file under the final name. True when a non-empty file landed."""
    directory, name = os.path.split(os.fspath(destination))
    fd, temporary = tempfile.mkstemp(dir=directory, prefix=".part-", suffix=os.path.splitext(name)[1])
    os.close(fd)
    try:
        subprocess.run([temporary if arg == destination else arg for arg in cmd], check=True, timeout=timeout,
                       input=input, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if os.path.getsize(temporary) == 0:
            return False
        os.replace(temporary, destination)
        return True
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class WorkQueue:
    def __init__(self, workers, capacity, name):
        self.executor = ThreadPoolExecutor(max_workers=workers, thread_name_prefix=name)
        self.capacity = capacity
        self.jobs = {}
        self.lock = threading.Lock()

    def submit(self, key, work, done=None):

        from gi.repository import GLib  # only the bridge and calls.py queue work
        with self.lock:
            if key in self.jobs:
                return True
            if len(self.jobs) >= self.capacity:
                return False
            future = self.executor.submit(work)
            self.jobs[key] = future

        def finished(result):
            with self.lock:
                self.jobs.pop(key, None)
            if done:
                GLib.idle_add(deliver, result)

        def deliver(result):
            try:
                value = result.result()
            except Exception as error:
                done(None, error)
            else:
                done(value, None)
            return False

        future.add_done_callback(finished)
        return True

    def cancel_pending(self):
        with self.lock:
            pending = list(self.jobs.values())
        for future in pending:
            future.cancel()

    def close(self):
        self.executor.shutdown(wait=False, cancel_futures=True)
