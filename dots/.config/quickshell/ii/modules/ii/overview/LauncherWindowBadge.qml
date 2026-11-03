pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets

IconImage {
    id: root
    property bool centerIcon: true
    property real uiScale: 1
    property Item boundsItem: parent
    readonly property real inset: Math.min(6 * uiScale, boundsItem.width / 8, boundsItem.height / 8)
    anchors.horizontalCenter: centerIcon ? boundsItem.horizontalCenter : undefined
    anchors.verticalCenter: centerIcon ? boundsItem.verticalCenter : undefined
    anchors.left: !centerIcon ? boundsItem.left : undefined
    anchors.top: !centerIcon ? boundsItem.top : undefined
    anchors.margins: inset
    implicitSize: Math.max(0, Math.min(boundsItem.width, boundsItem.height) * 0.4)
    mipmap: true
}
