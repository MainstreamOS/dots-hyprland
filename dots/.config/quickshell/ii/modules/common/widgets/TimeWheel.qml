import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// One column of a time picker, turned by dragging, scrolling or clicking a neighbor.
Tumbler {
    id: root

    required property int selected
    property var contentColors: Appearance.colors
    property real rowHeight: 26
    property real digitSize: 20
    property real cornerRadius: 8
    signal chosen(int index)

    property bool ready: false
    Component.onCompleted: root.ready = true

    implicitWidth: root.digitSize * 2
    implicitHeight: root.rowHeight * root.visibleItemCount
    visibleItemCount: 3
    currentIndex: root.selected
    onCurrentIndexChanged: {
        if (root.ready && root.currentIndex !== root.selected)
            root.chosen(root.currentIndex);
    }

    background: Item {
        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: root.rowHeight
            radius: root.cornerRadius
            color: ColorUtils.transparentize(root.contentColors.colPrimary, 0.85)
        }
    }

    delegate: StyledText {
        required property int index
        required property var modelData
        text: modelData
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: root.digitSize
        font.weight: Font.DemiBold
        font.features: ({ "tnum": 1 })
        color: root.contentColors.colOnLayer1
        opacity: 1 - Math.abs(Tumbler.displacement) * 0.65

        TapHandler {
            onTapped: root.chosen(parent.index)
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const step = event.angleDelta.y > 0 ? -1 : 1;
            root.chosen((root.currentIndex + step + root.count) % root.count);
        }
    }
}
