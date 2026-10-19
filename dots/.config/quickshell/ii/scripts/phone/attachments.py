"""Device-scoped attachment identities and private, atomic file caches."""

import fcntl
import hashlib
import json
import os
from pathlib import Path
import threading
from concurrent.futures import CancelledError

from phone_runtime import CACHE_HOME, PHONE_CACHE, atomic_file, valid_device, valid_uid

_index_cache = {}
_index_lock = threading.Lock()


def valid_identity(device, uid):
    return valid_device(device) and valid_uid(uid)


def attachment_file(device, uid):
    if not valid_identity(device, uid):
        return ""
    index = PHONE_CACHE / "attachments.json"
    try:
        stat = index.stat()
        signature = (stat.st_ino, stat.st_mtime_ns, stat.st_size)
        with _index_lock:
            cached = _index_cache.get(str(index))
            if not cached or cached[0] != signature:
                cached = (signature, json.loads(index.read_text()))
                _index_cache[str(index)] = cached
            saved = cached[1].get(device, {}).get(uid, "")
        if saved and Path(saved).is_file():
            return saved
    except (OSError, ValueError, TypeError, AttributeError):
        pass
    legacy = CACHE_HOME / "kdeconnect.daemon" / device
    for suffix in ("", ".jpg", ".jpeg", ".png", ".gif", ".webp"):
        candidate = legacy / (uid + suffix)
        if candidate.is_file() and candidate.stat().st_size:
            return str(candidate)
    return ""


def remember_attachment(device, uid, path):
    if not valid_identity(device, uid) or not Path(path).is_absolute() or not Path(path).is_file():
        return
    if attachment_file(device, uid) == path:
        return
    directory = PHONE_CACHE
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (directory / "attachments.lock").open("a+") as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        index = directory / "attachments.json"
        try:
            data = json.loads(index.read_text())
            if not isinstance(data, dict):
                data = {}
        except (OSError, ValueError):
            data = {}
        bucket = data.get(device)
        if not isinstance(bucket, dict):
            bucket = {}
            data[device] = bucket
        if bucket.get(uid) == path:
            return
        bucket[uid] = path
        with atomic_file(index, prefix="attachments-") as output:
            json.dump(data, output, separators=(",", ":"))
        stat = index.stat()
        with _index_lock:
            _index_cache[str(index)] = ((stat.st_ino, stat.st_mtime_ns, stat.st_size), data)


def copy_phone_file(device, path, mount, cancelled=None):
    def check():
        if cancelled and cancelled():
            raise CancelledError()

    check()
    source = Path(path).resolve(strict=True)
    if not mount or not source.is_relative_to(Path(mount).resolve(strict=True)) or not source.is_file():
        raise ValueError("File is outside the phone's mounted storage")
    stat = source.stat()
    digest = hashlib.sha256(f"{device}\0{source}\0{stat.st_size}\0{stat.st_mtime_ns}".encode()).hexdigest()
    directory = PHONE_CACHE / "open" / digest
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    destination = directory / source.name
    if destination.is_file() and destination.stat().st_size == stat.st_size:
        return str(destination)
    with atomic_file(destination, "wb", "copy-") as output, source.open("rb") as input_file:
        while chunk := input_file.read(256 * 1024):
            check()
            output.write(chunk)
        check()
        after = source.stat()
        if (after.st_size, after.st_mtime_ns) != (stat.st_size, stat.st_mtime_ns):
            raise ValueError("The phone file changed while it was being copied; try again")
    return str(destination)
