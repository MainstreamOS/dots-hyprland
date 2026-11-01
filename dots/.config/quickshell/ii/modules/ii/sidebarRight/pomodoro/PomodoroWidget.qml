import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property var tabButtonList: [
        {"name": Translation.tr("Timer"), "icon": "hourglass_empty"},
        {"name": Translation.tr("Focus"), "icon": "search_activity"},
        {"name": Translation.tr("Stopwatch"), "icon": "timer"}
    ]
    readonly property var tabKeys: ["timer", "focus", "stopwatch"]
    readonly property int savedTab: Math.max(0, root.tabKeys.indexOf(Persistent.states.timer.tab))
    onSavedTabChanged: if (swipeView.currentIndex !== root.savedTab) swipeView.setCurrentIndex(root.savedTab)

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
                TimerService.toggleCountdown()
            } else if (tabBar.currentIndex === 1) {
                TimerService.togglePomodoro()
            } else {
                TimerService.toggleStopwatch()
            }
            event.accepted = true
        } else if (event.key === Qt.Key_R) { // Reset with R
            if (tabBar.currentIndex === 0) {
                TimerService.resetCountdown()
            } else if (tabBar.currentIndex === 1) {
                TimerService.resetPomodoro()
            } else {
                TimerService.stopwatchReset()
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
            running: [TimerService.countdownRunning, TimerService.pomodoroRunning, TimerService.stopwatchRunning]
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
            currentIndex: root.savedTab
            onCurrentIndexChanged: Persistent.states.timer.tab = root.tabKeys[currentIndex]

            // Tabs
            CountdownTimer {}
            PomodoroTimer {}
            Stopwatch {}
        }
    }
}
