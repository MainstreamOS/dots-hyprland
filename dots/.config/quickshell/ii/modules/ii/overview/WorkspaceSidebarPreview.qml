pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.services

ClippingRectangle {
    id: root
    required property string screenName
    property real previewScale: 1
    property real originX: 0
    property real originY: 0
    // The rounded clip renders offscreen, so callers hide it while no sidebar is shown.
    readonly property bool hasPreviews: previews.count > 0
    signal activated()
    color: "transparent"

    Repeater {
        id: previews
        model: SidebarPreviews.entries.filter(preview => preview.screenName === root.screenName)
        delegate: Image {
            required property var modelData
            x: (modelData.x - root.originX) * root.previewScale
            y: (modelData.y - root.originY) * root.previewScale
            width: modelData.width * root.previewScale
            height: modelData.height * root.previewScale
            source: modelData.source
            retainWhileLoading: true
            MouseArea {
                anchors.fill: parent
                onClicked: root.activated()
            }
        }
    }
}
