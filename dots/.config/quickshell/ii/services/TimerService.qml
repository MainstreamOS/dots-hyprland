pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Simple Pomodoro time manager.
 */
Singleton {
    id: root

    property int focusTime: Config.options.time.pomodoro.focus
    property int breakTime: Config.options.time.pomodoro.breakTime
    property int longBreakTime: Config.options.time.pomodoro.longBreak
    property int cyclesBeforeLongBreak: Config.options.time.pomodoro.cyclesBeforeLongBreak

    property bool pomodoroRunning: Persistent.states.timer.pomodoro.running
    property bool pomodoroBreak: Persistent.states.timer.pomodoro.isBreak
    property bool pomodoroLongBreak: Persistent.states.timer.pomodoro.isBreak && (pomodoroCycle + 1 == cyclesBeforeLongBreak);
    property int pomodoroTimeAdjustment: 0
    property int pomodoroLapDuration: (pomodoroLongBreak ? longBreakTime : pomodoroBreak ? breakTime : focusTime) + pomodoroTimeAdjustment
    property int pomodoroSecondsLeft: pomodoroLapDuration // Reasonable init value, to be changed
    property int pomodoroCycle: Persistent.states.timer.pomodoro.cycle

    property bool stopwatchRunning: Persistent.states.timer.stopwatch.running
    property int stopwatchTime: 0
    property int stopwatchStart: Persistent.states.timer.stopwatch.start
    property var stopwatchLaps: Persistent.states.timer.stopwatch.laps

    property bool countdownRunning: Persistent.states.timer.countdown.running
    property int countdownDuration: Persistent.states.timer.countdown.duration
    property int countdownSecondsLeft: countdownDuration

    // General
    Component.onCompleted: {
        if (!stopwatchRunning)
            stopwatchReset();
    }

    function getCurrentTimeInSeconds() {  // Pomodoro uses Seconds
        return Math.floor(Date.now() / 1000);
    }

    function getCurrentTimeIn10ms() {  // Stopwatch uses 10ms
        return Math.floor(Date.now() / 10);
    }

    // Pomodoro
    function refreshPomodoro() {
        // Work <-> break ?
        if (getCurrentTimeInSeconds() >= Persistent.states.timer.pomodoro.start + pomodoroLapDuration) {
            // Reset counts
            Persistent.states.timer.pomodoro.isBreak = !Persistent.states.timer.pomodoro.isBreak;
            Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();
            pomodoroTimeAdjustment = 0;

            // Send notification
            let notificationMessage;
            if (Persistent.states.timer.pomodoro.isBreak && (pomodoroCycle + 1 == cyclesBeforeLongBreak)) {
                notificationMessage = Translation.tr(`🌿 Long break: %1 minutes`).arg(Math.floor(longBreakTime / 60));
            } else if (Persistent.states.timer.pomodoro.isBreak) {
                notificationMessage = Translation.tr(`☕ Break: %1 minutes`).arg(Math.floor(breakTime / 60));
            } else {
                notificationMessage = Translation.tr(`🔴 Focus: %1 minutes`).arg(Math.floor(focusTime / 60));
            }

            Quickshell.execDetached(["notify-send", Translation.tr("Focus"), notificationMessage, "-a", "Shell"]);
            if (Config.options.sounds.pomodoro) {
                Audio.playSystemSound("alarm-clock-elapsed")
            }

            if (!pomodoroBreak) {
                Persistent.states.timer.pomodoro.cycle = (Persistent.states.timer.pomodoro.cycle + 1) % root.cyclesBeforeLongBreak;
            }
        }

        pomodoroSecondsLeft = pomodoroLapDuration - (getCurrentTimeInSeconds() - Persistent.states.timer.pomodoro.start);
    }

    Timer {
        id: pomodoroTimer
        interval: 200
        running: root.pomodoroRunning
        repeat: true
        onTriggered: refreshPomodoro()
    }

    function togglePomodoro() {
        Persistent.states.timer.pomodoro.running = !pomodoroRunning;
        if (Persistent.states.timer.pomodoro.running) {
            // Start/Resume
            Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds() + pomodoroSecondsLeft - pomodoroLapDuration;
        }
    }

    function resetPomodoro() {
        Persistent.states.timer.pomodoro.running = false;
        Persistent.states.timer.pomodoro.isBreak = false;
        Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();
        Persistent.states.timer.pomodoro.cycle = 0;
        pomodoroTimeAdjustment = 0;
        refreshPomodoro();
    }

    function adjustPomodoroTime(seconds) {
        let baseDuration = pomodoroLongBreak ? longBreakTime : pomodoroBreak ? breakTime : focusTime;
        let newAdjustment = pomodoroTimeAdjustment + seconds;
        let newLapDuration = baseDuration + newAdjustment;
        let newSecondsLeft = pomodoroSecondsLeft + seconds;

        // Don't allow time to go negative or to zero
        if (newLapDuration >= 1 && newSecondsLeft > 0) {
            pomodoroTimeAdjustment = newAdjustment;
            if (pomodoroRunning) {
                refreshPomodoro();
            } else {
                pomodoroSecondsLeft = newSecondsLeft;
            }
        }
    }

    // Stopwatch
    function refreshStopwatch() {  // Stopwatch stores time in 10ms
        stopwatchTime = getCurrentTimeIn10ms() - stopwatchStart;
    }

    Timer {
        id: stopwatchTimer
        interval: 10
        running: root.stopwatchRunning
        repeat: true
        onTriggered: refreshStopwatch()
    }

    function toggleStopwatch() {
        if (root.stopwatchRunning)
            stopwatchPause();
        else
            stopwatchResume();
    }

    function stopwatchPause() {
        Persistent.states.timer.stopwatch.running = false;
    }

    function stopwatchResume() {
        if (stopwatchTime === 0) Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running = true;
        Persistent.states.timer.stopwatch.start = getCurrentTimeIn10ms() - stopwatchTime;
    }

    function stopwatchReset() {
        stopwatchTime = 0;
        Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running = false;
    }

    function stopwatchRecordLap() {
        Persistent.states.timer.stopwatch.laps.push(stopwatchTime);
    }

    // Countdown
    function refreshCountdown() {
        let elapsed = getCurrentTimeInSeconds() - Persistent.states.timer.countdown.start;
        let left = countdownDuration - elapsed;
        if (left <= 0) {
            if (Config.options.sounds.timer) {
                Audio.playSystemSound("alarm-clock-elapsed");
            }
            Quickshell.execDetached(["notify-send", "Timer", Translation.tr("Timer finished!"), "-a", "Shell"]);
            resetCountdown();
        } else {
            countdownSecondsLeft = left;
        }
    }

    Timer {
        id: countdownTimer
        interval: 200
        running: root.countdownRunning
        repeat: true
        onTriggered: refreshCountdown()
    }

    // How a countdown reads wherever it shows.
    function formatCountdown(totalSeconds) {
        const s = Math.max(0, Math.ceil(totalSeconds));
        const pad = value => String(value).padStart(2, "0");
        return `${Math.floor(s / 3600)}:${pad(Math.floor(s / 60) % 60)}:${pad(s % 60)}`;
    }

    function formatSeconds(totalSeconds) {
        const s = Math.max(0, Math.round(totalSeconds));
        const sec = (s % 60).toString().padStart(2, "0");
        if (s < 3600)
            return `${Math.floor(s / 60)}:${sec}`;
        return `${Math.floor(s / 3600)}:${(Math.floor(s / 60) % 60).toString().padStart(2, "0")}:${sec}`;
    }

    // The next moment an "H:MM" time comes around, or null when it isn't one. An am or pm is
    // still read so a time saved by an earlier version keeps working.
    function nextClockTime(text) {
        const m = text.trim().toLowerCase().match(/^(\d{1,2})(?::?(\d{2}))?\s*(?:([ap])\.?m?\.?)?$/);
        if (!m)
            return null;
        const hour = parseInt(m[1]);
        const minute = m[2] ? parseInt(m[2]) : 0;
        if (hour > 23 || minute > 59 || (m[3] && (hour < 1 || hour > 12)))
            return null;
        const at = new Date();
        at.setHours(m[3] ? hour % 12 + (m[3] === "p" ? 12 : 0) : hour, minute, 0, 0);
        if (at <= new Date())
            at.setDate(at.getDate() + 1);
        return at;
    }

    function secondsUntilClockTime(text) {
        const at = root.nextClockTime(text);
        return at ? Math.round((at - new Date()) / 1000) : -1;
    }

    readonly property bool countdownToClock: Persistent.states.timer.countdown.mode === "clock"
    // The time the timer is set to go off, or an hour or so from now with none picked yet.
    readonly property var countdownEndParts: {
        const at = root.nextClockTime(Persistent.states.timer.countdown.endTime)
            ?? new Date(Math.ceil((Date.now() + 3600000) / 300000) * 300000);
        return { hour: at.getHours(), minute: at.getMinutes() };
    }

    // Switching tabs only changes which picker shows next, so a timer already going keeps going.
    function setCountdownMode(clock) {
        Persistent.states.timer.countdown.mode = clock ? "clock" : "length";
    }

    function setCountdownEndTime(hour, minute) {
        Persistent.states.timer.countdown.endTime = `${hour}:${String(minute).padStart(2, "0")}`;
    }

    function addCountdownMinutes(minutes) {
        const addSeconds = minutes * 60;
        if (root.countdownRunning) {
            Persistent.states.timer.countdown.duration += addSeconds;
        } else {
            Persistent.states.timer.countdown.duration = (Persistent.states.timer.countdown.duration ?? 0) + addSeconds;
            countdownSecondsLeft = Persistent.states.timer.countdown.duration;
        }
    }

    // Nothing under way, so the tabs' pickers set what the next run does.
    readonly property bool countdownIdle: !root.countdownRunning && root.countdownSecondsLeft >= root.countdownDuration
    // Whether the run under way was aimed at a time of day. A paused one takes its
    // time back up from the clock, and a run of set length keeps what it has left.
    property bool countdownAimedAtClock: false
    readonly property bool countdownPicksEndTime: root.countdownToClock && !root.countdownRunning
        && (root.countdownIdle || root.countdownAimedAtClock)

    function toggleCountdown() {
        if (root.countdownIdle)
            root.countdownAimedAtClock = root.countdownToClock;
        if (!root.countdownRunning && root.countdownToClock && root.countdownAimedAtClock) {
            root.setCountdownEndTime(root.countdownEndParts.hour, root.countdownEndParts.minute);
            // Worked out at each start, so a pause doesn't move the time it goes off.
            root.setCountdownTime(root.secondsUntilClockTime(Persistent.states.timer.countdown.endTime));
        }
        Persistent.states.timer.countdown.running = !countdownRunning;
        if (Persistent.states.timer.countdown.running) {
            Persistent.states.timer.countdown.start = getCurrentTimeInSeconds() - (countdownDuration - countdownSecondsLeft);
        }
    }

    function resetCountdown() {
        Persistent.states.timer.countdown.running = false;
        countdownSecondsLeft = countdownDuration;
    }

    function setCountdownTime(seconds) {
        let newSeconds = Math.max(1, seconds);
        Persistent.states.timer.countdown.duration = newSeconds;
        countdownDuration = newSeconds;
        countdownSecondsLeft = newSeconds;
        Persistent.states.timer.countdown.running = false;
    }
}
