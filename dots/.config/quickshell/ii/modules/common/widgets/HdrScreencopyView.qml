import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// Tone-maps the capture to SDR while the screen runs in HDR.
ScreencopyView {
    layer.enabled: GlobalStates.hdrActive
    layer.effect: ShaderEffect {
        property real sdrPaperWhite: 203.0
        fragmentShader: "file://" + Quickshell.shellPath("shaders/pq_to_srgb.frag.qsb")
    }
}
