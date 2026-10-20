import qs
import qs.services
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import "calendar_layout.js" as CalendarLayout
import QtQuick
import QtQuick.Layouts

Item {
    // Layout.topMargin: 10
    anchors.topMargin: 10
    property int monthShift: 0
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0)
    width: calendarColumn.width
    implicitHeight: calendarColumn.height + 10 * 2

    // Snap the view back to the current month each time the right sidebar
    // closes, so reopening it always lands on today rather than wherever
    // the user scrolled to last time. Cheap (just resets an int).
    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) monthShift = 0;
        }
    }

    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)
            && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown) {
                monthShift++;
            } else if (event.key === Qt.Key_PageUp) {
                monthShift--;
            }
            event.accepted = true;
        }
    }
    MouseArea {
        anchors.fill: parent
        onWheel: (event) => {
            if (event.angleDelta.y > 0) {
                monthShift--;
            } else if (event.angleDelta.y < 0) {
                monthShift++;
            }
        }
    }

    ColumnLayout {
        id: calendarColumn
        anchors.centerIn: parent
        spacing: 5

        // Calendar header
        RowLayout {
            Layout.fillWidth: true
            spacing: 5
            IslandButton {
                contentColors: Appearance.colors
                implicitWidth: monthLabel.implicitWidth + 10 * 2
                Behavior on implicitWidth {
                    SmoothedAnimation {
                        velocity: Appearance.animation.elementMove.velocity
                    }
                }
                clip: true
                downAction: () => {
                    monthShift = 0;
                }
                contentItem: StyledText {
                    id: monthLabel
                    text: `${monthShift != 0 ? "• " : ""}${viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")}`
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                StyledToolTip {
                    text: Translation.tr("Jump to current month")
                    extraVisibleCondition: monthShift !== 0
                }
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: false
            }
            IslandButton {
                contentColors: Appearance.colors
                visible: CalendarEvents.accountsAppAvailable
                symbol: "person_add"
                downAction: () => {
                    Quickshell.execDetached(["gnome-online-accounts-gtk"]);
                }
                StyledToolTip {
                    text: Translation.tr("Online Accounts")
                }
            }
            IslandButton {
                contentColors: Appearance.colors
                downAction: () => {
                    CalendarEvents.sync();
                }
                // Its own icon, so the icon can spin while the calendars sync.
                contentItem: MaterialSymbol {
                    id: syncSymbol
                    text: "sync"
                    iconSize: 18
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: Appearance.colors.colOnLayer1
                    RotationAnimator {
                        target: syncSymbol
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                        running: CalendarEvents.syncing
                        onRunningChanged: if (!running) syncSymbol.rotation = 0
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Sync calendars")
                }
            }
            IslandButton {
                contentColors: Appearance.colors
                symbol: "chevron_left"
                downAction: () => {
                    monthShift--;
                }
            }
            IslandButton {
                contentColors: Appearance.colors
                symbol: "chevron_right"
                downAction: () => {
                    monthShift++;
                }
            }
        }

        // Week days row
        RowLayout {
            id: weekDaysRow
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: false
            spacing: 5
            Repeater {
                model: CalendarLayout.weekDays
                delegate: CalendarDayButton {
                    day: Translation.tr(modelData.day)
                    isToday: modelData.today
                    bold: true
                    enabled: false
                }
            }
        }

        // Real week rows
        Repeater {
            id: calendarRows
            // model: calendarLayout
            model: 6
            delegate: RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                spacing: 5
                Repeater {
                    model: Array(7).fill(modelData)
                    delegate: CalendarDayButton {
                        property var cellData: calendarLayout[modelData][index]
                        day: cellData.day
                        isToday: cellData.today
                        hasTasks: Todo.list.length >= 0 && cellData.year !== undefined && Todo.hasTasksForDate(cellData.year, cellData.month, cellData.monthDay)
                        tasksForDay: Todo.list.length >= 0 && cellData.year !== undefined ? Todo.getTasksForDate(cellData.year, cellData.month, cellData.monthDay) : []
                        hasEvents: CalendarEvents.eventsByDate && cellData.year !== undefined && CalendarEvents.hasEventsForDate(cellData.year, cellData.month, cellData.monthDay)
                        eventsForDay: CalendarEvents.eventsByDate && cellData.year !== undefined ? CalendarEvents.getEventsForDate(cellData.year, cellData.month, cellData.monthDay) : []
                    }
                }
            }
        }
    }
}