import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Row of the file sheet's folder and search result lists.
RippleButton {
    id: root

    required property var sheet
    required property int index
    property string path
    property string name
    property bool isDir
    property string detail
    property int detailElide: Text.ElideRight
    readonly property var iconInfo: root.sheet.fileIconInfo(root.name, root.isDir)

    width: root.ListView.view.width
    implicitHeight: 46
    buttonRadius: Appearance.rounding.small
    colBackground: (root.ListView.isCurrentItem && root.ListView.view.activeFocus)
        ? Appearance.colors.colSecondaryContainer
        : "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover

    contentItem: RowLayout {
        anchors {
            fill: parent
            leftMargin: 10
            rightMargin: 10
        }
        spacing: 10

        // File / Folder Icon or Image Thumbnail
        Item {
            implicitWidth: 28
            implicitHeight: 28
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                visible: Boolean(root.iconInfo.isImage)
                anchors.fill: parent
                radius: Appearance.rounding.verysmall
                clip: true
                color: "transparent"

                StyledImage {
                    anchors.fill: parent
                    source: root.iconInfo.isImage ? FileUtils.fileUrl(root.path) : ""
                    fillMode: Image.PreserveAspectCrop
                }
            }

            MaterialSymbol {
                visible: !root.iconInfo.isImage
                anchors.centerIn: parent
                text: root.iconInfo.icon
                iconSize: 22
                color: root.iconInfo.color
            }
        }

        // Name and detail line
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                text: root.name
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: root.isDir ? Font.Medium : Font.Normal
                color: Appearance.m3colors.m3onSurface
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: root.detail
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: root.detailElide
            }
        }

        // Right action icon
        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: root.isDir ? "chevron_right" : "add"
            iconSize: 18
            color: Appearance.colors.colSubtext
        }
    }

    onClicked: {
        root.ListView.view.currentIndex = root.index;
        root.sheet.handleItemSelection(root.path, root.isDir);
    }
}
