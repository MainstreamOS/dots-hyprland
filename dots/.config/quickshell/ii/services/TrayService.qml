pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray

Singleton {
    id: root

    property bool smartTray: Config.options.tray.filterPassive
    property list<var> itemsInUserList: SystemTray.items.values.filter(i => (Config.options.tray.pinnedItems.includes(i.id) && (!smartTray || i.status !== Status.Passive)))
    property list<var> itemsNotInUserList: SystemTray.items.values.filter(i => (!Config.options.tray.pinnedItems.includes(i.id) && (!smartTray || i.status !== Status.Passive)))

    property bool invertPins: Config.options.tray.invertPinnedItems
    property list<var> pinnedItems: invertPins ? itemsNotInUserList : itemsInUserList
    property list<var> unpinnedItems: invertPins ? itemsInUserList : itemsNotInUserList

    // A few StatusNotifier clients only register when they first start. The
    // watcher is recreated with Quickshell, so those clients disappear after
    // a reload unless they are invited to register again. Quickshell's tray
    // API deliberately does not expose arbitrary session-bus calls; use the
    // system bus client directly here rather than maintaining a companion
    // shell script with its own parsing and retry policy.
    property var _registrationQueue: []

    function reregisterStatusNotifierItems() {
        if (sessionBusList.running)
            return;
        sessionBusList.running = true;
    }

    function _queueRegistrations(output) {
        let services;
        try {
            services = JSON.parse(output)
                .map(entry => String(entry.name || ""))
                .filter(name => /(^|\.)StatusNotifierItem(?:[-.]|$)/.test(name));
        } catch (error) {
            console.warn("[Tray] Could not read StatusNotifier services:", error);
            return;
        }

        _registrationQueue = [...new Set(services)];
        _registerNextItem();
    }

    function _registerNextItem() {
        if (registerItem.running || _registrationQueue.length === 0)
            return;
        const service = _registrationQueue.shift();
        registerItem.command = [
            "busctl", "--user", "call",
            "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
            "org.kde.StatusNotifierWatcher", "RegisterStatusNotifierItem",
            "s", service
        ];
        registerItem.running = true;
    }

    // The first pass handles already-running clients. The second catches
    // sandboxed or slow-starting clients that claim their bus name shortly
    // after Quickshell has come up.
    Timer {
        interval: 2500
        running: true
        onTriggered: root.reregisterStatusNotifierItems()
    }

    Timer {
        interval: 8000
        running: true
        onTriggered: root.reregisterStatusNotifierItems()
    }

    Process {
        id: sessionBusList
        command: ["busctl", "--user", "--no-pager", "--no-legend", "--json=short", "list"]
        stdout: StdioCollector {
            onStreamFinished: root._queueRegistrations(text)
        }
    }

    Process {
        id: registerItem
        onExited: root._registerNextItem()
    }

    function getTooltipForItem(item) {
        var result = item.tooltipTitle.length > 0 ? item.tooltipTitle
                : (item.title.length > 0 ? item.title : item.id);
        if (item.tooltipDescription.length > 0) result += " • " + item.tooltipDescription;
        if (Config.options.tray.showItemId) result += "\n[" + item.id + "]";
        return result;
    }

    // Pinning
    function pin(itemId) {
        var pins = Config.options.tray.pinnedItems;
        if (pins.includes(itemId)) return;
        Config.options.tray.pinnedItems.push(itemId);
    }
    function unpin(itemId) {
        Config.options.tray.pinnedItems = Config.options.tray.pinnedItems.filter(id => id !== itemId);
    }
    function isPinned(itemId) {
        for (var i = 0; i < root.pinnedItems.length; i++) {
            if (root.pinnedItems[i].id === itemId)
                return true;
        }
        return false;
    }

    function togglePin(itemId) {
        var pins = Config.options.tray.pinnedItems;
        if (pins.includes(itemId)) {
            unpin(itemId)
        } else {
            pin(itemId)
        }
    }

}
