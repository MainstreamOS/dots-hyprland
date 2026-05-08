#!/usr/bin/env python3
"""
Send files to a LocalSend device.

Usage:
    send.py <protocol> <host> <port> <file_or_url> [<file_or_url> ...]

protocol: "http" or "https" (https uses self-signed cert, verification disabled)

Inputs may be plain filesystem paths or file:// URLs (percent-decoded automatically).

Output (line-based on stdout):
    SESSION:<sessionId>
    PROGRESS:<bytesSent>:<totalBytes>
    FILE_DONE:<fileId>
    ALL_DONE
    ERROR:<message>
"""

import http.client
import json
import mimetypes
import os
import socket
import ssl
import sys
import urllib.parse
import uuid

ALIAS = "Quickshell Bar"
SELF_PORT = 53317
PROGRESS_INTERVAL = 65536
CHUNK_SIZE = 65536


def emit(line):
    print(line, flush=True)


def decode_path(arg):
    if arg.startswith("file://"):
        return urllib.parse.unquote(arg[len("file://"):])
    return arg


def make_connection(protocol, host, port, timeout=600):
    if protocol == "https":
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        return http.client.HTTPSConnection(host, port, timeout=timeout, context=ctx)
    return http.client.HTTPConnection(host, port, timeout=timeout)


def main():
    if len(sys.argv) < 5:
        emit("ERROR:usage: send.py PROTOCOL HOST PORT FILE [FILE ...]")
        return 2
    protocol = sys.argv[1].lower()
    if protocol not in ("http", "https"):
        emit(f"ERROR:invalid protocol: {protocol}")
        return 2
    host = sys.argv[2]
    try:
        port = int(sys.argv[3])
    except ValueError:
        emit(f"ERROR:invalid port: {sys.argv[3]}")
        return 2

    inputs = sys.argv[4:]
    files_meta = {}
    total_bytes = 0
    for arg in inputs:
        path = decode_path(arg)
        if not os.path.isfile(path):
            emit(f"ERROR:not a file: {path}")
            return 2
        size = os.path.getsize(path)
        fid = uuid.uuid4().hex
        ftype = mimetypes.guess_type(path)[0] or "application/octet-stream"
        files_meta[fid] = {
            "_path": path,
            "id": fid,
            "fileName": os.path.basename(path),
            "size": size,
            "fileType": ftype,
            "preview": None,
        }
        total_bytes += size

    payload_files = {fid: {k: v for k, v in m.items() if not k.startswith("_")}
                     for fid, m in files_meta.items()}
    payload = {
        "info": {
            "alias": ALIAS,
            "version": "2.0",
            "deviceModel": "Hyprland",
            "deviceType": "desktop",
            "fingerprint": "qs-" + uuid.uuid4().hex[:16],
            "port": SELF_PORT,
            "protocol": protocol,
            "download": False,
        },
        "files": payload_files,
    }
    body = json.dumps(payload).encode()

    try:
        conn = make_connection(protocol, host, port)
        conn.request("POST", "/api/localsend/v2/prepare-upload",
                     body=body, headers={"Content-Type": "application/json"})
        resp = conn.getresponse()
        prepare_status = resp.status
        prepare_data = resp.read()
        conn.close()
    except (socket.error, ssl.SSLError, http.client.HTTPException) as e:
        emit(f"ERROR:prepare-upload failed: {e}")
        return 1

    if prepare_status == 204:
        emit("ERROR:receiver declined (no files accepted)")
        return 1
    if prepare_status == 401 or prepare_status == 403:
        emit("ERROR:receiver requires PIN (not supported yet)")
        return 1
    if prepare_status >= 400:
        snippet = prepare_data[:200].decode("utf-8", "replace")
        emit(f"ERROR:prepare-upload status {prepare_status}: {snippet}")
        return 1

    try:
        resp_json = json.loads(prepare_data)
    except Exception as e:
        emit(f"ERROR:invalid prepare-upload response: {e}")
        return 1

    session_id = resp_json.get("sessionId")
    file_tokens = resp_json.get("files", {}) or {}
    if not session_id or not file_tokens:
        emit("ERROR:no session or no files accepted")
        return 1
    emit(f"SESSION:{session_id}")

    bytes_sent = 0
    last_report = -PROGRESS_INTERVAL
    for fid, token in file_tokens.items():
        meta = files_meta.get(fid)
        if not meta:
            emit(f"ERROR:unknown file id from receiver: {fid}")
            return 1
        path = meta["_path"]
        size = meta["size"]
        params = urllib.parse.urlencode({
            "sessionId": session_id,
            "fileId": fid,
            "token": token,
        })
        upload_path = f"/api/localsend/v2/upload?{params}"

        try:
            conn = make_connection(protocol, host, port)
            conn.putrequest("POST", upload_path)
            conn.putheader("Content-Type", meta["fileType"])
            conn.putheader("Content-Length", str(size))
            conn.endheaders()

            sent_in_file = 0
            with open(path, "rb") as f:
                while True:
                    chunk = f.read(CHUNK_SIZE)
                    if not chunk:
                        break
                    conn.send(chunk)
                    sent_in_file += len(chunk)
                    overall = bytes_sent + sent_in_file
                    if overall - last_report >= PROGRESS_INTERVAL or overall == total_bytes:
                        emit(f"PROGRESS:{overall}:{total_bytes}")
                        last_report = overall

            up_resp = conn.getresponse()
            up_data = up_resp.read()
            conn.close()
            if up_resp.status >= 400:
                snippet = up_data[:200].decode("utf-8", "replace")
                emit(f"ERROR:upload status {up_resp.status}: {snippet}")
                return 1
        except (socket.error, ssl.SSLError, http.client.HTTPException) as e:
            emit(f"ERROR:upload failed: {e}")
            return 1

        bytes_sent += size
        emit(f"FILE_DONE:{fid}")
        emit(f"PROGRESS:{bytes_sent}:{total_bytes}")
        last_report = bytes_sent

    emit("ALL_DONE")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main() or 0)
    except KeyboardInterrupt:
        emit("ERROR:cancelled")
        sys.exit(130)
