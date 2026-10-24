import qs
import qs.services
import qs.modules.common
import qs.modules.common.utils
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth

    PanelWindow {
        id: panelWindow
        visible: GlobalStates.sidebarRightOpen
        contentItem.visible: !GlobalStates.scrollOverviewOpen || GlobalStates.scrollOverviewSidebarPreviews
        mask: Region {
            width: GlobalStates.overviewOpen || GlobalStates.scrollOverviewOpen ? 0 : panelWindow.width
            height: panelWindow.height
        }

        function hide() {
            GlobalStates.sidebarRightOpen = false;
        }

        exclusiveZone: 0
        implicitWidth: sidebarWidth
        WlrLayershell.namespace: "quickshell:sidebarRight"
        WlrLayershell.keyboardFocus: GlobalStates.sidebarRightOpen && !GlobalStates.overviewOpen && !GlobalStates.scrollOverviewOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        readonly property bool onLeft: Appearance.sizes.sidebarRightEdge === "left"

        anchors {
            top: true
            left: panelWindow.onLeft
            right: !panelWindow.onLeft
            bottom: true
        }

        function syncFocusGrab() {
            if (visible && !GlobalStates.overviewOpen && !GlobalStates.scrollOverviewOpen) {
                GlobalFocusGrab.addDismissable(panelWindow);
            } else {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
        }
        onVisibleChanged: panelWindow.syncFocusGrab()
        Connections {
            target: GlobalStates
            function onOverviewOpenChanged() { Qt.callLater(panelWindow.syncFocusGrab); }
            function onScrollOverviewOpenChanged() { Qt.callLater(panelWindow.syncFocusGrab); }
        }
        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                if (!GlobalStates.overviewOpen && !GlobalStates.scrollOverviewOpen)
                    panelWindow.hide();
            }
        }

        Loader {
            id: sidebarContentLoader
            active: GlobalStates.sidebarRightOpen || Config?.options.sidebar.keepRightSidebarLoaded
            anchors {
                fill: parent
                margins: Appearance.sizes.hyprlandGapsOut
                // The window is wider than the card by the room the shadow
                // needs; that slack belongs on the side facing the desktop,
                // which swaps when the panel moves to the other edge.
                leftMargin: panelWindow.onLeft ? Appearance.sizes.hyprlandGapsOut : Appearance.sizes.elevationMargin
                rightMargin: panelWindow.onLeft ? Appearance.sizes.elevationMargin : Appearance.sizes.hyprlandGapsOut
            }
            width: sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
            height: parent.height - Appearance.sizes.hyprlandGapsOut * 2

            focus: GlobalStates.sidebarRightOpen
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    panelWindow.hide();
                }
            }

            sourceComponent: SidebarRightContent {}
        }
        SidebarPreviewSource {
            side: "right"
            namespace: "quickshell:sidebarRight"
            panel: panelWindow
            sourceItem: sidebarContentLoader
        }
    }

    IpcHandler {
        target: "sidebarRight"

        function toggle(): void {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }

        function close(): void {
            GlobalStates.sidebarRightOpen = false;
        }

        function open(): void {
            GlobalStates.sidebarRightOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }
    }
    GlobalShortcut {
        name: "sidebarRightOpen"
        description: "Opens right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = true;
        }
    }
    GlobalShortcut {
        name: "sidebarRightClose"
        description: "Closes right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = false;
        }
    }
}
