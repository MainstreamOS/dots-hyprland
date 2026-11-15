pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import qs

// Tone-maps the capture to SDR while the screen runs in HDR.
ScreencopyView {
    id: root

    property bool sharpenDownscale: false

    readonly property real outputScale: root.Window.window?.devicePixelRatio ?? Screen.devicePixelRatio
    readonly property real outputWidth: Math.max(1, Math.round(width * outputScale))
    readonly property real outputHeight: Math.max(1, Math.round(height * outputScale))
    readonly property real horizontalShrink: sourceSize.width / outputWidth
    readonly property real verticalShrink: sourceSize.height / outputHeight
    readonly property bool filterActive: sharpenDownscale && hasContent && width > 0 && height > 0
        && GraphicsInfo.api !== GraphicsInfo.Software && Math.max(horizontalShrink, verticalShrink) >= 1.5
    // The layer samples the capture once at half size on axes shrinking by at least 2:1.
    readonly property size filterTextureSize: Qt.size(
        Math.max(1, Math.ceil(sourceSize.width / (horizontalShrink >= 2 ? 2 : 1))),
        Math.max(1, Math.ceil(sourceSize.height / (verticalShrink >= 2 ? 2 : 1))))

    layer.enabled: GlobalStates.hdrActive || filterActive
    layer.textureSize: filterActive ? filterTextureSize : Qt.size(0, 0)
    layer.effect: ShaderEffect {
        property var source
        property real sdrPaperWhite: 203.0
        property real toneMapHdr: GlobalStates.hdrActive ? 1 : 0
        property point texelStep: Qt.point(1 / root.filterTextureSize.width, 1 / root.filterTextureSize.height)
        property point footprint: root.filterActive
            ? Qt.point(root.filterTextureSize.width / root.outputWidth, root.filterTextureSize.height / root.outputHeight)
            : Qt.point(0, 0)
        fragmentShader: "file://" + Quickshell.shellPath("shaders/window_preview.frag.qsb")
    }
}
