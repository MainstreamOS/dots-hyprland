pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

/**
 * Paints the window border from two roles of the current palette.
 *
 * The palette's own border colour is written by matugen into
 * hypr/hyprland/colors.lua on every wallpaper change. This writes to the
 * shell's override file instead, which is required after that one, so the
 * choice survives a regeneration — and clearing it hands the border straight
 * back to matugen rather than leaving a stale copy behind.
 *
 * Two modes. Palette mode holds role names rather than colours, so the pair is
 * re-derived from whatever palette is current and the border keeps up with the
 * wallpaper the way the rest of the desktop does. Custom mode holds the two
 * colours literally and stops tracking the wallpaper, which is the point of
 * asking for them. Either way the choice lives in config.json, so a theme
 * carries it.
 */
Singleton {
    id: root

    readonly property string activeKey: "general:col:active_border"
    readonly property string inactiveKey: "general:col:inactive_border"
    readonly property var opts: Config.options?.appearance?.borderGradient ?? null
    readonly property var inactiveOpts: Config.options?.appearance?.borderGradientInactive ?? null

    function load() {}

    function _alpha(alphaPercent) {
        return Math.round(Math.max(0, Math.min(100, alphaPercent)) * 2.55)
            .toString(16).padStart(2, "0")
    }

    function _rgba(role, alphaPercent) {
        const colour = Appearance.m3colors["m3" + role]
        if (!colour) return ""
        const hex = n => Math.round(Math.max(0, Math.min(255, n * 255)))
            .toString(16).padStart(2, "0")
        return `rgba(${hex(colour.r)}${hex(colour.g)}${hex(colour.b)}${root._alpha(alphaPercent)})`
    }

    function _hexRgba(hex, alphaPercent) {
        const rgb = String(hex).trim().replace(/^#/, "").toLowerCase()
        if (!/^[0-9a-f]{6}$/.test(rgb)) return ""
        return `rgba(${rgb}${root._alpha(alphaPercent)})`
    }

    // The focused and the unfocused borders are the same machinery pointed at
    // two keys. A lane's payload is its gradient, null to clear, or undefined
    // to leave the key alone — and both lanes travel in one write, because two
    // detached edits of the same file race and the loser's key survives.
    function lanePayload(o) {
        if (!o || !o.enable) return null
        const a = o.custom ? root._hexRgba(o.customFrom, o.opacity) : root._rgba(o.from, o.opacity)
        const b = o.custom ? root._hexRgba(o.customTo, o.opacity) : root._rgba(o.to, o.opacity)
        // A role missing from the palette, or a hand-edited colour that isn't
        // one, would otherwise write an empty colour: Hyprland rejects it and
        // the border stays on whatever it happened to be.
        if (a.length === 0 || b.length === 0) return undefined
        return `{colors={"${a}","${b}"},angle=${Math.round(o.angle)}}`
    }

    // What the override file was last told. A palette moves on every wallpaper
    // change, and with both lanes off the write is two resets of keys that are
    // already absent — a process and a full config reload for no difference,
    // repeatedly, while a slideshow is running.
    property string _lastApplied: ""

    function apply() {
        if (!Config.ready) return
        const entries = ({})
        const lanes = [[root.activeKey, root.opts], [root.inactiveKey, root.inactiveOpts]]
        for (const [key, o] of lanes) {
            const payload = root.lanePayload(o)
            if (payload !== undefined)
                entries[key] = payload
        }
        const signature = JSON.stringify(entries)
        if (signature === root._lastApplied) return
        root._lastApplied = signature
        HyprlandConfig.applyLuaMany(entries)
    }

    // Re-derived whenever the palette moves, which is what keeps it in step
    // with the wallpaper.
    Connections {
        target: Appearance.m3colors
        function onM3primaryChanged() { applyDebounce.restart() }
        function onM3backgroundChanged() { applyDebounce.restart() }
    }
    Connections {
        target: root.opts
        function onEnableChanged() { applyDebounce.restart() }
        function onFromChanged() { applyDebounce.restart() }
        function onToChanged() { applyDebounce.restart() }
        function onCustomChanged() { applyDebounce.restart() }
        function onCustomFromChanged() { applyDebounce.restart() }
        function onCustomToChanged() { applyDebounce.restart() }
        function onAngleChanged() { applyDebounce.restart() }
        function onOpacityChanged() { applyDebounce.restart() }
    }
    Connections {
        target: root.inactiveOpts
        function onEnableChanged() { applyDebounce.restart() }
        function onFromChanged() { applyDebounce.restart() }
        function onToChanged() { applyDebounce.restart() }
        function onCustomChanged() { applyDebounce.restart() }
        function onCustomFromChanged() { applyDebounce.restart() }
        function onCustomToChanged() { applyDebounce.restart() }
        function onAngleChanged() { applyDebounce.restart() }
        function onOpacityChanged() { applyDebounce.restart() }
    }
    Connections {
        target: Config
        function onReadyChanged() { if (Config.ready) applyDebounce.restart() }
    }

    // Each apply is a process and a compositor reload, and a palette change
    // moves several roles at once.
    Timer {
        id: applyDebounce
        interval: 250
        onTriggered: root.apply()
    }
}
