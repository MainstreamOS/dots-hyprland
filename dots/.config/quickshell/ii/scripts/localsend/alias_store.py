#!/usr/bin/env python3
"""
Persisted device alias for LocalSend.

The first time this is asked for an alias and finds nothing saved, it
picks a random two-word "Adjective Noun" name -- the same style the real
LocalSend apps use for their default device name (e.g. "Nice Orange",
"Secret Banana") -- and saves it immediately. Every later call, from any
of send.py/receive.py/discover.py, and every later run of any of them,
reads back that same saved name. common.ALIAS reads through here, so it
only has to happen once, ever, per machine.

Config lives at $XDG_CONFIG_HOME/mainstream/localsend/alias.json, mirroring
the mainstream/localsend/ namespace send.py's client_cert() already uses
under XDG_STATE_HOME for the TLS certificate.
"""

import json
import os
import random

ADJECTIVES = [
    "Happy", "Clever", "Brave", "Gentle", "Swift", "Calm", "Bright", "Quiet",
    "Bold", "Cheerful", "Curious", "Eager", "Fancy", "Friendly", "Jolly",
    "Kind", "Lively", "Lucky", "Merry", "Nice", "Playful", "Proud", "Quick",
    "Silly", "Smart", "Sunny", "Sweet", "Tidy", "Witty", "Zesty", "Breezy",
    "Cozy",
]

NOUNS = [
    "Coconut", "Banana", "Orange", "Mango", "Peach", "Cherry", "Lemon",
    "Melon", "Papaya", "Fig", "Kiwi", "Plum", "Apple", "Grape", "Berry",
    "Otter", "Falcon", "Panda", "Dolphin", "Fox", "Owl", "Rabbit", "Tiger",
    "Wolf", "Bear", "Eagle", "Koala", "Penguin", "Dog", "Cat", "Turtle",
    "Squirrel",
]


def random_alias():
    """One "Adjective Noun" pick, e.g. "Smart Coconut"."""
    return f"{random.choice(ADJECTIVES)} {random.choice(NOUNS)}"


def _config_path():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "mainstream", "localsend", "alias.json")


def _read_saved():
    try:
        with open(_config_path(), "r") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None
    alias = (data or {}).get("alias")
    return alias.strip() if isinstance(alias, str) and alias.strip() else None


def get_alias(default=None):
    """Return the saved alias.

    If nothing has been saved yet: passing `default` returns that literal
    value without saving it (a static fallback, mainly for testing). Left
    as None -- the normal case -- a random two-word name is generated,
    saved, and returned, so every future call sees the same name.
    """
    saved = _read_saved()
    if saved:
        return saved
    if default is not None:
        return default
    return _generate_and_persist()


def _generate_and_persist():
    path = _config_path()
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    name = random_alias()
    try:
        # O_EXCL makes this atomic across processes. send.py, receive.py,
        # and discover.py can all start around the same time on a brand
        # new machine, each finding no saved alias; without this, each
        # would generate and persist a *different* random name, and
        # whichever wrote last would silently win. With O_EXCL, only the
        # first writer actually creates the file -- everyone else hits
        # FileExistsError and reads back the name that writer picked, so
        # the whole machine converges on one name instead of racing.
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        with os.fdopen(fd, "w") as f:
            json.dump({"alias": name}, f)
        return name
    except FileExistsError:
        return _read_saved() or name


def set_alias(name):
    """Save `name` as the alias to use from now on, replacing any random
    or previously-chosen one."""
    path = _config_path()
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"alias": name.strip()}, f)
    os.replace(tmp, path)


def clear_alias():
    """Remove the saved alias. The next call to get_alias() anywhere will
    pick a fresh random name and save that instead."""
    try:
        os.remove(_config_path())
    except FileNotFoundError:
        pass
