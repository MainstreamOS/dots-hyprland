#!/usr/bin/env python3
"""Owns the window rules the settings page manages.

The rules live as JSON — the shape the page edits and a theme snapshots — and
are compiled whole into a Lua file the Hyprland config loads. One direction
only: this file is regenerated from the JSON on every write, so nothing ever
parses Lua back. Rules written by hand elsewhere are not read, not shown and
not touched.

    windowrules.py read    <rules.json>
    windowrules.py write   <rules.json> <userrules.lua>   (new rules on stdin)
    windowrules.py compile <rules.json> <userrules.lua>
    windowrules.py windows

Effects are held to a schema: a known effect renders with its own type, and a
custom effect is a field name plus a literal that must look like one — the
generated file runs inside the compositor's config, so nothing free-form goes
in whole.
"""
import json
import os
import re
import subprocess
import sys

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
# A literal the generated config can carry without carrying anything else:
# a boolean, a number, a quoted string, or a one-line braced table of those.
_SCALAR = r'(?:true|false|-?\d+(?:\.\d+)?|"[^"\\]*")'
LITERAL_RE = re.compile(
    r"^(%s|\{\s*%s(?:\s*,\s*%s)*\s*\})$" % (_SCALAR, _SCALAR, _SCALAR))


def lua_string(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


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


def validate(rules):
    if not isinstance(rules, list):
        return "rules must be a list"
    for i, rule in enumerate(rules):
        if not isinstance(rule, dict):
            return f"rule {i}: not an object"
        match = rule.get("match") or {}
        if not any(match.get(k) not in (None, "") for k in MATCHES):
            return f"rule {i}: no match"
        for k in match:
            if k not in MATCHES:
                return f"rule {i}: unknown match '{k}'"
        effects = rule.get("effects") or {}
        custom = rule.get("custom") or []
        if not effects and not custom:
            return f"rule {i}: no effects"
        for k in effects:
            if k not in EFFECTS:
                return f"rule {i}: unknown effect '{k}'"
        for c in custom:
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
    try:
        with open(json_path) as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return []
    rules = data.get("rules", []) if isinstance(data, dict) else []
    return rules if validate(rules) is None else []


def save(json_path, lua_path, rules):
    for path, text in ((json_path, json.dumps({"rules": rules}, indent=2) + "\n"),
                       (lua_path, compile_lua(rules))):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w") as fh:
            fh.write(text)
        os.replace(tmp, path)
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
        json.dump({"rules": load(argv[2])}, sys.stdout, indent=2)
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
        save(argv[2], argv[3], rules)
        print("OK")
        return 0
    if verb == "compile":
        save(argv[2], argv[3], load(argv[2]))
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
            out.append({"class": c.get("class", ""),
                        "title": c.get("title", ""),
                        "initialClass": c.get("initialClass", ""),
                        "initialTitle": c.get("initialTitle", "")})
        json.dump(out, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0
    print("unknown verb: " + verb, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
