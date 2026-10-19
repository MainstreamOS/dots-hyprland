pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "../sidebarRight/calendar/calendar_layout.js" as CalendarLayout

ColumnLayout {
    id: root
    readonly property color elevatedSurface: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer0, 0.92)
    property int taskIndex: 0
    property int monthOffset: 0
    readonly property date month: CalendarLayout.getDateInXMonthsTime(monthOffset)
    readonly property var days: CalendarLayout.getCalendarLayout(month, monthOffset === 0).reduce((days, week) => days.concat(week), [])
    readonly property var tasks: Todo.list.filter(task => !task.done)
    readonly property var currentTask: tasks[Math.min(taskIndex, tasks.length - 1)] ?? null
    property var completingTask: null
    property string completionCaption: ""
    property real checkProgress: 0
    readonly property var displayedTask: completingTask || currentTask
    readonly property bool busy: completion.running
    function completeCurrentTask() {
        if (busy || !currentTask) return;
        const index = Todo.list.indexOf(currentTask);
        if (index < 0) return;
        completionCaption = Translation.tr("Tasks") + " · " + (taskIndex + 1) + " / " + tasks.length;
        completingTask = currentTask;
        // Persist immediately; keep this task's visual snapshot until the
        // check has animated and the row has faded out.
        Todo.markDone(index);
        completion.restart();
    }
    SequentialAnimation {
        id: completion
        NumberAnimation { target: root; property: "checkProgress"; to: 1; duration: 160; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 140 }
        NumberAnimation { target: taskRow; property: "opacity"; to: 0; duration: 180; easing.type: Easing.InCubic }
        ScriptAction { script: { root.completingTask = null; root.completionCaption = ""; root.checkProgress = 0; } }
        NumberAnimation { target: taskRow; property: "opacity"; to: 1; duration: 140; easing.type: Easing.OutCubic }
    }
    onTasksChanged: taskIndex = Math.max(0, Math.min(taskIndex, tasks.length - 1))
    spacing: 2

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 154
        topLeftRadius: Appearance?.rounding?.normal ?? 17
        topRightRadius: Appearance?.rounding?.normal ?? 17
        bottomLeftRadius: 5
        bottomRightRadius: 5
        color: root.elevatedSurface

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                IslandButton {
                    implicitHeight: 24
                    implicitWidth: 24
                    symbol: "chevron_left"
                    Accessible.name: Translation.tr("Previous month")
                    onClicked: root.monthOffset--
                }
                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 24
                    topPadding: 0
                    bottomPadding: 0
                    buttonRadius: 8
                    Accessible.name: Translation.tr("Return to today")
                    onClicked: root.monthOffset = 0
                    contentItem: StyledText {
                        text: Qt.formatDate(root.month, "MMMM yyyy")
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer0
                    }
                }
                IslandButton {
                    implicitHeight: 24
                    implicitWidth: 24
                    symbol: "chevron_right"
                    Accessible.name: Translation.tr("Next month")
                    onClicked: root.monthOffset++
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 14
                spacing: 0
                Repeater {
                    model: CalendarLayout.weekDays
                    StyledText {
                        required property var modelData
                        Layout.fillWidth: true
                        text: Translation.tr(modelData.day)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        color: Appearance.colors.colSubtext
                        font.pixelSize: 10
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 7
                rowSpacing: 1
                columnSpacing: 0
                Repeater {
                    model: root.days
                    Item {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 16
                        Rectangle {
                            anchors.centerIn: parent
                            width: 17
                            height: 17
                            radius: 8.5
                            color: Appearance.colors.colPrimary
                            visible: parent.modelData.today === 1
                        }
                        StyledText {
                            anchors.centerIn: parent
                            text: parent.modelData.day
                            opacity: parent.modelData.today === -1 ? 0.35 : 1
                            color: parent.modelData.today === 1 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                            font.pixelSize: 11
                            font.weight: parent.modelData.today === 1 ? Font.DemiBold : Font.Normal
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 46
        topLeftRadius: 5
        topRightRadius: 5
        bottomLeftRadius: Appearance?.rounding?.normal ?? 17
        bottomRightRadius: Appearance?.rounding?.normal ?? 17
        color: root.elevatedSurface

        RowLayout {
            id: taskRow
            anchors.fill: parent
            anchors.margins: 6
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            IslandButton {
                symbol: "chevron_left"
                implicitHeight: 26
                implicitWidth: 26
                enabled: root.tasks.length > 1 && !root.busy
                Accessible.name: Translation.tr("Previous task")
                onClicked: root.taskIndex = (root.taskIndex - 1 + root.tasks.length) % root.tasks.length
            }

            RippleButton {
                implicitHeight: 26
                implicitWidth: 26
                topPadding: 0
                bottomPadding: 0
                buttonRadius: 6
                enabled: !!root.displayedTask
                Accessible.role: Accessible.CheckBox
                Accessible.name: Translation.tr("Complete task")
                Accessible.checked: !!root.completingTask
                Accessible.onToggleAction: root.completeCurrentTask()
                onClicked: root.completeCurrentTask()
                contentItem: Item {
                    Rectangle {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        radius: 5
                        border.width: 2
                        border.color: root.completingTask ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                        color: root.completingTask ? Appearance.colors.colPrimary : "transparent"
                        Behavior on color { ColorAnimation { duration: 160 } }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "check"
                            iconSize: 14
                            color: Appearance.colors.colOnPrimary
                            opacity: root.checkProgress
                            scale: 0.5 + root.checkProgress * 0.5
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0

                StyledText {
                    text: root.completionCaption || Translation.tr("Tasks") + (root.tasks.length ? " · " + (root.taskIndex + 1) + " / " + root.tasks.length : "")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: 10
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.displayedTask?.content || Translation.tr("All caught up")
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }
            }

            IslandButton {
                symbol: "chevron_right"
                implicitHeight: 26
                implicitWidth: 26
                enabled: root.tasks.length > 1 && !root.busy
                Accessible.name: Translation.tr("Next task")
                onClicked: root.taskIndex = (root.taskIndex + 1) % root.tasks.length
            }
        }
    }
}
