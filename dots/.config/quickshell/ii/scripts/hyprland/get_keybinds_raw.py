#!/usr/bin/env python3
"""
Lossless Hyprland keybind parser for the settings app's keybinds editor.

Parses the Lua-config format introduced in Hyprland 0.55:
    hl.bind("MODS + KEY", DISPATCHER_EXPR, {OPTIONS})
    hl.unbind("MODS + KEY")
    hl.define_submap("name", function() ... end)

Output shape (matches the legacy hyprlang parser as closely as possible):
    {
        "path": "<absolute path>",
        "exists": true,
        "submapsDefined": [{"name": "...", "lineNumber": N}, ...],
        "binds": [
            {
                "lineNumber": N,            # 1-indexed
                "indent": "<leading ws>",
                "bindType": "bind",          # synthesized from opts table
                "mods": ["SUPER", "SHIFT"],
                "key": "Return",
                "dispatcher": "exec",        # mapped back from hl.dsp.* form
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

Best-effort dispatcher extraction. For dispatchers not in the inverse map,
`dispatcher` is set to the raw expression and `args` is left empty so the
UI can still display and edit-as-raw.
"""

import argparse
import json
import os
import re
import sys

HL_BIND_RE = re.compile(r'^([ \t]*)hl\.bind\(\s*"([^"]+)"\s*,\s*(.+?)\)\s*(?:--\s*(.*))?$')
HL_UNBIND_RE = re.compile(r'^([ \t]*)hl\.unbind\(\s*"([^"]+)"\s*\)\s*(?:--\s*(.*))?$')
HL_DEFINE_SUBMAP_RE = re.compile(r'^[ \t]*hl\.define_submap\(\s*"([^"]+)"\s*,')
HIDDEN_TAG = "[hidden]"


def parse_lua_key(key_str: str) -> tuple[list[str], str]:
    """Split a Lua-form key string like "SUPER + SHIFT + Q" into (mods, key)."""
    parts = [p.strip() for p in key_str.split("+") if p.strip()]
    if not parts:
        return [], ""
    return parts[:-1], parts[-1]


# Inverse of the dispatcher map in KeybindsConfig.qml's _editFile.
# Pattern → (hyprlang dispatcher name, capture-group index for args, or None)
INVERSE_DSP = [
    (re.compile(r'^hl\.dsp\.exec_cmd\("(.*)"\)$', re.S),                        ("exec", 1)),
    (re.compile(r'^hl\.dsp\.exit\(\)$'),                                          ("exit", None)),
    (re.compile(r'^hl\.dsp\.window\.close\(\)$'),                                 ("killactive", None)),
    (re.compile(r'^hl\.dsp\.window\.pin\(\)$'),                                   ("pin", None)),
    (re.compile(r'^hl\.dsp\.window\.pseudo\(\)$'),                                ("pseudo", None)),
    (re.compile(r'^hl\.dsp\.window\.center\(\)$'),                                ("centerwindow", None)),
    (re.compile(r'^hl\.dsp\.window\.float\(\{action\s*=\s*"toggle"\}\)$'),        ("togglefloating", None)),
    (re.compile(r'^hl\.dsp\.window\.fullscreen\(\{mode\s*=\s*"maximized"\}\)$'),  ("fullscreen", "1")),
    (re.compile(r'^hl\.dsp\.window\.fullscreen\(\{mode\s*=\s*"fullscreen"\}\)$'), ("fullscreen", "0")),
    (re.compile(r'^hl\.dsp\.window\.move\(\{direction\s*=\s*"(.+?)"\}\)$'),       ("movewindow", 1)),
    (re.compile(r'^hl\.dsp\.window\.move\(\{workspace\s*=\s*"(.+?)",\s*follow\s*=\s*false\}\)$'), ("movetoworkspacesilent", 1)),
    (re.compile(r'^hl\.dsp\.window\.move\(\{workspace\s*=\s*"(.+?)"\}\)$'),       ("movetoworkspace", 1)),
    (re.compile(r'^hl\.dsp\.window\.resize\(\)$'),                                ("resizewindow", None)),
    (re.compile(r'^hl\.dsp\.window\.swap\(\{direction\s*=\s*"(.+?)"\}\)$'),       ("swapwindow", 1)),
    (re.compile(r'^hl\.dsp\.window\.bring_to_top\(\)$'),                          ("bringactivetotop", None)),
    (re.compile(r'^hl\.dsp\.window\.alter_zorder\("(.+?)"\)$'),                   ("alterzorder", 1)),
    (re.compile(r'^hl\.dsp\.focus\(\{direction\s*=\s*"(.+?)"\}\)$'),              ("movefocus", 1)),
    (re.compile(r'^hl\.dsp\.focus\(\{workspace\s*=\s*"(.+?)"\}\)$'),              ("workspace", 1)),
    (re.compile(r'^hl\.dsp\.focus\(\{window\s*=\s*"(.+?)"\}\)$'),                 ("focuswindow", 1)),
    (re.compile(r'^hl\.dsp\.focus\(\{monitor\s*=\s*"(.+?)"\}\)$'),                ("focusmonitor", 1)),
    (re.compile(r'^hl\.dsp\.focus\(\{last\s*=\s*true\}\)$'),                      ("focuscurrentorlast", None)),
    (re.compile(r'^hl\.dsp\.focus\(\{urgent_or_last\s*=\s*true\}\)$'),            ("focusurgentorlast", None)),
    (re.compile(r'^hl\.dsp\.workspace\.toggle_special\("(.*)"\)$'),               ("togglespecialworkspace", 1)),
    (re.compile(r'^hl\.dsp\.layout\("(.+?)"\)$'),                                 ("layoutmsg", 1)),
    (re.compile(r'^hl\.dsp\.submap\("(.+?)"\)$'),                                 ("submap", 1)),
    (re.compile(r'^hl\.dsp\.global\("(.+?)"\)$'),                                 ("global", 1)),
    (re.compile(r'^hl\.dsp\.event\("(.+?)"\)$'),                                  ("event", 1)),
    (re.compile(r'^hl\.dsp\.dpms\(\{action\s*=\s*"(.+?)"\}\)$'),                  ("dpms", 1)),
    (re.compile(r'^hl\.dsp\.pass\(\{window\s*=\s*"(.+?)"\}\)$'),                  ("pass", 1)),
    (re.compile(r'^hl\.dsp\.group\.toggle\(\)$'),                                 ("togglegroup", None)),
    (re.compile(r'^hl\.dsp\.group\.next\(\)$'),                                   ("changegroupactive", "f")),
    (re.compile(r'^hl\.dsp\.group\.prev\(\)$'),                                   ("changegroupactive", "b")),
    (re.compile(r'^hl\.dsp\.group\.move_window\(\{forward\s*=\s*true\}\)$'),      ("moveoutofgroup", None)),
]


def map_dispatcher_back(expr: str) -> tuple[str, str]:
    """Reverse the dispatcher mapping. Returns (dispatcher, args)."""
    e = expr.strip().rstrip(",")
    for pat, info in INVERSE_DSP:
        m = pat.match(e)
        if m:
            disp, arg_spec = info
            if arg_spec is None:
                return disp, ""
            if isinstance(arg_spec, int):
                return disp, m.group(arg_spec)
            return disp, arg_spec
    # Unknown — pass the whole expression through so the editor can show it.
    return e, ""


def split_top_level(s: str) -> list[str]:
    """Split a comma-separated string respecting nested parens/braces/strings."""
    parts: list[str] = []
    depth_paren = 0
    depth_brace = 0
    in_str = False
    str_char = ""
    buf: list[str] = []
    i = 0
    while i < len(s):
        c = s[i]
        if in_str:
            buf.append(c)
            if c == "\\" and i + 1 < len(s):
                buf.append(s[i + 1])
                i += 2
                continue
            if c == str_char:
                in_str = False
        else:
            if c in ('"', "'"):
                in_str = True
                str_char = c
                buf.append(c)
            elif c == "(":
                depth_paren += 1
                buf.append(c)
            elif c == ")":
                depth_paren -= 1
                buf.append(c)
            elif c == "{":
                depth_brace += 1
                buf.append(c)
            elif c == "}":
                depth_brace -= 1
                buf.append(c)
            elif c == "," and depth_paren == 0 and depth_brace == 0:
                parts.append("".join(buf).strip())
                buf = []
            else:
                buf.append(c)
        i += 1
    if buf:
        parts.append("".join(buf).strip())
    return parts


def parse_opts(opts_str: str) -> dict:
    """Parse a Lua options table body like `{description = "x", locked = true}`."""
    s = opts_str.strip()
    if s.startswith("{"):
        s = s[1:]
    if s.endswith("}"):
        s = s[:-1]
    out: dict = {}
    for entry in split_top_level(s):
        e = entry.strip().rstrip(",").strip()
        if not e:
            continue
        m = re.match(r'^(\w+)\s*=\s*(.+)$', e, re.S)
        if not m:
            continue
        k, v = m.group(1), m.group(2).strip()
        if v.startswith('"') and v.endswith('"'):
            out[k] = v[1:-1]
        elif v == "true":
            out[k] = True
        elif v == "false":
            out[k] = False
        else:
            out[k] = v
    return out


def bind_type_for_opts(opts: dict) -> str:
    """Synthesise the hyprlang bind-type prefix from the options table."""
    if opts.get("mouse"):
        return "bindm"
    flags = []
    if opts.get("locked"):
        flags.append("l")
    if opts.get("repeating"):
        flags.append("e")
    if opts.get("description"):
        flags.append("d")
    if opts.get("non_consuming"):
        flags.append("n")
    if opts.get("transparent"):
        flags.append("t")
    if opts.get("ignore_mods"):
        flags.append("i")
    if opts.get("release"):
        flags.append("r")
    if opts.get("long_press"):
        flags.append("o")
    return "bind" + "".join(flags)


def parse_bind_line(rest_after_open_paren: str) -> tuple[str, str, str]:
    """Split the hl.bind(...) inner CSV into (key_str, dispatcher_expr, opts_or_empty)."""
    parts = split_top_level(rest_after_open_paren)
    if not parts:
        return "", "", ""
    key_str = parts[0].strip()
    if key_str.startswith('"') and key_str.endswith('"'):
        key_str = key_str[1:-1]
    dispatcher = parts[1].strip() if len(parts) > 1 else ""
    opts_str = parts[2].strip() if len(parts) > 2 else ""
    return key_str, dispatcher, opts_str


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

    submap_stack = ["global"]
    pending_submap_end = []  # depth counter; tracks nesting

    for i, raw in enumerate(lines):
        line_no = i + 1
        stripped = raw.strip()

        sm = HL_DEFINE_SUBMAP_RE.match(raw)
        if sm:
            name = sm.group(1)
            submap_stack.append(name)
            out["submapsDefined"].append({"name": name, "lineNumber": line_no})
            continue

        # Crude block end detection: a line that's just `end)` closes
        # the current submap. Good enough for our auto-generated content.
        if stripped == "end)" and len(submap_stack) > 1:
            submap_stack.pop()
            continue

        current_submap = submap_stack[-1]

        m = HL_BIND_RE.match(raw)
        if m:
            indent = m.group(1)
            key_str = m.group(2)
            tail = m.group(3)
            comment = (m.group(4) or "").strip()
            is_hidden = comment.startswith(HIDDEN_TAG)
            if is_hidden:
                comment = comment[len(HIDDEN_TAG):].strip()
            # Reconstruct the inner CSV from "key", dispatcher[, opts]
            inner = '"' + key_str + '", ' + tail
            _, dispatcher_expr, opts_str = parse_bind_line(inner)
            opts = parse_opts(opts_str) if opts_str else {}
            mods, key = parse_lua_key(key_str)
            dispatcher, args = map_dispatcher_back(dispatcher_expr)
            if opts.get("description") and not comment:
                comment = str(opts["description"])
            out["binds"].append({
                "lineNumber": line_no,
                "indent": indent,
                "bindType": bind_type_for_opts(opts),
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

        u = HL_UNBIND_RE.match(raw)
        if u:
            indent = u.group(1)
            key_str = u.group(2)
            mods, key = parse_lua_key(key_str)
            out["unbinds"].append({
                "lineNumber": line_no,
                "indent": indent,
                "mods": mods,
                "key": key,
                "raw": raw,
            })

    return out


def main():
    parser = argparse.ArgumentParser(description="Lossless Hyprland keybind parser (Lua syntax)")
    parser.add_argument("--path", required=True, help="Path to a Hyprland Lua keybind file (no requires followed)")
    args = parser.parse_args()

    result = parse_file(args.path)
    json.dump(result, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
