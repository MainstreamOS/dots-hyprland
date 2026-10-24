import QtQuick
import Quickshell
import qs
import qs.services

// One small in-memory capture per open sidebar, shared by every launcher workspace;
// capturing the live item keeps its page and draft without starting a second sidebar.
Scope {
    id: root
    required property string side
    required property string namespace
    required property var panel
    required property Item sourceItem
    property var grab: null
    property bool pending: false
    property int generation: 0
    readonly property bool active: GlobalStates.overviewOpen && root.panel.visible
    readonly property var layer: Object.values(HyprlandData.layers[root.panel.screen?.name]?.levels ?? {})
        .reduce((layers, level) => layers.concat(level), []).find(layer => layer.namespace === root.namespace) ?? null
    readonly property var monitor: HyprlandData.monitors.find(m => m.name === root.panel.screen?.name)
    readonly property var preview: {
        if (!root.grab || !root.panel.visible || !root.layer || !root.monitor)
            return null;
        const point = root.sourceItem.mapToItem(root.panel.contentItem, 0, 0);
        return {source: root.grab.url, screenName: root.panel.screen.name,
            x: root.layer.x - root.monitor.x + point.x,
            y: root.layer.y - root.monitor.y + point.y,
            width: root.sourceItem.width, height: root.sourceItem.height};
    }

    Binding {
        target: SidebarPreviews
        property: root.side
        value: root.preview
        restoreMode: Binding.RestoreNone
    }

    function capture(): void {
        if (!root.active || root.pending || root.sourceItem.width <= 0 || root.sourceItem.height <= 0)
            return;
        const generation = root.generation;
        const scale = Math.min(1, 768 / root.sourceItem.height);
        root.pending = root.sourceItem.grabToImage(result => {
            root.pending = false;
            if (root.active && generation === root.generation)
                root.grab = result;
        }, Qt.size(Math.max(1, Math.ceil(root.sourceItem.width * scale)),
            Math.max(1, Math.ceil(root.sourceItem.height * scale))));
    }
    onActiveChanged: {
        root.generation++;
        if (root.active) {
            HyprlandData.updateLayers();
            Qt.callLater(root.capture);
        }
        // Keep the last frame through the launcher's closing fade.
        if (!root.panel.visible)
            root.grab = null;
    }
    Timer {
        interval: 500
        repeat: true
        running: root.active
        onTriggered: root.capture()
    }
    Component.onDestruction: SidebarPreviews[root.side] = null
}
