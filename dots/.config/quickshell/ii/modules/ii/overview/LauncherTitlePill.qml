pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

Rectangle {
    id: root
    required property string text
    property real uiScale: 1
    readonly property QtObject fontSizes: Appearance.font.sizesFor(QsWindow.window)
    // On a panel, where the accent would compete with what the panel holds.
    property bool quiet: false

    implicitWidth: label.implicitWidth + 20 * uiScale
    implicitHeight: 26 * uiScale
    radius: RoundedCorners.on ? height / 2 : 0
    color: quiet ? Appearance.launcherPanelBackground : Appearance.colors.colPrimary

    StyledText {
        id: label
        anchors.fill: parent
        anchors.leftMargin: 10 * root.uiScale
        anchors.rightMargin: 10 * root.uiScale
        text: root.text
        font.pixelSize: root.fontSizes.small * root.uiScale
        color: root.quiet ? Appearance.launcherPanelContent.colOnLayer0 : Appearance.colors.colOnPrimary
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }
}
