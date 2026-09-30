pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * LauncherBlur — the launcher's frost stays at the shipped depth.
 *
 * The compositor has one blur depth for everything it frosts, read at draw
 * time, and the launcher's dim is frosted by the compositor because it has to
 * blur the windows behind it, which the shell cannot sample. So the depth the
 * Blur depth sliders choose for windows reached the launcher too, and a light
 * setting meant for a window edge left the launcher barely frosted.
 *
 * While the launcher is open the compositor is handed the stock blur depth,
 * and when it closes it gets back the depth it had when the launcher opened.
 * Both are read from and handed to the compositor directly, rather than
 * through a Python run each way. If something else changed the depth while
 * the launcher was open (the settings page, a theme apply), that is the newer
 * choice and is left alone. The bar and the dock float above the dim and share
 * the swap for those moments; the dim arriving over the whole screen is when
 * the eye is least on them.
 *
 * An answer from the compositor that can't be read falls back to the earlier
 * way: the stock depth on open, and on close whatever the file says.
 */
Singleton {
    id: root

    readonly property string configDir: FileUtils.trimFileProtocol(Directories.config)
    readonly property string decorationsPy: `${configDir}/quickshell/ii/scripts/themes/decorations.py`
    readonly property string generalConf: `${configDir}/hypr/hyprland/general.lua`
    readonly property string flagDir: `${configDir}/hypr/custom`
    readonly property string depthKeys: "blurSize,blurPasses,blurNoise,blurVibrancy"

    function load() {} // For forcing singleton initialization

    // Each depth setting's option, kind and stock value, read once from the
    // schema decorations.py works from.
    property var depthRows: []
    FileView {
        path: `${root.configDir}/quickshell/ii/scripts/themes/decorations-schema.json`
        printErrors: false
        onLoaded: {
            try {
                const keys = root.depthKeys.split(",")
                root.depthRows = JSON.parse(text()).keys.filter(row =>
                    keys.includes(row.key) && row.hypr && row.default !== undefined)
            } catch (e) {
                root.depthRows = []
            }
        }
    }

    // Written the way decorations.py writes a value, so the same depth reads
    // the same whichever of the two sent it.
    function _lua(value, kind) {
        if (kind === "int")
            return String(Math.round(Number(value)))
        const text = Number(value).toFixed(4).replace(/0+$/, "").replace(/\.$/, "")
        return text.length > 0 ? text : "0"
    }
    function _evalFor(values) {
        const sections = ({})
        for (const row of root.depthRows) {
            const parts = row.hypr.split(":")
            ;(sections[parts[0]] = sections[parts[0]] ?? []).push(`["${parts.slice(1).join(".")}"] = ${root._lua(values[row.key], row.type)}`)
        }
        const body = Object.keys(sections).map(s => `${s} = { ${sections[s].join(", ")} }`).join(", ")
        return body.length > 0 ? `hl.config({ ${body} })` : ""
    }
    function _stock() {
        const values = ({})
        for (const row of root.depthRows)
            values[row.key] = row.default
        return values
    }
    function _same(a, b) {
        return root.depthRows.every(row => root._lua(a[row.key], row.type) === root._lua(b[row.key], row.type))
    }
    // The compositor's answer to one getoption per setting, as {key: value},
    // or null when it doesn't give a number for every one of them. Matched on
    // the option's name, or on the order they were asked in when the names
    // come back spelled another way.
    function _parse(text) {
        const byName = ({})
        const inOrder = []
        for (const m of (text ?? "").match(/\{[^{}]*\}/g) ?? []) {
            try {
                const o = JSON.parse(m)
                const v = o.int ?? o.float
                if (typeof v !== "number") continue
                inOrder.push(v)
                if (typeof o.option === "string") byName[o.option] = v
            } catch (e) {}
        }
        if (root.depthRows.length === 0) return null
        const out = ({})
        const named = root.depthRows.every(row => byName[row.hypr] !== undefined)
        if (!named && inOrder.length !== root.depthRows.length) return null
        root.depthRows.forEach((row, i) => out[row.key] = named ? byName[row.hypr] : inOrder[i])
        return out
    }
    function _readCommand() {
        return ["hyprctl", "--batch", root.depthRows.map(row => `j/getoption ${row.hypr}`).join(" ; ")]
    }

    // idle: the compositor has the user's depth. opening: reading it. pushed:
    // stock is on, `saved` holds theirs. closing: checking before putting it
    // back. untouched: theirs is stock, nothing to swap. fallback: the earlier
    // way, for an answer that couldn't be read.
    property string phase: "idle"
    property var saved: null

    function _pushStock() {
        const lua = root._evalFor(root._stock())
        if (lua.length > 0)
            Quickshell.execDetached(["hyprctl", "eval", lua])
        else
            Quickshell.execDetached(["python3", root.decorationsPy, "push-defaults", root.generalConf,
                                     "--keys", root.depthKeys])
    }
    function _syncFromFile() {
        Quickshell.execDetached(["python3", root.decorationsPy, "sync", root.generalConf,
                                 "--flag-dir", root.flagDir, "--keys", root.depthKeys])
    }

    Process {
        id: openRead
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.phase !== "opening") return
                const now = root._parse(text)
                if (!now) {
                    root.phase = "fallback"
                    root._pushStock()
                } else if (root._same(now, root._stock())) {
                    root.phase = "untouched"
                } else {
                    root.saved = now
                    root.phase = "pushed"
                    root._pushStock()
                }
            }
        }
    }
    Process {
        id: closeRead
        stdout: StdioCollector {
            onStreamFinished: {
                // Opened again before this came back: stock is still on and
                // what was saved still stands.
                if (root.phase !== "closing") return
                root.phase = "idle"
                const now = root._parse(text)
                if (!now)
                    root._syncFromFile()
                else if (root._same(now, root._stock()))
                    Quickshell.execDetached(["hyprctl", "eval", root._evalFor(root.saved)])
            }
        }
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            // Only the depth moves; whether the blur reads through to the
            // wallpaper is a look, not a strength, and stays the user's.
            if (GlobalStates.overviewOpen) {
                if (root.phase === "pushed" || root.phase === "closing") {
                    root.phase = "pushed"
                } else if (root.depthRows.length === 0) {
                    root.phase = "fallback"
                    root._pushStock()
                } else {
                    root.phase = "opening"
                    openRead.command = root._readCommand()
                    openRead.running = true
                }
                return
            }
            if (root.phase === "pushed") {
                root.phase = "closing"
                closeRead.command = root._readCommand()
                closeRead.running = true
            } else {
                if (root.phase === "fallback")
                    root._syncFromFile()
                root.phase = "idle"
            }
        }
    }
}
