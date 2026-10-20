import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

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
    implicitHeight: Math.max(60, itemRow.implicitHeight + 20)
    // A row of the Dynamic Island's grouped lists: the row surface, the chosen one in its accent container.
    buttonRadius: 4
    colBackground: root.selected ? Appearance.colors.colPrimaryContainer
        : root.isFocused ? Appearance.colors.colLayer2Hover : Appearance.surfaces.row
    colBackgroundHover: root.selected ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover

    Accessible.name: root.name
    Accessible.description: root.description

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

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 34
            implicitHeight: 34
            radius: 10
            color: root.selected ? Appearance.colors.colPrimary : Appearance.surfaces.raised
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.iconName
                iconSize: 20
                color: root.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.name
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: root.selected ? Font.DemiBold : Font.Normal
                color: root.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.m3colors.m3onSurface
            }

            StyledText {
                Layout.fillWidth: true
                text: root.description
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.selected ? ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.18) : Appearance.colors.colSubtext
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
            }
        }

        MaterialSymbol {
            visible: root.selected
            Layout.alignment: Qt.AlignVCenter
            text: "check_circle"
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnPrimaryContainer
        }
    }
}
