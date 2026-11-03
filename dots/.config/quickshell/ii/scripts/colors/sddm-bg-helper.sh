#!/usr/bin/env bash
# Helper for the login screen wallpaper and clock size.
# Intended to be run via pkexec with a matching polkit rule that
# allows passwordless execution.
#
# Usage: sddm-bg-helper.sh <source> <dest>
#        sddm-bg-helper.sh --clear <dest>
#        sddm-bg-helper.sh --clock-size <percent>

set -euo pipefail


if [[ "${1:-}" == --supports-clock-size ]]; then
    exit 0
fi

[[ $# -gt 0 ]] || exit 2

caller="${PKEXEC_UID:-}"
[[ "$caller" =~ ^[0-9]+$ ]] || exit 1
caller_name="$(getent passwd "$caller" | cut -d: -f1)"
[[ -n "$caller_name" ]] || exit 1

if [[ "$1" == --clock-size ]]; then
    [[ $# -eq 2 && "$2" =~ ^[0-9]{2,3}$ ]] || exit 2
    percent=$((10#$2))
    (( percent >= 50 && percent <= 200 )) || exit 2
    theme_dir=/usr/share/sddm/themes/pixie
    [[ -d "$theme_dir" && ! -L "$theme_dir" ]] || exit 1
    # SDDM overlays this file on theme.conf. Keep the choice outside theme
    # sources so updating the theme cannot reset it.
    python3 -I - "$theme_dir/theme.conf.user" "$percent" <<'CLOCK_PY'
import fcntl
import os
from pathlib import Path
import re
import stat
import sys
import tempfile

path = Path(sys.argv[1])
flags = os.O_NOFOLLOW | os.O_CLOEXEC
lock = os.open(str(path) + ".lock", os.O_CREAT | os.O_RDWR | flags, 0o600)
try:
    fcntl.flock(lock, fcntl.LOCK_EX)
    try:
        fd = os.open(path, os.O_RDONLY | flags)
    except FileNotFoundError:
        text = ""
    else:
        with os.fdopen(fd, "r", encoding="utf-8", newline="") as existing:
            if not stat.S_ISREG(os.fstat(existing.fileno()).st_mode):
                raise ValueError("Theme override is not a regular file")
            text = existing.read()
    newline = "\r\n" if "\r\n" in text else "\n"
    section, written, lines = "", False, []
    entry = "clockSize=" + sys.argv[2] + newline
    for line in text.splitlines(keepends=True):
        header = re.match(r"^\s*\[([^\]]+)\]\s*(?:[;#].*)?$", line)
        if header:
            if section == "General" and not written:
                if lines and not lines[-1].endswith("\n"):
                    lines[-1] += newline
                lines.append(entry)
                written = True
            section = header[1]
        if section == "General" and re.match(r"^\s*clockSize\s*=", line):
            if not written:
                lines.append(entry)
                written = True
            continue
        lines.append(line)
    if not written:
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += newline
        if section != "General":
            lines.append("[General]" + newline)
        lines.append(entry)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", newline="", dir=path.parent,
                                         prefix=".clock-size-", delete=False) as output:
            temporary = output.name
            output.write("".join(lines))
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)
finally:
    os.close(lock)
CLOCK_PY
    exit 0
fi

mode=copy
if [[ "$1" == "--clear" ]]; then
    mode=clear
    shift
fi

src="$1"
dest="${2:-$1}"
[[ "$mode" == clear ]] && dest="$1"
dest_dir="$(dirname "$dest")"

# Strict path validation — only allow the exact pixie theme backgrounds dir
[[ "$dest_dir" == "/usr/share/sddm/themes/pixie/assets/backgrounds" ]] || exit 1

# Dropping a moving wallpaper takes the same privilege as placing one, and is
# limited to the videos, so a still can never be removed this way.

if [[ "$mode" == clear ]]; then
    [[ "$dest" == "$dest_dir/$caller_name.mp4" ]] || exit 1
    [[ ! -L "$dest" && ! -L "$dest_dir" ]] || exit 1
    rm -f -- "$dest"
    exit 0
fi

# Source must be a regular file (not a symlink, device, etc.)
[[ -f "$src" && ! -L "$src" ]] || exit 1
# Root copies the file into a world-readable place, so the person asking has
# to be able to read it themselves; otherwise this is a way to publish any
# file on the system by naming it as a wallpaper.
runuser -u "$caller_name" -- test -r "$src" || exit 1

# Destination must not be a symlink (prevent symlink attacks)
[[ ! -L "$dest" ]] || exit 1
[[ ! -L "$dest_dir" ]] || exit 1

# A still to show, or the moving version of the same wallpaper, and named for
# the person asking so one account cannot place another account's background.
[[ "$dest" == "$dest_dir/$caller_name.jpg" || "$dest" == "$dest_dir/$caller_name.mp4" ]] || exit 1

mkdir -p "$dest_dir"
cp -- "$src" "$dest"
chmod 644 "$dest"
