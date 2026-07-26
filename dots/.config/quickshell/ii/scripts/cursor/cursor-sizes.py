#!/usr/bin/env python3
"""Print the sizes a cursor theme can actually draw, largest last, one per line.

An XCursor theme is a set of bitmaps, so it can only be drawn at the sizes it
ships; asking for one it doesn't have gets the nearest it does. Themes vary
enormously — some carry a dozen sizes from 16 to 96, others four — so a fixed
list of sizes in the settings offers choices that quietly do nothing.

Prints nothing when the theme can't be found or isn't in this format, which
includes the scalable ones; the caller should treat that as "no restriction".
"""

import os
import struct
import sys

# An XCursor file is a header, then a table of chunks. Image chunks carry the
# nominal size they were drawn for in the subtype field, which is what the
# loader matches against when something asks for a size.
IMAGE_CHUNK = 0xFFFD0002
# Names to try, in order — every theme defines at least one of them, and they
# all carry the same set of sizes within a theme.
PROBES = ("default", "left_ptr", "arrow", "top_left_arrow")


def theme_dirs():
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    yield os.path.expanduser("~/.icons")
    yield os.path.join(data_home, "icons")
    for base in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":"):
        if base:
            yield os.path.join(base, "icons")


def sizes_in(path):
    try:
        with open(path, "rb") as handle:
            data = handle.read()
    except OSError:
        return set()
    if data[:4] != b"Xcur" or len(data) < 16:
        return set()
    try:
        _, header, _version, count = struct.unpack_from("<4sIII", data, 0)
    except struct.error:
        return set()
    found = set()
    for index in range(count):
        try:
            chunk, subtype, _position = struct.unpack_from("<III", data, header + index * 12)
        except struct.error:
            break
        if chunk == IMAGE_CHUNK and subtype > 0:
            found.add(subtype)
    return found


def main():
    if len(sys.argv) < 2 or not sys.argv[1].strip():
        return 0
    theme = os.path.basename(sys.argv[1].strip())
    for root in theme_dirs():
        cursors = os.path.join(root, theme, "cursors")
        if not os.path.isdir(cursors):
            continue
        for name in PROBES:
            found = sizes_in(os.path.join(cursors, name))
            if found:
                print("\n".join(str(size) for size in sorted(found)))
                return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
