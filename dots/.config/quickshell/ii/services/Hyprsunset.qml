pragma Singleton

import QtQuick
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Simple hyprsunset service with automatic mode.
 * In theory we don't need this because hyprsunset has a config file, but it somehow doesn't work.
 * It should also be possible to control it via hyprctl, but it doesn't work consistently either so we're just killing and launching.
 */
Singleton {
    id: root
    signal gammaChangeAttempt()

    readonly property real gammaLowerLimit: 25

    // Whether the window follows the sun rather than a pair of stored hours.
    // This keys on scheduleMode rather than mode because the day and night
    // theme scheduler reads the window while the filter is switched off, and
    // mode forgets which kind of schedule was chosen the moment it turns
    // "disabled" or "enabled".
    readonly property bool followsSun: (Config.options?.light?.night?.scheduleMode ?? "manual") === "automatic"
    // A located sun replaces the stored hours; anything short of one leaves
    // them in force, so a machine that has never reached the network keeps
    // whatever window it was given.
    readonly property bool usingSolar: root.followsSun && SolarSchedule.valid

    property string from: root.usingSolar ? SolarSchedule.sunset : (Config.options?.light?.night?.from ?? "19:00")
    property string to: root.usingSolar ? SolarSchedule.sunrise : (Config.options?.light?.night?.to ?? "06:30")

    // A sun that never sets, and one that never rises, have no crossing to
    // compare a clock against, so they answer the question outright. Handing
    // back the stored hours instead would warm the screen in the middle of an
    // Arctic afternoon that never gets dark.
    readonly property var solarOverride: {
        if (!root.followsSun)
            return undefined;
        if (SolarSchedule.state === "polarDay")
            return false;
        if (SolarSchedule.state === "polarNight")
            return true;
        return undefined;
    }
    property bool automatic: Config.options?.light?.night?.automatic && (Config?.ready ?? true)
    property int colorTemperature: Config.options?.light?.night?.colorTemperature ?? 5000
    property int defaultColorTemperature: 6000
    property int gamma: 100
    property bool shouldBeOn
    property bool firstEvaluation: true
    property bool temperatureActive: false

    property int fromHour: Number(from.split(":")[0])
    property int fromMinute: Number(from.split(":")[1])
    property int toHour: Number(to.split(":")[0])
    property int toMinute: Number(to.split(":")[1])

    property int clockHour: DateTime.clock.hours
    property int clockMinute: DateTime.clock.minutes

    property var manualActive
    property int manualActiveHour
    property int manualActiveMinute

    onClockMinuteChanged: reEvaluate()
    onAutomaticChanged: {
        root.manualActive = undefined;
        root.firstEvaluation = true;
        reEvaluate();
    }

    // The window above is read from the config file, which arrives after this
    // singleton is built, so the first evaluation runs against the shipped
    // defaults. A filter that is switched on gets corrected for free, because
    // `automatic` turns true on the same event and re-evaluates; a switched off
    // one has nothing to correct it, and the day and night theme scheduler
    // follows this window whether the filter runs or not.
    readonly property bool configReady: Config?.ready ?? true
    onConfigReadyChanged: if (root.configReady) root.reEvaluate()

    // The sun moves the window once a day, and once more when a location first
    // arrives, so following it cannot storm the way a handler on the stored
    // hours would: those move on every step of a spin box.
    onFollowsSunChanged: root.reEvaluate()
    Connections {
        target: SolarSchedule
        enabled: root.followsSun
        function onSunriseChanged() {
            root.reEvaluate();
        }
        function onSunsetChanged() {
            root.reEvaluate();
        }
        function onStateChanged() {
            root.reEvaluate();
        }
    }

    function inBetween(t, from, to) {
        if (from < to) {
            return (t >= from && t <= to);
        } else {
            // Wrapped around midnight
            return (t >= from || t <= to);
        }
    }

    function reEvaluate() {
        const t = clockHour * 60 + clockMinute;
        const from = fromHour * 60 + fromMinute;
        const to = toHour * 60 + toMinute;
        const manualActive = manualActiveHour * 60 + manualActiveMinute;

        if (root.manualActive !== undefined && (inBetween(from, manualActive, t) || inBetween(to, manualActive, t))) {
            root.manualActive = undefined;
        }
        root.shouldBeOn = (root.solarOverride !== undefined) ? root.solarOverride : inBetween(t, from, to);
        if (firstEvaluation) {
            firstEvaluation = false;
            root.ensureState();
        }
    }

    onShouldBeOnChanged: ensureState()
    function ensureState() {
        // console.log("[Hyprsunset] Ensuring state:", root.shouldBeOn, "Automatic mode:", root.automatic);
        if (!root.automatic || root.manualActive !== undefined)
            return;
        if (root.shouldBeOn) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    function startHyprsunset() {
        Quickshell.execDetached(["bash", "-c", `pidof hyprsunset || hyprsunset`]);
    }

    function load() {
        root.startHyprsunset();
        root.ensureState();
    }

    Timer {
        id: updateHyprsunset
        interval: 100
        repeat: false
        onTriggered: {
            root.ensureState();
            root.setGamma(root.gamma);
        }
    }

    function enableTemperature() {
        root.temperatureActive = true;

        // console.log("[Hyprsunset] Enabling");
        root.startHyprsunset();
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset temperature ${root.colorTemperature}`]);
    }

    function disableTemperature() {
        root.temperatureActive = false;
        // console.log("[Hyprsunset] Disabling");
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset temperature ${root.defaultColorTemperature}`]);
    }

    function setGamma(gamma) {
        root.gamma = Math.max(root.gammaLowerLimit, Math.min(100, gamma));

        root.gammaChangeAttempt();

        root.startHyprsunset();
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset gamma ${root.gamma}`]);
    }

    function fetchState() {
        fetchProc.running = true;
    }

    Process {
        id: fetchProc
        running: true
        command: ["bash", "-c", "hyprctl hyprsunset temperature"]
        stdout: StdioCollector {
            id: stateCollector
            onStreamFinished: {
                const output = stateCollector.text.trim();
                if (output.length == 0 || output.startsWith("Couldn't"))
                    root.temperatureActive = false;
                else
                    root.temperatureActive = (output != root.defaultColorTemperature); // 6000 is the default when off
                // console.log("[Hyprsunset] Fetched state:", output, "->", root.temperatureActive);
            }
        }
    }

    function toggleTemperature(active = undefined) {
        if (root.manualActive === undefined) {
            root.manualActive = root.temperatureActive;
            root.manualActiveHour = root.clockHour;
            root.manualActiveMinute = root.clockMinute;
        }

        root.manualActive = active !== undefined ? active : !root.manualActive;
        if (root.manualActive) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    // Single source of truth for applying a Night Light mode picked by
    // either dropdown (Settings → Display, right-sidebar dialog) or
    // the right-sidebar toggle button. Writes Config.options.light.night.mode
    // (the dropdown's persistent state) and propagates the appropriate
    // automatic/scheduleMode/temperatureActive transitions so the runtime
    // matches. Also bookmarks the last non-disabled mode in
    // lastActiveMode so the toggle button can restore the previous
    // state when flipped back on from "disabled".
    function applyNightLightMode(mode) {
        const s = Config.options.light.night;
        s.mode = mode;
        if (mode !== "disabled") s.lastActiveMode = mode;
        if (mode === "disabled") {
            if (s.automatic) s.automatic = false;
            if (root.temperatureActive) root.toggleTemperature(false);
        } else if (mode === "automatic") {
            if (s.scheduleMode !== "automatic") s.scheduleMode = "automatic";
            if (!s.automatic) s.automatic = true;
        } else if (mode === "manual") {
            if (s.scheduleMode !== "manual") s.scheduleMode = "manual";
            if (!s.automatic) s.automatic = true;
        } else if (mode === "enabled") {
            if (s.automatic) s.automatic = false;
            if (!root.temperatureActive) root.toggleTemperature(true);
        }
    }

    // Change temp
    Connections {
        target: Config.options.light.night
        function onColorTemperatureChanged() {
            if (!root.temperatureActive) return;
            Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", `${Config.options.light.night.colorTemperature}`]);
        }
    }
}