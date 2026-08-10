#!/usr/bin/env python3
"""Read and write the decoration settings held in hypr/hyprland/general.lua.

The only code that knows how those settings are spelled in Lua. The settings
page, the snapshot a saved theme keeps, and the restore an apply performs all
go through here, so none of them can drift from the others about what a key
means or where it lives.

    decorations.py read  <general.lua> [--flag-dir DIR]
    decorations.py write <general.lua> <values.json> [--flag-dir DIR]
    decorations.py set   <general.lua> key=value ... [--flag-dir DIR]
    decorations.py push  <values.json>

Where a setting lives is derived from its hyprctl keyword rather than stated
twice: decoration:blur:size is the field `size`, inside `blur`, inside
`decoration`. Blocks are found by matching braces rather than by scanning to
the next `}` -- general holds col and snap, decoration holds blur and shadow,
and shadow holds an offset pair, so a field can sit after a nested block has
closed and a scan would stop short of it.

write() only touches keys the values file actually carries. A theme saved
before a setting existed says nothing about it, and silence means leave it
alone: defaults belong to the settings page, not to a restore, or applying an
older theme would quietly reset whatever the machine had.
"""

import json
import os
import re
import sys

SCHEMA = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                      "decorations-schema.json")


def load_schema(path=SCHEMA):
    with open(path) as fh:
        return json.load(fh)


def lua_location(row):
    """('decoration:blur:size') -> (['decoration', 'blur'], 'size')"""
    parts = row["hypr"].split(":")
    return parts[:-1], parts[-1]


def _find_block(text, name, start, end):
    """Span inside `name = {` ... matching `}`, searched within [start, end)."""
    opener = re.compile(r"^[ \t]*" + re.escape(name) + r"[ \t]*=[ \t]*\{", re.M)
    m = opener.search(text, start, end)
    if not m:
        return None
    depth, i = 0, m.end() - 1
    while i < end:
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return (m.end(), i)
        i += 1
    return None


def _find_field(text, path, field):
    """(value_start, value_end) for `field = value` at the block path's own level."""
    start, end = 0, len(text)
    for name in path:
        span = _find_block(text, name, start, end)
        if span is None:
            return None
        start, end = span
    pattern = re.compile(r"^[ \t]*" + re.escape(field) + r"[ \t]*=[ \t]*(\"(?:[^\"\\\n]|\\.)*\"|[^,\n}]+)")
    pos, depth = start, 0
    while pos < end:
        nl = text.find("\n", pos)
        if nl < 0 or nl > end:
            nl = end
        line = text[pos:nl]
        # Checked before the depth update, so a field on the same line as the
        # block it belongs to still counts as that block's own.
        if depth == 0:
            m = pattern.match(line)
            if m:
                return (pos + m.start(1), pos + m.end(1))
        depth += line.count("{") - line.count("}")
        pos = nl + 1
    return None


def _insert_field(text, path, field, rendered):
    """Add `field = value,` to the end of the block, keeping its indentation.

    Hyprland defaults a setting that the config never mentions, so there is
    nothing to patch until someone changes it. Shipping the line in the default
    config would only help fresh installs — general.lua belongs to the user and
    is not rewritten on update — so the line is added on first use instead.
    """
    start, end = 0, len(text)
    for name in path:
        span = _find_block(text, name, start, end)
        if span is None:
            return None
        start, end = span

    indent, last_end, depth, pos = None, None, 0, start
    while pos < end:
        nl = text.find("\n", pos)
        if nl < 0 or nl > end:
            nl = end
        line = text[pos:nl]
        stripped = line.strip()
        if depth == 0 and stripped and not stripped.startswith("--"):
            if indent is None:
                indent = line[:len(line) - len(line.lstrip())]
            last_end = pos + len(line.rstrip())
        depth += line.count("{") - line.count("}")
        pos = nl + 1

    if indent is None:
        indent = "    "
    if last_end is None:
        return text[:start] + "\n" + indent + field + " = " + rendered + ",\n" + text[start:]
    # The block's final entry may have no trailing comma; it needs one now that
    # something follows it.
    head, tail = text[:last_end], text[last_end:]
    if not head.rstrip().endswith(","):
        head += ","
    return head + "\n" + indent + field + " = " + rendered + tail


def _parse(raw, kind):
    raw = raw.strip().rstrip(",").strip()
    if kind == "bool":
        return raw.lower() in ("true", "1", "yes", "on")
    try:
        return int(raw) if kind == "int" else float(raw)
    except ValueError:
        return None


def _format(value, kind):
    if kind == "bool":
        return "true" if value else "false"
    if kind == "int":
        return str(int(round(float(value))))
    text = ("%.4f" % float(value)).rstrip("0").rstrip(".")
    return text or "0"


def read(general_path, flag_dir=None, schema=None):
    schema = schema or load_schema()
    try:
        with open(general_path) as fh:
            text = fh.read()
    except FileNotFoundError:
        text = ""
    out = {}
    for row in schema["keys"]:
        if row.get("mechanism") == "flagfile":
            if flag_dir:
                fp = os.path.join(flag_dir, row["path"])
                out[row["key"]] = (open(fp).read().strip() != "0") \
                    if os.path.exists(fp) else True
            continue
        path, field = lua_location(row)
        span = _find_field(text, path, field)
        if span is None:
            continue
        value = _parse(text[span[0]:span[1]], row["type"])
        if value is not None:
            out[row["key"]] = value
    # Emitted alongside the real values so a copy of the shell that predates
    # this file still finds the booleans it knows how to restore.
    for row in schema["keys"]:
        legacy = row.get("legacy")
        if legacy and row["key"] in out and legacy["bool"] not in out:
            out[legacy["bool"]] = out[row["key"]] != legacy["off"]
    return out


def resolve(values, row):
    """What a theme is asking for, or None to leave the setting alone."""
    if row["key"] in values:
        return values[row["key"]]
    legacy = row.get("legacy")
    if legacy and legacy["bool"] in values:
        return legacy["on"] if values[legacy["bool"]] else legacy["off"]
    return None


def write(general_path, values, flag_dir=None, schema=None):
    schema = schema or load_schema()
    try:
        with open(general_path) as fh:
            text = fh.read()
    except FileNotFoundError:
        return 0
    written = 0
    for row in schema["keys"]:
        value = resolve(values, row)
        if value is None:
            continue
        if row.get("mechanism") == "flagfile":
            if flag_dir:
                try:
                    os.makedirs(flag_dir, exist_ok=True)
                    with open(os.path.join(flag_dir, row["path"]), "w") as fh:
                        fh.write("1" if value else "0")
                    written += 1
                except OSError:
                    pass
            continue
        path, field = lua_location(row)
        rendered = _format(value, row["type"])
        span = _find_field(text, path, field)
        if span is None:
            grown = _insert_field(text, path, field, rendered)
            if grown is None:
                continue
            text = grown
        else:
            text = text[:span[0]] + rendered + text[span[1]:]
        written += 1
    # Beside the target and renamed over it: general.lua is sourced by the
    # Hyprland config and a reload can be reading it at any moment.
    tmp = general_path + ".tmp"
    with open(tmp, "w") as fh:
        fh.write(text)
    try:
        os.chmod(tmp, os.stat(general_path).st_mode & 0o7777)
    except OSError:
        pass
    os.replace(tmp, general_path)
    return written


def push(values, schema=None):
    """Send the settings to the running compositor.

    `hyprctl keyword` is Legacy-only in 0.55 ("can't work with non-legacy
    parsers. Use eval."), so this goes through hl.config(). The first part of
    the keyword is the section and the rest becomes a bracket-string key, which
    is what carries a nested block: decoration:blur:size -> ["blur.size"].
    One eval for the whole set, since each is a round trip.
    """
    import subprocess
    schema = schema or load_schema()
    sections = {}
    for row in schema["keys"]:
        if not row.get("hypr"):
            continue
        value = resolve(values, row)
        if value is None:
            continue
        path, field = lua_location(row)
        leaf = ".".join(path[1:] + [field])
        lua = "true" if value is True else "false" if value is False else str(value)
        sections.setdefault(path[0], []).append('["' + leaf + '"] = ' + lua)
    if not sections:
        return
    body = ", ".join(s + " = { " + ", ".join(v) + " }" for s, v in sections.items())
    subprocess.run(["hyprctl", "eval", "hl.config({ " + body + " })"],
                   capture_output=True)


def coerce(schema, pairs):
    """['rounding=12'] -> {'rounding': 12}, typed by the schema."""
    kinds = {row["key"]: row["type"] for row in schema["keys"]}
    out = {}
    for pair in pairs:
        if "=" not in pair:
            continue
        key, raw = pair.split("=", 1)
        kind = kinds.get(key)
        if kind is None:
            continue
        parsed = _parse(raw, kind)
        if parsed is not None:
            out[key] = parsed
    return out


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    verb, general = argv[1], argv[2]
    rest = argv[3:]
    flag_dir = None
    if "--flag-dir" in rest:
        i = rest.index("--flag-dir")
        flag_dir = rest[i + 1] if i + 1 < len(rest) else None
        rest = rest[:i] + rest[i + 2:]
    if verb == "read":
        json.dump(read(general, flag_dir), sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return 0
    if verb == "write":
        if not rest:
            print("write needs a values file", file=sys.stderr)
            return 2
        with open(rest[0]) as fh:
            values = json.load(fh)
        write(general, values, flag_dir)
        return 0
    if verb == "set":
        # `set <general.lua> key=value ...` — one call from the settings page
        # covers the file and the running compositor, so neither can be updated
        # without the other.
        schema = load_schema()
        values = coerce(schema, rest)
        if not values:
            return 0
        write(general, values, flag_dir, schema)
        push(values, schema)
        return 0
    if verb == "push":
        # `push <values.json>` — the compositor only; the file is already right.
        try:
            with open(general) as fh:
                values = json.load(fh)
        except Exception:
            return 0
        push(values)
        return 0
    print("unknown verb: " + verb, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
