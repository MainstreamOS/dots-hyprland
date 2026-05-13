#!/usr/bin/env python3
"""Hyprland 0.55 Lua-config cheatsheet parser.

Reads a sectioned keybind file (hyprland/keybinds.lua, custom/keybinds.lua)
and emits a nested {children, keybinds, name} tree the cheatsheet UI walks.

Recognised syntax — same `#+!` heading depth convention as the legacy
hyprlang parser, just inside a Lua-comment prefix:

  -- #!                   column boundary marker  (scope 1)
  -- ##! Name             section header          (scope 2)
  -- ###! Name            subsection              (scope 3)
  -- #/# bind = MODS + KEY,, -- description       documentation-only bind
                                                  (rendered on cheatsheet
                                                  even though no real bind
                                                  exists; lets one line stand
                                                  in for "all four arrows" etc.)
  hl.bind("MODS + KEY", DISPATCHER[, {description = "..."}])   real bind

Only binds with a `description = "..."` show up. `[hidden]` anywhere in the
description drops the bind (legacy convention).
"""

import argparse
import json
import os
import re
from os.path import expanduser, expandvars

# `^\s*--(#+)!` — section marker with `#` count = heading depth/scope.
TITLE_RE = re.compile(r"^\s*--(#+)!\s*(.*)$")
# `-- #/# <rest>` — documentation-only placeholder bind.
CB_RE = re.compile(r"^\s*--#/#\s*(.*)$")
# `hl.bind("...", dispatcher_expr[, {opts}])`. Non-greedy on the dispatcher so
# the trailing `{...}` block is captured separately when present.
HL_BIND_RE = re.compile(
    r'^\s*hl\.(bind\w*)\(\s*"([^"]+)"\s*,\s*'
    r'(.+?)'
    r'(?:\s*,\s*\{(.+?)\})?\s*\)\s*$'
)
DESC_RE = re.compile(r'description\s*=\s*"([^"]*)"')
DSP_NAME_RE = re.compile(r'hl\.dsp\.([\w.]+)\(')
HIDE = "[hidden]"


def parse_lua_combo(combo):
    """`SUPER + Q` -> (['SUPER'], 'Q'). Single-token combo: ([], token)."""
    parts = [p.strip() for p in re.split(r"\s*\+\s*", combo) if p.strip()]
    if not parts:
        return [], ""
    if len(parts) == 1:
        return [], parts[0]
    return parts[:-1], parts[-1]


def parse_hl_bind(line):
    """Parse a real `hl.bind(...)` line. None if no description (= not shown
    on the cheatsheet) or if `[hidden]` appears in it."""
    match = HL_BIND_RE.match(line)
    if not match:
        return None
    combo, dsp_expr, opts = match.group(2), match.group(3), match.group(4) or ""
    desc_match = DESC_RE.search(opts)
    if not desc_match:
        return None
    desc = desc_match.group(1)
    if HIDE in desc:
        return None
    mods, key = parse_lua_combo(combo)
    dsp_name = DSP_NAME_RE.search(dsp_expr)
    dispatcher = dsp_name.group(1) if dsp_name else "function"
    return {
        "mods": mods,
        "key": key,
        "dispatcher": dispatcher,
        "params": "",
        "comment": desc,
    }


def parse_comment_bind(line):
    """Parse `-- #/# bind[X] = ... -- description`. None if `[hidden]` or no
    description."""
    match = CB_RE.match(line)
    if not match:
        return None
    inner = match.group(1).strip()

    # Split off the trailing description (`-- text` or legacy `# text`).
    desc = ""
    if " -- " in inner:
        inner, desc = inner.rsplit(" -- ", 1)
    elif " # " in inner:
        inner, desc = inner.rsplit(" # ", 1)
    desc = desc.strip()
    if not desc or HIDE in desc:
        return None

    # Strip `bind = ` / `binde = ` / etc.
    if "=" not in inner:
        return None
    _, rest = inner.split("=", 1)
    fields = [f.strip() for f in rest.split(",")]
    first = fields[0] if fields else ""

    # Two accepted layouts — depending on whether the converter wrote
    # `MODS + KEY` (Lua-style) or `MODS, KEY` (legacy hyprlang) in the
    # placeholder.
    if "+" in first:
        mods, key = parse_lua_combo(first)
    else:
        mods_str = first
        key = fields[1] if len(fields) > 1 else ""
        mods = (
            [m.strip() for m in re.split(r"\s*\+\s*", mods_str) if m.strip()]
            if mods_str
            else []
        )

    return {
        "mods": mods,
        "key": key,
        "dispatcher": "",
        "params": "",
        "comment": desc,
    }


def _paren_balance(text):
    """Net (open - close) round-paren count, ignoring parens inside strings."""
    depth = 0
    in_string = False
    quote = ""
    i = 0
    while i < len(text):
        c = text[i]
        if in_string:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                in_string = False
        else:
            if c == '"' or c == "'":
                in_string = True
                quote = c
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
        i += 1
    return depth


def parse_file(path):
    expanded = expanduser(expandvars(path))
    if not os.access(expanded, os.R_OK):
        return {"children": [], "keybinds": [], "name": ""}
    with open(expanded) as f:
        lines = f.read().splitlines()

    root = {"children": [], "keybinds": [], "name": ""}
    # Stack of (scope, section_dict) — root sits at scope 0 permanently.
    stack = [(0, root)]

    # Buffer for multi-line `hl.bind(...)` calls. Many binds in the fork
    # span several lines because their dispatcher or comment is long
    # (Utilities screenshot pipelines, scrolloverview's plugin-existence
    # guard, etc.) — we glue them back into a single logical line before
    # running parse_hl_bind on it.
    pending = None  # accumulated "hl.bind(...)" lines so far
    pending_balance = 0

    for line in lines:
        # If we're in the middle of a multi-line bind, keep appending until
        # the parens balance — only THEN re-run regex against the joined
        # text. Section markers and comment-binds can't occur inside an
        # open bind call, so we don't dispatch them here.
        if pending is not None:
            pending += " " + line.strip()
            pending_balance += _paren_balance(line)
            if pending_balance <= 0:
                kb = parse_hl_bind(pending.strip())
                if kb is not None:
                    stack[-1][1]["keybinds"].append(kb)
                pending = None
                pending_balance = 0
            continue

        title = TITLE_RE.match(line)
        if title:
            scope = len(title.group(1))
            name = title.group(2).strip()
            # Pop until parent has strictly smaller scope.
            while len(stack) > 1 and stack[-1][0] >= scope:
                stack.pop()
            parent = stack[-1][1]
            new_section = {"children": [], "keybinds": [], "name": name}
            parent["children"].append(new_section)
            stack.append((scope, new_section))
            continue

        kb = parse_comment_bind(line)
        if kb is not None:
            stack[-1][1]["keybinds"].append(kb)
            continue

        if "hl.bind(" in line:
            bal = _paren_balance(line)
            if bal > 0:
                # Unclosed — buffer and resume on next line.
                pending = line.strip()
                pending_balance = bal
                continue
            kb = parse_hl_bind(line)
            if kb is not None:
                stack[-1][1]["keybinds"].append(kb)

    return root


def main():
    parser = argparse.ArgumentParser(description="Hyprland Lua keybind reader")
    parser.add_argument(
        "--path",
        type=str,
        default="$HOME/.config/hypr/hyprland/keybinds.lua",
        help="path to a Lua keybind file (sourcing isn't supported)",
    )
    args = parser.parse_args()
    print(json.dumps(parse_file(args.path)))


if __name__ == "__main__":
    main()
