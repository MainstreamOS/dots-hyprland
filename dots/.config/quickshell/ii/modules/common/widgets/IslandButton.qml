import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RippleButton {
    id: root
    property var contentColors: Appearance.islandContent
    property string symbol: ""
    property string subtitle: ""
    property bool compact: false
    readonly property bool iconOnly: text.length === 0 && subtitle.length === 0
    readonly property color ink: highlighted ? Appearance.colors.colOnPrimaryContainer : root.contentColors.colOnLayer1

    implicitHeight: compact ? 42 : subtitle ? 58 : 34
    implicitWidth: iconOnly ? implicitHeight : subtitle ? 170 : Math.max(implicitHeight, (buttonContent ? buttonContent.implicitWidth : 0) + leftPadding + rightPadding)
    topPadding: 0
    bottomPadding: 0
    leftPadding: iconOnly ? 0 : (compact ? 10 : 12)
    rightPadding: iconOnly ? 0 : (compact ? 10 : 12)
    buttonRadius: subtitle ? 12 : compact ? 9 : 10
    colBackground: highlighted ? Appearance.colors.colPrimaryContainer : Appearance.surfaces.raised
    colBackgroundHover: highlighted ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
    colRipple: highlighted ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active

    contentItem: Item {
        implicitWidth: root.iconOnly ? iconDisplay.implicitWidth : buttonContent.implicitWidth
        implicitHeight: root.iconOnly ? iconDisplay.implicitHeight : buttonContent.implicitHeight

        MaterialSymbol {
            id: iconDisplay
            anchors.centerIn: parent
            visible: root.iconOnly
            text: root.symbol
            iconSize: root.compact ? 16 : 18
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: root.ink
        }

        RowLayout {
            id: buttonContent
            anchors.centerIn: parent
            visible: !root.iconOnly
            spacing: root.compact ? 6 : 7

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                visible: root.symbol.length > 0
                text: root.symbol
                iconSize: root.compact ? 16 : 18
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: root.ink
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                visible: root.text.length > 0 || root.subtitle.length > 0
                spacing: 1

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    text: root.text
                    elide: Text.ElideRight
                    color: root.ink
                    font.pixelSize: root.compact ? 11 : 12
                    font.weight: Font.DemiBold
                    verticalAlignment: Text.AlignVCenter
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.subtitle
                    visible: text.length > 0
                    color: root.highlighted ? Appearance.colors.colOnPrimaryContainer : root.contentColors.colSubtext
                    font.pixelSize: root.compact ? 10 : 11
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    Layout.maximumWidth: root.width - 48
                }
            }
        }
    }
}
