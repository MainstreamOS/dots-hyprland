pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Cheatsheet keybind reader — feeds CheatsheetKeybinds.qml the nested
 * {children, keybinds, name} tree the section-aware UI walks.
 *
 * Parses BOTH the fork default file (hyprland/keybinds.lua) and the user
 * file (custom/keybinds.lua), merging their top-level children so user
 * sections render alongside the defaults.
 *
 * Refreshes on Hyprland's `configreloaded` event.
 */
Singleton {
    id: root
    // Targets the Lua-config tree introduced in Hyprland 0.55.
    property string keybindParserPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hyprland/get_keybinds.py`)
    property string defaultKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/keybinds.lua`)
    property string userKeybindConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/keybinds.lua`)
    property var defaultKeybinds: ({ children: [], keybinds: [], name: "" })
    property var userKeybinds: ({ children: [], keybinds: [], name: "" })
    property var keybinds: ({
        children: [
            ...(defaultKeybinds.children ?? []),
            ...(userKeybinds.children ?? []),
        ]
    })

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                getDefaultKeybinds.running = true
                getUserKeybinds.running = true
            }
        }
    }

    Process {
        id: getDefaultKeybinds
        running: true
        command: [root.keybindParserPath, "--path", root.defaultKeybindConfigPath]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.defaultKeybinds = JSON.parse(text)
                } catch (e) {
                    console.error("[HyprlandKeybinds] parse default failed:", e, String(text).slice(0, 200))
                }
            }
        }
    }

    Process {
        id: getUserKeybinds
        running: true
        command: [root.keybindParserPath, "--path", root.userKeybindConfigPath]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.userKeybinds = JSON.parse(text)
                } catch (e) {
                    console.error("[HyprlandKeybinds] parse user failed:", e, String(text).slice(0, 200))
                }
            }
        }
    }
}
