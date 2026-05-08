#!/usr/bin/env python3
"""
Continuous LocalSend discovery via UDP multicast on 224.0.0.167:53317.

Sends an announce packet every ANNOUNCE_INTERVAL seconds and listens forever
for replies. Each unique remote device (by fingerprint) is printed once as a
JSON line on stdout. Runs until the process is killed.
"""

import json
import socket
import struct
import sys
import threading
import time
import uuid

MULTICAST_ADDR = "224.0.0.167"
MULTICAST_PORT = 53317
ANNOUNCE_INTERVAL = 2.0
SELF_FINGERPRINT = "qs-discover-" + uuid.uuid4().hex[:12]


def local_ips():
    ips = {"127.0.0.1"}
    try:
        hostname = socket.gethostname()
        _, _, addrs = socket.gethostbyname_ex(hostname)
        ips.update(addrs)
    except Exception:
        pass
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 53))
        ips.add(s.getsockname()[0])
        s.close()
    except Exception:
        pass
    return ips


def announcer(sock, payload, stop_event):
    while not stop_event.is_set():
        try:
            sock.sendto(payload, (MULTICAST_ADDR, MULTICAST_PORT))
        except OSError:
            pass
        stop_event.wait(ANNOUNCE_INTERVAL)


def main():
    locals_ = local_ips()
    seen = set()

    announce = {
        "alias": "Quickshell Bar",
        "version": "2.0",
        "deviceModel": "Hyprland",
        "deviceType": "desktop",
        "fingerprint": SELF_FINGERPRINT,
        "port": MULTICAST_PORT,
        "protocol": "http",
        "download": False,
        "announce": True,
    }
    payload = json.dumps(announce).encode()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except (AttributeError, OSError):
        pass
    sock.bind(("", MULTICAST_PORT))

    mreq = struct.pack("4sl", socket.inet_aton(MULTICAST_ADDR), socket.INADDR_ANY)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)

    stop_event = threading.Event()
    threading.Thread(
        target=announcer, args=(sock, payload, stop_event), daemon=True
    ).start()

    sock.settimeout(0.5)
    try:
        while True:
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
            fp = info.get("fingerprint") or ""
            if fp == SELF_FINGERPRINT:
                continue
            if addr[0] in locals_:
                continue
            if fp in seen:
                continue
            seen.add(fp)
            out = {
                "address": addr[0],
                "port": int(info.get("port") or MULTICAST_PORT),
                "alias": info.get("alias") or "",
                "fingerprint": fp,
                "deviceType": info.get("deviceType") or "",
                "deviceModel": info.get("deviceModel") or "",
                "protocol": info.get("protocol") or "http",
            }
            print(json.dumps(out), flush=True)
    finally:
        stop_event.set()
        try:
            sock.close()
        except Exception:
            pass

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main() or 0)
    except KeyboardInterrupt:
        sys.exit(0)
