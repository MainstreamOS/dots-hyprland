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

    // How the bar is painted, saved beside the on/off flag and read by
    // plugins.lua on the same reload.
    //
    // Dark mode and light mode each keep their own colors: the dark set under
    // the plain names and the light set under the same names ending in Light.
    // plugins.lua picks the set from custom/colormode, which switchwall.sh
    // writes as it settles the mode. An empty color or opacity is that mode's
    // stock one. The button size is one value for both modes.
    readonly property string customDir: `${FileUtils.trimFileProtocol(Directories.config)}/hypr/custom`
    function slotPath(name, dark) {
        return `${root.customDir}/${name}${dark ? "" : "Light"}`
    }

    // The mode on screen, whose set the properties below show and edits land in.
    readonly property bool dark: Appearance.m3colors.darkmode

    property string colorDark: ""
    property string colorLight: ""
    readonly property string color: root.dark ? root.colorDark : root.colorLight
    // The plugin's untouched bar ships at 88 alpha over its stock gray, so
    // the dark default keeps the opacity slider continuous with that look
    // until the user moves it.
    readonly property real defaultOpacityDark: 0.5333
    readonly property real defaultOpacityLight: 0.3
    property real opacityDark: root.defaultOpacityDark
    property real opacityLight: root.defaultOpacityLight
    readonly property real opacity: root.dark ? root.opacityDark : root.opacityLight
    property bool appearanceLoaded: false

    // The buttons keep their own size and colors, apart from the bar's, so a
    // bar color pick does not drag them along with it. The highlight is the
    // circle behind a button while the pointer is over it.
    readonly property string buttonSizePath: `${root.customDir}/titlebars.buttonSize`

    // The bar height plugins.lua sets, and the ceiling it puts on a button:
    // past about three fifths of the bar there is no room left around the icon.
    // Below about two fifths the icon, drawn at 0.62 of the button, is too
    // small to read and the button too small to hit, so that is the floor.
    // Kept here as well so the slider cannot offer a size the plugin clamps.
    readonly property real barHeight: 30
    readonly property real minButtonSize: Math.ceil(barHeight * 0.4)
    readonly property real maxButtonSize: Math.floor(barHeight * 0.6)
    // Half the bar, which sits inside that ceiling with room left around the icon.
    readonly property real defaultButtonSize: Math.round(barHeight * 0.5)

    property real buttonSize: defaultButtonSize
    property string buttonBackgroundDark: ""
    property string buttonBackgroundLight: ""
    property string buttonIconColorDark: ""
    property string buttonIconColorLight: ""
    property string buttonHighlightDark: ""
    property string buttonHighlightLight: ""
    readonly property string buttonBackground: root.dark ? root.buttonBackgroundDark : root.buttonBackgroundLight
    readonly property string buttonIconColor: root.dark ? root.buttonIconColorDark : root.buttonIconColorLight
    readonly property string buttonHighlight: root.dark ? root.buttonHighlightDark : root.buttonHighlightLight

    // What plugins.lua draws for an empty color in the mode on screen, as the
    // pickers show it. The swatch has no alpha to show, so a see-through stock
    // color appears here as its opaque self.
    readonly property string defaultColor: root.dark ? "#333333" : "#f3f3f3"
    readonly property string defaultButtonBackground: root.dark ? "#49454e" : "#d8d3dd"
    readonly property string defaultButtonIconColor: root.dark ? "#ffffff" : "#1d1b20"
    readonly property string defaultButtonHighlight: root.dark ? "#6c6675" : "#b5afbc"

    // Whether either mode holds a color or opacity of its own, so a reset can
    // be offered for the mode that is not on screen as well.
    readonly property bool anyModeValueSet: [root.colorDark, root.colorLight,
        root.buttonBackgroundDark, root.buttonBackgroundLight,
        root.buttonIconColorDark, root.buttonIconColorLight,
        root.buttonHighlightDark, root.buttonHighlightLight].some(c => c !== "")
        || Math.abs(root.opacityDark - root.defaultOpacityDark) > 0.0001
        || Math.abs(root.opacityLight - root.defaultOpacityLight) > 0.0001

    // The plugin empties its button list before each config reload and the Lua
    // config fills it again, so the size and one mode's colors travel together
    // and one reload redraws them. The mode is the caller's to name, because
    // an edit waiting on a debounce belongs to the mode it was made in.
    function setButtons(newSize, newColor, newIconColor, newHighlight, dark) {
        const d = dark === undefined ? root.dark : dark
        root.buttonSize = newSize
        if (d) {
            root.buttonBackgroundDark = newColor
            root.buttonIconColorDark = newIconColor
            root.buttonHighlightDark = newHighlight
        } else {
            root.buttonBackgroundLight = newColor
            root.buttonIconColorLight = newIconColor
            root.buttonHighlightLight = newHighlight
        }
        Quickshell.execDetached(["bash", "-c",
            'printf "%s" "$1" > "$0" && printf "%s" "$3" > "$2" && printf "%s" "$5" > "$4" && printf "%s" "$7" > "$6" && hyprctl reload',
            root.buttonSizePath, String(newSize),
            root.slotPath("titlebars.buttonBackground", d), String(newColor),
            root.slotPath("titlebars.buttonIconColor", d), String(newIconColor),
            root.slotPath("titlebars.buttonHighlight", d), String(newHighlight)])
    }

    // The buttons can stay hidden until the pointer is over the bar, saved
    // beside the other title bar values and applied on the same reload.
    readonly property string buttonsOnHoverPath: `${root.customDir}/titlebars.buttonsOnHover`
    property bool buttonsOnHover: false

    function setButtonsOnHover(value) {
        if (value === root.buttonsOnHover) return
        root.buttonsOnHover = value
        Quickshell.execDetached(["bash", "-c",
            'printf "%s" "$1" > "$0" && hyprctl reload',
            root.buttonsOnHoverPath, value ? "1" : "0"])
    }

    // The close, maximize and minimize buttons can be left off the bars
    // altogether. On unless switched off, so an absent file reads as on.
    // plugins.lua adds none while this says "0", and the plugin empties its
    // list before each reload, so one reload takes them away or brings them
    // back.
    readonly property string buttonsEnabledPath: `${root.customDir}/titlebars.buttons`
    property bool buttonsEnabled: true

    function setButtonsEnabled(value) {
        if (value === root.buttonsEnabled) return
        root.buttonsEnabled = value
        Quickshell.execDetached(["bash", "-c",
            'printf "%s" "$1" > "$0" && hyprctl reload',
            root.buttonsEnabledPath, value ? "1" : "0"])
    }

    // Scrolling on a title bar steps its window between minimized, normal,
    // maximized and fullscreen. On unless switched off, so an absent file
    // reads as on. Saved beside the other title bar values and applied on
    // the same reload.
    readonly property string scrollActionsPath: `${root.customDir}/titlebars.scrollActions`
    property bool scrollActions: true

    function setScrollActions(value) {
        if (value === root.scrollActions) return
        root.scrollActions = value
        Quickshell.execDetached(["bash", "-c",
            'printf "%s" "$1" > "$0" && hyprctl reload',
            root.scrollActionsPath, value ? "1" : "0"])
    }

    // Written together, because they compose into one value the plugin reads:
    // hyprbars takes a single bar_color carrying its own alpha, so a colour
    // saved without its opacity would land at whatever the other file last
    // said. One reload covers both.
    //
    // The values travel as arguments rather than inside the script, so a colour
    // string stays a colour string whatever it contains.
    function setAppearance(newColor, newOpacity, dark) {
        const d = dark === undefined ? root.dark : dark
        if (d) {
            root.colorDark = newColor
            root.opacityDark = newOpacity
        } else {
            root.colorLight = newColor
            root.opacityLight = newOpacity
        }
        Quickshell.execDetached(["bash", "-c",
            'printf "%s" "$1" > "$0" && printf "%s" "$3" > "$2" && hyprctl reload',
            root.slotPath("titlebars.color", d), String(newColor),
            root.slotPath("titlebars.opacity", d), String(newOpacity)])
    }

    // Everything back to how the title bars come, both modes at once, under a
    // single reload. The buttons come with the bars, so they return too.
    function resetAppearance() {
        root.colorDark = ""
        root.colorLight = ""
        root.opacityDark = root.defaultOpacityDark
        root.opacityLight = root.defaultOpacityLight
        root.buttonsEnabled = true
        root.buttonSize = root.defaultButtonSize
        root.buttonBackgroundDark = ""
        root.buttonBackgroundLight = ""
        root.buttonIconColorDark = ""
        root.buttonIconColorLight = ""
        root.buttonHighlightDark = ""
        root.buttonHighlightLight = ""
        const emptied = []
        for (const name of ["titlebars.color", "titlebars.opacity", "titlebars.buttonBackground",
                "titlebars.buttonIconColor", "titlebars.buttonHighlight"])
            emptied.push(root.slotPath(name, true), root.slotPath(name, false))
        Quickshell.execDetached(["bash", "-c",
            'printf "%s" "$1" > "$0" && printf "%s" "$3" > "$2" && shift 3 && for f in "$@"; do : > "$f" || exit; done && hyprctl reload',
            root.buttonSizePath, String(root.defaultButtonSize),
            root.buttonsEnabledPath, "1"].concat(emptied))
    }

    Process {
        id: readerProc
        // Read in one pass, one line per file, so the service never shows an
        // on/off state from one moment beside a color from another. A missing
        // file gives the value that means "as it was". Each value is cut to its
        // first line and given exactly one newline here, so a file that ends in
        // a newline of its own cannot push the fields after it down a line.
        command: ["bash", "-c",
            'while [ $# -gt 1 ]; do ' +
            'if v="$(head -n1 -- "$1" 2>/dev/null)"; then printf "%s\\n" "$v"; else printf "%s\\n" "$2"; fi; ' +
            'shift 2; done',
            "titlebars",
            root.flagPath, "1",
            root.slotPath("titlebars.opacity", true), "",
            root.slotPath("titlebars.opacity", false), "",
            root.buttonSizePath, String(root.defaultButtonSize),
            root.buttonsOnHoverPath, "0",
            root.slotPath("titlebars.color", true), "",
            root.slotPath("titlebars.color", false), "",
            root.slotPath("titlebars.buttonBackground", true), "",
            root.slotPath("titlebars.buttonBackground", false), "",
            root.slotPath("titlebars.buttonIconColor", true), "",
            root.slotPath("titlebars.buttonIconColor", false), "",
            root.slotPath("titlebars.buttonHighlight", true), "",
            root.slotPath("titlebars.buttonHighlight", false), "",
            root.scrollActionsPath, "1",
            root.buttonsEnabledPath, "1"]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => readerProc.buf += data + "\n" }
        onExited: {
            // One line each: the parser has already split on the newlines the
            // loop put between them.
            const lines = readerProc.buf.split("\n").map(l => l.trim())
            root.enabled = (lines[0] ?? "") !== "0"
            const od = parseFloat(lines[1] ?? "")
            root.opacityDark = isNaN(od) ? root.defaultOpacityDark : Math.max(0, Math.min(1, od))
            const ol = parseFloat(lines[2] ?? "")
            root.opacityLight = isNaN(ol) ? root.defaultOpacityLight : Math.max(0, Math.min(1, ol))
            const bs = parseFloat(lines[3] ?? "")
            root.buttonSize = isNaN(bs) ? root.defaultButtonSize : Math.max(root.minButtonSize, Math.min(root.maxButtonSize, bs))
            root.buttonsOnHover = (lines[4] ?? "") === "1"
            root.colorDark = lines[5] ?? ""
            root.colorLight = lines[6] ?? ""
            root.buttonBackgroundDark = lines[7] ?? ""
            root.buttonBackgroundLight = lines[8] ?? ""
            root.buttonIconColorDark = lines[9] ?? ""
            root.buttonIconColorLight = lines[10] ?? ""
            root.buttonHighlightDark = lines[11] ?? ""
            root.buttonHighlightLight = lines[12] ?? ""
            root.scrollActions = (lines[13] ?? "") !== "0"
            root.buttonsEnabled = (lines[14] ?? "") !== "0"
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
