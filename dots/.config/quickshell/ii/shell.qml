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
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        FirstRunExperience.load()
        ConflictKiller.load()
        Cliphist.refresh()
        Wallpapers.load()
        Updates.load()
        ReleaseUpdates.load()
        ThemeManager.load()
        // Day/Night scheduler runs only here in the main shell — see the
        // _autoApplyEnabled comment in ThemeManager for why. Settings.qml
        // never sets this so its ThemeManager singleton stays passive.
        ThemeManager._autoApplyEnabled = true
    }


    // Panel families
    property list<string> families: ["ii", "waffle"]
    function cyclePanelFamily() {
        const currentIndex = families.indexOf(Config.options.panelFamily)
        const nextIndex = (currentIndex + 1) % families.length
        Config.options.panelFamily = families[nextIndex]
    }

    component PanelFamilyLoader: LazyLoader {
        required property string identifier
        property bool extraCondition: true
        active: Config.ready && Config.options.panelFamily === identifier && extraCondition
    }
    
    PanelFamilyLoader {
        identifier: "ii"
        component: IllogicalImpulseFamily {}
    }

    PanelFamilyLoader {
        identifier: "waffle"
        component: WaffleFamily {}
    }


    // Shortcuts
    IpcHandler {
        target: "panelFamily"

        function cycle(): void {
            root.cyclePanelFamily()
        }
    }

    GlobalShortcut {
        name: "panelFamilyCycle"
        description: "Cycles panel family"

        onPressed: root.cyclePanelFamily()
    }
}

