"""Shared LocalSend identity and plumbing for the shell's discover/send/receive scripts.

One alias and one stable fingerprint across all three means peers see a
single device instead of one entry per running script, and the /info and
/register responses stay identical between the discovery and receive
servers.
"""

import hashlib
import json
import socket
import struct
import subprocess
import threading
import urllib.parse
import uuid
from http.server import BaseHTTPRequestHandler

from alias_store import get_alias

ALIAS = get_alias()
MULTICAST_ADDR = "224.0.0.167"
PORT = 53317


def _machine_seed():
    for path in ("/etc/machine-id", "/var/lib/dbus/machine-id"):
        try:
            with open(path) as f:
                seed = f.read().strip()
                if seed:
                    return seed
        except OSError:
            continue
    return socket.gethostname() or uuid.uuid4().hex


FINGERPRINT = "qs-" + hashlib.sha256(_machine_seed().encode()).hexdigest()[:24]


def device_info(announce=False, port=PORT, protocol="http"):
    return {
        "alias": ALIAS,
        "version": "2.0",
        "deviceModel": "Hyprland",
        "deviceType": "desktop",
        "fingerprint": FINGERPRINT,
        "port": port,
        "protocol": protocol,
        "download": False,
        "announce": announce,
    }


def emit(line):
    print(line, flush=True)


def lan_addresses():
    """Choose local multicast interfaces even when a VPN owns the default route."""
    try:
        result = subprocess.run(["ip", "-j", "-4", "address", "show", "up"],
                                capture_output=True, text=True, timeout=2, check=True)
        addresses = []
        for interface in json.loads(result.stdout):
            flags = interface.get("flags", [])
            if "MULTICAST" not in flags or "POINTOPOINT" in flags or "LOOPBACK" in flags:
                continue
            for address in interface.get("addr_info", []):
                if address.get("family") == "inet" and address.get("scope") == "global":
                    addresses.append(address["local"])
        return list(dict.fromkeys(addresses))
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        return []


def join_multicast_socket():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except (AttributeError, OSError):
        pass
    sock.bind(("", PORT))
    joined = False
    last_error = None
    for address in lan_addresses() or ["0.0.0.0"]:
        membership = struct.pack("=4s4s", socket.inet_aton(MULTICAST_ADDR), socket.inet_aton(address))
        try:
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, membership)
            joined = True
        except OSError as error:
            last_error = error
    if not joined:
        sock.close()
        raise last_error
    return sock


def announce_loop(sock, payload, stop_event, interval):
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
    while not stop_event.is_set():
        for address in lan_addresses() or ["0.0.0.0"]:
            try:
                sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(address))
                sock.sendto(payload, (MULTICAST_ADDR, PORT))
            except OSError:
                pass
        stop_event.wait(interval)


def start_announcer(sock, payload, stop_event, interval):
    threading.Thread(
        target=announce_loop, args=(sock, payload, stop_event, interval), daemon=True
    ).start()


class LocalSendHandler(BaseHTTPRequestHandler):
    """Base for the LocalSend HTTP surfaces: shared helpers plus the /info
    route, so both servers present the same identity."""

    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _empty(self, code):
        self.send_response(code)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _read_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length > 0 else b""

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if path in ("/api/localsend/v2/info", "/api/localsend/v1/info"):
            self._json(200, device_info())
        else:
            self._empty(404)
