pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    readonly property var ids: Persistent.states.launcher.recentApps
    readonly property string activeAppId: ToplevelManager.activeToplevel
        ? TaskbarApps.resolveAppId(ToplevelManager.activeToplevel) : ""
    onActiveAppIdChanged: root.rememberActive()

    // Seed the first view from the compositor's focus history. Closed apps
    // remain in the saved list after they have been used with the shell running.
    readonly property var runningIds: {
        AppSearch.list;
        return Array.from(ToplevelManager.toplevels.values)
            .sort((a, b) => (HyprlandData.clientForToplevel(a)?.focusHistoryID ?? Infinity)
                - (HyprlandData.clientForToplevel(b)?.focusHistoryID ?? Infinity))
            .map(toplevel => TaskbarApps.resolveAppId(toplevel));
    }
    readonly property var visibleEntries: new Map(AppSearch.list.filter(app => !app.noDisplay).map(app => [app.id, app]))
    readonly property var apps: Array.from(new Set(root.ids.concat(root.runningIds)))
        .map(id => root.visibleEntries.get(id)).filter(Boolean)

    function rememberActive() {
        if (!Persistent.ready || !root.activeAppId) return;
        const app = root.visibleEntries.get(root.activeAppId);
        if (!app || root.ids[0] === app.id) return;
        Persistent.states.launcher.recentApps = [app.id]
            .concat(root.ids.filter(id => id !== app.id)).slice(0, 64);
    }

    Component.onCompleted: root.rememberActive()
    Connections {
        target: Persistent
        function onReadyChanged() { root.rememberActive(); }
    }
    Connections {
        target: AppSearch
        function onListChanged() { root.rememberActive(); }
    }
}
