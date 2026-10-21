import QtQuick
import qs.modules.common

Item {
    id: root
    property real size: 20
    property color color: Appearance.dockContent.colOnLayer0
    readonly property real dotSpacing: Math.round(size / 5)
    readonly property real dotSize: (size - dotSpacing * 2) / 3
    implicitWidth: size
    implicitHeight: size

    Grid {
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        columns: 3
        spacing: root.dotSpacing
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
