import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The overview's icon, running dot and hover highlight, used by both docks.
Rectangle {
    id: root
    property string appId: ""
    property bool running: false
    property bool applications: false
    property bool isFolder: false
    property var folderAppIds: []
    property string edge: "bottom"
    property bool hovered: iconHover.hovered
    property string tooltipText: applications ? Translation.tr("Show applications")
        : AppSearch.guessDesktopEntry(appId)?.name || appId

    implicitWidth: Appearance.overviewDock.buttonSize
    implicitHeight: implicitWidth
    // The overview clips its row to the button height, including the mark
    // tucked over the edge. Keep that same silhouette on the desktop dock.
    clip: true
    radius: Appearance.overviewDock.buttonRadius
    color: hovered ? Appearance.overviewDock.hover : "transparent"

    IconImage {
        anchors.centerIn: parent
        visible: !root.applications && !root.isFolder
        implicitSize: Appearance.overviewDock.iconSize
        source: root.applications || root.isFolder ? ""
            : Quickshell.iconPath(AppSearch.guessIcon(root.appId), "application-x-executable")
    }
    DockFolderTile {
        anchors.centerIn: parent
        visible: root.isFolder
        size: Appearance.overviewDock.iconSize
        appIds: root.isFolder ? root.folderAppIds : []
        color: Appearance.dockContent.colLayer1
        border.color: Appearance.dockContent.colLayer0BorderOnLayer1
    }
    Rectangle {
        visible: root.running && !root.applications && !root.isFolder
        width: 4; height: 4; radius: Appearance.rounding.full
        color: Appearance.overviewDock.foreground
        x: root.edge === "left" ? 1 - width
            : root.edge === "right" ? parent.width - 1 : (parent.width - width) / 2
        y: root.edge === "top" ? 1 - height
            : root.edge === "bottom" ? parent.height - 1 : (parent.height - height) / 2
    }
    Grid {
        anchors.centerIn: parent
        visible: root.applications
        columns: 3; spacing: 4
        Repeater {
            model: root.applications ? 9 : 0
            Rectangle { width: 4; height: 4; radius: Appearance.rounding.full; color: Appearance.overviewDock.foreground }
        }
    }
    HoverHandler { id: iconHover }
    StyledToolTip {
        extraVisibleCondition: root.tooltipText.length > 0
        text: root.tooltipText
    }
}
