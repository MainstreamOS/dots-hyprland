import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

// Shared dropdown popup for the monitor settings rows: a scrollable option
// list that caps at maxVisibleRows, keeps the current option in view when it
// opens, and shows the scrollbar whenever the list overflows. Positioned
// relative to its parent row.
Popup {
    id: root

    property var options: []
    property int currentIndex: -1
    property int maxVisibleRows: 6
    readonly property int rowHeight: 36
    signal selected(var modelData, int index)

    y: (parent?.height ?? 0) + 4
    width: parent?.width ?? 0
    padding: 8
    enter: Transition { PropertyAnimation { properties: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
    exit:  Transition { PropertyAnimation { properties: "opacity"; to: 0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

    background: Item {
        StyledRectangularShadow { target: bg }
        Rectangle { id: bg; anchors.fill: parent; radius: Appearance.rounding.normal; color: Appearance.m3colors.m3surfaceContainerHigh }
    }

    contentItem: Loader {
        active: root.visible
        sourceComponent: ListView {
            id: listView
            implicitHeight: Math.min(contentHeight, root.maxVisibleRows * root.rowHeight + (root.maxVisibleRows - 1) * spacing)
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.options
            Component.onCompleted: Qt.callLater(() => {
                if (root.currentIndex >= 0)
                    listView.positionViewAtIndex(root.currentIndex, ListView.Contain)
            })
            ScrollBar.vertical: StyledScrollBar {
                policy: (root.options?.length ?? 0) > root.maxVisibleRows ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
            }
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: ListView.view.width
                height: root.rowHeight
                radius: Appearance.rounding.small
                readonly property bool isCurrent: index === root.currentIndex
                color: itemArea.containsMouse
                    ? (isCurrent ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover)
                    : (isCurrent ? Appearance.colors.colSecondaryContainer : "transparent")
                Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                StyledText {
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                    text: modelData.label
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                }
                MouseArea {
                    id: itemArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.selected(modelData, index);
                        root.close();
                    }
                }
            }
        }
    }
}
