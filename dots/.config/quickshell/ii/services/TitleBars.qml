pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * TitleBars — single source of truth for the hyprbars (Hyprland window
 * title bars) plugin toggle.
 *
 * The plugin is ALWAYS loaded (general.lua loads it unconditionally) and is
 * never unloaded at runtime: a runtime `hyprctl plugin unload` leaves a
 * dangling mouse-move hook that segfaults the compositor. On/off is instead a
 * flag file — ~/.config/hypr/custom/titlebars.enabled ("1"/"0", absent = on)
 * — which general.lua reads on every reload to set plugin:hyprbars:enabled,
 * bar_height, and the buttons. setEnabled() writes the flag and runs
 * `hyprctl reload` (which keeps the .so loaded, so no dangling hook).
 *
 * Both Settings → Layouts and Settings → Interface call into this service,
 * so neither page can drift out of sync with the other.
 */
Singleton {
    id: root

    // On/off persists in this flag file ("1"/"0", absent = on); general.lua
    // reads it on every reload to drive plugin:hyprbars:enabled.
    readonly property string flagPath: `${FileUtils.trimFileProtocol(Directories.config)}/hypr/custom/titlebars.enabled`

    // Whether title bars are on. Mirrors the titlebars.enabled flag; refreshed
    // at startup and after a theme apply. Read-only to consumers — call
    // setEnabled() to change it.
    property bool enabled: false

    // Flips true once readerProc has produced its first result. Consumers
    // bind their Switch's `animateChanges` to this so the toggle position
    // snaps in from the file-state on page-open instead of animating from
    // the default false → restored true on every menu reopen. The flag
    // STAYS true once set — subsequent re-reads (theme apply etc.) keep
    // user-driven animations intact.
    property bool enabledLoaded: false

    function load() {} // For forcing singleton initialization

    function refresh() {
        readerProc.running = false
        readerProc.running = true
    }

    // Flip the title-bars plugin on or off. Persists the flag, then reloads
    // Hyprland — general.lua re-reads the flag and applies enabled/height/
    // buttons. The plugin is NEVER unloaded (reload keeps the .so loaded), so
    // there is no dangling mouse hook and no compositor crash.
    function setEnabled(value) {
        if (value === root.enabled) return
        root.enabled = value
        Quickshell.execDetached(["sh", "-c",
            `printf '%s' '${value ? "1" : "0"}' > '${root.flagPath}' && hyprctl reload`])
    }

    Process {
        id: readerProc
        // Read the flag; a missing file makes `cat` fail so buf stays empty
        // and we default to on.
        command: ["sh", "-c", `cat '${root.flagPath}' 2>/dev/null || echo 1`]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => readerProc.buf += data + "\n" }
        onExited: {
            root.enabled = readerProc.buf.trim() !== "0"
            // First read complete — Switches can start animating from here.
            root.enabledLoaded = true
        }
    }

    // Apply-theme can rewrite the plugin directive (decorations.json
    // captures titleBars true/false per theme). Re-read after each
    // theme apply so the Settings switches reflect the new state.
    Connections {
        target: Config
        function onThemeApplyInProgressChanged() {
            if (Config.themeApplyInProgress) return
            root.refresh()
        }
    }

    Component.onCompleted: refresh()
}
