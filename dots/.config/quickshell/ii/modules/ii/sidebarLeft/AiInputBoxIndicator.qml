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
    property color colBackground: Appearance.surfaces.raised
    property color colBackgroundHover: Appearance.surfaces.raisedHover

    readonly property real labelPadding: button.leftPadding + button.rightPadding + rowLayout.spacing * 2
        + (cIcon.visible ? cIcon.width : materialIcon.implicitWidth) + chevron.implicitWidth
    implicitHeight: 28
    implicitWidth: Math.ceil(Math.min(providerName.implicitWidth, Math.max(0, maxTextWidth)) + labelPadding)

    RippleButton {
        id: button
        anchors.fill: parent
        topPadding: 0
        bottomPadding: 0
        leftPadding: 8
        rightPadding: 8
        implicitHeight: 28
        implicitWidth: root.implicitWidth
        buttonRadius: 8
        colBackground: root.colBackground
        colBackgroundHover: root.colBackgroundHover
        clip: true
        Accessible.name: root.text
        onClicked: root.clicked()

        contentItem: RowLayout {
            id: rowLayout
            anchors.centerIn: parent
            spacing: 4

            CustomIcon {
                id: cIcon
                visible: root.customIcon !== ""
                width: 15
                height: 15
                source: root.customIcon
                colorize: true
                color: root.iconColor
                Layout.alignment: Qt.AlignVCenter
            }

            MaterialSymbol {
                id: materialIcon
                visible: !cIcon.visible
                Layout.alignment: Qt.AlignVCenter
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: root.icon
                iconSize: Appearance.font.pixelSize.normal
                color: root.iconColor
            }

            StyledText {
                id: providerName
                Layout.alignment: Qt.AlignVCenter
                verticalAlignment: Text.AlignVCenter
                Layout.maximumWidth: root.maxTextWidth
                Layout.preferredWidth: Math.min(implicitWidth, root.maxTextWidth)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root.textColor
                elide: Text.ElideRight
                text: root.text
                animateChange: true
            }

            MaterialSymbol {
                id: chevron
                Layout.alignment: Qt.AlignVCenter
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
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
