import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Option row of the Reasoning and Execution mode sheets.
RippleButton {
    id: root

    property string iconName
    property string name
    property string description
    property bool selected: false
    property bool sheetShown: false
    readonly property bool isFocused: root.ListView.isCurrentItem && root.sheetShown

    width: root.ListView.view.width
    implicitHeight: itemRow.implicitHeight + 16
    buttonRadius: Appearance.rounding.small
    colBackground: (root.selected || root.isFocused) ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
    colBackgroundHover: (root.selected || root.isFocused) ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover

    contentItem: RowLayout {
        id: itemRow
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 12
            rightMargin: 12
        }
        spacing: 12

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: root.iconName
            iconSize: Appearance.font.pixelSize.larger
            color: root.selected ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                text: root.name
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: root.selected ? Font.DemiBold : Font.Normal
                color: root.selected ? Appearance.colors.colPrimary : Appearance.m3colors.m3onSurface
            }

            StyledText {
                Layout.fillWidth: true
                text: root.description
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
            }
        }

        MaterialSymbol {
            visible: root.selected
            Layout.alignment: Qt.AlignVCenter
            text: "check"
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colPrimary
        }
    }
}
