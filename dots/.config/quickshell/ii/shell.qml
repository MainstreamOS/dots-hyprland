//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1

import "modules/common"
import "services"
import "panelFamilies"

import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    // Stuff for every panel family
    ReloadPopup {}

    // Shake-to-locate cursor helper: runs only while enabled, and resets the
    // cursor zoom if it's killed mid-magnify.
    Process {
        id: cursorShakeProc
        readonly property bool wanted: Config.options.cursor.shakeMode !== "off"
        command: ["python3", CF.FileUtils.trimFileProtocol(Directories.scriptPath) + "/cursor/shake-zoom.py",
            Config.options.cursor.shakeMode,
            String(Config.options.cursor.shakeZoomFactor),
            String(Config.options.cursor.shakeGrowFactor)]

        onWantedChanged: if (wanted !== running) running = wanted
        Component.onCompleted: running = wanted
        // Quickshell doesn't relaunch on a command-only change, so restart when
        // the mode or factor changes. terminate() is asynchronous, so running is
        // still true here — assign unguarded and let the relaunch happen once
        // the child has actually exited.
        onCommandChanged: if (running) {
            running = false
            Qt.callLater(() => running = wanted)
        }
    }

    Component.onCompleted: {
        // Only the main shell clears the shared caches, see _clearCachesEnabled.
        Directories._clearCachesEnabled = true
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        Location.load()
        FirstRunExperience.load()
        ConflictKiller.load()
        Cliphist.refresh()
        BluetoothStatus.reconnectTrustedAudioDevicesAtStartup()
        Wallpapers.load()
        Updates.load()
        ReleaseUpdates.load()
        // Release announcements come from the main shell only — see the
        // _announceEnabled comment in ReleaseUpdates. Settings reads the same
        // singleton for its version display without ever setting this.
        ReleaseUpdates._announceEnabled = true
        ThemeManager.load()
        // Day/Night scheduler runs only here in the main shell — see the
        // _autoApplyEnabled comment in ThemeManager for why. Settings.qml
        // never sets this so its ThemeManager singleton stays passive.
        ThemeManager._autoApplyEnabled = true
        WallpaperSlideshow.load()
        BorderGradient.load()
        LauncherBlur.load()
        // Same story for the wallpaper rotation — see _rotationEnabled.
        WallpaperSlideshow._rotationEnabled = true
        // The touchpad watcher runs from the main shell only, see _watchEnabled.
        TouchpadAutoDisable._watchEnabled = true
        // Only the shell's bar is ever put away, see _publishBarOpen.
        GlobalStates._publishBarOpen = true
        // Only the shell draws the launcher, see _judgeLauncherEnabled.
        Appearance._judgeLauncherEnabled = true
    }


    // Panels
    LazyLoader {
        active: Config.ready
        component: IllogicalImpulseFamily {}
    }

    // An update replaces the files this shell is running from, one at a time.
    // Reloading part-way through means loading a tree that is half old and half
    // new: panels come back wrong, the controls that would put it right are the
    // ones that broke, and the way out is a terminal or the power button.
    //
    // The updater holds reloading for the copying and releases it afterwards.
    // Held is never a resting state: releasing always reloads, so the shell ends
    // on the finished tree whether or not anything changed while it waited.
    // A reload under the lock screen leaves the session locked with nothing to
    // unlock it, so a release while locked waits for the unlock.
    property bool reloadPending: false

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) unlockedReloadTimer.stop()
            else unlockedReloadTimer.restart()
        }
    }

    // Started by every unlock, and a release meanwhile waits for it, so the unlock
    // can let go of the lock, put the workspaces back and unlock the keyring.
    Timer {
        id: unlockedReloadTimer
        interval: 2000
        onTriggered: {
            if (!root.reloadPending || GlobalStates.screenLocked) return
            root.reloadPending = false
            Quickshell.watchFiles = true
            Quickshell.reload(true)
        }
    }

    IpcHandler {
        target: "updates"

        function holdReload(): void {
            root.reloadPending = false
            Quickshell.watchFiles = false
        }

        function resumeReload(): void {
            if (GlobalStates.screenLocked || unlockedReloadTimer.running) {
                root.reloadPending = true
                // Still held, so held() says so and no file change reloads it first.
                Quickshell.watchFiles = false
                return
            }
            Quickshell.watchFiles = true
            Quickshell.reload(true)
        }

        function held(): bool {
            return !Quickshell.watchFiles
        }
    }
}

