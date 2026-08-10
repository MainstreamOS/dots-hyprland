import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions

/**
 * The editing menu for a text field, drawn the way the shell draws every
 * other context menu rather than the way the toolkit draws its own.
 *
 * A field showing dots instead of characters keeps its content out of the
 * clipboard: cut and copy stay disabled however much is selected.
 */
Popup {
    id: root

    required property Item target
    padding: 0

    readonly property bool secret: root.target.echoMode !== undefined
        && root.target.echoMode !== TextInput.Normal

    function openAt(px, py) {
        root.x = px
        root.y = py
        root.open()
    }

    background: Item {
        StyledRectangularShadow {
            target: menuBg
        }
        Rectangle {
            id: menuBg
            anchors.fill: parent
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
        }
    }

    component MenuRow: RippleButton {
        id: row
        property string symbol: ""
        property string label: ""
        Layout.fillWidth: true
        implicitHeight: 36
        implicitWidth: Math.max(rowContent.implicitWidth + 20, 160)
        buttonRadius: Appearance.rounding.small
        contentItem: RowLayout {
            id: rowContent
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 14
            }
            spacing: 8
            MaterialSymbol {
                text: row.symbol
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3onSurface
                opacity: row.enabled ? 1 : 0.4
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                text: row.label
                horizontalAlignment: Text.AlignLeft
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.m3colors.m3onSurface
                opacity: row.enabled ? 1 : 0.4
                elide: Text.ElideRight
            }
        }
    }

    contentItem: ColumnLayout {
        spacing: 0

        MenuRow {
            symbol: "content_cut"
            label: Translation.tr("Cut")
            enabled: !root.secret && !root.target.readOnly && root.target.selectedText.length > 0
            onClicked: {
                root.target.cut()
                root.close()
            }
        }
        MenuRow {
            symbol: "content_copy"
            label: Translation.tr("Copy")
            enabled: !root.secret && root.target.selectedText.length > 0
            onClicked: {
                root.target.copy()
                root.close()
            }
        }
        MenuRow {
            symbol: "content_paste"
            label: Translation.tr("Paste")
            enabled: !root.target.readOnly && root.target.canPaste
            onClicked: {
                root.target.paste()
                root.close()
            }
        }

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

        MenuRow {
            symbol: "select_all"
            label: Translation.tr("Select all")
            enabled: root.target.length > 0
            onClicked: {
                root.target.selectAll()
                root.close()
            }
        }
    }
}
