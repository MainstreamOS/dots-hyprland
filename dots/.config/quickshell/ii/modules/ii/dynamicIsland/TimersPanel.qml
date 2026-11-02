pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ColumnLayout {
    id: root
    spacing: 2
    implicitHeight: 208
    Layout.fillWidth: true
    Layout.fillHeight: true


    // 0: Timer (Countdown), 1: Stopwatch, 2: Focus. The tabs show them as Timer, Focus, Stopwatch.
    readonly property var tabModes: [0, 2, 1]
    readonly property var modeKeys: ["timer", "stopwatch", "focus"]
    readonly property int currentMode: Math.max(0, root.modeKeys.indexOf(Persistent.states.timer.tab))

    readonly property bool needsKeyboardFocus: false

    readonly property bool showsEndTime: root.currentMode === 0 && TimerService.countdownPicksEndTime
    readonly property bool showsLength: root.currentMode === 0 && !TimerService.countdownToClock && TimerService.countdownIdle

    function format10ms(time10ms) {
        const totalSeconds = Math.floor(time10ms / 100);
        const m = Math.floor(totalSeconds / 60).toString().padStart(2, '0');
        const s = (totalSeconds % 60).toString().padStart(2, '0');
        const ms = (Math.floor(time10ms) % 100).toString().padStart(2, '0');
        return `${m}:${s}.${ms}`;
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 154
        topLeftRadius: Appearance?.rounding?.normal ?? 17
        topRightRadius: Appearance?.rounding?.normal ?? 17
        bottomLeftRadius: 5
        bottomRightRadius: 5
        color: Appearance.surfaces.raised

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                SegmentedTabBar {
                    Layout.fillWidth: false
                    Layout.preferredWidth: 236
                    contentColors: Appearance.islandContent
                    model: [
                        {"name": Translation.tr("Timer"), "icon": "hourglass_top"},
                        {"name": Translation.tr("Focus"), "icon": "search_activity"},
                        {"name": Translation.tr("Stopwatch"), "icon": "timer"}
                    ]
                    running: [TimerService.countdownRunning, TimerService.pomodoroRunning, TimerService.stopwatchRunning]
                    currentIndex: root.tabModes.indexOf(root.currentMode)
                    onActivated: index => Persistent.states.timer.tab = root.modeKeys[root.tabModes[index]]
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredHeight: 22
                    implicitWidth: statusContent.implicitWidth + 14
                    radius: 11
                    color: ColorUtils.mix(Appearance.colors.colSecondaryContainer, "transparent", 0.3)

                    RowLayout {
                        id: statusContent
                        anchors.centerIn: parent
                        spacing: 5

                        Rectangle {
                            width: 6; height: 6; radius: 3
                            color: {
                                if (root.currentMode === 0) return TimerService.countdownRunning ? Appearance.islandContent.colPrimary : Appearance.islandContent.colSubtext;
                                if (root.currentMode === 1) return TimerService.stopwatchRunning ? Appearance.islandContent.colPrimary : Appearance.islandContent.colSubtext;
                                return TimerService.pomodoroRunning ? Appearance.islandContent.colPrimary : Appearance.islandContent.colSubtext;
                            }
                        }

                        StyledText {
                            text: {
                                if (root.currentMode === 0) {
                                    return TimerService.countdownRunning ? Translation.tr("Running") : (TimerService.countdownSecondsLeft === TimerService.countdownDuration ? Translation.tr("Ready") : Translation.tr("Paused"));
                                }
                                if (root.currentMode === 1) {
                                    const lapCount = TimerService.stopwatchLaps?.length ?? 0;
                                    if (lapCount > 0) return Translation.tr("%1 Laps").arg(lapCount);
                                    return TimerService.stopwatchRunning ? Translation.tr("Running") : (TimerService.stopwatchTime === 0 ? Translation.tr("Ready") : Translation.tr("Paused"));
                                }
                                return Translation.tr("Cycle %1 of %2").arg(TimerService.pomodoroCycle + 1).arg(TimerService.cyclesBeforeLongBreak);
                            }
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14

                CircularProgress {
                    Layout.alignment: Qt.AlignVCenter
                    implicitSize: 84
                    lineWidth: 6
                    enableAnimation: true
                    value: {
                        if (root.currentMode === 0) {
                            return TimerService.countdownDuration > 0 ? (TimerService.countdownSecondsLeft / TimerService.countdownDuration) : 0;
                        }
                        if (root.currentMode === 1) {
                            return (TimerService.stopwatchTime % 6000) / 6000;
                        }
                        return TimerService.pomodoroLapDuration > 0 ? (TimerService.pomodoroSecondsLeft / TimerService.pomodoroLapDuration) : 0;
                    }
                    colPrimary: Appearance.colors.colPrimary
                    colSecondary: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.4)

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: {
                                if (root.currentMode === 0) return "hourglass_top";
                                if (root.currentMode === 1) return "timer";
                                return TimerService.pomodoroLongBreak ? "eco" : TimerService.pomodoroBreak ? "local_cafe" : "search_activity";
                            }
                            iconSize: 22
                            color: Appearance.islandContent.colPrimary
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: {
                                if (root.currentMode === 0) {
                                    const pct = TimerService.countdownDuration > 0 ? Math.round((TimerService.countdownSecondsLeft / TimerService.countdownDuration) * 100) : 0;
                                    return `${pct}%`;
                                }
                                if (root.currentMode === 1) {
                                    const sec = Math.floor(TimerService.stopwatchTime / 100) % 60;
                                    return `${sec}s`;
                                }
                                return TimerService.pomodoroLongBreak ? Translation.tr("Long") : TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus");
                            }
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            color: Appearance.islandContent.colSubtext
                        }
                    }
                }

                ClockTimePicker {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.showsEndTime
                    contentColors: Appearance.islandContent
                    rowHeight: 24
                    cornerRadius: 6
                }

                DurationPicker {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.showsLength
                    contentColors: Appearance.islandContent
                    rowHeight: 24
                    cornerRadius: 6
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    Item {
                        visible: !root.showsEndTime && !root.showsLength
                        implicitWidth: digitsRow.implicitWidth
                        implicitHeight: digitsRow.implicitHeight

                        RowLayout {
                            id: digitsRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            StyledText {
                                text: {
                                    if (root.currentMode === 0) {
                                        return TimerService.formatCountdown(TimerService.countdownSecondsLeft);
                                    }
                                    if (root.currentMode === 1) {
                                        const totalSeconds = Math.floor(TimerService.stopwatchTime / 100);
                                        const m = Math.floor(totalSeconds / 60).toString().padStart(2, '0');
                                        const s = (totalSeconds % 60).toString().padStart(2, '0');
                                        return `${m}:${s}`;
                                    }
                                    return TimerService.formatCountdown(TimerService.pomodoroSecondsLeft);
                                }
                                font.pixelSize: 34
                                font.weight: Font.DemiBold
                                font.features: ({ "tnum": 1 })
                                color: Appearance.islandContent.colOnLayer0
                            }

                            StyledText {
                                visible: root.currentMode === 1
                                text: {
                                    const ms = (Math.floor(TimerService.stopwatchTime) % 100).toString().padStart(2, '0');
                                    return `.${ms}`;
                                }
                                font.pixelSize: 22
                                font.weight: Font.Medium
                                font.features: ({ "tnum": 1 })
                                color: Appearance.islandContent.colSubtext
                                Layout.alignment: Qt.AlignBaseline
                            }
                        }
                    }

                    StyledText {
                        visible: !root.showsEndTime && !root.showsLength
                        text: {
                            if (root.currentMode === 0) {
                                if (TimerService.countdownRunning) {
                                    const endsAt = Qt.formatTime(new Date(Date.now() + TimerService.countdownSecondsLeft * 1000), "h:mm AP");
                                    return Translation.tr("Target: %1 · Ends at %2").arg(TimerService.formatCountdown(TimerService.countdownDuration)).arg(endsAt);
                                }
                                return "";
                            }
                            if (root.currentMode === 1) {
                                const laps = TimerService.stopwatchLaps ?? [];
                                if (laps.length > 0) {
                                    const last = laps[laps.length - 1];
                                    const prev = laps.length > 1 ? laps[laps.length - 2] : 0;
                                    return Translation.tr("Lap %1 · Split: +%2").arg(laps.length).arg(root.format10ms(last - prev));
                                }
                                return Translation.tr("Press Lap while running to record splits");
                            }
                            if (TimerService.pomodoroBreak) {
                                return Translation.tr("Break time · %1 min remaining").arg(Math.ceil(TimerService.pomodoroSecondsLeft / 60));
                            }
                            return Translation.tr("Next: %1 min break").arg(Math.floor(TimerService.breakTime / 60));
                        }
                        font.pixelSize: 11
                        color: Appearance.islandContent.colSubtext
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        spacing: 8
                        Layout.topMargin: 4

                        RippleButton {
                            implicitHeight: 32
                            implicitWidth: 86
                            buttonRadius: 10
                            colBackground: {
                                const running = (root.currentMode === 0 && TimerService.countdownRunning)
                                    || (root.currentMode === 1 && TimerService.stopwatchRunning)
                                    || (root.currentMode === 2 && TimerService.pomodoroRunning);
                                return running ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary;
                            }
                            colBackgroundHover: {
                                const running = (root.currentMode === 0 && TimerService.countdownRunning)
                                    || (root.currentMode === 1 && TimerService.stopwatchRunning)
                                    || (root.currentMode === 2 && TimerService.pomodoroRunning);
                                return running ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colPrimaryHover;
                            }
                            colRipple: {
                                const running = (root.currentMode === 0 && TimerService.countdownRunning)
                                    || (root.currentMode === 1 && TimerService.stopwatchRunning)
                                    || (root.currentMode === 2 && TimerService.pomodoroRunning);
                                return running ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colPrimaryActive;
                            }

                            onClicked: {
                                if (root.currentMode === 0) TimerService.toggleCountdown();
                                else if (root.currentMode === 1) TimerService.toggleStopwatch();
                                else TimerService.togglePomodoro();
                            }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 5
                                readonly property bool running: (root.currentMode === 0 && TimerService.countdownRunning)
                                    || (root.currentMode === 1 && TimerService.stopwatchRunning)
                                    || (root.currentMode === 2 && TimerService.pomodoroRunning);

                                MaterialSymbol {
                                    text: parent.running ? "pause" : "play_arrow"
                                    iconSize: 16
                                    color: parent.running ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                                }
                                StyledText {
                                    text: {
                                        if (parent.running) return Translation.tr("Pause");
                                        if (root.currentMode === 0) return TimerService.countdownSecondsLeft === TimerService.countdownDuration ? Translation.tr("Start") : Translation.tr("Resume");
                                        if (root.currentMode === 1) return TimerService.stopwatchTime === 0 ? Translation.tr("Start") : Translation.tr("Resume");
                                        return TimerService.pomodoroSecondsLeft === TimerService.pomodoroLapDuration ? Translation.tr("Start") : Translation.tr("Resume");
                                    }
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: parent.running ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                                }
                            }
                        }

                        RippleButton {
                            implicitHeight: 32
                            implicitWidth: 80
                            buttonRadius: 10
                            readonly property bool isLapMode: root.currentMode === 1 && TimerService.stopwatchRunning
                            readonly property bool canReset: {
                                if (root.currentMode === 0) return TimerService.countdownSecondsLeft < TimerService.countdownDuration;
                                if (root.currentMode === 1) return TimerService.stopwatchTime > 0 || (TimerService.stopwatchLaps?.length ?? 0) > 0;
                                return TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration || TimerService.pomodoroCycle > 0 || TimerService.pomodoroBreak;
                            }
                            enabled: isLapMode || canReset

                            colBackground: isLapMode ? Appearance.colors.colPrimaryContainer : Appearance.surfaces.row
                            colBackgroundHover: isLapMode ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                            colRipple: isLapMode ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                            opacity: enabled ? 1 : 0.45

                            onClicked: {
                                if (isLapMode) {
                                    TimerService.stopwatchRecordLap();
                                } else {
                                    if (root.currentMode === 0) TimerService.resetCountdown();
                                    else if (root.currentMode === 1) TimerService.stopwatchReset();
                                    else TimerService.resetPomodoro();
                                }
                            }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 5
                                MaterialSymbol {
                                    text: parent.parent.isLapMode ? "flag" : "replay"
                                    iconSize: 15
                                    color: parent.parent.isLapMode ? Appearance.colors.colOnPrimaryContainer : Appearance.islandContent.colOnLayer1
                                }
                                StyledText {
                                    text: parent.parent.isLapMode ? Translation.tr("Lap") : Translation.tr("Reset")
                                    font.pixelSize: 12
                                    font.weight: parent.parent.isLapMode ? Font.DemiBold : Font.Medium
                                    color: parent.parent.isLapMode ? Appearance.colors.colOnPrimaryContainer : Appearance.islandContent.colOnLayer1
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 52
        topLeftRadius: 5
        topRightRadius: 5
        bottomLeftRadius: Appearance?.rounding?.normal ?? 17
        bottomRightRadius: Appearance?.rounding?.normal ?? 17
        color: Appearance.surfaces.raised

        RowLayout {
            visible: root.currentMode === 0
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 6

            SegmentedTabBar {
                Layout.fillWidth: false
                Layout.preferredWidth: 176
                contentColors: Appearance.islandContent
                model: [
                    {"name": Translation.tr("Length"), "icon": "hourglass_top"},
                    {"name": Translation.tr("Clock time"), "icon": "schedule"}
                ]
                currentIndex: TimerService.countdownToClock ? 1 : 0
                onActivated: index => {
                    TimerService.setCountdownMode(index === 1);
                }
            }

            StyledText {
                visible: !TimerService.countdownToClock
                text: Translation.tr("Add:")
                font.pixelSize: 11
                font.weight: Font.Medium
                color: Appearance.islandContent.colSubtext
                Layout.alignment: Qt.AlignVCenter
            }

            Repeater {
                model: [
                    { label: "+1m", mins: 1 },
                    { label: "+5m", mins: 5 },
                    { label: "+10m", mins: 10 },
                    { label: "+15m", mins: 15 }
                ]
                delegate: RippleButton {
                    required property var modelData
                    visible: !TimerService.countdownToClock
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    buttonRadius: 8
                    colBackground: ColorUtils.mix(Appearance.colors.colLayer1, Appearance.colors.colLayer2, 0.45)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: TimerService.addCountdownMinutes(modelData.mins)

                    StyledText {
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Appearance.islandContent.colOnLayer1
                    }
                }
            }
        }

        RowLayout {
            visible: root.currentMode === 1
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            readonly property var laps: TimerService.stopwatchLaps ?? []
            readonly property bool hasLaps: laps.length > 0

            MaterialSymbol {
                text: parent.hasLaps ? "history" : "info"
                iconSize: 16
                color: Appearance.islandContent.colSubtext
            }

            StyledText {
                text: {
                    if (parent.hasLaps) {
                        const lastTime = parent.laps[parent.laps.length - 1];
                        return Translation.tr("Last Lap %1: %2").arg(parent.laps.length).arg(root.format10ms(lastTime));
                    }
                    return Translation.tr("Tap Lap while running to save splits");
                }
                font.pixelSize: 11
                font.weight: Font.Medium
                color: Appearance.islandContent.colOnLayer1
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            StyledText {
                visible: parent.hasLaps && parent.laps.length > 1
                text: {
                    if (parent.laps.length > 1) {
                        const lastTime = parent.laps[parent.laps.length - 1];
                        const prevTime = parent.laps[parent.laps.length - 2];
                        return `+${root.format10ms(lastTime - prevTime)}`;
                    }
                    return "";
                }
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: Appearance.islandContent.colPrimary
            }

            RippleButton {
                visible: parent.hasLaps && !TimerService.stopwatchRunning
                implicitHeight: 28
                implicitWidth: 64
                buttonRadius: 6
                colBackground: ColorUtils.mix(Appearance.colors.colLayer1, Appearance.colors.colLayer2, 0.45)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: TimerService.stopwatchReset()

                StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("Reset")
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: Appearance.islandContent.colOnLayer1
                }
            }
        }

        RowLayout {
            visible: root.currentMode === 2
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 6

            StyledText {
                text: Translation.tr("Adjust:")
                font.pixelSize: 11
                font.weight: Font.Medium
                color: Appearance.islandContent.colSubtext
                Layout.alignment: Qt.AlignVCenter
            }

            Repeater {
                model: [
                    { label: "-5m", secs: -300 },
                    { label: "-1m", secs: -60 },
                    { label: "+1m", secs: 60 },
                    { label: "+5m", secs: 300 }
                ]
                delegate: RippleButton {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    buttonRadius: 8
                    colBackground: ColorUtils.mix(Appearance.colors.colLayer1, Appearance.colors.colLayer2, 0.45)
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: TimerService.adjustPomodoroTime(modelData.secs)

                    StyledText {
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: Appearance.islandContent.colOnLayer1
                    }
                }
            }
        }
    }
}
