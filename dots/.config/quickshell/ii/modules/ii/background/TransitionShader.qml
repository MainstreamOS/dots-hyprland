import QtQuick
import qs.modules.ii.background

// Blends two on-screen items with one of the shader transitions. Each
// item is captured through its own source, cropped to the rectangle the
// screen shows of it, so an oversized, panned wallpaper reads as what the
// user sees. The shaders name their samplers two ways, so both names are
// bound.
Item {
    id: root
    required property Item fromItem
    required property Item toItem
    property rect fromRect: Qt.rect(0, 0, fromItem.width, fromItem.height)
    property rect toRect: Qt.rect(0, 0, toItem.width, toItem.height)
    property string effect: "circle"
    property real progress: 0
    property real time: 0
    property bool hideSources: true

    ShaderEffectSource {
        id: fromSource
        sourceItem: root.fromItem
        sourceRect: root.fromRect
        hideSource: root.hideSources
        live: true
        visible: false
    }
    ShaderEffectSource {
        id: toSource
        sourceItem: root.toItem
        sourceRect: root.toRect
        hideSource: root.hideSources
        live: true
        visible: false
    }

    ShaderEffect {
        anchors.fill: parent
        property var fromImage: fromSource
        property var toImage: toSource
        property var source1: fromSource
        property var source2: toSource
        property real progress: root.progress
        property real time: root.time
        property real aspectX: root.height > 0 ? root.width / root.height : 1
        property real aspectY: 1.0
        property vector2d aspectRatio: Qt.vector2d(aspectX, aspectY)
        property vector2d origin: Qt.vector2d(0.5, 0.5)
        fragmentShader: TransitionEffects.shaderUrl(root.effect)
    }
}
