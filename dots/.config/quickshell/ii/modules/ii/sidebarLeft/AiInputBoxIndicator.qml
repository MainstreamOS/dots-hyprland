import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    signal clicked()
    property string icon: "api"
    property string customIcon: ""
    property string text: ""
    property string tooltipText: ""
    property real maxTextWidth: 160
    property color textColor: Appearance.m3colors.m3onSurface
    property color iconColor: Appearance.m3colors.m3onSurface
    property color colBackground: Appearance.colors.colLayer2
    property color colBackgroundHover: Appearance.colors.colLayer2Hover

    implicitHeight: 30
    implicitWidth: button.implicitWidth

    RippleButton {
        id: button
        anchors.fill: parent
        implicitHeight: 30
        implicitWidth: rowLayout.implicitWidth + 8 * 2
        buttonRadius: Appearance.rounding.small
        colBackground: root.colBackground
        colBackgroundHover: root.colBackgroundHover
        clip: true
        onClicked: root.clicked()

        contentItem: RowLayout {
            id: rowLayout
            anchors.centerIn: parent
            spacing: 4

            CustomIcon {
                id: cIcon
                visible: root.customIcon !== ""
                width: 16
                height: 16
                source: root.customIcon
                colorize: true
                color: root.iconColor
                Layout.alignment: Qt.AlignVCenter
            }

            MaterialSymbol {
                visible: !cIcon.visible
                Layout.alignment: Qt.AlignVCenter
                text: root.icon
                iconSize: Appearance.font.pixelSize.normal
                color: root.iconColor
            }

            StyledText {
                id: providerName
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: root.maxTextWidth
                Layout.preferredWidth: Math.min(implicitWidth, root.maxTextWidth)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.textColor
                elide: Text.ElideRight
                text: root.text
                animateChange: true
            }

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "expand_more"
                iconSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }
    }

    StyledToolTip {
        extraVisibleCondition: false
        alternativeVisibleCondition: button.hovered
        text: root.tooltipText.length > 0 ? root.tooltipText : Translation.tr("Click to select AI model")
    }
}
