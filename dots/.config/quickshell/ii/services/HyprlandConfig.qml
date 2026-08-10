pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs.modules.common
import qs.modules.common.functions

/**
 * Configs Hyprland
 */
Singleton {
    id: root
    
    signal reloaded()

    readonly property string configuratorScriptPath: Quickshell.shellPath("scripts/hyprland/hyprconfigurator.py")
    readonly property string shellOverridesPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/shellOverrides/main.lua`)

    function set(key: string, value: var) {
        Quickshell.execDetached(["bash", "-c", //
            `${root.configuratorScriptPath} --file ${root.shellOverridesPath} --set "${key}" "${value}"` //
        ])
    }
    
    // A value written through as Lua rather than quoted, for the settings that
    // are a table: a gradient is {colors={...},angle=N}, and the single-string
    // form is rejected.
    function setLua(key: string, lua: string) {
        Quickshell.execDetached(["bash", "-c", //
            `${root.configuratorScriptPath} --file ${root.shellOverridesPath} --set-lua "${key}" '${lua}'` //
        ])
    }

    function setMany(entries: var) {
        let args = ""
        for (let key in entries) {
            args += `--set "${key}" "${entries[key]}" `
        }
        Quickshell.execDetached(["bash", "-c", //
            `${root.configuratorScriptPath} --file ${root.shellOverridesPath} ${args}` //
        ])
    }
    
    // Every entry lands in one invocation — a value as --set-lua, a null as
    // --reset. Two detached edits of the same file race read-modify-replace,
    // and the loser's key comes back from the dead.
    function applyLuaMany(entries: var) {
        let args = ""
        for (let key in entries) {
            if (entries[key] === null)
                args += `--reset "${key}" `
            else
                args += `--set-lua "${key}" '${entries[key]}' `
        }
        if (args.length === 0) return
        Quickshell.execDetached(["bash", "-c",
            `${root.configuratorScriptPath} --file ${root.shellOverridesPath} ${args}`])
    }

    function reset(key: string) {
        Quickshell.execDetached(["bash", "-c", //
            `${root.configuratorScriptPath} --file ${root.shellOverridesPath} --reset "${key}"` //
        ])
    }
    
    function resetMany(keys: list<string>) {
        let args = ""
        for (let i = 0; i < keys.length; i++) {
            args += `--reset "${keys[i]}" `
        }
        Quickshell.execDetached(["bash", "-c", //
            `${root.configuratorScriptPath} --file ${root.shellOverridesPath} ${args}` //
        ])
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                root.reloaded()
            }
        }
    }
}
