#!/usr/bin/env python3
# eds-tasks.py — two-way task bridge to evolution-data-server for the
# sidebar To Do list. Reads every enabled task list (local ones and the
# online accounts' lists, e.g. Google Tasks) and writes changes back, so a
# task checked off in the shell completes in the account too. Prints empty
# results when EDS or its bindings are missing.
#
# Subcommands:
#   list                                  -> {"lists":[...],"tasks":[...]}
#   add <listUid> <summary> <YYYY-MM-DD|->
#   set-done <listUid> <uid> <1|0>
#   update <listUid> <uid> <summary> <YYYY-MM-DD|->
#   delete <listUid> <uid>

import json
import sys


def ical_escape(text):
    return (text.replace("\\", "\\\\").replace(";", "\\;")
                .replace(",", "\\,").replace("\n", "\\n"))


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    try:
        import gi
        gi.require_version("ECal", "2.0")
        gi.require_version("EDataServer", "1.2")
        gi.require_version("ICalGLib", "4.0")
        from gi.repository import ECal, EDataServer, ICalGLib
        registry = EDataServer.SourceRegistry.new_sync(None)
    except Exception:
        print(json.dumps({"lists": [], "tasks": []} if cmd == "list" else {"ok": False}))
        return 0

    def sources():
        return registry.list_enabled(EDataServer.SOURCE_EXTENSION_TASK_LIST)

    def connect_uid(uid):
        for s in sources():
            if s.get_uid() == uid:
                return ECal.Client.connect_sync(s, ECal.ClientSourceType.TASKS, 5, None)
        return None

    def strip_due(ical):
        while True:
            prop = ical.get_first_property(ICalGLib.PropertyKind.DUE_PROPERTY)
            if prop is None:
                return
            ical.remove_property(prop)

    if cmd == "list":
        lists, tasks = [], []
        for src in sources():
            try:
                ext = src.get_extension(EDataServer.SOURCE_EXTENSION_TASK_LIST)
                backend = ext.get_backend_name() if ext else "local"
                color = ext.get_color() if ext else None
                remote = backend != "local"
                luid, lname = src.get_uid(), src.get_display_name()
                lists.append({"uid": luid, "name": lname,
                              "color": color, "remote": remote})
                client = ECal.Client.connect_sync(
                    src, ECal.ClientSourceType.TASKS, 5, None)
                ok, comps = client.get_object_list_as_comps_sync("#t", None)
                for comp in comps or []:
                    try:
                        ical = comp.get_icalcomponent()
                        s = comp.get_summary()
                        summary = (s.get_value() if s else None) or "(untitled)"
                        done = comp.get_status() == ICalGLib.PropertyStatus.COMPLETED
                        date = None
                        due = comp.get_due()
                        if due is not None and due.get_value() is not None:
                            t = due.get_value()
                            date = f"{t.get_year():04d}-{t.get_month():02d}-{t.get_day():02d}T12:00:00"
                        tasks.append({
                            "uid": ical.get_uid(), "listUid": luid,
                            "listName": lname, "color": color,
                            "remote": remote, "eds": True,
                            "content": summary, "done": done, "date": date,
                        })
                    except Exception:
                        continue
            except Exception:
                continue
        print(json.dumps({"lists": lists, "tasks": tasks}))
        return 0

    try:
        if cmd == "add":
            luid, summary = sys.argv[2], sys.argv[3]
            datearg = sys.argv[4] if len(sys.argv) > 4 else "-"
            client = connect_uid(luid)
            due = ""
            if datearg != "-":
                due = f"\nDUE;VALUE=DATE:{datearg[:10].replace('-', '')}"
            ics = f"BEGIN:VTODO\nSUMMARY:{ical_escape(summary)}{due}\nEND:VTODO"
            comp = ICalGLib.Component.new_from_string(ics)
            client.create_object_sync(comp, ECal.OperationFlags.NONE, None)

        elif cmd == "set-done":
            luid, uid, val = sys.argv[2], sys.argv[3], sys.argv[4] == "1"
            client = connect_uid(luid)
            ical = client.get_object_sync(uid, None, None)[1]
            comp = ECal.Component.new_from_icalcomponent(ical)
            if val:
                comp.set_status(ICalGLib.PropertyStatus.COMPLETED)
                comp.set_percent_complete(100)
            else:
                comp.set_status(ICalGLib.PropertyStatus.NEEDSACTION)
                comp.set_percent_complete(0)
                comp.set_completed(None)
            client.modify_object_sync(comp.get_icalcomponent(),
                                      ECal.ObjModType.THIS,
                                      ECal.OperationFlags.NONE, None)

        elif cmd == "update":
            luid, uid, summary = sys.argv[2], sys.argv[3], sys.argv[4]
            datearg = sys.argv[5] if len(sys.argv) > 5 else "-"
            client = connect_uid(luid)
            ical = client.get_object_sync(uid, None, None)[1]
            ical.set_summary(summary)
            strip_due(ical)
            if datearg != "-":
                t = ICalGLib.Time.new_from_string(datearg[:10].replace("-", ""))
                ical.add_property(ICalGLib.Property.new_due(t))
            client.modify_object_sync(ical, ECal.ObjModType.THIS,
                                      ECal.OperationFlags.NONE, None)

        elif cmd == "delete":
            luid, uid = sys.argv[2], sys.argv[3]
            client = connect_uid(luid)
            client.remove_object_sync(uid, None, ECal.ObjModType.THIS,
                                      ECal.OperationFlags.NONE, None)
        else:
            print(json.dumps({"ok": False}))
            return 1
        print(json.dumps({"ok": True}))
        return 0
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}))
        return 1


sys.exit(main())
