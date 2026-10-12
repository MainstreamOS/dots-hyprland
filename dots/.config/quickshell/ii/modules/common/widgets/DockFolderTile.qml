import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common

// A dock folder's face: up to four of its apps on a small tile.
Rectangle {
    id: root
    property real size: 34
    property var appIds: []
    property real rasterSize: size * 0.4

    implicitWidth: size
    implicitHeight: size
    radius: Appearance.rounding.small
    border.width: 1

    Grid {
        anchors.centerIn: parent
        columns: 2
        spacing: 1
        Repeater {
            model: root.appIds
            IconImage {
                required property var modelData
                source: Quickshell.iconPath(AppSearch.guessIcon(modelData), "image-missing")
                implicitSize: root.size * 0.4
                mipmap: true
                backer.sourceSize.width: root.rasterSize
                backer.sourceSize.height: root.rasterSize
            }
        }
    }
}
