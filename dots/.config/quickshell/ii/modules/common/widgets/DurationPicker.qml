import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Picks how long a timer runs, in hours, minutes and seconds.
RowLayout {
    id: root

    property real uiScale: QsWindow.window?.uiScale ?? 1
    property var contentColors: Appearance.colors
    property real rowHeight: 26 * root.uiScale
    property real digitSize: 20 * root.uiScale
    // Matches the chosen tab of the timer tabs above it.
    property real cornerRadius: 8 * root.uiScale
    spacing: 2 * root.uiScale

    readonly property int hours: Math.floor(TimerService.countdownDuration / 3600)
    readonly property int minutes: Math.floor(TimerService.countdownDuration / 60) % 60
    readonly property int seconds: TimerService.countdownDuration % 60

    readonly property var hourNames: Array.from({ length: 24 }, (_, i) => String(i).padStart(2, "0"))
    readonly property var sixty: Array.from({ length: 60 }, (_, i) => String(i).padStart(2, "0"))

    TimeWheel {
        contentColors: root.contentColors
        rowHeight: root.rowHeight
        digitSize: root.digitSize
        cornerRadius: root.cornerRadius
        model: root.hourNames
        selected: Math.min(root.hours, 23)
        onChosen: index => TimerService.setCountdownTime(index * 3600 + root.minutes * 60 + root.seconds)
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
        model: root.sixty
        selected: root.minutes
        onChosen: index => TimerService.setCountdownTime(root.hours * 3600 + index * 60 + root.seconds)
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
        model: root.sixty
        selected: root.seconds
        onChosen: index => TimerService.setCountdownTime(root.hours * 3600 + root.minutes * 60 + index)
    }
}
