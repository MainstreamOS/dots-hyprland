#!/usr/bin/env python3
"""Installs AppImages as ordinary apps, and removes them again from wherever they went.

inspect FILE            What FILE is, as JSON. Reads it without ever running it.
install FILE --dir DIR  Moves FILE into DIR and gives it a launcher entry.
list                    Every AppImage with a launcher entry, however it got one, as JSON.
remove DESKTOP_ID       Deletes the AppImage, its launcher entry and its icon.

The launcher entry is the only record of an install, and it holds the full path, so a
custom location needs nothing extra to be found and removed later.
"""

import argparse
import fcntl
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HOME = Path.home()
DATA = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))
CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache"))
APPLICATIONS = DATA / "applications"
ICONS = DATA / "icons/hicolor"
INSPECTED = CACHE / "quickshell/user/generated/appimage"
DEFAULT_FOLDER = HOME / "AppImages"
PREFIX = "mainstream-appimage-"
PATH_KEY = "X-Mainstream-AppImage"
# Which app an entry holds, so another app with the same name is never taken for an update of it.
ID_KEY = "X-Mainstream-AppImage-Id"
ICON_SIZES = (16, 22, 24, 32, 48, 64, 96, 128, 192, 256, 512)
MAX_DESKTOP_FILE = 64 * 1024
MAX_ICON_FILE = 8 * 1024 * 1024
# An entry whose file has gone can't be recognized by its contents, only by its name.
APPIMAGE_NAME = re.compile(r"\.appimage$", re.IGNORECASE)


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def appimage_type(path):
    """1 or 2 for an AppImage, else 0."""
    try:
        with open(path, "rb") as file:
            head = file.read(11)
    except OSError:
        return 0
    if len(head) == 11 and head[:4] == b"\x7fELF" and head[8:10] == b"AI" and head[10] in (1, 2):
        return head[10]
    return 0


def payload_offset(path):
    """Where the image's filesystem starts, which is where its ELF runtime ends."""
    with open(path, "rb") as file:
        head = file.read(64)
        if head[4] == 2:
            table = struct.unpack_from("<Q", head, 0x28)[0]
            entry, count = struct.unpack_from("<HH", head, 0x3A)
        else:
            table = struct.unpack_from("<I", head, 0x20)[0]
            entry, count = struct.unpack_from("<HH", head, 0x2E)
        offset = table + entry * count
        file.seek(offset)
        return offset, file.read(4)


def read_entry(text):
    """The [Desktop Entry] group of a launcher entry, unescaped only as far as we need."""
    values, inside = {}, False
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("["):
            inside = line == "[Desktop Entry]"
        elif inside and "=" in line and not line.startswith("#"):
            key, _, value = line.partition("=")
            values.setdefault(key.strip(), value.strip())
    return values


def read_bounded(image, offset, name, limit):
    """One file from the image, or None when it is missing or larger than limit. It comes through a
    pipe that is cut off past the limit, so a small image holding a file that decompresses to fill
    the disk is refused before any of it is written. The name is taken literally, never as a pattern."""
    command = ["unsquashfs", "-q", "-no-wildcards", "-o", str(offset), "-cat", str(image), name]
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as process:
        data = process.stdout.read(limit + 1)
        if len(data) > limit:
            process.kill()
            return None
    return data if process.returncode == 0 and data else None


def top_level(path, offset):
    """The names at the top of the image, each with its link target or None. Only a guide to what
    to ask for: a link target can hold a line break and forge a line here, so no size is read from it."""
    listing = subprocess.run(["unsquashfs", "-o", str(offset), "-lls", str(path)], capture_output=True, text=True).stdout
    files = {}
    for line in listing.splitlines():
        match = re.match(r"([-l])\S+\s+\S+\s+\d+\s+\S+\s+\S+\s+squashfs-root/([^/]+?)(?: -> (.+))?$", line)
        if match:
            files[match[2]] = match[3] if match[1] == "l" else None
    return files


def read_inside(path, work):
    """Name, icon and details from inside a squashfs image. Nothing in it is run or trusted."""
    offset, magic = payload_offset(path)
    if magic != b"hsqs" or not shutil.which("unsquashfs"):
        return {}
    files = top_level(path, offset)
    desktop_names = [name for name in files if name.endswith(".desktop") and files[name] is None]
    text = read_bounded(path, offset, desktop_names[0], MAX_DESKTOP_FILE) if desktop_names else None
    if text is None:
        return {}
    entry = read_entry(text.decode(errors="replace"))
    # A name from the entry may only pick a file at the top of the image. Otherwise .DirIcon,
    # which is often a link to one there.
    wanted = os.path.basename(entry.get("Icon", ""))
    candidates = [name for name in (wanted + ".png", wanted + ".svg") if name in files]
    if not candidates and ".DirIcon" in files:
        candidates = [files[".DirIcon"] or ".DirIcon"]
    data = read_bounded(path, offset, candidates[0], MAX_ICON_FILE) if candidates else None
    icon = None
    if data:
        # Saved under a name of our own, by what the file really is.
        icon = work / "icon"
        icon.write_bytes(data)
        kind, _ = icon_kind(icon)
        if kind:
            icon = icon.rename(work / f"icon.{kind}")
        else:
            icon.unlink()
            icon = None
    return {"entry": entry, "icon": icon, "desktopName": desktop_names[0]}


def name_from_file(path):
    """A readable name for an image we can't look inside: "Foo_Bar-1.2.3-x86_64.AppImage" is "Foo Bar"."""
    stem = APPIMAGE_NAME.sub("", path.name)
    stem = re.sub(r"[-_.]?(x86[-_]64|amd64|aarch64|arm64|i[36]86)\b", "", stem, flags=re.IGNORECASE)
    stem = re.sub(r"[-_ ]v?\d+(\.\d+)*.*$", "", stem)
    return re.sub(r"[-_]+", " ", stem).strip() or path.name


def slug_for(name):
    """A file-safe name. Letters outside a-z are dropped, so a name with any keeps a short hash of
    itself, and two apps named only in other scripts never share one."""
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    if slug and name.isascii():
        return slug
    return f"{slug or 'app'}-{hashlib.sha256(name.encode()).hexdigest()[:8]}"


def icon_kind(path):
    """Which of our icon formats a file really is, whatever it is called."""
    with open(path, "rb") as file:
        head = file.read(256)
    if head.startswith(b"\x89PNG\r\n\x1a\n"):
        # A real PNG opens with its IHDR chunk, which holds the width.
        if len(head) < 24 or head[12:16] != b"IHDR":
            return "", 0
        return "png", struct.unpack(">I", head[16:20])[0]
    if b"<svg" in head or head.lstrip().startswith(b"<?xml"):
        return "svg", 0
    return "", 0


def clean(value):
    return re.sub(r"[\x00-\x1f]", " ", value or "").strip()


def forget_old_inspections():
    """Folders from looks inside images a day ago, which nothing is showing any more."""
    cutoff = time.time() - 24 * 3600
    for old in INSPECTED.glob("*"):
        try:
            if old.stat().st_mtime < cutoff:
                shutil.rmtree(old, ignore_errors=True)
        except OSError:
            pass


def describe(path, work=None):
    kind = appimage_type(path)
    if not kind:
        fail("This file isn't an AppImage.")
    stat = path.stat()
    # Each look inside gets a folder of its own, so a new version's icon is never taken for the
    # old one's, and two at once never clear what the other still needs.
    if work is None:
        INSPECTED.mkdir(parents=True, exist_ok=True)
        forget_old_inspections()
        work = Path(tempfile.mkdtemp(dir=INSPECTED))
    inside = read_inside(path, work) if kind == 2 else {}
    entry = inside.get("entry", {})
    name = clean(entry.get("Name")) or name_from_file(path)
    identity = inside.get("desktopName") or name
    apps = {app["desktopId"]: app for app in installed_apps()}
    # An app installed under this name is updated only when it is this same app. Another one that
    # happens to share the name gets a number rather than being overwritten. An entry written
    # before the identity was kept counts as the same app.
    base = slug = slug_for(name)
    number = 1
    while (app := apps.get(PREFIX + slug)) and app["identity"] not in ("", identity):
        number += 1
        slug = f"{base}-{number}"
    installed = apps.get(PREFIX + slug)
    icon = inside.get("icon")
    return {
        "name": name,
        "slug": slug,
        "identity": identity,
        "comment": clean(entry.get("Comment")),
        "version": clean(entry.get("X-AppImage-Version")),
        "categories": clean(entry.get("Categories")),
        "wmClass": clean(entry.get("StartupWMClass")),
        "keywords": clean(entry.get("Keywords")),
        "icon": str(icon) if icon else "",
        "size": stat.st_size,
        "path": str(path),
        "defaultFolder": str(DEFAULT_FOLDER),
        "installedPath": installed["path"] if installed else "",
    }


def install_problem(folder, size, moving_within):
    """Why this folder can't hold a runnable app, or "" when it can."""
    try:
        folder.mkdir(parents=True, exist_ok=True)
    except OSError:
        return f"{folder} can't be created."
    if not os.access(folder, os.W_OK | os.X_OK):
        return f"You don't have permission to write to {folder}."
    stat = os.statvfs(folder)
    if stat.f_flag & os.ST_NOEXEC:
        return f"{folder} is on a drive that doesn't allow running programs. Pick another location."
    if not moving_within and stat.f_bavail * stat.f_frsize < size:
        return f"There isn't enough free space in {folder}."
    # Some filesystems, FAT and exFAT among them, drop the executable bit.
    try:
        with tempfile.NamedTemporaryFile(dir=folder, prefix=".appimage-check-") as probe:
            os.chmod(probe.name, 0o755)
            if not os.access(probe.name, os.X_OK):
                return f"{folder} can't hold runnable programs. Pick another location."
    except OSError:
        return f"You don't have permission to write to {folder}."
    return ""


def desktop_string(value):
    return value.replace("\\", "\\\\").replace("\n", " ")


def exec_argument(path):
    """A path as one argument of an Exec line, by the Desktop Entry spec's two layers of escaping."""
    value = str(path).replace("%", "%%")
    if re.fullmatch(r"[A-Za-z0-9_@%+=:,./-]+", value):
        return value
    value = re.sub(r'(["`$\\])', r"\\\1", value)
    return desktop_string(f'"{value}"')


def refresh_entries():
    if shutil.which("update-desktop-database"):
        subprocess.run(["update-desktop-database", str(APPLICATIONS)], capture_output=True)


def install_icon(icon, slug):
    remove_icons(slug)
    if not icon:
        return "application-x-executable"
    source = Path(icon)
    name = PREFIX + slug
    # The image is already in place by now, so an icon that can't be copied still leaves it a launcher entry.
    try:
        kind, width = icon_kind(source)
        if kind == "png":
            size = next((size for size in ICON_SIZES if size >= width), ICON_SIZES[-1])
            target = ICONS / f"{size}x{size}/apps/{name}.png"
        elif kind == "svg":
            target = ICONS / f"scalable/apps/{name}.svg"
        else:
            return "application-x-executable"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    except OSError:
        return "application-x-executable"
    return name


def remove_icons(slug):
    for icon in ICONS.glob(f"*/apps/{PREFIX}{slug}.*"):
        icon.unlink(missing_ok=True)


def move_into_place(source, target):
    """Gets the image to its home whole or not at all, and leaves a read-only source behind."""
    if source == target:
        return
    try:
        os.replace(source, target)
        return
    except OSError:
        pass
    tmp = target.with_name(f".{target.name}.part")
    try:
        shutil.copyfile(source, tmp)
        os.replace(tmp, target)
    except OSError as error:
        tmp.unlink(missing_ok=True)
        fail(f"Couldn't copy the AppImage: {error.strerror or error}")
    try:
        source.unlink()
    except OSError:
        pass


def install(source_path, folder_path):
    INSPECTED.mkdir(parents=True, exist_ok=True)
    # One install at a time: picking a free name and taking it must not interleave with another
    # install picking the same one.
    with open(INSPECTED.parent / "appimage-install.lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with tempfile.TemporaryDirectory(dir=INSPECTED) as work:
            install_with(Path(source_path).absolute(), Path(folder_path).expanduser().absolute(), Path(work))


def install_with(source, folder, work):
    info = describe(source, work)
    problem = install_problem(folder, info["size"], folder.stat().st_dev == source.stat().st_dev if folder.exists() else False)
    if problem:
        fail(problem)
    slug = info["slug"]
    target = folder / f"{slug}.AppImage"
    previous = info["installedPath"]
    move_into_place(source, target)
    os.chmod(target, 0o755)
    # An update to a new folder takes the old copy with it.
    if previous and Path(previous) != target and appimage_type(previous):
        Path(previous).unlink(missing_ok=True)
    lines = ["[Desktop Entry]", "Type=Application", f"Name={desktop_string(info['name'])}"]
    if info["comment"]:
        lines.append(f"Comment={desktop_string(info['comment'])}")
    lines.append(f"Icon={install_icon(info['icon'], slug)}")
    lines.append(f"TryExec={desktop_string(str(target))}")
    # Tells images that offer to add their own launcher entry not to.
    lines.append(f"Exec=env DESKTOPINTEGRATION=1 {exec_argument(target)} %U")
    lines.append("Terminal=false")
    categories = re.sub(r"[^A-Za-z0-9;-]", "", info["categories"])
    lines.append(f"Categories={categories or 'Utility;'}")
    if info["keywords"]:
        lines.append(f"Keywords={desktop_string(info['keywords'])}")
    if info["wmClass"]:
        lines.append(f"StartupWMClass={desktop_string(info['wmClass'])}")
    if info["version"]:
        lines.append(f"X-AppImage-Version={desktop_string(info['version'])}")
    lines.append(f"{PATH_KEY}={desktop_string(str(target))}")
    lines.append(f"{ID_KEY}={desktop_string(info['identity'])}")
    APPLICATIONS.mkdir(parents=True, exist_ok=True)
    entry = APPLICATIONS / f"{PREFIX}{slug}.desktop"
    tmp = entry.with_name(f".{entry.name}.part")
    tmp.write_text("\n".join(lines) + "\n")
    tmp.replace(entry)
    refresh_entries()
    print(json.dumps({"name": info["name"], "path": str(target), "desktopId": entry.stem}))


def unescape_desktop(value):
    return re.sub(r"\\(.)", lambda m: {"s": " ", "n": "\n", "t": "\t", "r": "\r", "\\": "\\"}.get(m[1], m[0]), value)


def exec_target(line):
    """The program an Exec line runs, looking past env and its settings."""
    tokens = re.findall(r'"((?:[^"\\]|\\.)*)"|(\S+)', unescape_desktop(line))
    words = [re.sub(r"\\(.)", r"\1", quoted) if quoted else plain for quoted, plain in tokens]
    words = [word.replace("%%", "%") for word in words]
    if words and os.path.basename(words[0]) == "env":
        words = words[1:]
        while words and (words[0].startswith("-") or re.match(r"\w+=", words[0])):
            words = words[1:]
    return words[0] if words else ""


def appimage_of(entry):
    """The AppImage a launcher entry launches, or "" when it launches something else."""
    ours = entry.get(PATH_KEY)
    if ours:
        return unescape_desktop(ours)
    target = exec_target(entry.get("Exec", ""))
    if not target.startswith("/"):
        return ""
    if os.path.exists(target):
        return target if appimage_type(target) else ""
    return target if APPIMAGE_NAME.search(target) else ""


def installed_apps():
    apps = []
    try:
        files = sorted(APPLICATIONS.glob("*.desktop"))
    except OSError:
        return apps
    for file in files:
        try:
            entry = read_entry(file.read_text(errors="replace"))
        except OSError:
            continue
        path = appimage_of(entry)
        if not path:
            continue
        size = os.path.getsize(path) if os.path.exists(path) else 0
        apps.append({"desktopId": file.stem, "name": entry.get("Name") or file.stem, "icon": entry.get("Icon", ""),
                     "path": path, "bytes": size, "missing": not os.path.exists(path), "kind": "appimage",
                     "identity": unescape_desktop(entry.get(ID_KEY, ""))})
    return apps


def remove(desktop_id):
    if "/" in desktop_id or desktop_id.startswith("."):
        fail("That isn't an app this can remove.")
    file = APPLICATIONS / f"{desktop_id}.desktop"
    try:
        entry = read_entry(file.read_text(errors="replace"))
    except OSError:
        fail("That app is already gone.")
    path = appimage_of(entry)
    if not path:
        fail("That app isn't an AppImage.")
    if os.path.lexists(path):
        try:
            os.unlink(path)
        except OSError as error:
            fail(f"Couldn't delete {path}: {error.strerror or error}")
    file.unlink(missing_ok=True)
    if desktop_id.startswith(PREFIX):
        remove_icons(desktop_id[len(PREFIX):])
    # Other tools keep an icon beside the image, in a folder made for it.
    icon = entry.get("Icon", "")
    if icon.startswith("/") and Path(icon).parent == Path(path).parent / ".icons":
        Path(icon).unlink(missing_ok=True)
    refresh_entries()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("inspect").add_argument("file", type=Path)
    add = commands.add_parser("install")
    add.add_argument("file")
    add.add_argument("--dir", default=str(DEFAULT_FOLDER))
    commands.add_parser("list")
    commands.add_parser("remove").add_argument("desktop_id")
    args = parser.parse_args()
    if args.command == "inspect":
        print(json.dumps(describe(args.file.absolute())))
    elif args.command == "install":
        install(args.file, args.dir)
    elif args.command == "list":
        print(json.dumps(installed_apps()))
    else:
        remove(args.desktop_id)


if __name__ == "__main__":
    main()
