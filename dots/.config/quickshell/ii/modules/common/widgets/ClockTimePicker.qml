import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Picks the time of day a timer goes off, with AM and PM on a 12-hour clock.
RowLayout {
    id: root

    property real uiScale: QsWindow.window?.uiScale ?? 1
    readonly property QtObject fontSizes: Appearance.font.sizesFor(QsWindow.window)
    property var contentColors: Appearance.colors
    property real rowHeight: 26 * root.uiScale
    property real digitSize: 20 * root.uiScale
    // Matches the chosen tab of the timer tabs above it.
    property real cornerRadius: 8 * root.uiScale
    spacing: 2 * root.uiScale

    readonly property bool twelveHour: /ap/i.test(Config.options.time.format)
    readonly property int hour: TimerService.countdownEndParts.hour
    readonly property int minute: TimerService.countdownEndParts.minute
    readonly property bool afternoon: root.hour >= 12

    readonly property var hours12: ["12", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11"]
    readonly property var hours24: Array.from({ length: 24 }, (_, i) => String(i).padStart(2, "0"))
    readonly property var minutes: Array.from({ length: 60 }, (_, i) => String(i).padStart(2, "0"))

    TimeWheel {
        contentColors: root.contentColors
        rowHeight: root.rowHeight
        digitSize: root.digitSize
        cornerRadius: root.cornerRadius
        model: root.twelveHour ? root.hours12 : root.hours24
        selected: root.twelveHour ? root.hour % 12 : root.hour
        onChosen: index => TimerService.setCountdownEndTime(root.twelveHour && root.afternoon ? index + 12 : index, root.minute)
    }

    StyledText {
        text: ":"
        font.pixelSize: root.digitSize
        font.weight: Font.DemiBold
        color: root.contentColors.colOnLayer1
    }

    TimeWheel {
        contentColors: root.contentColors
        rowHeight: root.rowHeight
        digitSize: root.digitSize
        cornerRadius: root.cornerRadius
        model: root.minutes
        selected: root.minute
        onChosen: index => TimerService.setCountdownEndTime(root.hour, index)
    }

    ColumnLayout {
        visible: root.twelveHour
        Layout.leftMargin: 4 * root.uiScale
        spacing: 2 * root.uiScale

        Repeater {
            model: [
                { label: "AM", afternoon: false },
                { label: "PM", afternoon: true }
            ]
            delegate: RippleButton {
                id: periodButton
                required property var modelData
                readonly property bool chosen: root.afternoon === modelData.afternoon
                implicitWidth: root.digitSize * 2
                implicitHeight: root.rowHeight
                topPadding: 0
                bottomPadding: 0
                buttonRadius: root.cornerRadius
                colBackground: chosen ? root.contentColors.colPrimary : "transparent"
                colBackgroundHover: chosen ? root.contentColors.colPrimaryHover : root.contentColors.colLayer1Hover
                colRipple: chosen ? root.contentColors.colPrimaryActive : root.contentColors.colLayer1Active
                onClicked: TimerService.setCountdownEndTime(root.hour % 12 + (modelData.afternoon ? 12 : 0), root.minute)

                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: periodButton.modelData.label
                    font.pixelSize: root.fontSizes.small * root.uiScale
                    font.weight: Font.DemiBold
                    color: periodButton.chosen ? root.contentColors.colOnPrimary : root.contentColors.colOnLayer1
                }
            }
        }
    }
}
