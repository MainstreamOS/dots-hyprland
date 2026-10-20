import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// A segmented switch in the Dynamic Island's style: segments on its row surface, the chosen one in the
// highlight accent with its icon and label. Items are {name, icon}; a true entry in `running` dots
// that segment while another one is shown, kept apart so the segments are not rebuilt when it
// changes. The view it switches owns the index: bind currentIndex to it and move it from activated,
// which a click or a wheel step over the switch sends.
Rectangle {
    id: root
    property var model: []
    property var running: []
    property int currentIndex: 0
    // The ink for the surface it sits on, such as Appearance.islandContent on the Island.
    property var contentColors: Appearance.colors
    // The Island's sizes; a larger switch scales its corners with them.
    property real iconSize: 13
    property real labelSize: 11
    signal activated(int index)

    Layout.fillWidth: true
    implicitHeight: 28
    radius: 8
    color: Appearance.surfaces.row

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const next = root.currentIndex + (event.angleDelta.y < 0 ? 1 : (event.angleDelta.y > 0 ? -1 : 0));
            if (next !== root.currentIndex && next >= 0 && next < root.model.length)
                root.activated(next);
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 2
        spacing: 2

        Repeater {
            model: root.model
            RippleButton {
                id: segment
                required property var modelData
                required property int index
                readonly property bool chosen: root.currentIndex === index
                readonly property color ink: chosen ? Appearance.colors.colOnPrimaryContainer : root.contentColors.colSubtext
                Layout.fillWidth: true
                Layout.fillHeight: true
                buttonRadius: root.radius - 2
                colBackground: chosen ? Appearance.colors.colPrimaryContainer : "transparent"
                colBackgroundHover: chosen ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                colRipple: chosen ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                onClicked: root.activated(index)

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        text: segment.modelData.icon ?? ""
                        iconSize: root.iconSize
                        color: segment.ink
                    }
                    StyledText {
                        text: segment.modelData.name ?? ""
                        font.pixelSize: root.labelSize
                        font.weight: segment.chosen ? Font.DemiBold : Font.Medium
                        color: segment.ink
                    }
                    Rectangle {
                        visible: (root.running[segment.index] ?? false) && !segment.chosen
                        width: 5; height: 5; radius: 2.5
                        color: root.contentColors.colPrimary
                    }
                }
            }
        }
    }
}
