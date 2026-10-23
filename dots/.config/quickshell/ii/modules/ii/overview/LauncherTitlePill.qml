pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Rectangle {
    id: root
    required property string text
    property real uiScale: 1

    implicitWidth: label.implicitWidth + 20 * uiScale
    implicitHeight: 26 * uiScale
    radius: RoundedCorners.on ? height / 2 : 0
    color: Appearance.colors.colPrimary

    StyledText {
        id: label
        anchors.fill: parent
        anchors.leftMargin: 10 * root.uiScale
        anchors.rightMargin: 10 * root.uiScale
        text: root.text
        font.pixelSize: Appearance.font.pixelSize.small * root.uiScale
        color: Appearance.colors.colOnPrimary
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }
}
