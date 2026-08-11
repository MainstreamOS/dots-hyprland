#!/usr/bin/env python3
"""Owns the window rules the settings page manages.

The rules live as JSON — the shape the page edits and a theme snapshots — and
are compiled whole into a Lua file the Hyprland config loads. One direction
only: this file is regenerated from the JSON on every write, so nothing ever
parses Lua back. Rules written by hand elsewhere are not read, not shown and
not touched.

    windowrules.py read    <rules.json>
    windowrules.py write   <rules.json> <userrules.lua> [--no-reload]
                                                        (new rules on stdin)
    windowrules.py compile <rules.json> <userrules.lua>
    windowrules.py windows

Effects are held to a schema: a known effect renders with its own type, and a
custom effect is a field name plus a literal that must look like one — the
generated file runs inside the compositor's config, so nothing free-form goes
in whole.
"""
import fcntl
import json
import os
import re
import subprocess
import sys
import tempfile

# JSON key -> (lua field, kind). What the page offers by name; anything else
# rides the custom escape hatch.
EFFECTS = {
    "opacity":        ("opacity", "number"),
    "noBlur":         ("no_blur", "bool"),
    "float":          ("float", "bool"),
    "tile":           ("tile", "bool"),
    "center":         ("center", "bool"),
    "size":           ("size", "vec2"),
    "pin":            ("pin", "bool"),
    "fullscreen":     ("fullscreen", "bool"),
    "maximize":       ("maximize", "bool"),
    "workspace":      ("workspace", "string"),
    "tearing":        ("immediate", "bool"),
    "idleInhibit":    ("idle_inhibit", "string"),
    "keepAspect":     ("keep_aspect_ratio", "bool"),
    "noAnim":         ("no_anim", "bool"),
    "borderSize":     ("border_size", "int"),
    "noShadow":       ("no_shadow", "bool"),
    "noDim":          ("no_dim", "bool"),
    "rounding":       ("rounding", "int"),
    "suppressEvent":  ("suppress_event", "string"),
}

MATCHES = {
    "class":        "class",
    "title":        "title",
    "initialClass": "initial_class",
    "initialTitle": "initial_title",
    "xwayland":     "xwayland",
}

FIELD_RE = re.compile(r"^[a-z][a-z0-9_]*$")
# A literal the generated config can carry without carrying anything else: a
# boolean, a number, or a double-quoted string with no escapes. A braced table
# holds a comma-separated list of exactly those — the braces cannot wrap a bare
# Lua expression, or a custom effect value like `{os.execute("...")}` would ride
# an imported theme straight into the compositor's config.
_SCALAR = r'(?:true|false|-?\d+(?:\.\d+)?|"[^"\\]*")'
LITERAL_RE = re.compile(
    r"^(%s|\{\s*%s(?:\s*,\s*%s)*\s*\})$" % (_SCALAR, _SCALAR, _SCALAR))


def lua_string(s):
    out = str(s).replace("\\", "\\\\").replace('"', '\\"')
    # A Lua short string cannot hold a raw newline, so one in a pattern would
    # leave the string open and take every rule after it down with it. The
    # three-digit form keeps a following digit from being read as part of it.
    return '"' + re.sub(r"[\x00-\x1f\x7f]",
                        lambda m: "\\%03d" % ord(m.group()), out) + '"'


def render_effect(kind, value):
    if kind == "bool":
        return "true" if value else "false"
    if kind == "int":
        return str(int(value))
    if kind == "number":
        text = ("%.4f" % float(value)).rstrip("0").rstrip(".")
        return text or "0"
    if kind == "vec2":
        return "{%s, %s}" % (int(value[0]), int(value[1]))
    return lua_string(value)


def _type_ok(kind, value):
    """Whether render_effect can turn this value into what the kind promises.

    Checked here rather than left to render_effect, which would raise on a
    wrong shape and abort the whole write — the rules on disk would then be
    unwritable until someone found the file by hand.
    """
    if kind == "bool":
        return isinstance(value, bool)
    if kind in ("int", "number"):
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if kind == "vec2":
        return (isinstance(value, (list, tuple)) and len(value) == 2
                and all(isinstance(n, (int, float)) and not isinstance(n, bool)
                        for n in value))
    return isinstance(value, str)


def validate(rules):
    if not isinstance(rules, list):
        return "rules must be a list"
    for i, rule in enumerate(rules):
        if not isinstance(rule, dict):
            return f"rule {i}: not an object"
        match = rule.get("match") or {}
        if not isinstance(match, dict):
            return f"rule {i}: match must be an object"
        if not any(match.get(k) not in (None, "") for k in MATCHES):
            return f"rule {i}: no match"
        for k, v in match.items():
            if k not in MATCHES:
                return f"rule {i}: unknown match '{k}'"
            if k == "xwayland":
                if not isinstance(v, bool):
                    return f"rule {i}: match '{k}' must be true or false"
            elif not isinstance(v, str):
                return f"rule {i}: match '{k}' must be text"
        effects = rule.get("effects") or {}
        if not isinstance(effects, dict):
            return f"rule {i}: effects must be an object"
        custom = rule.get("custom") or []
        if not isinstance(custom, list):
            return f"rule {i}: custom must be a list"
        if not effects and not custom:
            return f"rule {i}: no effects"
        for k, v in effects.items():
            if k not in EFFECTS:
                return f"rule {i}: unknown effect '{k}'"
            if not _type_ok(EFFECTS[k][1], v):
                return f"rule {i}: effect '{k}' has the wrong kind of value"
        for c in custom:
            if not isinstance(c, dict):
                return f"rule {i}: custom entry is not an object"
            field = str(c.get("field", ""))
            value = str(c.get("value", ""))
            if not FIELD_RE.match(field):
                return f"rule {i}: bad custom field '{field}'"
            if not LITERAL_RE.match(value):
                return f"rule {i}: bad custom value '{value}'"
    return None


def compile_lua(rules):
    out = ["-- Written by the settings page; edits here are overwritten.",
           "-- Rules of your own belong in custom/, which nothing regenerates.",
           ""]
    for rule in rules:
        if not rule.get("enabled", True):
            continue
        parts = []
        match = rule.get("match") or {}
        mparts = []
        for k, lua_key in MATCHES.items():
            v = match.get(k)
            if v in (None, ""):
                continue
            if k == "xwayland":
                mparts.append(f"{lua_key} = {'true' if v else 'false'}")
            else:
                mparts.append(f"{lua_key} = {lua_string(v)}")
        parts.append("match = {" + ", ".join(mparts) + "}")
        effects = rule.get("effects") or {}
        for k, (lua_key, kind) in EFFECTS.items():
            if k in effects and effects[k] is not None:
                parts.append(f"{lua_key} = {render_effect(kind, effects[k])}")
        for c in rule.get("custom") or []:
            parts.append(f"{c['field']} = {c['value']}")
        out.append("hl.window_rule({" + ", ".join(parts) + "})")
    return "\n".join(out) + "\n"


def load(json_path):
    """(rules, problem). A problem means the store was not understood.

    An unreadable or unrecognised store used to read as an empty list, which
    the page showed as "no rules yet" and the next save wrote over the top of
    — the rules were gone and nothing had said so. The reason travels with the
    result instead, so a caller can refuse to overwrite what it cannot read.
    """
    if not os.path.exists(json_path):
        return [], None
    try:
        with open(json_path) as fh:
            data = json.load(fh)
    except OSError as e:
        return [], f"cannot read {os.path.basename(json_path)}: {e.strerror}"
    except ValueError as e:
        return [], f"{os.path.basename(json_path)} is not valid JSON: {e}"
    if not isinstance(data, dict) or not isinstance(data.get("rules", []), list):
        return [], "the rules file does not hold a rule list"
    rules = data.get("rules", [])
    try:
        problem = validate(rules)
    except Exception as e:
        problem = f"rules could not be checked: {e}"
    return ([], problem) if problem else (rules, None)


def _publish(path, text):
    """Write beside the target and rename over it, under a name of our own.

    A shared temp name let two writers hold one inode, so the loser could
    rename a file the winner was still filling.
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path),
                               prefix=os.path.basename(path) + ".")
    try:
        with os.fdopen(fd, "w") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def save(json_path, lua_path, rules, reload=True):
    # Both files under one lock: they are one fact in two spellings, and a
    # reader that caught the store from one write and the generated rules from
    # another would show rules the compositor is not enforcing.
    lock = None
    try:
        os.makedirs(os.path.dirname(json_path), exist_ok=True)
        lock = open(json_path + ".lock", "w")
        fcntl.flock(lock, fcntl.LOCK_EX)
    except OSError:
        lock = None
    try:
        _publish(json_path, json.dumps({"rules": rules}, indent=2) + "\n")
        _publish(lua_path, compile_lua(rules))
    finally:
        if lock is not None:
            try:
                fcntl.flock(lock, fcntl.LOCK_UN)
            finally:
                lock.close()
    if not reload:
        return
    try:
        subprocess.run(["hyprctl", "reload"], capture_output=True, timeout=10)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    verb = argv[1]
    if verb == "read":
        rules, problem = load(argv[2])
        out = {"rules": rules}
        if problem:
            out["error"] = problem
        json.dump(out, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0
    if verb == "write":
        try:
            data = json.load(sys.stdin)
        except ValueError as e:
            print(f"ERR|parse: {e}")
            return 1
        rules = data.get("rules", []) if isinstance(data, dict) else data
        problem = validate(rules)
        if problem:
            print(f"ERR|{problem}")
            return 1
        save(argv[2], argv[3], rules, reload="--no-reload" not in argv[4:])
        print("OK")
        return 0
    if verb == "compile":
        rules, problem = load(argv[2])
        if problem:
            # Regenerating from a store that wasn't understood would publish an
            # empty rule set over a file that still holds the real one.
            print(f"ERR|{problem}")
            return 1
        save(argv[2], argv[3], rules)
        print("OK")
        return 0
    if verb == "windows":
        try:
            raw = subprocess.run(["hyprctl", "clients", "-j"],
                                 capture_output=True, text=True, timeout=10).stdout
            clients = json.loads(raw)
        except Exception:
            clients = []
        seen = set()
        out = []
        for c in clients:
            key = (c.get("class", ""), c.get("title", ""))
            if key in seen or not any(key):
                continue
            seen.add(key)
            out.append({"class": c.get("class", ""), "title": c.get("title", "")})
        json.dump(out, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0
    print("unknown verb: " + verb, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
