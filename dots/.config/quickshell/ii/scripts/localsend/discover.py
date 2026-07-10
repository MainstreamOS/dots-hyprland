#!/usr/bin/env python3
"""
Continuous LocalSend discovery via UDP multicast on 224.0.0.167:53317.

Peers respond to an announcement at the ADVERTISED port — the official app
prefers an HTTP POST to /api/localsend/v2/register there, with a UDP reply
as fallback. Advertising 53317 would hand those replies to the receiver
(when armed) or to nothing (when not), so this process advertises its own
ephemeral port and answers both reply styles there itself. Multicast
announces from peers still arrive on the group socket. Each unique remote
device (by fingerprint) is printed once as a JSON line on stdout. Runs
until the process is killed.
"""

import json
import select
import socket
import sys
import threading
from http.server import ThreadingHTTPServer

from common import (FINGERPRINT, PORT, LocalSendHandler, device_info,
                    join_multicast_socket, start_announcer)

ANNOUNCE_INTERVAL = 2.0

_print_lock = threading.Lock()
_seen = set()
_locals = set()


def emit_device(info, address):
    if not isinstance(info, dict):
        return
    fp = info.get("fingerprint") or ""
    if not fp or fp == FINGERPRINT:
        return
    if address in _locals:
        return
    with _print_lock:
        if fp in _seen:
            return
        _seen.add(fp)
        print(json.dumps({
            "address": address,
            "port": int(info.get("port") or PORT),
            "alias": info.get("alias") or "",
            "fingerprint": fp,
            "deviceType": info.get("deviceType") or "",
            "deviceModel": info.get("deviceModel") or "",
            "protocol": info.get("protocol") or "http",
        }), flush=True)


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


class RegisterHandler(LocalSendHandler):

    def do_POST(self):
        body = self._read_body()
        if self.path.split("?")[0] == "/api/localsend/v2/register":
            try:
                emit_device(json.loads(body or b"{}"), self.client_address[0])
            except Exception:
                pass
            self._json(200, device_info())
        else:
            self._empty(404)


def bind_reply_pair():
    # The UDP reply socket and the /register HTTP listener must share one
    # port number, since both reply styles target the single advertised
    # port. Grab an ephemeral UDP port, then bind TCP to the same number;
    # retry with a fresh port if that number is taken on TCP.
    for _ in range(20):
        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        udp.bind(("", 0))
        port = udp.getsockname()[1]
        try:
            httpd = ThreadingHTTPServer(("", port), RegisterHandler)
            return udp, httpd, port
        except OSError:
            udp.close()
    raise OSError("no usable reply port")


def main():
    global _locals
    _locals = local_ips()

    udp, httpd, reply_port = bind_reply_pair()
    payload = json.dumps(device_info(announce=True, port=reply_port)).encode()

    rx = join_multicast_socket()

    stop_event = threading.Event()
    start_announcer(udp, payload, stop_event, ANNOUNCE_INTERVAL)
    threading.Thread(target=httpd.serve_forever, kwargs={"poll_interval": 0.5}, daemon=True).start()

    try:
        while True:
            readable, _, _ = select.select([rx, udp], [], [], 0.5)
            for sock in readable:
                try:
                    data, addr = sock.recvfrom(8192)
                except OSError:
                    continue
                try:
                    info = json.loads(data.decode("utf-8", "replace"))
                except Exception:
                    continue
                emit_device(info, addr[0])
    finally:
        stop_event.set()
        httpd.shutdown()
        for sock in (rx, udp):
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
