"""Read installed timezones and their current UTC offsets for the desktop clocks."""

import argparse
from datetime import datetime, timezone
import json
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError, available_timezones


ALIASES = {"America/Miami": "America/New_York", "America/Houston": "America/Chicago"}


def offsets(zones, now=None):
    now = now or datetime.now(timezone.utc)
    result = {}
    for zone in zones:
        try:
            result[zone] = int(now.astimezone(ZoneInfo(ALIASES.get(zone, zone))).utcoffset().total_seconds() / 60)
        except (ZoneInfoNotFoundError, ValueError):
            result[zone] = None
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true")
    parser.add_argument("zones", nargs="*")
    args = parser.parse_args()
    print(json.dumps(sorted(available_timezones()) if args.list else offsets(args.zones)))


if __name__ == "__main__":
    main()
