pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions

/**
 * Lossless keybind reader for the settings keybinds editor.
 *
 * Parallel to `HyprlandKeybinds` (which drops `[hidden]` lines for the
 * cheatsheet). This service preserves every `bind*` line with line
 * numbers so the editor can round-trip and edit-in-place.
 *
 * Refreshes on Hyprland's `configreloaded` event with a 100ms debounce
 * to avoid reading mid-write.
 */
Singleton {
    id: root

    readonly property string parserPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/get_keybinds_raw.py`)
    readonly property string defaultPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/keybinds.conf`)
    readonly property string userPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybinds.conf`)

    property var defaultData: ({ binds: [], unbinds: [], submapsDefined: [], exists: false })
    property var userData: ({ binds: [], unbinds: [], submapsDefined: [], exists: false })
    property int revision: 0

    signal reloaded()

    function refresh() {
        getDefault.running = false; getDefault.running = true
        getUser.running = false;    getUser.running = true
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded")
                debounceTimer.restart()
        }
    }

    Timer {
        id: debounceTimer
        interval: 100
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: getDefault
        running: true
        command: [root.parserPath, "--path", root.defaultPath]
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.defaultData = JSON.parse(data)
                } catch (e) {
                    console.error("[HyprlandKeybindsRaw] parse default failed:", e, String(data).slice(0, 200))
                }
                root.revision = root.revision + 1
                root.reloaded()
            }
        }
    }

    Process {
        id: getUser
        running: true
        command: [root.parserPath, "--path", root.userPath]
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.userData = JSON.parse(data)
                } catch (e) {
                    console.error("[HyprlandKeybindsRaw] parse user failed:", e, String(data).slice(0, 200))
                }
                root.revision = root.revision + 1
                root.reloaded()
            }
        }
    }

    /**
     * Returns the merged owned + locked bind list.
     *
     * Locked = default-file binds whose (mods, key) combo is NOT
     * unbound by a user-file `unbind = ...` line and is NOT shadowed
     * by a user-file bind on the same combo.
     *
     * Owned = all user-file binds (editable in place).
     */
    function buildMergedList() {
        const userUnbinds = (userData.unbinds || []).map(u => _comboKey(u.mods, u.key))
        const userBindCombos = (userData.binds || []).map(b => _comboKey(b.mods, b.key))
        const userUnbindSet = {}
        for (const c of userUnbinds) userUnbindSet[c] = true
        const userBindSet = {}
        for (const c of userBindCombos) userBindSet[c] = true

        const owned = (userData.binds || []).map(b => Object.assign({}, b, {
            isOwned: true,
            isOverride: userUnbindSet[_comboKey(b.mods, b.key)] === true,
            sourcePath: root.userPath
        }))

        const locked = []
        for (const b of (defaultData.binds || [])) {
            const c = _comboKey(b.mods, b.key)
            // If user-file overrides this exact combo via unbind+bind or just
            // unbinds it without rebinding, skip showing the original.
            if (userUnbindSet[c] || userBindSet[c]) continue
            locked.push(Object.assign({}, b, {
                isOwned: false,
                isOverride: false,
                sourcePath: root.defaultPath
            }))
        }

        return { owned: owned, locked: locked }
    }

    function _comboKey(mods, key) {
        const m = (mods || []).filter(x => x).map(x => x.toLowerCase()).sort().join("+")
        return m + "|" + (key || "").toLowerCase()
    }
}
