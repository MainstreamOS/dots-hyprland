pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

/**
 * Names the user gives workspaces from the bar. They live in the shell's
 * state file rather than in Hyprland, which forgets a workspace's name
 * whenever the workspace empties; these are meant to stay until cleared.
 */
Singleton {
    id: root

    readonly property var names: Persistent.states.workspaces.names ?? ({})
    readonly property bool ready: Persistent.ready

    // Every named workspace in order, for the list the window title opens.
    readonly property var entries: Object.keys(root.names)
        .map(key => ({ id: Number(key), name: root.names[key] }))
        .filter(entry => root.canName(entry.id))
        .sort((a, b) => a.id - b.id)

    // Only the numbered workspaces a name can follow. Special workspaces and
    // the lock screen's temporary ones come and go under other ids.
    function canName(id) {
        return Number.isInteger(id) && id >= 1 && id <= 100;
    }

    function nameFor(id) {
        return root.names[String(id)] ?? "";
    }

    // An empty name clears it. The state file only saves when the property is
    // assigned, so every change builds a new object instead of editing this one.
    function setName(id, name) {
        if (!root.canName(id)) return;
        const next = Object.assign({}, root.names);
        const trimmed = (name ?? "").trim();
        if (trimmed.length > 0) next[String(id)] = trimmed;
        else delete next[String(id)];
        Persistent.states.workspaces.names = next;
    }
}
