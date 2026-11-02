import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    implicitHeight: contentColumn.implicitHeight
    implicitWidth: contentColumn.implicitWidth

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        spacing: 0

        CircularProgress {
            Layout.alignment: Qt.AlignHCenter
            lineWidth: 8
            value: TimerService.countdownDuration > 0 ? TimerService.countdownSecondsLeft / TimerService.countdownDuration : 0
            implicitSize: 200
            enableAnimation: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                ClockTimePicker {
                    Layout.alignment: Qt.AlignHCenter
                    visible: timeItem.showsEndTime
                }

                DurationPicker {
                    Layout.alignment: Qt.AlignHCenter
                    visible: timeItem.showsLength
                }

                Item {
                    id: timeItem
                    visible: !timeItem.showsEndTime && !timeItem.showsLength
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 160
                    implicitHeight: 50

                    readonly property bool showsEndTime: TimerService.countdownPicksEndTime
                    readonly property bool showsLength: !TimerService.countdownToClock && TimerService.countdownIdle

                    StyledText {
                        anchors.centerIn: parent
                        text: TimerService.formatCountdown(TimerService.countdownSecondsLeft)
                        font.pixelSize: 32
                        color: Appearance.m3colors.m3onSurface
                    }
                }

                StyledText {
                    visible: !timeItem.showsEndTime && !timeItem.showsLength
                    Layout.alignment: Qt.AlignHCenter
                    text: TimerService.countdownRunning
                        ? Translation.tr("Ends at %1").arg(Qt.formatTime(new Date(Date.now() + TimerService.countdownSecondsLeft * 1000), Config.options.time.format))
                        : Translation.tr("Timer")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }
            }
        }

        SegmentedTabBar {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 220
            model: [
                {"name": Translation.tr("Length"), "icon": "hourglass_empty"},
                {"name": Translation.tr("Clock time"), "icon": "schedule"}
            ]
            currentIndex: TimerService.countdownToClock ? 1 : 0
            onActivated: index => {
                TimerService.setCountdownMode(index === 1);
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            RippleButton {
                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: TimerService.countdownRunning ? Translation.tr("Pause") : (TimerService.countdownSecondsLeft === TimerService.countdownDuration) ? Translation.tr("Start") : Translation.tr("Resume")
                    color: TimerService.countdownRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                }
                implicitHeight: 32
                buttonRadius: 10
                implicitWidth: 90
                font.pixelSize: Appearance.font.pixelSize.larger
                onClicked: TimerService.toggleCountdown()
                colBackground: TimerService.countdownRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
                colBackgroundHover: TimerService.countdownRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
            }

            RippleButton {
                implicitHeight: 32
                buttonRadius: 10
                implicitWidth: 90

                onClicked: TimerService.resetCountdown()
                enabled: TimerService.countdownSecondsLeft < TimerService.countdownDuration

                font.pixelSize: Appearance.font.pixelSize.larger
                colBackground: Appearance.surfaces.row
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active

                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Reset")
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }
}
