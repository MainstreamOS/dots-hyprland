#!/usr/bin/env python3
"""
Receive files from LocalSend devices.

Runs a LocalSend v2 receiver on TCP port 53317 and keeps the device visible
via UDP multicast on 224.0.0.167:53317. Every incoming session is accepted
automatically for as long as the process runs, so the caller decides when
receiving is armed. Files land in the target directory with de-duplicated
names. Runs until killed.

Usage:
    receive.py [TARGET_DIR]        (default: ~/Downloads)

Output (line-based on stdout):
    READY:<alias>
    SESSION:<senderAlias>
    PROGRESS:<bytesReceived>:<totalBytes>
    SESSION_DONE:<fileCount>
    CANCELLED
    ERROR:<message>
"""

import json
import os
import re
import socket
import sys
import threading
import time
import urllib.parse
import uuid
from http.server import ThreadingHTTPServer

from common import (ALIAS, FINGERPRINT, PORT, LocalSendHandler, device_info,
                    emit, join_multicast_socket, start_announcer)

ANNOUNCE_INTERVAL = 4.0
CHUNK_SIZE = 262144
PROGRESS_MIN_SECONDS = 0.1


def safe_name(name):
    name = os.path.basename(str(name or "")).strip()
    name = re.sub(r'[\x00-\x1f/\\]', "_", name)
    return name or ("file-" + uuid.uuid4().hex[:8])


def dedupe_path(directory, name):
    base, ext = os.path.splitext(name)
    candidate = os.path.join(directory, name)
    counter = 1
    while os.path.exists(candidate):
        candidate = os.path.join(directory, f"{base} ({counter}){ext}")
        counter += 1
    return candidate


class Session:
    def __init__(self, sender_alias, files):
        self.id = uuid.uuid4().hex
        self.sender_alias = sender_alias
        self.files = files            # fileId -> meta dict
        self.tokens = {fid: uuid.uuid4().hex for fid in files}
        self.total_bytes = sum(int(m.get("size") or 0) for m in files.values())
        self.received_bytes = 0
        self.done_files = 0


TARGET_DIR = ""
SESSION = None
LOCK = threading.Lock()


class Handler(LocalSendHandler):

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        if path == "/api/localsend/v2/register":
            self._read_body()
            self._json(200, device_info())
        elif path == "/api/localsend/v2/prepare-upload":
            self._prepare_upload()
        elif path == "/api/localsend/v2/upload":
            self._upload()
        elif path == "/api/localsend/v2/cancel":
            self._cancel()
        else:
            self._empty(404)

    def _prepare_upload(self):
        global SESSION
        try:
            payload = json.loads(self._read_body() or b"{}")
        except Exception:
            self._empty(400)
            return
        files = payload.get("files") or {}
        if not isinstance(files, dict) or not files:
            self._empty(400)
            return
        sender = ((payload.get("info") or {}).get("alias")) or "Unknown device"
        with LOCK:
            if SESSION is not None:
                self._empty(409)
                return
            session = Session(str(sender), files)
            SESSION = session
        emit(f"SESSION:{session.sender_alias}")
        self._json(200, {"sessionId": session.id, "files": session.tokens})

    def _upload(self):
        global SESSION
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        session_id = (query.get("sessionId") or [""])[0]
        file_id = (query.get("fileId") or [""])[0]
        token = (query.get("token") or [""])[0]
        session = SESSION
        if session is None or session.id != session_id:
            self._empty(403)
            return
        if session.tokens.get(file_id) != token:
            self._empty(403)
            return
        meta = session.files.get(file_id) or {}
        length = int(self.headers.get("Content-Length") or 0)
        name = safe_name(meta.get("fileName"))
        os.makedirs(TARGET_DIR, exist_ok=True)
        with LOCK:
            dest = dedupe_path(TARGET_DIR, name)
            partial = dest + ".part"
        try:
            remaining = length
            last_report = 0.0
            with open(partial, "wb") as f:
                while remaining > 0:
                    chunk = self.rfile.read(min(CHUNK_SIZE, remaining))
                    if not chunk:
                        raise IOError("connection closed mid-upload")
                    f.write(chunk)
                    remaining -= len(chunk)
                    with LOCK:
                        session.received_bytes += len(chunk)
                        received = session.received_bytes
                        total = session.total_bytes
                    now = time.monotonic()
                    if now - last_report >= PROGRESS_MIN_SECONDS or remaining == 0:
                        emit(f"PROGRESS:{received}:{max(total, 1)}")
                        last_report = now
            os.replace(partial, dest)
        except Exception as e:
            try:
                os.unlink(partial)
            except OSError:
                pass
            emit(f"ERROR:upload of {name} failed: {e}")
            with LOCK:
                SESSION = None
            self._empty(500)
            return
        finished = False
        with LOCK:
            session.done_files += 1
            finished = session.done_files >= len(session.files)
            if finished:
                SESSION = None
        if finished:
            emit(f"SESSION_DONE:{session.done_files}")
        self._empty(200)

    def _cancel(self):
        global SESSION
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        session_id = (query.get("sessionId") or [""])[0]
        with LOCK:
            session = SESSION
            if session is not None and (not session_id or session.id == session_id):
                SESSION = None
                emit("CANCELLED")
        self._empty(200)


def multicast_presence(stop_event):
    try:
        sock = join_multicast_socket()
    except OSError as e:
        emit(f"ERROR:multicast unavailable: {e}")
        return

    announce_payload = json.dumps(device_info(announce=True)).encode()
    reply_payload = json.dumps(device_info()).encode()
    start_announcer(sock, announce_payload, stop_event, ANNOUNCE_INTERVAL)

    sock.settimeout(0.5)
    while not stop_event.is_set():
        try:
            data, addr = sock.recvfrom(8192)
        except socket.timeout:
            continue
        except OSError:
            break
        try:
            info = json.loads(data.decode("utf-8", "replace"))
        except Exception:
            continue
        if not isinstance(info, dict):
            continue
        if info.get("fingerprint") == FINGERPRINT:
            continue
        if info.get("announce"):
            try:
                sock.sendto(reply_payload, addr)
            except OSError:
                pass
    try:
        sock.close()
    except Exception:
        pass


def main():
    global TARGET_DIR
    TARGET_DIR = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(os.path.expanduser("~"), "Downloads")

    try:
        server = ThreadingHTTPServer(("", PORT), Handler)
    except OSError as e:
        emit(f"ERROR:port {PORT} unavailable: {e}")
        return 1

    stop_event = threading.Event()
    threading.Thread(target=multicast_presence, args=(stop_event,), daemon=True).start()
    emit(f"READY:{ALIAS}")
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        stop_event.set()
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main() or 0)
