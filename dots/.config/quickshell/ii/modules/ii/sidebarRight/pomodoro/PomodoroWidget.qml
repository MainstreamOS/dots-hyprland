import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property var tabButtonList: [
        {"name": Translation.tr("Pomodoro"), "icon": "search_activity"},
        {"name": Translation.tr("Stopwatch"), "icon": "timer"},
        {"name": Translation.tr("Timer"), "icon": "hourglass_empty"}
    ]

    // These are keybinds for stopwatch and pomodoro
    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) { // Switch tabs
            if (event.key === Qt.Key_PageDown) {
                swipeView.incrementCurrentIndex();
            } else if (event.key === Qt.Key_PageUp) {
                swipeView.decrementCurrentIndex();
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Space || event.key === Qt.Key_S) { // Pause/resume with Space or S
            if (tabBar.currentIndex === 0) {
                TimerService.togglePomodoro()
            } else if (tabBar.currentIndex === 1) {
                TimerService.toggleStopwatch()
            } else {
                TimerService.toggleCountdown()
            }
            event.accepted = true
        } else if (event.key === Qt.Key_R) { // Reset with R
            if (tabBar.currentIndex === 0) {
                TimerService.resetPomodoro()
            } else if (tabBar.currentIndex === 1) {
                TimerService.stopwatchReset()
            } else {
                TimerService.resetCountdown()
            }
            event.accepted = true
        } else if (event.key === Qt.Key_L) { // Record lap with L
            TimerService.stopwatchRecordLap()
            event.accepted = true
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 5
        anchors.rightMargin: 5
        spacing: 0

        SegmentedTabBar {
            id: tabBar
            // Level with the calendar's month header and the collapse button beside it.
            Layout.topMargin: 10
            implicitHeight: 30
            radius: 10
            iconSize: 16
            labelSize: 13
            model: root.tabButtonList
            running: [TimerService.pomodoroRunning, TimerService.stopwatchRunning, TimerService.countdownRunning]
            currentIndex: swipeView.currentIndex
            onActivated: index => swipeView.setCurrentIndex(index)
        }

        SwipeView {
            id: swipeView
            Layout.topMargin: 10
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            clip: true

            // Tabs
            PomodoroTimer {}
            Stopwatch {}
            CountdownTimer {}
        }
    }
}
