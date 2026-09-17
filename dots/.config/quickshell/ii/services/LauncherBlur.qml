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

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            // Only the depth moves; whether the blur reads through to the
            // wallpaper is a look, not a strength, and stays the user's.
            if (GlobalStates.overviewOpen)
                Quickshell.execDetached(["python3", root.decorationsPy, "push-defaults", root.generalConf,
                                         "--keys", root.depthKeys])
            else
                Quickshell.execDetached(["python3", root.decorationsPy, "sync", root.generalConf,
                                         "--flag-dir", root.flagDir, "--keys", root.depthKeys])
        }
    }
}
