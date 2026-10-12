import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Text field used by the chat tab's sheets for search, filter and name input.
Rectangle {
    id: root

    property string icon: "search"
    property string placeholder
    property real fontPixelSize: Appearance.font.pixelSize.small
    property bool clearable: false
    property alias text: textInput.text
    readonly property alias input: textInput

    signal fieldKeyPressed(var event)

    function selectAll(): void {
        textInput.selectAll();
    }

    implicitHeight: 38
    radius: Appearance.rounding.small
    color: Appearance.colors.colLayer1
    border.width: textInput.activeFocus ? 2 : 1
    border.color: textInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 6

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: root.icon
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colSubtext
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledText {
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                visible: textInput.text.length === 0 && !textInput.inputMethodComposing
                text: root.placeholder
                font.pixelSize: root.fontPixelSize
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }

            StyledTextInput {
                id: textInput
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
                clip: true
                font.pixelSize: root.fontPixelSize
                color: Appearance.m3colors.m3onSurface
                Keys.onPressed: event => root.fieldKeyPressed(event)
            }
        }

        RippleButton {
            visible: root.clearable && textInput.text.length > 0
            implicitWidth: 24
            implicitHeight: 24
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "clear"
                iconSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            onClicked: {
                textInput.text = "";
                textInput.forceActiveFocus();
            }
        }
    }
}
