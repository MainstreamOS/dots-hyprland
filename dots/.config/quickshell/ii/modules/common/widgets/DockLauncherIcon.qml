import QtQuick
import qs.modules.common

Item {
    id: root
    property real size: 20
    property color color: Appearance.dockContent.colOnLayer0
    property real dotSpacing: -1
    readonly property real resolvedSpacing: Math.max(0, Math.min(Math.max(0, (size - 3) / 2),
        dotSpacing >= 0 ? dotSpacing : Math.round(size / 5)))
    readonly property real dotSize: Math.max(0, (size - resolvedSpacing * 2) / 3)
    implicitWidth: size
    implicitHeight: size

    Grid {
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        columns: 3
        spacing: root.resolvedSpacing
        Repeater {
            model: 9
            Rectangle {
                width: root.dotSize
                height: width
                radius: width / 2
                color: root.color
            }
        }
    }
}
