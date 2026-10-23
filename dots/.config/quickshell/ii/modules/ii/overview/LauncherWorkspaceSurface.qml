pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common

Rectangle {
    id: root
    property real uiScale: 1
    property Item backdropSource: null
    property rect backdropRect: Qt.rect(0, 0, 1, 1)
    radius: RoundedCorners.on ? Appearance.rounding.dockBody * uiScale : 0
    color: "transparent"

    Item {
        anchors.fill: parent
        visible: Appearance.sizes.dockShowBackground
        layer.enabled: visible
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: root.width
                height: root.height
                radius: root.radius
            }
        }
        ShaderEffectSource {
            anchors.fill: parent
            opacity: 0.5
            sourceItem: parent.visible ? root.backdropSource : null
            sourceRect: root.backdropRect
            textureSize: Qt.size(Math.max(1, Math.ceil(sourceRect.width * Screen.devicePixelRatio)),
                Math.max(1, Math.ceil(sourceRect.height * Screen.devicePixelRatio)))
        }
        Rectangle {
            anchors.fill: parent
            color: Appearance.dockOwnShadow
        }
        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: Appearance.colors.colDockBackground
            border.width: 1.5 * root.uiScale
            border.color: Appearance.colors.colDockBackgroundBorder
        }
    }
}
