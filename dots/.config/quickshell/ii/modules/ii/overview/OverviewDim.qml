import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: dimWindow

    WlrLayershell.namespace: "quickshell:overviewDim"
    // Use Overlay layer (not Top) so the dim stays visible during fullscreen
    // apps. See the matching comment in Overview.qml for the full reasoning.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: Qt.rgba(0, 0, 0, 0.01)
    // Surface lifecycle — see Overview.qml for the full reasoning. The dim
    // layer is click-through by design (empty mask), so keeping it visible
    // permanently has no input-side effect; contentFade.opacity already
    // makes it visually invisible while the overview is closed.
    visible: (Config.options.overview.keepSurfaceAlive ?? true)
        || GlobalStates.overviewOpen
        || contentFade.opacity > 0

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Purely visual — all input passes through
    mask: Region {}

    Item {
        id: contentFade
        anchors.fill: parent
        opacity: GlobalStates.overviewOpen ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0Base
            opacity: 0.90
        }
    }
}
