import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// The rule between two groups of a context menu. It sits in a ColumnLayout of
// menu rows and insets itself from their edges, so the line reads as a break in
// the list rather than an edge of the card.
Item {
    Layout.fillWidth: true
    implicitHeight: 9

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 10
            rightMargin: 10
        }
        implicitHeight: 1
        color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
    }
}
