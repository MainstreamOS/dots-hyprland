import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool interactive: true
    property color contentColor: Appearance.barContent.colOnLayer1
    property bool borderless: Config.options.bar.borderless
    property bool showDate: Config.options.bar.verbose
    implicitWidth: rowLayout.implicitWidth
    implicitHeight: Appearance.sizes.baseBarHeight

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: 4

        StyledText {
            font.pixelSize: Appearance.font.pixelSize.large
            font.features: { "tnum": 1 }
            color: root.contentColor
            text: DateTime.time
        }

        StyledText {
            visible: root.showDate
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.contentColor
            text: "•"
        }

        StyledText {
            visible: root.showDate
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.contentColor
            text: DateTime.longDate
        }
    }

    MouseArea {
        id: mouseArea
        enabled: root.interactive
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow

        ClockWidgetPopup {
            hoverTarget: mouseArea
        }
    }
}
