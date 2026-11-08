import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Row {
    id: root
    property real uiScale: QsWindow.window?.uiScale ?? 1
    required property var icon
    required property var label
    spacing: 5 * root.uiScale

    MaterialSymbol {
        anchors.verticalCenter: parent.verticalCenter
        fill: 0
        font.weight: Font.DemiBold
        text: root.icon
        iconSize: Appearance.font.basePixelSize.large * root.uiScale
        color: Appearance.colors.colOnSurfaceVariant
    }

    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        font {
            weight: Font.DemiBold
            pixelSize: Appearance.font.basePixelSize.normal * root.uiScale
        }
        color: Appearance.colors.colOnSurfaceVariant
    }
}