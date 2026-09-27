import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: notificationPopup

    PanelWindow {
        id: root
        visible: (Notifications.popupList.length > 0) && !GlobalStates.screenLocked
        screen: Quickshell.screens.find(s => Config.options.notifications.forceMonitor.enable ? s.name === Config.options.notifications.forceMonitor.name : s.name === Hyprland.focusedMonitor?.name) ?? null

        readonly property string position: Appearance.sizes.notificationPosition
        readonly property bool atBottom: root.position.startsWith("bottom")
        readonly property string side: root.position.slice(root.position.indexOf("_") + 1) // left | center | right
        readonly property real edgeInset: 4

        // Held while the pointer is over the stack, so a sidebar closing under
        // a click does not pull the card out from under it.
        property real sidebarCover: 0
        Binding on sidebarCover {
            when: !stackHover.hovered
            value: GlobalStates.sidebarLeftCover
            restoreMode: Binding.RestoreNone
        }

        // Room kept for surfaces that show up on an edge without reserving it.
        // Pinned ones reserve an exclusive zone, which the compositor already
        // keeps this window out of.
        function roomOn(edge) {
            const bar = Config.options.bar;
            const barRoom = Appearance.sizes.barShown && Appearance.sizes.barEdge === edge
                && bar.autoHide.enable && !bar.autoHide.pushWindows
                ? (bar.vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight) : 0;
            const dockRoom = Config.options.dock.enable && !GlobalStates.dockPinned
                && Appearance.sizes.dockEdge === edge
                ? Appearance.sizes.dockHeight + Appearance.sizes.hyprlandGapsOut : 0;
            const sidebarRoom = Appearance.sizes.sidebarLeftEdge === edge ? root.sidebarCover : 0;
            return Math.max(barRoom, dockRoom, sidebarRoom);
        }

        WlrLayershell.namespace: "quickshell:notificationPopup"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0

        // Full height on every spot, so a stack taller than the screen still
        // scrolls; top or bottom is settled by the list inside. Anchored to
        // neither side, the compositor centers the column.
        anchors {
            top: true
            bottom: true
            left: root.side === "left"
            right: root.side === "right"
        }
        margins {
            top: root.roomOn("top")
            bottom: root.roomOn("bottom")
            left: root.roomOn("left")
            right: root.roomOn("right")
        }

        // A bottom-up list keeps its contentItem below the cards, so the input
        // region follows the stack itself.
        mask: Region {
            item: stackArea
        }

        color: "transparent"
        implicitWidth: Appearance.sizes.notificationPopupWidth

        NotificationListView {
            id: listview
            anchors {
                top: parent.top
                bottom: parent.bottom
                topMargin: root.atBottom ? 0 : root.edgeInset
                bottomMargin: root.atBottom ? root.edgeInset : 0
            }
            // The shadow's room goes on the side away from the screen edge.
            x: root.side === "left" ? root.edgeInset
                : root.side === "right" ? parent.width - width - root.edgeInset
                : (parent.width - width) / 2
            implicitWidth: parent.width - Appearance.sizes.elevationMargin * 2
            popup: true
            verticalLayoutDirection: root.atBottom ? ListView.BottomToTop : ListView.TopToBottom
            removeDirection: root.side === "left" ? -1 : root.side === "right" ? 1 : 0

            HoverHandler {
                id: stackHover
            }
        }

        Item {
            id: stackArea
            x: listview.x
            width: listview.width
            height: Math.min(listview.contentHeight, listview.height)
            y: root.atBottom ? listview.y + listview.height - height : listview.y
        }
    }
}
