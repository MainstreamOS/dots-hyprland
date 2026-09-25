pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * TouchpadAutoDisable: the touchpad stays off while an external mouse is in
 * use, when Settings > Mouse asks for it.
 *
 * scripts/hypr/touchpad_auto_disable.py decides which devices count and
 * switches the touchpad. This service only runs it while the switch is on and
 * passes along what udev cannot tell it: a Hyprland config reload, which puts
 * the touchpad back to its saved setting, and a change to that setting. The
 * script puts the touchpad back itself when it is stopped or loses this shell.
 */
Singleton {
    id: root

    // Only the main shell sets this. Settings runs as a process of its own and
    // reads the switch from the same file, and two watchers would fight over
    // one touchpad.
    property bool _watchEnabled: false

    function load() {} // For forcing singleton initialization

    readonly property string customDir: `${FileUtils.trimFileProtocol(Directories.config)}/hypr/custom`
    // "1" when the Settings switch is on. Absent means off, as it comes.
    readonly property string flagPath: `${root.customDir}/touchpad.disableWithMouse`
    readonly property string envPath: `${root.customDir}/env.lua`
    readonly property string scriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/hypr/touchpad_auto_disable.py`

    property bool switchedOn: false
    // The script found no internal touchpad. A config reload, or the switch
    // being turned on, is when one that turned up since is looked for.
    property bool noTouchpad: false
    readonly property bool wanted: root._watchEnabled && root.switchedOn && !root.noTouchpad

    property int retryDelay: 2000

    onSwitchedOnChanged: {
        if (root.switchedOn)
            root.noTouchpad = false;
    }
    onWantedChanged: root.sync()

    function sync() {
        if (root.wanted) {
            if (!watcher.running && !restartTimer.running)
                watcher.running = true;
        } else {
            restartTimer.stop();
            // The script answers the terminate by putting the touchpad back.
            if (watcher.running)
                watcher.running = false;
        }
    }

    function configReloaded() {
        if (root.noTouchpad)
            root.noTouchpad = false;
        else if (watcher.running)
            watcher.write("reload\n");
    }

    FileView {
        id: flagFile
        path: root._watchEnabled ? root.flagPath : ""
        watchChanges: true
        printErrors: false
        onLoaded: root.switchedOn = flagFile.text().trim() === "1"
        onLoadFailed: root.switchedOn = false
        onFileChanged: flagFile.reload()
    }

    FileView {
        path: watcher.running ? root.envPath : ""
        watchChanges: true
        preload: false
        printErrors: false
        onFileChanged: {
            if (watcher.running)
                watcher.write("settings\n");
        }
    }

    Connections {
        target: Hyprland
        enabled: root._watchEnabled && root.switchedOn
        function onRawEvent(event) {
            if (event.name === "configreloaded")
                root.configReloaded();
        }
    }

    Process {
        id: watcher
        property real startedAt: 0
        command: ["python3", root.scriptPath, "watch", root.envPath]
        // Held open for the commands above; the script also takes the pipe
        // closing as this shell being gone.
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => console.info("[TouchpadAutoDisable] " + line)
        }
        stderr: SplitParser {
            onRead: line => console.warn("[TouchpadAutoDisable] " + line)
        }
        onRunningChanged: {
            if (running)
                startedAt = Date.now();
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 3) {
                root.noTouchpad = true;
                return;
            }
            if (!root.wanted)
                return;
            // Back off while it keeps dying young, so a broken setup is not
            // restarted in a tight loop.
            if (Date.now() - watcher.startedAt >= 60000)
                root.retryDelay = 2000;
            restartTimer.interval = root.retryDelay;
            root.retryDelay = Math.min(root.retryDelay * 2, 60000);
            restartTimer.restart();
        }
    }

    Timer {
        id: restartTimer
        onTriggered: root.sync()
    }
}
