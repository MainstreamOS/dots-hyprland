import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    property string activeWindowAddress: `0x${activeWindow?.HyprlandToplevel?.address}`
    property bool focusingThisMonitor: HyprlandData.activeWorkspace?.monitor == monitor?.name
    property var biggestWindow: HyprlandData.biggestWindowForWorkspace(HyprlandData.monitors[root.monitor?.id]?.activeWorkspace.id)

    // Whether this instance is the variant drawn on a pill. The stock widget
    // sits bare on the strip; the pilled one is a separate entry in the layout
    // catalog, so which look the bar wears is the user's pick rather than ours.
    property bool pilled: false

    // Room between the title and the pill drawn around it, the same the tray
    // and the utility buttons keep, so the three read as the same kind of
    // thing. Zero when there is no pill: against the bare strip the title
    // keeps the exact footprint it has always had.
    readonly property real contentPadding: pilled ? 4 : 0

    // The width the title keeps whatever it says, matching the clock so the two
    // read as the same kind of thing. The lines inside elide into it: they can
    // only do that once something has settled how wide the widget is, and
    // asking for the text's own width answers "as wide as the title is long".
    readonly property real titleWidth: 270

    // Held rather than fitted. Sizing to the title makes the widget as wide as
    // whatever happens to be focused, so the bar rearranged itself around a
    // window being picked up or put down. A set width is the same on every
    // window: short names leave room to spare, long ones elide into it, and
    // nothing beside it ever moves.
    implicitWidth: root.titleWidth

    ColumnLayout {
        id: colLayout

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.contentPadding
        anchors.rightMargin: root.contentPadding
        spacing: -4

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            text: root.focusingThisMonitor && root.activeWindow?.activated && root.biggestWindow ? 
                root.activeWindow?.appId :
                (root.biggestWindow?.class) ?? Translation.tr("Desktop")

        }

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
            elide: Text.ElideRight
            text: root.focusingThisMonitor && root.activeWindow?.activated && root.biggestWindow ? 
                root.activeWindow?.title :
                (root.biggestWindow?.title) ?? `${Translation.tr("Workspace")} ${monitor?.activeWorkspace?.id ?? 1}`
        }

    }

}
