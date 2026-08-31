#!/usr/bin/env python3
"""Read and write the decoration settings held in hypr/hyprland/general.lua.

The only code that knows how those settings are spelled in Lua. The settings
page, the snapshot a saved theme keeps, and the restore an apply performs all
go through here, so none of them can drift from the others about what a key
means or where it lives.

    decorations.py read     <general.lua> [--flag-dir DIR]
    decorations.py defaults <general.lua>
    decorations.py shipped  <general.lua>
    decorations.py write    <general.lua> <values.json> [--flag-dir DIR]
    decorations.py restore  <general.lua> <values.json> [--flag-dir DIR] [--push]
    decorations.py set      <general.lua> key=value ... [--flag-dir DIR]
    decorations.py push     <values.json> [--no-reload]

Where a setting lives is derived from its hyprctl keyword rather than stated
twice: decoration:blur:size is the field `size`, inside `blur`, inside
`decoration`. Blocks are found by matching braces rather than by scanning to
the next `}` -- general holds col and snap, decoration holds blur and shadow,
and shadow holds an offset pair, so a field can sit after a nested block has
closed and a scan would stop short of it.

write() only touches keys the values file actually carries — the settings
page speaks one key at a time. restore() is what a theme apply uses instead:
it fills every key the snapshot doesn't name from the schema defaults, because
a setting absent from a snapshot did not exist when the theme was saved, and
stock is what the machine showed then. Leaving those keys alone instead meant
applying an older theme kept whatever the previous theme had put in the newer
keys, and the older theme no longer looked like its save. Snapshots from
before two keys were renamed still say borders / roundCorners; a false there
restores as its modern spelling's zero, and a true is the default the
completion supplies anyway. restore --push also sends that completed set to
the compositor, so a theme apply spends one interpreter rather than two.
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


def _find_field(text, path, field, commented=False):
    """(value_start, value_end) for `field = value` at the block path's own level.

    commented looks for the same field behind a `--` instead, which is how the
    previous release recorded a setting being turned off.
    """
    start, end = 0, len(text)
    for name in path:
        span = _find_block(text, name, start, end)
        if span is None:
            return None
        start, end = span
    # A braced value closes on its own line, which is what tells it apart from
    # a nested block opening; it and the quoted string are tried first, since
    # the scalar pattern stops at the first comma and both may contain one —
    # rgba(20, 20, 20, 0.5) is a colour Hyprland accepts, and matching only
    # `"rgba(20` would splice the replacement in front of the rest of it.
    lead = r"^[ \t]*--[ \t]*" if commented else r"^[ \t]*"
    pattern = re.compile(lead + re.escape(field)
                         + r"[ \t]*=[ \t]*(\{[^}\n]*\}|\"(?:[^\"\\\n]|\\.)*\"|[^,\n}]+)")
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
        depth += line.count("{") - line.count("}")
        # Anchored on a line that ENDS back at depth 0, so a block whose last
        # entry is a nested table anchors on that table's closing brace rather
        # than its opening line — anchoring on the opening line spliced the new
        # field inside the nested table and left `{,` behind.
        if depth == 0 and stripped and not stripped.startswith("--"):
            if indent is None:
                indent = line[:len(line) - len(line.lstrip())]
            last_end = pos + len(line.rstrip())
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
    if kind == "str":
        return raw.strip('"') or None
    if kind == "vec2":
        parts = raw.strip("{}").split(",")
        if len(parts) != 2:
            return None
        try:
            return [int(x) if float(x) == int(float(x)) else float(x)
                    for x in (p.strip() for p in parts)]
        except ValueError:
            return None
    try:
        return int(raw) if kind == "int" else float(raw)
    except ValueError:
        return None


def _format(value, kind):
    if kind == "bool":
        return "true" if value else "false"
    if kind == "str":
        # A theme's decorations.json is untrusted on import, and this string
        # lands in general.lua, which the compositor evaluates as Lua. Escaping
        # the quote and backslash keeps a value like `x" .. os.execute(...)`
        # a harmless string instead of an expression that breaks out of it.
        safe = str(value).replace("\\", "\\\\").replace('"', '\\"')
        return '"' + safe + '"'
    if kind == "vec2":
        return "{%s, %s}" % (int(round(float(value[0]))), int(round(float(value[1]))))
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
                if not os.path.exists(fp):
                    out[row["key"]] = row.get("default", True)
                else:
                    raw = open(fp).read().strip()
                    if row.get("type") == "bool":
                        out[row["key"]] = raw != "0"
                    elif row.get("type") == "float":
                        try:
                            out[row["key"]] = float(raw)
                        except ValueError:
                            out[row["key"]] = row.get("default")
                    else:
                        out[row["key"]] = raw
            continue
        if row.get("mechanism") == "namefile":
            fp = os.path.join(os.path.dirname(general_path), row["path"])
            try:
                name = open(fp).read().strip()
            except OSError:
                continue
            if name:
                out[row["key"]] = name
            continue
        path, field = lua_location(row)
        span = _find_field(text, path, field)
        if span is None:
            # The release before this one turned a setting off by commenting
            # its line out, so an upgraded install has `-- border_size = 4,`
            # sitting where the field should be. Reading that as "not set"
            # would show the switch on while the compositor has none, and a
            # theme saved from that state would turn it back on. A commented
            # field means the off value the old toggle meant by it.
            legacy = row.get("legacy")
            if legacy is not None and _find_field(text, path, field, commented=True):
                out[row["key"]] = legacy["off"]
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


def _locked(path):
    """Exclusive hold on a file's sibling lock, for the length of a `with`.

    The settings page and a theme apply both read general.lua, change part of
    it and write it back, and they overlap: the page is live while a theme
    applies. Without this the second writer starts from the text the first one
    had already replaced, and that writer's whole edit disappears.
    """
    import fcntl

    class _Lock:
        def __enter__(self):
            try:
                self.fh = open(path + ".lock", "w")
                fcntl.flock(self.fh, fcntl.LOCK_EX)
            except OSError:
                # A read-only or missing directory is not a reason to refuse
                # the edit; it only means it is not serialised.
                self.fh = None
            return self

        def __exit__(self, *exc):
            if self.fh is not None:
                try:
                    fcntl.flock(self.fh, fcntl.LOCK_UN)
                finally:
                    self.fh.close()
            return False

    return _Lock()


def write(general_path, values, flag_dir=None, schema=None):
    with _locked(general_path):
        return _write_locked(general_path, values, flag_dir, schema)


def _write_locked(general_path, values, flag_dir=None, schema=None):
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
                    # A flag file used to mean a switch and nothing else, so
                    # every value was flattened to 1 or 0. A colour or an
                    # opacity written that way arrives as the word "1".
                    if row.get("type") == "bool":
                        text_value = "1" if value else "0"
                    else:
                        text_value = "" if value is None else str(value)
                    with open(os.path.join(flag_dir, row["path"]), "w") as fh:
                        fh.write(text_value)
                    written += 1
                except OSError:
                    pass
            continue
        if row.get("mechanism") == "namefile":
            if re.fullmatch(r"[\w-]+", str(value)):
                fp = os.path.join(os.path.dirname(general_path), row["path"])
                try:
                    os.makedirs(os.path.dirname(fp), exist_ok=True)
                    with open(fp, "w") as fh:
                        fh.write(str(value) + "\n")
                    written += 1
                except OSError:
                    pass
            continue
        path, field = lua_location(row)
        try:
            rendered = _format(value, row["type"])
        except (TypeError, ValueError, IndexError, KeyError):
            # A snapshot from a version where this key held a different shape.
            # One unrenderable value must not cost the whole set its write.
            continue
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
    # Hyprland config and a reload can be reading it at any moment. The name is
    # unique per writer — a shared one meant two writers held the same inode,
    # and the loser's rename published a half-written file.
    import tempfile
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(general_path) or ".",
                               prefix=os.path.basename(general_path) + ".")
    try:
        with os.fdopen(fd, "w") as fh:
            fh.write(text)
        try:
            os.chmod(tmp, os.stat(general_path).st_mode & 0o7777)
        except OSError:
            pass
        os.replace(tmp, general_path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return written


def push(values, schema=None, allow_reload=True):
    """Send the settings to the running compositor.

    `hyprctl keyword` is Legacy-only in 0.55 ("can't work with non-legacy
    parsers. Use eval."), so this goes through hl.config(). The first part of
    the keyword is the section and the rest becomes a bracket-string key, which
    is what carries a nested block: decoration:blur:size -> ["blur.size"].
    One eval for the whole set, since each is a round trip.

    A profile name only takes effect on a reload, so one is issued when the
    set names it. allow_reload is for the caller that reloads anyway — a
    reload re-parses the whole config and is the most expensive thing here,
    so the theme apply asks for its own rather than paying for two.
    """
    import subprocess
    schema = schema or load_schema()
    needs_reload = allow_reload and any(
        row.get("mechanism") == "namefile"
        and resolve(values, row) is not None
        for row in schema["keys"])
    sections = {}
    for row in schema["keys"]:
        if not row.get("hypr"):
            continue
        value = resolve(values, row)
        if value is None:
            continue
        path, field = lua_location(row)
        leaf = ".".join(path[1:] + [field])
        # Same renderer as the file write, so this eval carries the same
        # escaping — the value reaches the compositor either way.
        try:
            lua = _format(value, row["type"])
        except (TypeError, ValueError, IndexError, KeyError):
            continue
        sections.setdefault(path[0], []).append('["' + leaf + '"] = ' + lua)
    try:
        # Bounded: a wedged compositor would otherwise hang the theme apply
        # for good, holding its lock and leaving the shell stuck on "applying".
        if needs_reload:
            subprocess.run(["hyprctl", "reload"], capture_output=True, timeout=10)
        if not sections:
            return
        body = ", ".join(s + " = { " + ", ".join(v) + " }" for s, v in sections.items())
        subprocess.run(["hyprctl", "eval", "hl.config({ " + body + " })"],
                       capture_output=True, timeout=10)
    except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
        # No compositor to talk to: the file write already happened and is
        # what a later start reads, so this is a no-op rather than a failure.
        pass


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
    if verb == "shipped":
        # The names every install already has. Callers used to each dig this
        # out of the schema themselves, with validators that disagreed about
        # what a profile may be called.
        schema = load_schema()
        row = next((r for r in schema["keys"] if r["key"] == "animationProfile"), None)
        for name in (row or {}).get("shipped", []):
            print(name)
        return 0
    if verb == "defaults":
        # What each setting is worth on a stock install. Kept apart from read so
        # a theme snapshot stays a record of what was set, not of what shipped.
        schema = load_schema()
        json.dump({row["key"]: row["default"] for row in schema["keys"]
                   if "default" in row},
                  sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return 0
    if verb == "write":
        if not rest:
            print("write needs a values file", file=sys.stderr)
            return 2
        with open(rest[0]) as fh:
            values = json.load(fh)
        if write(general, values, flag_dir) == 0:
            print(f"nothing written to {general}", file=sys.stderr)
            return 1
        return 0
    if verb == "restore":
        if not rest:
            print("restore needs a values file", file=sys.stderr)
            return 2
        with open(rest[0]) as fh:
            values = json.load(fh)
        schema = load_schema()
        full = {row["key"]: row["default"] for row in schema["keys"]
                if "default" in row}
        known = {row["key"] for row in schema["keys"]}
        # Snapshots from before the border/corner keys were split still carry
        # the old bools (borders, roundCorners). Map each through the schema's
        # own legacy table so every key a bool used to drive moves with it —
        # borders off meant no border AND no gaps AND no resize edge, not just
        # a zero border size.
        for row in schema["keys"]:
            legacy = row.get("legacy")
            if legacy and legacy["bool"] in values and row["key"] not in values:
                full[row["key"]] = legacy["on"] if values[legacy["bool"]] else legacy["off"]
        for key, value in values.items():
            if key in known:
                full[key] = value
        # Nothing persisted means the file was missing or held none of these
        # blocks; telling the compositor anyway would put the desktop in a
        # state no file backs, which the next start would silently undo.
        if write(general, full, flag_dir) == 0:
            print(f"nothing written to {general}", file=sys.stderr)
            return 1
        # --push sends the same completed set to the running compositor here
        # rather than through a second invocation reading a temp file: this
        # process already holds the values and the schema. The caller reloads
        # for its own reasons, so no reload is issued from inside.
        if "--push" in rest:
            push(full, schema, allow_reload=False)
        return 0
    if verb == "set":
        # `set <general.lua> key=value ...` — one call from the settings page
        # covers the file and the running compositor, so neither can be updated
        # without the other.
        schema = load_schema()
        values = coerce(schema, rest)
        if not values:
            return 0
        if write(general, values, flag_dir, schema) == 0:
            print(f"nothing written to {general}", file=sys.stderr)
            return 1
        push(values, schema)
        return 0
    if verb == "push":
        # `push <values.json>` — the compositor only; the file is already right.
        try:
            with open(general) as fh:
                values = json.load(fh)
        except Exception:
            return 0
        push(values, allow_reload="--no-reload" not in rest)
        return 0
    print("unknown verb: " + verb, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
