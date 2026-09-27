#!/usr/bin/env python3
"""Settings > Layouts choices, carried over when an update replaces the files.

Settings > Layouts keeps two of its choices in files every release ships: the
default layout, as `layout = "..."` in the general table of
hyprland/general.lua, and the switch to per-workspace layouts, as an active
tryRequire("workspaces") line in hyprland.lua. An update that replaces either
file puts the stock choice back.

  layouts.py carry CARRY_DIR LIVE_GENERAL NEW_GENERAL LIVE_HYPRLAND NEW_HYPRLAND

CARRY_DIR is the updater's folder of copies: yours/ holds the user's files as
they were just before the update replaced them, and was/N/ what each earlier
release shipped. A choice that differs from every earlier release's is the
user's own and goes back into the live file, unless the live file no longer
holds what the new release shipped, which means something changed it since
and that is the newer choice. Prints one line per choice it put back.
"""

import glob
import os
import re
import sys

LAYOUT = re.compile(r'(^[ \t]*general\s*=\s*\{[^}]*?layout\s*=\s*")([^"]+)(")', re.S | re.M)
ACTIVE_WORKSPACES = re.compile(r'(?m)^\s*tryRequire\("workspaces"\)')
COMMENTED_WORKSPACES = re.compile(r'(?m)^(\s*)--\s*(tryRequire\("workspaces"\))')
UNCOMMENTED_WORKSPACES = re.compile(r'(?m)^(\s*)(tryRequire\("workspaces"\))')


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def layout_of(text):
    m = LAYOUT.search(text) if text is not None else None
    return m.group(2) if m else None


def per_workspace_of(text):
    if text is None:
        return None
    # A file with the line in neither form says nothing either way.
    if ACTIVE_WORKSPACES.search(text):
        return True
    if COMMENTED_WORKSPACES.search(text):
        return False
    return None


def write(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    try:
        os.chmod(tmp, os.stat(path).st_mode & 0o7777)
    except OSError:
        pass
    os.replace(tmp, path)


def carry(carry_dir, live_general, new_general, live_hyprland, new_hyprland):
    kept = []
    was = sorted(glob.glob(os.path.join(carry_dir, "was", "*")))

    mine = layout_of(read(os.path.join(carry_dir, "yours", "general.lua")))
    shipped = [layout_of(read(os.path.join(d, "general.lua"))) for d in was]
    shipped = [v for v in shipped if v is not None]
    live_text = read(live_general)
    if mine and shipped and mine not in shipped and live_text is not None:
        now, new = layout_of(live_text), layout_of(read(new_general))
        if now is not None and now != mine and now == new:
            write(live_general, LAYOUT.sub(lambda m: m.group(1) + mine + m.group(3), live_text, count=1))
            kept.append("default layout")

    mine = per_workspace_of(read(os.path.join(carry_dir, "yours", "hyprland.lua")))
    shipped = [per_workspace_of(read(os.path.join(d, "hyprland.lua"))) for d in was]
    shipped = [v for v in shipped if v is not None]
    live_text = read(live_hyprland)
    if mine is not None and shipped and mine not in shipped and live_text is not None:
        now, new = per_workspace_of(live_text), per_workspace_of(read(new_hyprland))
        if now is not None and now != mine and now == new:
            if mine:
                text = COMMENTED_WORKSPACES.sub(r"\1\2", live_text, count=1)
            else:
                text = UNCOMMENTED_WORKSPACES.sub(r"\1-- \2", live_text, count=1)
            write(live_hyprland, text)
            kept.append("per-workspace layouts")
    return kept


def main():
    if len(sys.argv) != 7 or sys.argv[1] != "carry":
        print(__doc__, file=sys.stderr)
        return 2
    for label in carry(*sys.argv[2:]):
        print(label)
    return 0


if __name__ == "__main__":
    sys.exit(main())
