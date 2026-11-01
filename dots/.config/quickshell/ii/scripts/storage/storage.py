#!/usr/bin/env python3
"""Measures disk use and frees space for the Settings Storage page.

scan             One JSON object per line as each result is ready, the last scan's first.
list PATH        The entries of a folder inside Home with their sizes, as JSON.
large            The largest files in Home outside hidden folders, as JSON.
clean ID         Runs one of the cleanups scan offers.
trash PATH       Moves something inside Home to the Trash.
"""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
CACHE = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache"))
DATA = Path(os.environ.get("XDG_DATA_HOME", HOME / ".local/share"))
LAST_SCAN = CACHE / "quickshell/user/generated/storage-scan.jsonl"
TRASH = DATA / "Trash"
COREDUMPS = Path("/var/lib/systemd/coredump")
KEPT_JOURNAL = 200 * 1024 * 1024
THUMBNAILS = [CACHE / "thumbnails"]
TOOL_CACHES = [CACHE / name for name in ("yay", "paru", "uv", "pip", "pnpm", "go-build")] + [HOME / ".npm/_cacache"]
LARGEST_FILES = 15
LARGEST_FILE_MIN = 100 * 1024 * 1024
ENV = {**os.environ, "LC_ALL": "C"}
# Filesystems that hold no files of the user's own.
PSEUDO = {"tmpfs", "devtmpfs", "squashfs", "overlay", "efivarfs", "autofs", "ramfs", "iso9660"}


def run(*command):
    try:
        return subprocess.run(command, capture_output=True, text=True, env=ENV).stdout
    except OSError:
        return ""


def du(*paths, depth=None, every_file=False):
    """{path: bytes} for what du can read; a folder it can't read counts for what it could."""
    command = ["du", "-x", "-B1"]
    if depth is not None:
        command.append(f"--max-depth={depth}")
    if every_file:
        command.append("-a")
    found = [str(path) for path in paths if os.path.lexists(path)]
    if not found:
        return {}
    result = {}
    for line in run(*command, "--", *found).splitlines():
        size, _, path = line.partition("\t")
        if size.isdigit():
            result[path] = int(size)
    return result


def size_of(paths):
    return sum(du(path).get(str(path), 0) for path in paths)


def parse_size(text):
    match = re.search(r"([\d.]+)\s*([KMGT]?)i?B?", text)
    if not match:
        return 0
    return round(float(match[1]) * 1024 ** " KMGT".index(match[2] or " "))


def mounts():
    """(mount, device, filesystem) of every real filesystem, longest path first."""
    found = []
    for line in Path("/proc/self/mountinfo").read_text().splitlines():
        left, _, right = line.partition(" - ")
        mount = left.split()[4].replace("\\040", " ")
        fstype, device = right.split()[:2]
        if fstype not in PSEUDO and device.startswith("/dev/") and not device.startswith("/dev/loop"):
            found.append((mount, device, fstype))
    return sorted(found, key=lambda entry: len(entry[0]), reverse=True)


def device_of(path):
    for mount, device, _ in mounts():
        if str(path) == mount or str(path).startswith(mount.rstrip("/") + "/"):
            return device
    return ""


def disks():
    seen = {}
    for mount, device, fstype in mounts():
        # One filesystem mounted in several places shows once, at its shortest path.
        seen[device] = (mount, fstype)
    result = []
    for device, (mount, fstype) in seen.items():
        if mount == "/boot" or mount.startswith(("/boot/", "/efi")):
            continue
        try:
            stat = os.statvfs(mount)
        except OSError:
            continue
        total = stat.f_blocks * stat.f_frsize
        if total > 0:
            result.append({"kind": "disk", "mount": mount, "device": device, "fstype": fstype, "total": total,
                           "free": stat.f_bavail * stat.f_frsize, "used": total - stat.f_bfree * stat.f_frsize})
    return sorted(result, key=lambda disk: (disk["mount"] != "/", disk["mount"]))


def user_folders():
    names = {"documents": ("DOCUMENTS", "Documents"), "downloads": ("DOWNLOAD", "Downloads"),
             "pictures": ("PICTURES", "Pictures"), "videos": ("VIDEOS", "Videos"), "music": ("MUSIC", "Music")}
    configured = {}
    try:
        for line in (Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "user-dirs.dirs").read_text().splitlines():
            match = re.match(r'XDG_(\w+)_DIR="(.*)"', line)
            if match:
                configured[match[1]] = match[2].replace("$HOME", str(HOME))
    except OSError:
        pass
    return {key: Path(configured.get(xdg, HOME / folder)) for key, (xdg, folder) in names.items()}


def usage():
    """What fills the disk. Home is measured once, a few levels deep, and read from for its parts."""
    home = du(HOME, depth=3)
    folders = user_folders()
    parts = {key: [path] for key, path in folders.items()}
    parts["games"] = [DATA / "Steam", HOME / ".steam/steam", HOME / "Games"]
    parts["cache"] = [CACHE]
    parts["trash"] = [TRASH]
    parts["flatpak"] = [DATA / "flatpak"]
    # Each folder is counted once. A symlink such as ~/.steam/steam would count what its target
    # already did, a folder set to Home itself is how a user folder is turned off, and a folder
    # named twice or inside another's counts only where it is named first or most closely.
    counted = []
    for key, paths in parts.items():
        for path in paths:
            if (not path.is_symlink() and str(path) in home and path.is_relative_to(HOME) and path != HOME
                    and all(path != other for other, _ in counted)):
                counted.append((path, key))
    sizes = {key: 0 for key in parts}
    for path, key in counted:
        inside = [other for other, _ in counted if other != path and other.is_relative_to(path)]
        nearest = [other for other in inside if not any(other != mid and other.is_relative_to(mid) for mid in inside)]
        sizes[key] += max(0, home[str(path)] - sum(home[str(other)] for other in nearest))
    sizes["otherHome"] = max(0, home.get(str(HOME), 0) - sum(sizes.values()))
    home_device = device_of(HOME)
    for key, size in sizes.items():
        paths = parts.get(key, [HOME])
        path = next((path for path in paths if path.exists()), paths[0])
        yield {"kind": "usage", "id": key, "size": size, "path": str(path), "device": home_device}
    system = du("/usr", "/opt", "/var/lib/flatpak")
    yield {"kind": "usage", "id": "apps", "size": system.get("/usr", 0) + system.get("/opt", 0), "path": "",
           "device": device_of("/usr")}
    # Flatpak's system apps usually sit beside the user's, and a split /home splits them too.
    yield {"kind": "usage", "id": "flatpakSystem", "size": system.get("/var/lib/flatpak", 0), "path": "",
           "device": device_of("/var/lib/flatpak")}


def orphans():
    return run("pacman", "-Qdttq").split()


def unused_flatpaks():
    if not shutil.which("flatpak"):
        return []
    try:
        output = subprocess.run(["flatpak", "uninstall", "--unused"], input="n\n", capture_output=True, text=True, env=ENV).stdout
    except OSError:
        return []
    return re.findall(r"^\s*\d+\.\s+(\S+)", output, re.M)


def cleanups():
    yield {"kind": "clean", "id": "trash", "size": size_of([TRASH]), "items": []}
    match = re.search(r"disk space saved: ([\d.]+ \w+)", run("paccache", "-dk1"))
    yield {"kind": "clean", "id": "packages", "size": parse_size(match[1]) if match else 0, "items": []}
    yield {"kind": "clean", "id": "toolCaches", "size": size_of(TOOL_CACHES), "items": []}
    yield {"kind": "clean", "id": "thumbnails", "size": size_of(THUMBNAILS), "items": []}
    match = re.search(r"take up ([\d.]+\s*\w+)", run("journalctl", "--disk-usage"))
    journal = parse_size(match[1]) if match else 0
    yield {"kind": "clean", "id": "logs", "size": max(0, journal - KEPT_JOURNAL), "items": []}
    yield {"kind": "clean", "id": "coredumps", "size": size_of([COREDUMPS]), "items": []}
    names = orphans()
    size = 0
    if names:
        for line in run("pacman", "-Qi", *names).splitlines():
            if line.startswith("Installed Size"):
                size += parse_size(line.split(":", 1)[1])
    yield {"kind": "clean", "id": "orphans", "size": size, "items": names}
    yield {"kind": "clean", "id": "flatpaks", "size": 0, "items": unused_flatpaks()}


def scan():
    def emit(entry):
        print(json.dumps(entry), flush=True)

    for disk in disks():
        emit(disk)
    try:
        for line in LAST_SCAN.read_text().splitlines():
            print(line, flush=True)
    except OSError:
        pass
    emit({"kind": "cached"})
    fresh = []
    for source in (usage, cleanups):
        for entry in source():
            fresh.append(entry)
            emit(entry)
    LAST_SCAN.parent.mkdir(parents=True, exist_ok=True)
    tmp = LAST_SCAN.with_suffix(".tmp")
    tmp.write_text("".join(json.dumps(entry) + "\n" for entry in fresh))
    tmp.replace(LAST_SCAN)


def inside_home(path):
    resolved = Path(path).absolute()
    return resolved if resolved.is_relative_to(HOME) and ".." not in resolved.parts else None


def list_folder(path):
    folder = inside_home(path)
    if folder is None or not folder.is_dir():
        sys.exit("That folder is not inside Home.")
    sizes = du(folder, depth=1, every_file=True)
    entries = []
    for entry, size in sizes.items():
        item = Path(entry)
        if item == folder:
            continue
        entries.append({"name": item.name, "path": entry, "size": size,
                        "folder": item.is_dir() and not item.is_symlink(), "protected": is_protected(item)})
    entries.sort(key=lambda entry: entry["size"], reverse=True)
    print(json.dumps({"path": str(folder), "size": sizes.get(str(folder), 0), "entries": entries}))


def is_protected(path):
    """Home's hidden folders hold what apps need to run, and Home's own folders are expected to be there."""
    return path == HOME or (path.parent == HOME and (path.name.startswith(".") or path in user_folders().values()))


def large():
    output = run("find", str(HOME), "-xdev", "(", "-name", ".*", "-prune", ")", "-o", "-type", "f",
                 "-size", f"+{LARGEST_FILE_MIN}c", "-printf", "%b\t%p\n")
    files = []
    for line in output.splitlines():
        blocks, _, path = line.partition("\t")
        if blocks.isdigit():
            files.append({"name": os.path.basename(path), "path": path, "size": int(blocks) * 512,
                          "folder": False, "protected": False})
    files.sort(key=lambda entry: entry["size"], reverse=True)
    print(json.dumps({"entries": files[:LARGEST_FILES]}))


def remove_all(paths):
    for path in paths:
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path, ignore_errors=True)


def exec_or_fail(*command):
    if not shutil.which(command[1] if command[0] == "pkexec" else command[0]):
        sys.exit(f"{command[1] if command[0] == 'pkexec' else command[0]} is not installed.")
    os.execvp(command[0], command)


def empty_trash():
    remove_all([TRASH / "files", TRASH / "info"])
    (TRASH / "directorysizes").unlink(missing_ok=True)
    for folder in ("files", "info"):
        (TRASH / folder).mkdir(parents=True, exist_ok=True)


def clean(action):
    if action == "trash":
        empty_trash()
    elif action == "packages":
        exec_or_fail("pkexec", "paccache", "-rk1")
    elif action == "toolCaches":
        remove_all(TOOL_CACHES)
    elif action == "thumbnails":
        remove_all(THUMBNAILS)
    elif action == "logs":
        exec_or_fail("pkexec", "journalctl", f"--vacuum-size={KEPT_JOURNAL}")
    elif action == "coredumps":
        exec_or_fail("pkexec", "find", str(COREDUMPS), "-type", "f", "-delete")
    elif action == "orphans":
        names = orphans()
        if names:
            exec_or_fail("pkexec", "pacman", "-Rns", "--noconfirm", "--", *names)
    elif action == "flatpaks":
        exec_or_fail("flatpak", "uninstall", "--unused", "--noninteractive")
    else:
        sys.exit(f"Unknown cleanup: {action}")


def trash(path):
    item = inside_home(path)
    if item is None or not os.path.lexists(item) or is_protected(item):
        sys.exit("That can't be moved to the Trash from here.")
    exec_or_fail("gio", "trash", "--", str(item))


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "scan":
        scan()
    elif command == "large":
        large()
    elif command == "list" and len(sys.argv) == 3:
        list_folder(sys.argv[2])
    elif command == "clean" and len(sys.argv) == 3:
        clean(sys.argv[2])
    elif command == "trash" and len(sys.argv) == 3:
        trash(sys.argv[2])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
