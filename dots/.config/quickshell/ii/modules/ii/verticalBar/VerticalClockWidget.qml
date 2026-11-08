import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar as Bar

Item {
    id: root
    property real uiScale: QsWindow.window?.uiScale ?? 1
    property bool borderless: Config.options.bar.borderless
    implicitHeight: column.implicitHeight
    implicitWidth: Appearance.sizes.verticalBarWidth

    readonly property string dateTimeString: DateTime.time
    readonly property bool hasAmPm: dateTimeString.toLowerCase().includes("am") || dateTimeString.toLowerCase().includes("pm")

    Column {
        id: column
        anchors.centerIn: parent
        spacing: root.hasAmPm ? 6 : 0

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: -4 * root.uiScale

            Repeater {
                model: root.dateTimeString.split(/[: ]/)
                delegate: StyledText {
                    required property string modelData
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.pixelSize: {
                        if (modelData.match(/am|pm/i))
                            return Appearance.font.basePixelSize.smaller;
                        else
                            // Smaller "am"/"pm" text
                            return Appearance.font.basePixelSize.large;
                    }
                    color: Appearance.barContent.colOnLayer1
                    text: modelData.padStart(2, "0")
                }
            }
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            font.pixelSize: Appearance.font.basePixelSize.smallest * root.uiScale
            color: Appearance.barContent.colOnLayer1
            text: DateTime.shortDate
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: !Config.options.bar.tooltips.clickToShow

        Bar.ClockWidgetPopup {
            hoverTarget: mouseArea
        }
    }
}
