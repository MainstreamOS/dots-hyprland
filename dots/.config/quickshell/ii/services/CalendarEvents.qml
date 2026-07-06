pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions

/**
 * Calendar events from evolution-data-server — the same calendars GNOME
 * Calendar shows, including online accounts added through Online Accounts.
 * Refreshed when the right sidebar opens and every 15 minutes; installs
 * without the calendar bundle just get an empty map (the helper prints []).
 */
Singleton {
    id: root

    property var eventsByDate: ({})

    function keyFor(year, month, day) { // JS 0-based month, like Todo
        return `${year}-${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`
    }

    function hasEventsForDate(year, month, day) {
        const l = root.eventsByDate[keyFor(year, month, day)]
        return l !== undefined && l.length > 0
    }

    function getEventsForDate(year, month, day) {
        return root.eventsByDate[keyFor(year, month, day)] ?? []
    }

    function refresh() {
        if (!fetchProc.running) fetchProc.running = true
    }

    Process {
        id: fetchProc
        command: [FileUtils.trimFileProtocol(`${Directories.scriptPath}/calendar/eds-events.py`)]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(this.text || "[]")
                    const map = {}
                    for (const ev of list) {
                        if (!map[ev.date]) map[ev.date] = []
                        map[ev.date].push(ev)
                    }
                    for (const k in map) {
                        map[k].sort((a, b) => {
                            const ka = a.allDay ? "" : (a.start ?? "")
                            const kb = b.allDay ? "" : (b.start ?? "")
                            return ka < kb ? -1 : ka > kb ? 1 : 0
                        })
                    }
                    root.eventsByDate = map
                } catch (e) {
                    // keep the previous map on parse trouble
                }
            }
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) root.refresh()
        }
    }

    Timer {
        interval: 15 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()
}
