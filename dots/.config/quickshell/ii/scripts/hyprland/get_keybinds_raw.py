#!/usr/bin/env python3
"""
Lossless Hyprland keybind parser for the settings app's keybinds editor.

Unlike `get_keybinds.py` (which filters out `[hidden]` lines and ignores
non-bind lines for the cheatsheet), this script emits one JSON object per
`bind*` line, preserving line numbers, comments, and the full bind-type
prefix (`bind`, `binde`, `bindid`, `bindle`, etc.) so the editor can
round-trip every line in the user's config.

Output shape:
    {
        "path": "<absolute path>",
        "exists": true,
        "submapsDefined": [{"name": "...", "lineNumber": N}, ...],
        "binds": [
            {
                "lineNumber": N,            # 1-indexed
                "indent": "<leading ws>",
                "bindType": "bind",          # full prefix verbatim
                "mods": ["SUPER", "SHIFT"],
                "key": "Return",
                "dispatcher": "exec",
                "args": "kitty",
                "comment": "Open terminal",
                "isHidden": false,
                "submap": "global",
                "raw": "<original line>"
            },
            ...
        ],
        "unbinds": [
            {"lineNumber": N, "indent": "...", "mods": [...], "key": "...", "raw": "..."}
        ]
    }
"""

import argparse
import json
import os
import re
import sys

BIND_RE = re.compile(r"^([ \t]*)(bind[a-z]*)\s*=\s*(.*)$")
UNBIND_RE = re.compile(r"^([ \t]*)unbind\s*=\s*(.*)$")
SUBMAP_RE = re.compile(r"^[ \t]*submap\s*=\s*(.*)$")
HIDDEN_TAG = "[hidden]"
MOD_SEPARATORS = ("+", " ")


def parse_mods(mods_str: str) -> list[str]:
    """Split a Hyprland mod string into a clean list.

    Accepts both ``SUPER + SHIFT`` and ``SUPER+SHIFT`` and ``SUPER SHIFT``.
    Empty mod strings (e.g. ``,Escape``) return an empty list.
    """
    s = mods_str.strip()
    if not s:
        return []
    parts = re.split(r"[+\s]+", s)
    return [p for p in parts if p]


def parse_bind_args(rest: str) -> tuple[list[str], str, str, str, str, bool]:
    """Parse the ``= ...`` portion of a bind line.

    Returns (mods, key, dispatcher, args, comment, isHidden).

    Hyprland bind syntax: ``MODS, KEY, DISPATCHER, ARGS  # comment``.
    The arg field may itself contain commas (``exec, foo, bar``); only the
    first three commas are structural separators.
    """
    body, _, comment_part = rest.partition("#")
    comment = comment_part.strip()
    is_hidden = comment.startswith(HIDDEN_TAG)
    if is_hidden:
        comment = comment[len(HIDDEN_TAG):].strip()

    fields = body.split(",", 3)
    fields = [f.strip() for f in fields]
    while len(fields) < 4:
        fields.append("")

    mods_str, key, dispatcher, args = fields
    args = args.rstrip(",").strip()
    return parse_mods(mods_str), key, dispatcher, args, comment, is_hidden


def parse_unbind_args(rest: str) -> tuple[list[str], str]:
    body, _, _ = rest.partition("#")
    fields = [f.strip() for f in body.split(",", 1)]
    while len(fields) < 2:
        fields.append("")
    return parse_mods(fields[0]), fields[1]


def parse_file(path: str) -> dict:
    expanded = os.path.expanduser(os.path.expandvars(path))
    out = {
        "path": expanded,
        "exists": os.path.isfile(expanded),
        "submapsDefined": [],
        "binds": [],
        "unbinds": [],
    }
    if not out["exists"]:
        return out

    try:
        with open(expanded, "r") as f:
            lines = f.read().splitlines()
    except OSError:
        out["exists"] = False
        return out

    current_submap = "global"
    for i, raw in enumerate(lines):
        line_no = i + 1

        sm = SUBMAP_RE.match(raw)
        if sm:
            name = sm.group(1).strip()
            current_submap = name if name else "global"
            if name and name != "global":
                out["submapsDefined"].append({"name": name, "lineNumber": line_no})
            continue

        m = BIND_RE.match(raw)
        if m:
            indent, bind_type, rest = m.group(1), m.group(2), m.group(3)
            mods, key, dispatcher, args, comment, is_hidden = parse_bind_args(rest)
            out["binds"].append({
                "lineNumber": line_no,
                "indent": indent,
                "bindType": bind_type,
                "mods": mods,
                "key": key,
                "dispatcher": dispatcher,
                "args": args,
                "comment": comment,
                "isHidden": is_hidden,
                "submap": current_submap,
                "raw": raw,
            })
            continue

        u = UNBIND_RE.match(raw)
        if u:
            indent, rest = u.group(1), u.group(2)
            mods, key = parse_unbind_args(rest)
            out["unbinds"].append({
                "lineNumber": line_no,
                "indent": indent,
                "mods": mods,
                "key": key,
                "raw": raw,
            })

    return out


def main():
    parser = argparse.ArgumentParser(description="Lossless Hyprland keybind parser")
    parser.add_argument("--path", required=True, help="Path to a Hyprland config file (no sourcing)")
    args = parser.parse_args()

    result = parse_file(args.path)
    json.dump(result, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
