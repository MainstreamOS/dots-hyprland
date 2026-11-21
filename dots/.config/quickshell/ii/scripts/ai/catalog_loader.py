#!/usr/bin/env python3
# The AI model catalog for the helper scripts: the mainstream-assistance
# package's models.json, then the copy bundled with the shell, as services/Ai.qml
# chooses. A value the package's file lacks, as one older than the shell can,
# comes from the bundled copy.
#   catalog_loader.py get [--allow-empty] <dotted.key> [default]
import json
import os
import sys

SYSTEM_CATALOG_PATH = "/usr/share/mainstream/assistance/models.json"
BUNDLED_CATALOG_PATH = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "defaults", "ai", "models.json")
)
SUPPORTED_SCHEMA_VERSION = 1


def _read(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    version = data.get("schemaVersion")
    if isinstance(version, bool) or version != SUPPORTED_SCHEMA_VERSION:
        return None
    return data


def catalogs():
    system = os.environ.get("MAINSTREAM_AI_CATALOG_PATH") or SYSTEM_CATALOG_PATH
    return [data for data in (_read(system), _read(BUNDLED_CATALOG_PATH)) if data]


def lookup(dotted_key, kind):
    for value in catalogs():
        for part in dotted_key.split("."):
            value = value.get(part) if isinstance(value, dict) else None
        if isinstance(value, kind):
            return value
    return None


def load_script_config(section):
    return lookup(f"scripts.{section}", dict) or {}


def get_string(dotted_key, default="", allow_empty=False):
    value = lookup(dotted_key, str)
    if value is None:
        return default
    value = value.strip()
    return value if value or allow_empty else default


def main(argv):
    allow_empty = argv[1:2] == ["--allow-empty"]
    args = argv[2:] if allow_empty else argv[1:]
    if argv[:1] != ["get"] or not args:
        sys.stderr.write("Usage: catalog_loader.py get [--allow-empty] <dotted.key> [default]\n")
        return 2
    print(get_string(args[0], args[1] if len(args) > 1 else "", allow_empty))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
