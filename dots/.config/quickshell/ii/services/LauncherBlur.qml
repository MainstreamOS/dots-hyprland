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
 * and when it closes it is put back to whatever the file says. The file
 * rather than a remembered value, because the settings page and a theme apply
 * both write there and nothing kept here could be trusted to match. The bar
 * and the dock float above the dim and share the swap for those moments; the
 * dim arriving over the whole screen is when the eye is least on them.
 */
Singleton {
    id: root

    readonly property string configDir: FileUtils.trimFileProtocol(Directories.config)
    readonly property string decorationsPy: `${configDir}/quickshell/ii/scripts/themes/decorations.py`
    readonly property string generalConf: `${configDir}/hypr/hyprland/general.lua`
    readonly property string flagDir: `${configDir}/hypr/custom`
    readonly property string depthKeys: "blurSize,blurPasses,blurNoise,blurVibrancy"

    function load() {} // For forcing singleton initialization

    // The stock depth never changes while the shell runs, so what opening the
    // launcher sends is worked out once from the schema, in the same form
    // decorations.py sends it, and handed to hyprctl directly rather than
    // starting Python on every open. Closing still goes through the file,
    // which is the one place the user's own depth is kept current.
    property string stockEval: ""
    function _lua(value, kind) {
        if (kind === "int")
            return String(Math.round(Number(value)))
        const text = Number(value).toFixed(4).replace(/0+$/, "").replace(/\.$/, "")
        return text.length > 0 ? text : "0"
    }
    FileView {
        path: `${root.configDir}/quickshell/ii/scripts/themes/decorations-schema.json`
        printErrors: false
        onLoaded: {
            try {
                const keys = root.depthKeys.split(",")
                const sections = ({})
                for (const row of JSON.parse(text()).keys) {
                    if (!keys.includes(row.key) || !row.hypr || row.default === undefined)
                        continue
                    const parts = row.hypr.split(":")
                    const leaf = parts.slice(1).join(".")
                    ;(sections[parts[0]] = sections[parts[0]] ?? []).push(`["${leaf}"] = ${root._lua(row.default, row.type)}`)
                }
                const body = Object.keys(sections).map(s => `${s} = { ${sections[s].join(", ")} }`).join(", ")
                root.stockEval = body.length > 0 ? `hl.config({ ${body} })` : ""
            } catch (e) {
                root.stockEval = ""
            }
        }
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            // Only the depth moves; whether the blur reads through to the
            // wallpaper is a look, not a strength, and stays the user's.
            if (GlobalStates.overviewOpen && root.stockEval.length > 0)
                Quickshell.execDetached(["hyprctl", "eval", root.stockEval])
            else if (GlobalStates.overviewOpen)
                Quickshell.execDetached(["python3", root.decorationsPy, "push-defaults", root.generalConf,
                                         "--keys", root.depthKeys])
            else
                Quickshell.execDetached(["python3", root.decorationsPy, "sync", root.generalConf,
                                         "--flag-dir", root.flagDir, "--keys", root.depthKeys])
        }
    }
}
