"""Contact extraction, vCard parsing and photo caching for kdeconnect-bridge.py."""

import base64
import binascii
import hashlib
import os
import quopri
import re
from pathlib import Path

from phone_runtime import atomic_file, image_extension


def contact_card(text):
    """Read the identity fields and embedded photo in a KDE Connect vCard."""
    text = re.sub(r"\r?\n[ \t]", "", text)
    name, numbers, photo = "", [], b""
    lines = text.splitlines()
    for index, line in enumerate(lines):
        field, separator, value = line.partition(":")
        if not separator:
            continue
        field = field.upper()
        key = field.split(";")[0].split(".")[-1]
        if key == "FN":
            if "ENCODING=QUOTED-PRINTABLE" in field:
                try:
                    value = quopri.decodestring(value).decode("utf-8", "replace")
                except Exception:
                    pass
            name = re.sub(r"\\([nN,;\\])", lambda m: " " if m[1].lower() == "n" else m[1], value).strip()
        elif key == "TEL":
            value = re.sub(r"^tel:", "", value, flags=re.I).split(";")[0]
            number = ("+" if value.strip().startswith("+") else "") + re.sub(r"\D", "", value)
            if number:
                numbers.append(number)
        elif key == "PHOTO":
            if value.startswith("data:image/") and ";base64," in value:
                value = value.split(",", 1)[1]
            elif "ENCODING=BASE64" in field or "ENCODING=B" in field:
                # Some vCard 2.1 writers omit the space on base64 continuations.
                for continuation in lines[index + 1:]:
                    if not continuation or not re.fullmatch(r"[A-Za-z0-9+/=]+", continuation):
                        break
                    value += continuation
            else:
                continue
            if len(value) <= 3000000:
                try:
                    photo = base64.b64decode(value, validate=True)
                except (ValueError, binascii.Error):
                    pass
    return {"name": name, "numbers": numbers, "photo": photo}


class ContactRegistry:
    """Replaceable contact snapshots, preserving device and full-number identity."""

    def __init__(self, data_dir=None, cache_dir=None):
        base_data = data_dir or os.environ.get("XDG_DATA_HOME") or (Path.home() / ".local/share")
        base_cache = cache_dir or os.environ.get("XDG_CACHE_HOME") or (Path.home() / ".cache")
        self.folder = Path(base_data) / "kpeoplevcard"
        self.photos_dir = Path(base_cache) / "mainstream/island/contacts"
        self.signature = None
        self.cards = {}
        self.records = []

    def refresh(self, device=None):
        pattern = f"kdeconnect-{device}" if device else "kdeconnect-*"
        paths = sorted([*self.folder.glob(pattern + "/*.vcf"), *self.folder.glob(pattern + "/*.vcard")])
        signature = []
        for path in paths:
            try:
                stat = path.stat()
                signature.append((path, stat.st_mtime_ns, stat.st_size))
            except OSError:
                continue
        if (device, signature) == self.signature:
            return False
        self.photos_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        cards = {}
        for path, modified, size in signature:
            if size > 4000000:
                continue
            cached = self.cards.get(path)
            if cached and cached[0] == (modified, size):
                cards[path] = cached
                continue
            try:
                card = contact_card(path.read_text(encoding="utf-8", errors="replace"))
            except OSError:
                continue
            photo = card["photo"]
            picture = ""
            ext = image_extension(photo)
            if ext:
                target = self.photos_dir / f"{hashlib.sha256(photo).hexdigest()}.{ext}"
                try:
                    if not target.exists():
                        with atomic_file(target, "wb", "contact-") as output:
                            output.write(photo)
                    picture = target.as_uri()
                except OSError:
                    pass
            record = {"uid": path.stem, "deviceId": path.parent.name.removeprefix("kdeconnect-"),
                      "name": card["name"], "numbers": card["numbers"], "picture": picture}
            cards[path] = ((modified, size), record)
        self.cards = cards
        self.signature = (device, signature)
        self.records = [entry[1] for entry in cards.values()]
        return True
