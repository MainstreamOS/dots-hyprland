pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets

IconImage {
    id: root
    property real uiScale: 1
    property Item boundsItem: parent
    readonly property real inset: Math.min(6 * uiScale, boundsItem.width / 8, boundsItem.height / 8)
    anchors.horizontalCenter: boundsItem.horizontalCenter
    anchors.bottom: boundsItem.bottom
    anchors.bottomMargin: inset
    implicitSize: Math.max(0, Math.min(26 * uiScale, boundsItem.width * 0.25, boundsItem.height * 0.25))
    mipmap: true
}
