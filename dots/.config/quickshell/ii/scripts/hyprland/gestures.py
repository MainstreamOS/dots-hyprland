#!/usr/bin/env python3
"""Touchpad gestures: the block in hyprland/general.lua, made from config.json.

The gesture choices live in config.json (gestures.swipe3 and the rest), which
updates never touch. The hl.gesture() block between the BEGIN and END markers
in general.lua is only what Hyprland reads, and general.lua is a file every
release ships, so an update that replaces it puts the stock gestures back.
Settings > Mouse and the updater both write the block through here, so there
is one mapping and a replaced file gets the same gestures back.

  gestures.py block [--config PATH] [--slot NAME=VALUE ...]
  gestures.py apply [--config PATH] [--general PATH] [--slot NAME=VALUE ...]

--slot overrides what config.json says, for a page that has just changed a
value and would otherwise race its own write of config.json.

apply exits 0 when it rewrote the block, 1 when the markers are missing, and
2 when the file already matches, so running it costs nothing when nothing
changed.
"""

import argparse
import json
import os
import re
import sys

# The shared writer lives beside the theme scripts. No bytecode is written for
# it: the updater runs these from its clone, and a __pycache__ left there would
# be copied home as a changed file on the next full pass.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "themes"))
sys.dont_write_bytecode = True
from decorations import _locked, _publish

# Each slot's choices in order; the first is what a slot with no value, or a
# value this release does not know, falls back to, as the page's dropdowns do.
GESTURES = {
    "swipe3": {
        "move": '{\n    fingers = 3,\n    direction = "swipe",\n    action = "move"\n}',
        "workspace": '{\n    fingers = 3,\n    direction = "horizontal",\n    action = "workspace"\n}',
        "resize": '{\n    fingers = 3,\n    direction = "swipe",\n    action = "resize"\n}',
    },
    "pinch3": {
        "float": '{\n    fingers = 3,\n    direction = "pinch",\n    action = "float"\n}',
        "fullscreen": '{\n    fingers = 3,\n    direction = "pinch",\n    action = "fullscreen"\n}',
        "close": '{\n    fingers = 3,\n    direction = "pinch",\n    action = "close"\n}',
    },
    "horizontal4": {
        "workspace": '{\n    fingers = 4,\n    direction = "horizontal",\n    action = "workspace"\n}',
        "special": '{\n    fingers = 4,\n    direction = "horizontal",\n    action = "special"\n}',
    },
    "up4": {
        "overviewOpen": '{\n    fingers = 4,\n    direction = "up",\n    action = function()\n        hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesToggle"))\n    end\n}',
        "fullscreen": '{\n    fingers = 4,\n    direction = "up",\n    action = "fullscreen"\n}',
        "special": '{\n    fingers = 4,\n    direction = "up",\n    action = "special"\n}',
    },
    "down4": {
        "overviewClose": '{\n    fingers = 4,\n    direction = "down",\n    action = function()\n        hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesClose"))\n    end\n}',
        "close": '{\n    fingers = 4,\n    direction = "down",\n    action = "close"\n}',
    },
}

MARKERS = re.compile(r"(?s)(-- BEGIN gestures[^\n]*\n).*?(-- END gestures)")


def default_config_path():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "illogical-impulse", "config.json")


def default_general_path():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "hypr", "hyprland", "general.lua")


def read_choices(config_path, overrides):
    choices = {}
    try:
        with open(config_path, encoding="utf-8") as f:
            saved = json.load(f).get("gestures", {})
        if isinstance(saved, dict):
            choices.update({k: v for k, v in saved.items() if isinstance(v, str)})
    except (OSError, ValueError, AttributeError):
        # No config yet, or one that does not parse: the defaults are what the
        # shell itself falls back to.
        pass
    for pair in overrides:
        name, _, value = pair.partition("=")
        if name in GESTURES:
            choices[name] = value
    return choices


def block(choices):
    lines = []
    for slot, options in GESTURES.items():
        value = choices.get(slot)
        if value == "none":
            continue
        # The own-key check keeps a hand-edited value from reaching the Lua.
        if value not in options:
            value = next(iter(options))
        lines.append("hl.gesture(" + options[value] + ")")
    return "\n".join(lines)


def apply(general_path, text_block):
    with _locked(general_path):
        try:
            with open(general_path, encoding="utf-8") as f:
                text = f.read()
        except OSError:
            return 1
        new, count = MARKERS.subn(
            lambda m: m.group(1) + text_block + ("\n" if text_block else "") + m.group(2),
            text, count=1)
        if count == 0:
            return 1
        if new == text:
            return 2
        _publish(general_path, new, encoding="utf-8")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("verb", choices=["block", "apply"])
    parser.add_argument("--config", default=default_config_path())
    parser.add_argument("--general", default=default_general_path())
    parser.add_argument("--slot", action="append", default=[])
    args = parser.parse_args()
    text_block = block(read_choices(args.config, args.slot))
    if args.verb == "block":
        print(text_block)
        return 0
    return apply(args.general, text_block)


if __name__ == "__main__":
    sys.exit(main())
