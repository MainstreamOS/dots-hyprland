#!/usr/bin/env python3
# eds-events.py — dump upcoming calendar events from evolution-data-server as
# JSON for the sidebar calendar. Reads the same calendars GNOME Calendar
# shows (local ones and every online account added through Online Accounts),
# including expanded recurrences. Prints [] when EDS or its bindings are
# missing so the shell degrades gracefully on installs without the calendar
# bundle.
#
# Usage: eds-events.py [DAYS_BACK] [DAYS_FORWARD]   (defaults 45 120)
# Output: [{"date":"YYYY-MM-DD","title":str,"allDay":bool,
#           "start":"HH:MM"|null,"end":"HH:MM"|null,
#           "calendar":str,"color":"#RRGGBB"|null}, ...]

import json
import sys
from datetime import datetime, timedelta


def main():
    try:
        import gi
        gi.require_version("ECal", "2.0")
        gi.require_version("EDataServer", "1.2")
        gi.require_version("ICalGLib", "4.0")
        from gi.repository import ECal, EDataServer, ICalGLib  # noqa: F401
    except Exception:
        print("[]")
        return 0

    days_back = int(sys.argv[1]) if len(sys.argv) > 1 else 45
    days_forward = int(sys.argv[2]) if len(sys.argv) > 2 else 120
    now = datetime.now()
    t0 = int((now - timedelta(days=days_back)).timestamp())
    t1 = int((now + timedelta(days=days_forward)).timestamp())

    try:
        registry = EDataServer.SourceRegistry.new_sync(None)
    except Exception:
        print("[]")
        return 0

    events = []

    def add_instance(summary, ical_start, ical_end, cal_name, cal_color):
        try:
            all_day = bool(ical_start.is_date())
            start_ts = ical_start.as_timet()
            end_ts = ical_end.as_timet() if ical_end else start_ts
            start_dt = datetime.fromtimestamp(start_ts)
            end_dt = datetime.fromtimestamp(end_ts)
            # all-day DTEND is exclusive; walk each covered day
            last = (end_dt - timedelta(seconds=1)) if all_day else end_dt
            day = start_dt.date()
            while day <= last.date():
                events.append({
                    "date": day.isoformat(),
                    "title": summary or "(untitled)",
                    "allDay": all_day,
                    "start": None if all_day else start_dt.strftime("%H:%M"),
                    "end": None if all_day else end_dt.strftime("%H:%M"),
                    "calendar": cal_name,
                    "color": cal_color,
                })
                day += timedelta(days=1)
        except Exception:
            pass

    for source in registry.list_enabled(EDataServer.SOURCE_EXTENSION_CALENDAR):
        try:
            ext = source.get_extension(EDataServer.SOURCE_EXTENSION_CALENDAR)
            cal_color = ext.get_color() if ext else None
            cal_name = source.get_display_name()
            client = ECal.Client.connect_sync(
                source, ECal.ClientSourceType.EVENTS, 3, None)
            if client is None:
                continue

            def cb(comp, start, end, *_args, _n=cal_name, _c=cal_color):
                summary = None
                try:
                    if hasattr(comp, "get_summary"):
                        s = comp.get_summary()
                        summary = s.get_value() if hasattr(s, "get_value") else s
                    if summary is None and hasattr(comp, "get_icalcomponent"):
                        summary = comp.get_icalcomponent().get_summary()
                except Exception:
                    pass
                add_instance(summary, start, end, _n, _c)
                return True

            client.generate_instances_sync(t0, t1, None, cb)
        except Exception:
            continue

    print(json.dumps(events))
    return 0


sys.exit(main())
