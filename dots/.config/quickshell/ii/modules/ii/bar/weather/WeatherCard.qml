import Quickshell
import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    property real uiScale: QsWindow.window?.uiScale ?? 1
    radius: Appearance.rounding.small * root.uiScale
    color: Appearance.colors.colSurfaceContainerHigh
    implicitWidth: columnLayout.implicitWidth + 14 * 2 * root.uiScale
    implicitHeight: columnLayout.implicitHeight + 14 * 2 * root.uiScale
    Layout.fillWidth: parent

    property alias title: title.text
    property alias value: value.text
    property alias symbol: symbol.text

    ColumnLayout {
        id: columnLayout
        anchors.fill: parent
        spacing: -10 * root.uiScale
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            MaterialSymbol {
                id: symbol
                fill: 0
                iconSize: Appearance.font.basePixelSize.normal * root.uiScale
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                id: title
                font.pixelSize: Appearance.font.basePixelSize.smaller * root.uiScale
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
        StyledText {
            id: value
            Layout.alignment: Qt.AlignHCenter
            font.pixelSize: Appearance.font.basePixelSize.small * root.uiScale
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
}
