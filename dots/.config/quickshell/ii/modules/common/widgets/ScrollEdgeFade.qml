import QtQuick
import qs.modules.common
import qs.modules.common.functions

Item {
    id: root
    z: 99
    required property Item target
    property real fadeSize: Appearance.m3colors.darkmode ? 40 : 20
    property color color: Appearance.colors.colLayer1Base
    property bool vertical: true
    // A list with runway below its last item says where its content really ends.
    property bool atEnd: root.vertical ? root.target.atYEnd : root.target.atXEnd

    anchors.fill: target

    EndGradient {
        anchors {
            top: parent.top
            left: parent.left
            right: vertical ? parent.right : undefined
            bottom: vertical ? undefined : parent.bottom
        }
        shown: !(root.vertical ? root.target.atYBeginning : root.target.atXBeginning)
    }

    EndGradient {
        anchors {
            bottom: parent.bottom
            right: parent.right
            left: vertical ? parent.left : undefined
            top: vertical ? undefined : parent.top
        }
        shown: !root.atEnd
        rotation: 180
    }

    component EndGradient: Rectangle {
        required property bool shown
        height: vertical ? root.fadeSize : parent.height
        width: vertical ? parent.width : root.fadeSize

        opacity: shown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        gradient: Gradient {
            orientation: root.vertical ? Gradient.Vertical : Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: root.color
            }
            GradientStop {
                position: 1.0
                color: ColorUtils.transparentize(root.color)
            }
        }
    }
}
