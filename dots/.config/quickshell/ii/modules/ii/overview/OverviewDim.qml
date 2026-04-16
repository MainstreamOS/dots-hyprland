import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: dimWindow

    WlrLayershell.namespace: "quickshell:overviewDim"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: Qt.rgba(0, 0, 0, 0.01)
    visible: GlobalStates.overviewOpen || contentFade.opacity > 0

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
