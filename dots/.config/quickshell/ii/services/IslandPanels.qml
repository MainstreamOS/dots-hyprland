pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

Singleton {
    id: root
    readonly property var catalog: [
        {id: "system", name: Translation.tr("System"), icon: "tune"},
        {id: "media", name: Translation.tr("Media"), icon: "music_note"},
        {id: "notifications", name: Translation.tr("Notifications"), icon: "notifications"},
        {id: "weather", name: Translation.tr("Weather"), icon: "partly_cloudy_day"},
        {id: "timers", name: Translation.tr("Timers"), icon: "hourglass_top"},
        {id: "calendar", name: Translation.tr("Calendar & tasks"), icon: "calendar_month"},
        {id: "call", name: Translation.tr("Calls"), icon: "call"},
        {id: "text", name: Translation.tr("Messages"), icon: "chat_bubble"},
        {id: "resources", name: Translation.tr("Resources & Utility"), icon: "analytics"},
        {id: "localsend", name: Translation.tr("LocalSend"), icon: "share_reviews"}
    ]
    // Ignore unknown/duplicate ids and append panels added after a saved order.
    readonly property var order: [...Config.options.bar.island.panelOrder, ...Config.defaultIslandPanels]
        .filter((id, index, ids) => id !== "localsend" && Config.defaultIslandPanels.includes(id) && ids.indexOf(id) === index).concat(["localsend"])
    // Hidden panels keep the end of the list, in the order they were hidden.
    readonly property var shownOrder: order.filter(id => id !== "localsend" && enabled(id))
    readonly property var hiddenOrder: order.filter(id => id !== "localsend" && !enabled(id))
    function enabled(id) { return Config.defaultIslandPanels.includes(id) && !Config.options.bar.island.disabledPanels.includes(id); }
    function entry(id) { return catalog.find(panel => panel.id === id); }
    function setEnabled(id, on) {
        if (enabled(id) === on) return;
        const disabled = Config.options.bar.island.disabledPanels.filter(panel => panel !== id);
        // Taken out of the order first, so it lands at the end of whichever group it joins.
        const shown = shownOrder.filter(panel => panel !== id);
        const hidden = hiddenOrder.filter(panel => panel !== id);
        if (id !== "localsend")
            Config.options.bar.island.panelOrder = on ? [...shown, id, ...hidden] : [...shown, ...hidden, id];
        Config.options.bar.island.disabledPanels = on ? disabled : disabled.concat([id]);
    }
    function move(id, delta) {
        const ids = shownOrder.slice();
        const from = ids.indexOf(id), to = from + delta;
        if (from < 0 || to < 0 || to >= ids.length) return;
        ids.splice(to, 0, ids.splice(from, 1)[0]);
        Config.options.bar.island.panelOrder = ids.concat(hiddenOrder);
    }
}
