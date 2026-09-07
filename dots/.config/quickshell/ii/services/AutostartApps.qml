pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * AutostartApps — the apps that start when you log in.
 *
 * Each one is a desktop entry in an autostart directory, and a switch here is
 * a file in yours standing in front of the system's. scripts/apps/autostart.sh
 * does the reading and the writing; this service is the shell's side of it.
 *
 * A change lands in the session that follows, because the units are built at
 * login. Nothing here starts or stops an app that is already running: closing
 * something a person is in the middle of using is not what a switch labeled
 * "starts with your computer" promises.
 */
Singleton {
    id: root

    readonly property string scriptPath: Quickshell.shellPath("scripts/apps/autostart.sh")

    // One entry per app: id, source ("system" or "added"), enabled, name,
    // icon, description. Apps added here come first, then the rest by name.
    property var entries: []
    property bool loaded: false
    // The entry a write is in flight for, so its row can hold still.
    property string busyId: ""

    function load() {} // For forcing singleton initialization

    function refresh() {
        listReader.running = false;
        listReader.running = true;
    }

    function has(entryId) {
        return root.entries.some(entry => entry.id === entryId);
    }

    function setEnabled(entryId, value) {
        if (!entryId) return;
        root.busyId = entryId;
        writer.command = [root.scriptPath, value ? "enable" : "disable", entryId];
        writer.running = false;
        writer.running = true;
    }

    // Start an installed app at login. The id is a desktop entry's, the same
    // one the launcher knows it by.
    function add(entryId) {
        if (!entryId) return;
        root.busyId = entryId;
        writer.command = [root.scriptPath, "add", entryId];
        writer.running = false;
        writer.running = true;
    }

    // Only for an app added here. One the system starts can be switched off
    // but not dropped, and the script refuses rather than pretending.
    function remove(entryId) {
        if (!entryId) return;
        root.busyId = entryId;
        writer.command = [root.scriptPath, "remove", entryId];
        writer.running = false;
        writer.running = true;
    }

    Process {
        id: listReader
        command: [root.scriptPath, "list"]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => listReader.buf += data + "\n" }
        onExited: {
            const next = [];
            for (const line of listReader.buf.split("\n")) {
                if (line.length === 0) continue;
                const parts = line.split("\t");
                if (parts.length < 4) continue;
                next.push({
                    id: parts[0],
                    source: parts[1],
                    enabled: parts[2] === "1",
                    name: parts[3],
                    icon: parts[4] ?? "",
                    description: (parts[5] ?? "").trim(),
                });
            }
            next.sort((a, b) => {
                if (a.source !== b.source) return a.source === "added" ? -1 : 1;
                return a.name.localeCompare(b.name);
            });
            root.entries = next;
            root.loaded = true;
        }
    }

    Process {
        id: writer
        onExited: {
            root.busyId = "";
            root.refresh();
        }
    }

    Component.onCompleted: refresh()
}
