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

    // How the bar is painted. Both persist beside the on/off flag and are read
    // by general.lua on the same reload.
    //
    // An empty color means the plugin keeps the one it chooses for itself: a
    // theme written before these existed carries neither key, and inventing a
    // color for it would repaint every bar on the machine off the back of an
    // update.
    readonly property string colorPath: `${FileUtils.trimFileProtocol(Directories.config)}/hypr/custom/titlebars.color`
    readonly property string opacityPath: `${FileUtils.trimFileProtocol(Directories.config)}/hypr/custom/titlebars.opacity`

    property string color: ""
    // The plugin's untouched bar ships at 88 alpha over its stock gray, so
    // this default keeps the opacity slider continuous with that look until
    // the user moves it.
    property real opacity: 0.5333
    property bool appearanceLoaded: false

    // Written together, because they compose into one value the plugin reads:
    // hyprbars takes a single bar_color carrying its own alpha, so a colour
    // saved without its opacity would land at whatever the other file last
    // said. One reload covers both.
    //
    // The values travel as arguments rather than inside the script, so a colour
    // string stays a colour string whatever it contains.
    function setAppearance(newColor, newOpacity) {
        root.color = newColor
        root.opacity = newOpacity
        Quickshell.execDetached(["bash", "-c",
            'printf "%s" "$1" > "$0" && printf "%s" "$3" > "$2" && hyprctl reload',
            root.colorPath, String(newColor),
            root.opacityPath, String(newOpacity)])
    }

    Process {
        id: readerProc
        // All three read in one pass, newline separated, so the service never
        // shows an on/off state from one moment beside a colour from another.
        // A missing file makes `cat` fail, and the fallback on each line is the
        // value that means "as it was".
        // The newline after each field is written here rather than by the
        // fallback, because `echo` brings one of its own and `printf` does not:
        // a missing file would otherwise end a field with two and push
        // everything after it down a line.
        command: ["bash", "-c",
            '{ cat "$0" 2>/dev/null || printf 1; }; printf "\\n"; ' +
            '{ cat "$1" 2>/dev/null; }; printf "\\n"; ' +
            '{ cat "$2" 2>/dev/null || printf 0.5333; }; printf "\\n"',
            root.flagPath, root.colorPath, root.opacityPath]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => readerProc.buf += data + "\n" }
        onExited: {
            // One line each: the parser has already split on the newlines the
            // separators put between them.
            const lines = readerProc.buf.split("\n")
            root.enabled = (lines[0] ?? "").trim() !== "0"
            root.color = (lines[1] ?? "").trim()
            const o = parseFloat((lines[2] ?? "").trim())
            root.opacity = isNaN(o) ? 1.0 : Math.max(0, Math.min(1, o))
            // First read complete — Switches can start animating from here.
            root.enabledLoaded = true
            root.appearanceLoaded = true
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
