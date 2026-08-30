#!/usr/bin/env python3
"""
Manage this device's LocalSend name.

Usage:
    set_alias.py                    print the current name
    set_alias.py "My Device Name"   set (or change) the saved name
    set_alias.py --clear            drop the saved name

You don't need to run this at all: the first time send.py, receive.py, or
discover.py runs and finds no saved name, it picks a random two-word one
itself (like "Smart Coconut") the same way the official LocalSend apps do,
and saves it -- so it's set "once" automatically. Use this script only if
you want to see the current name or replace it with one of your choosing.
"""

import sys

from alias_store import clear_alias, get_alias, set_alias


def main():
    args = sys.argv[1:]
    if not args:
        current = get_alias(None)
        print(current if current else
              "(nothing saved yet -- a random name is picked on next run)")
        return 0
    if args[0] == "--clear":
        clear_alias()
        print("Cleared. A new random name will be picked on next run.")
        return 0
    name = " ".join(args).strip()
    if not name:
        print("error: name can't be empty", file=sys.stderr)
        return 2
    set_alias(name)
    print(f'Saved. This device will show up as "{name}".')
    return 0


if __name__ == "__main__":
    sys.exit(main())
