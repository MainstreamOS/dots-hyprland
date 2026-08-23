import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF
import qs.modules.common.widgets
import qs.modules.settings.windowrules

ContentPage {
    id: root
    forceWidth: true

    // Targets the Lua-config tree introduced in Hyprland 0.55.
    readonly property string generalConf: `${CF.FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprland/general.lua`
    property bool animationsEnabled: true
    property bool blurEnabled: true
    property bool shadowsEnabled: true
    property bool bordersEnabled: true
    property bool roundCornersEnabled: true
    property int  roundingValue: 10
    property int  shadowRangeValue: 20
    property int  shadowRenderPowerValue: 4
    property int  shadowOffsetXValue: 0
    property int  shadowOffsetYValue: 2
    property string shadowColorValue: "rgba(00000020)"
    property string animationProfileValue: "expressive"
    property int  borderSizeValue: 4
    property int  gapsInValue: 4
    property int  gapsOutValue: 5
    property int  blurSizeValue: 10
    property int  blurPassesValue: 3
    property real blurNoiseValue: 0.05
    property real blurVibrancyValue: 0.5
    property bool blurXrayEnabled: true
    property real activeOpacityValue: 1.0
    property real inactiveOpacityValue: 1.0
    property bool dimInactiveEnabled: true
    property real dimStrengthValue: 0.05
    property int previousCornerStyle: Config.options.bar.cornerStyle
    property bool _decoReady: false
    property int  cursorSize:      24

    property var sysGtkThemes: []
    property var sysIconThemes: []
    property var sysCursorThemes: []
    property string sysCurrentGtk: ""
    property string sysCurrentIcon: ""
    property string sysCurrentCursor: ""

    readonly property string gtkFontScript: Quickshell.env("HOME") + "/.config/quickshell/ii/scripts/themes/apply-gtk-font.sh"
    readonly property string cursorScript: Quickshell.env("HOME") + "/.config/quickshell/ii/scripts/cursor/apply-cursor.sh"
    readonly property string cursorSizeScript: Quickshell.env("HOME") + "/.config/quickshell/ii/scripts/cursor/cursor-sizes.py"

    // The sizes the chosen cursor theme can actually be drawn at. A cursor
    // theme is a set of bitmaps, so asking for a size it doesn't carry gets
    // the nearest one it does — offering the same five sizes for every theme
    // means some of them quietly do nothing. Empty means no restriction: the
    // theme is scalable, or isn't one we can read.
    property var cursorSizesAvailable: []

    // The sizes offered, snapped to what the theme has and with the duplicates
    // that snapping creates removed. A theme carrying all five keeps all five.
    readonly property var cursorSizeOptions: {
        const wanted = [
            { displayName: Translation.tr("Small"),   value: 16 },
            { displayName: Translation.tr("Default"), value: 24 },
            { displayName: Translation.tr("Large"),   value: 32 },
            { displayName: Translation.tr("Larger"),  value: 48 },
            { displayName: Translation.tr("Largest"), value: 64 },
        ];
        const have = root.cursorSizesAvailable;
        if (!have || have.length === 0) return wanted;
        let best = ({});
        for (const option of wanted) {
            let nearest = have[0];
            for (const size of have)
                if (Math.abs(size - option.value) < Math.abs(nearest - option.value))
                    nearest = size;
            const distance = Math.abs(nearest - option.value);
            // When two labels land on the same size, keep the one that asked
            // for it most nearly — 24 stays "Default" rather than "Small".
            if (best[nearest] === undefined || distance < best[nearest].distance)
                best[nearest] = { displayName: option.displayName, value: nearest, distance: distance };
        }
        return Object.keys(best)
            .map(size => best[size])
            .sort((a, b) => a.value - b.value)
            .map(entry => ({ displayName: entry.displayName, value: entry.value }));
    }

    function refreshCursorSizes() {
        cursorSizesProc.running = false;
        // Set rather than bound: a bound command isn't guaranteed to have been
        // re-evaluated by the time the process starts, and starting it with no
        // theme name reads as "this theme has no sizes".
        cursorSizesProc.command = ["python3", root.cursorSizeScript, root.sysCurrentCursor];
        cursorSizesProc.running = true;
    }
    Process {
        id: cursorSizesProc
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => cursorSizesProc.buf += data + "\n" }
        onExited: root.cursorSizesAvailable = (cursorSizesProc.buf || "")
            .split("\n").map(l => parseInt(l.trim()))
            .filter(n => !isNaN(n) && n > 0)
    }
    onSysCurrentCursorChanged: if (root.sysCurrentCursor.length > 0) root.refreshCursorSizes()

    Component.onCompleted: decoReader.running = true

    Connections {
        target: Config
        function onThemeApplyInProgressChanged() {
            if (Config.themeApplyInProgress) return
            decoReader.running = false
            decoReader.running = true
        }
    }

    readonly property string decorationsPy: `${CF.FileUtils.trimFileProtocol(Directories.config)}/quickshell/ii/scripts/themes/decorations.py`
    readonly property string flagDir: `${CF.FileUtils.trimFileProtocol(Directories.config)}/hypr/custom`

    // What each setting is worth on a stock install, read from the same table
    // the settings themselves come from so the mark on a track cannot claim a
    // default the schema has since moved.
    property var decoDefaults: ({})

    // The mark a track carries, as the single-value list the slider wants. An
    // empty list until the defaults land, which draws no mark rather than one
    // in the wrong place.
    function defaultMark(key) {
        const value = root.decoDefaults[key]
        return value === undefined ? [] : [value]
    }

    // The shipped profiles keep their translated names and their order; the
    // scan below appends whatever else is in the profile directory, named by
    // its filename — so a hand-written profile shows up without the page
    // having to know it exists.
    readonly property var shippedAnimationProfiles: [
        { displayName: Translation.tr("Expressive"), value: "expressive" },
        { displayName: Translation.tr("Snappy"), value: "snappy" },
        { displayName: Translation.tr("Smooth"), value: "smooth" },
        { displayName: Translation.tr("Bouncy"), value: "bouncy" },
        { displayName: Translation.tr("Minimal"), value: "minimal" },
    ]
    property var extraAnimationProfiles: []
    readonly property var animationProfiles: shippedAnimationProfiles.concat(extraAnimationProfiles)
    readonly property string animationsDir: `${CF.FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprland/animations`

    Process {
        id: animationProfilesScan
        running: true
        command: ["bash", "-c", `ls '${root.animationsDir}'/*.lua 2>/dev/null`]
        stdout: StdioCollector {
            onStreamFinished: {
                const shipped = new Set(root.shippedAnimationProfiles.map(p => p.value));
                root.extraAnimationProfiles = text.split("\n")
                    .map(line => line.trim().split("/").pop().replace(/\.lua$/, ""))
                    .filter(name => /^[\w-]+$/.test(name) && !shipped.has(name))
                    .sort()
                    .map(name => ({
                        displayName: name.replace(/[-_]/g, " ").replace(/\b\w/g, c => c.toUpperCase()),
                        value: name
                    }));
            }
        }
    }

    // The two faces of the shadow color string: how opaque it is, and what
    // hue that opacity is applied to.
    function shadowAlphaOf(rgba) {
        const m = String(rgba).match(/^rgba\(([0-9a-fA-F]{8})\)$/)
        return m ? Math.round(parseInt(m[1].slice(6, 8), 16) / 2.55) : 0
    }
    function shadowRgbOf(rgba) {
        const m = String(rgba).match(/^rgba\(([0-9a-fA-F]{8})\)$/)
        return m ? m[1].slice(0, 6) : "000000"
    }

    // Size and passes are one perceptual control: passes decides how far each
    // unit of size spreads, so raising one without the other gives grain or
    // mush rather than more blur. One slider walks both through pairs that
    // keep the balance; the stored keys stay the two Hyprland reads, so a
    // hand-written config or an imported theme still round-trips.
    readonly property var blurLadder: [[2, 1], [3, 1], [4, 2], [6, 2], [8, 2], [8, 3], [10, 3], [12, 3], [12, 4], [16, 4]]

    // Nearest ladder step to an arbitrary pair, compared on log2(size·2^passes)
    // — the spread of the blur in pixels — so off-ladder values from elsewhere
    // land on the step that looks most like them.
    function blurStrengthOf(size, passes) {
        const target = Math.log2(Math.max(1, size)) + passes
        let best = 1
        let bestDistance = Infinity
        for (let i = 0; i < blurLadder.length; i++) {
            const d = Math.abs(Math.log2(blurLadder[i][0]) + blurLadder[i][1] - target)
            if (d < bestDistance) { bestDistance = d; best = i + 1 }
        }
        return best
    }

    Process {
        id: decoDefaultsReader
        running: true
        command: ["python3", root.decorationsPy, "defaults", root.generalConf]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.decoDefaults = JSON.parse(text || "{}") }
                catch (e) { root.decoDefaults = ({}) }
            }
        }
    }

    Process {
        id: decoReader
        // The same reader a theme snapshot uses, so this page and a saved theme
        // can never disagree about what a setting is or where it lives.
        command: ["python3", root.decorationsPy, "read", root.generalConf,
                  "--flag-dir", root.flagDir]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => decoReader.buf += data }
        onExited: {
            let values = ({})
            try { values = JSON.parse(decoReader.buf || "{}") } catch (e) { values = ({}) }
            root.applyDecoValues(values)
            root._decoReady = true
        }
    }

    // Every window section back to stock in one motion, from the same table
    // the track marks are read from. Title bars go through their own service,
    // which owns the flag and the plugin's reload; the border gradient lives
    // in config.json, where its service is watching. System look and below
    // are left alone — the cursor and the fonts belong to the whole desktop,
    // not to its windows.
    function resetWindowSections() {
        const d = root.decoDefaults;
        const pairs = Object.keys(d)
            .filter(k => k !== "titleBars")
            .map(k => `${k}=${d[k]}`);
        if (pairs.length === 0) return;
        root.setDecoration(pairs);
        root.applyDecoValues(d);
        // A switch the user has toggled has lost its `checked:` binding (see
        // ConfigSwitch), so setting the backing property above no longer moves
        // it. Re-arm each so the reset shows on the switches, not just in the
        // file and the compositor.
        swAnimations.checked = Qt.binding(() => root.animationsEnabled);
        swBlur.checked = Qt.binding(() => root.blurEnabled);
        swShadows.checked = Qt.binding(() => root.shadowsEnabled);
        swBorders.checked = Qt.binding(() => root.bordersEnabled);
        swRoundCorners.checked = Qt.binding(() => root.roundCornersEnabled);
        swBlurXray.checked = Qt.binding(() => root.blurXrayEnabled);
        swDimInactive.checked = Qt.binding(() => root.dimInactiveEnabled);
        if (d.titleBars !== undefined) TitleBars.setEnabled(d.titleBars);
        swTitleBars.checked = Qt.binding(() => TitleBars.enabled);
        activeBorderLane.rearm();
        inactiveBorderLane.rearm();
        const gradientStock = [
            [Config.options.appearance.borderGradient, 50],
            [Config.options.appearance.borderGradientInactive, 15],
        ];
        for (const [bg, strength] of gradientStock) {
            bg.enable = false;
            bg.custom = false;
            bg.customFrom = "#8ab4f8";
            bg.customTo = "#c58af9";
            bg.angle = 90;
            bg.opacity = strength;
            bg.from = "primary";
            bg.to = "tertiary";
        }
    }

    // What the reader learned, or what the defaults table says: either way
    // the page's rows follow one set of assignments, so the reader and the
    // reset cannot disagree about what a key drives.
    function applyDecoValues(values) {
        if (values.animations !== undefined) root.animationsEnabled = values.animations
        if (values.blur !== undefined) root.blurEnabled = values.blur
        if (values.shadow !== undefined) root.shadowsEnabled = values.shadow
        if (values.borderSize !== undefined) root.bordersEnabled = values.borderSize > 0
        if (values.rounding !== undefined) root.roundCornersEnabled = values.rounding > 0
        if (values.rounding !== undefined && values.rounding > 0) root.roundingValue = values.rounding
        if (values.shadowRange !== undefined) root.shadowRangeValue = values.shadowRange
        if (values.shadowRenderPower !== undefined) root.shadowRenderPowerValue = values.shadowRenderPower
        if (values.shadowOffset !== undefined) {
            root.shadowOffsetXValue = values.shadowOffset[0]
            root.shadowOffsetYValue = values.shadowOffset[1]
        }
        if (values.shadowColor !== undefined) root.shadowColorValue = values.shadowColor
        if (values.animationProfile !== undefined) root.animationProfileValue = values.animationProfile
        if (values.borderSize !== undefined && values.borderSize > 0) root.borderSizeValue = values.borderSize
        if (values.gapsIn !== undefined) root.gapsInValue = values.gapsIn
        if (values.gapsOut !== undefined) root.gapsOutValue = values.gapsOut
        if (values.blurSize !== undefined) root.blurSizeValue = values.blurSize
        if (values.blurPasses !== undefined) root.blurPassesValue = values.blurPasses
        if (values.blurNoise !== undefined) root.blurNoiseValue = values.blurNoise
        if (values.blurVibrancy !== undefined) root.blurVibrancyValue = values.blurVibrancy
        if (values.blurXray !== undefined) root.blurXrayEnabled = values.blurXray
        if (values.activeOpacity !== undefined) root.activeOpacityValue = values.activeOpacity
        if (values.inactiveOpacity !== undefined) root.inactiveOpacityValue = values.inactiveOpacity
        if (values.dimInactive !== undefined) root.dimInactiveEnabled = values.dimInactive
        if (values.dimStrength !== undefined) root.dimStrengthValue = values.dimStrength
    }

    // A slider emits on every pixel of a drag, and each write is a process and
    // a round trip to the compositor. Collected and sent once the drag settles,
    // which also means several sliders moved together arrive as one change.
    property var _pending: ({})
    function queueDecoration(key, value) {
        if (!root._decoReady) return;
        root._pending[key] = value;
        decoFlush.restart();
    }
    Timer {
        id: decoFlush
        interval: 200
        onTriggered: {
            const pairs = Object.keys(root._pending).map(k => `${k}=${root._pending[k]}`);
            root._pending = ({});
            if (pairs.length > 0) root.setDecoration(pairs);
        }
    }

    // Writes the file and pushes the value to the running compositor in one
    // call, so the two cannot be updated independently of each other.
    function setDecoration(pairs) {
        Quickshell.execDetached(["python3", root.decorationsPy, "set", root.generalConf,
                                 "--flag-dir", root.flagDir, ...pairs])
    }

    Process {
        id: systemLookScanProc
        running: true
        command: ["python3", "-c", `
import glob, os, json, subprocess
def cur(key):
    try:
        return subprocess.run(["gsettings","get","org.gnome.desktop.interface",key],capture_output=True,text=True).stdout.strip().strip("'")
    except Exception:
        return ""
home = os.path.expanduser("~")
gtk, icons, cursors = set(), set(), set()
for base in ["/usr/share/themes", home+"/.themes", home+"/.local/share/themes"]:
    for d in glob.glob(base+"/*"):
        if os.path.isdir(d+"/gtk-3.0") or os.path.isdir(d+"/gtk-4.0"):
            gtk.add(os.path.basename(d))
for base in ["/usr/share/icons", home+"/.icons", home+"/.local/share/icons"]:
    for d in glob.glob(base+"/*"):
        if not os.path.isfile(d+"/index.theme"):
            continue
        name = os.path.basename(d)
        try:
            subs = [x for x in os.listdir(d) if os.path.isdir(os.path.join(d,x))]
        except Exception:
            continue
        if "cursors" in subs:
            cursors.add(name)
        if [x for x in subs if x != "cursors"]:
            icons.add(name)
print(json.dumps({"gtk":sorted(gtk),"icons":sorted(icons),"cursors":sorted(cursors),
    "curGtk":cur("gtk-theme"),"curIcon":cur("icon-theme"),"curCursor":cur("cursor-theme")}))
`]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.sysGtkThemes = d.gtk;
                    root.sysIconThemes = d.icons;
                    root.sysCursorThemes = d.cursors;
                    root.sysCurrentGtk = d.curGtk;
                    root.sysCurrentIcon = d.curIcon;
                    root.sysCurrentCursor = d.curCursor;
                } catch (e) {
                    console.log("[ThemesConfig] system look scan failed: " + e);
                }
            }
        }
    }

    function applySystemLook(kind, value) {
        if (kind === "gtk") {
            Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", value]);
            root.sysCurrentGtk = value;
        } else if (kind === "icon") {
            Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", value]);
            // Qt side reads qt6ct, not gsettings — keep them in step so the
            // shell and Qt apps follow the same theme (after their next start).
            Quickshell.execDetached(["bash", "-c",
                'for c in "$HOME/.config/qt6ct/qt6ct.conf" "$HOME/.config/qt5ct/qt5ct.conf"; do [ -f "$c" ] && sed -i "s/^icon_theme=.*/icon_theme=$0/" "$c"; done', value]);
            Quickshell.execDetached(["kwriteconfig6", "--file", "kdeglobals", "--group", "Icons", "--key", "Theme", value]);
            root.sysCurrentIcon = value;
        } else if (kind === "cursor") {
            Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", value]);
            // Keep the size the user picked; sending a fixed one here reset it
            // behind their back every time they tried a different cursor.
            Quickshell.execDetached(["hyprctl", "setcursor", value, String(root.cursorSize)]);
            root.sysCurrentCursor = value;
        }
    }

    Process {
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "cursor-size"]
        stdout: SplitParser {
            onRead: data => {
                const n = parseInt(String(data).trim())
                if (!isNaN(n) && n > 0)
                    root.cursorSize = n
            }
        }
    }

    function applyCursorSize(size) {
        root.cursorSize = size
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", String(size)])
        Quickshell.execDetached([root.cursorScript, String(size)])
    }

    function applyGtkFont() {
        Quickshell.execDetached([root.gtkFontScript,
            (Config.options.appearance.fonts.main || "").trim(),
            (Config.options.appearance.fonts.monospace || "").trim(),
            (Config.options.appearance.fonts.reading || "").trim()]);
    }

    Timer {
        id: gtkFontDebounce
        interval: 400
        onTriggered: root.applyGtkFont()
    }

    // ── Decorations ──────────────────────────────────────────────────────────
    ContentSection {
        icon: "auto_awesome"
        title: Translation.tr("Window decorations")

        // animateChanges: root._decoReady on each ConfigSwitch below — the
        // initial `checked` binding evaluates BEFORE decoReader has parsed
        // general.lua (so it sits at the property's QML default, usually
        // false). When the read completes, the property updates from
        // false → true and the switch's Behavior animations would slide
        // the thumb in. That looked like a re-entry animation every time
        // the user reopened the settings menu. Gating Behavior on
        // _decoReady means the post-read transition snaps into place, and
        // only subsequent user-driven clicks animate normally.
        ConfigRow {
            uniform: true
            ConfigSwitch {
                id: swAnimations
                Layout.fillWidth: true
                buttonIcon: "animation"
                text: Translation.tr("Animations")
                checked: root.animationsEnabled
                animateChanges: root._decoReady
                onCheckedChanged: {
                    if (!root._decoReady) return;
                    root.animationsEnabled = checked;
                    root.setDecoration(["animations=" + checked]);
                }
                StyledToolTip {
                    text: Translation.tr("Window open/close and workspace transition effects")
                }
            }
            ConfigSwitch {
                id: swBlur
                Layout.fillWidth: true
                buttonIcon: "blur_on"
                text: Translation.tr("Blur")
                checked: root.blurEnabled
                animateChanges: root._decoReady
                onCheckedChanged: {
                    if (!root._decoReady) return;
                    root.blurEnabled = checked;
                    root.setDecoration(["blur=" + checked]);
                }
                StyledToolTip {
                    text: Translation.tr("Background blur behind transparent windows and layers")
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                id: swShadows
                Layout.fillWidth: true
                buttonIcon: "ev_shadow"
                text: Translation.tr("Shadows")
                checked: root.shadowsEnabled
                animateChanges: root._decoReady
                onCheckedChanged: {
                    if (!root._decoReady) return;
                    root.shadowsEnabled = checked;
                    root.setDecoration(["shadow=" + checked]);
                }
                StyledToolTip {
                    text: Translation.tr("Drop shadows underneath windows")
                }
            }
            ConfigSwitch {
                id: swBorders
                Layout.fillWidth: true
                buttonIcon: "border_style"
                text: Translation.tr("Borders")
                checked: root.bordersEnabled
                animateChanges: root._decoReady
                onCheckedChanged: {
                    if (!root._decoReady) return;
                    root.bordersEnabled = checked;
                    root.setDecoration([`borderSize=${checked ? root.borderSizeValue : 0}`,
                                        `resizeOnBorder=${checked}`]);
                }
                StyledToolTip {
                    text: Translation.tr("Colored borders around active and inactive windows")
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                id: swRoundCorners
                buttonIcon: "rounded_corner"
                text: Translation.tr("Rounded Corners")
                checked: root.roundCornersEnabled
                animateChanges: root._decoReady
                onCheckedChanged: {
                    if (!root._decoReady) return;
                    root.roundCornersEnabled = checked;
                    root.setDecoration([`rounding=${checked ? root.roundingValue : 0}`]);
                    // The bar's own corners follow the window rounding.
                    if (!checked) {
                        root.previousCornerStyle = Config.options.bar.cornerStyle;
                        Config.options.bar.cornerStyle = 2;
                    } else {
                        Config.options.bar.cornerStyle = root.previousCornerStyle;
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Rounded corners on windows and the bar")
                }
            }
            // All file-edit + plugin load/unload mechanics live in the
            // TitleBars service so this page and Settings → Layouts
            // share one implementation.
            //
            // animateChanges: TitleBars.enabledLoaded — TitleBars reads
            // the plugin state asynchronously (TitleBars.qml's readerProc
            // runs `cat custom/general.lua`); gating on the read-completion
            // flag matches the decoration-switches pattern above and
            // prevents the slide-in animation on every menu reopen.
            ConfigSwitch {
                id: swTitleBars
                buttonIcon: "title"
                text: Translation.tr("Title Bars")
                checked: TitleBars.enabled
                animateChanges: TitleBars.enabledLoaded
                onCheckedChanged: {
                    if (!root._decoReady) return;
                    TitleBars.setEnabled(checked);
                }
                StyledToolTip {
                    text: Translation.tr("Show title bars on windows")
                }
            }
        }
    }

    // ── Shape ─────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "rounded_corner"
        title: Translation.tr("Window shape")

        ConfigSlider {
            text: Translation.tr("Corner roundness")
            stopIndicatorValues: root.defaultMark("rounding")
            buttonIcon: "rounded_corner"
            usePercentTooltip: false
            enabled: root.roundCornersEnabled
            opacity: root.roundCornersEnabled ? 1 : 0.5
            from: 1
            to: 24
            value: root.roundingValue
            onMoved: {
                const stepped = Math.round(value);
                if (stepped === root.roundingValue) return;
                root.roundingValue = stepped;
                root.queueDecoration("rounding", stepped);
            }
        }

        ConfigSlider {
            text: Translation.tr("Border thickness")
            stopIndicatorValues: root.defaultMark("borderSize")
            buttonIcon: "border_style"
            usePercentTooltip: false
            enabled: root.bordersEnabled
            opacity: root.bordersEnabled ? 1 : 0.5
            from: 1
            to: 10
            value: root.borderSizeValue
            onMoved: {
                const stepped = Math.round(value);
                if (stepped === root.borderSizeValue) return;
                root.borderSizeValue = stepped;
                root.queueDecoration("borderSize", stepped);
            }
        }

        ConfigSlider {
            text: Translation.tr("Gap between windows")
            stopIndicatorValues: root.defaultMark("gapsIn")
            buttonIcon: "width"
            usePercentTooltip: false
            from: 0
            to: 40
            value: root.gapsInValue
            onMoved: {
                const stepped = Math.round(value);
                if (stepped === root.gapsInValue) return;
                root.gapsInValue = stepped;
                root.queueDecoration("gapsIn", stepped);
            }
        }

        ConfigSlider {
            text: Translation.tr("Gap around the edge")
            stopIndicatorValues: root.defaultMark("gapsOut")
            buttonIcon: "fit_screen"
            usePercentTooltip: false
            from: 0
            to: 60
            value: root.gapsOutValue
            onMoved: {
                const stepped = Math.round(value);
                if (stepped === root.gapsOutValue) return;
                root.gapsOutValue = stepped;
                root.queueDecoration("gapsOut", stepped);
            }
        }
    }

    // ── Transparency ──────────────────────────────────────────────────────────
    ContentSection {
        icon: "opacity"
        title: Translation.tr("Window transparency")

        ConfigSlider {
            text: Translation.tr("Focused window")
            stopIndicatorValues: root.defaultMark("activeOpacity")
            buttonIcon: "filter_center_focus"
            from: 0.7
            to: 1.0
            value: root.activeOpacityValue
            onMoved: {
                if (Math.abs(value - root.activeOpacityValue) < 0.005) return;
                root.activeOpacityValue = value;
                root.queueDecoration("activeOpacity", value.toFixed(2));
            }
        }

        ConfigSlider {
            text: Translation.tr("Unfocused windows")
            stopIndicatorValues: root.defaultMark("inactiveOpacity")
            buttonIcon: "filter_none"
            from: 0.7
            to: 1.0
            value: root.inactiveOpacityValue
            onMoved: {
                if (Math.abs(value - root.inactiveOpacityValue) < 0.005) return;
                root.inactiveOpacityValue = value;
                root.queueDecoration("inactiveOpacity", value.toFixed(2));
            }
        }
    }

    // ── Blur depth ────────────────────────────────────────────────────────────
    ContentSection {
        icon: "blur_on"
        title: Translation.tr("Window blur")

        // Greyed rather than hidden when blur is off, so the settings stay
        // where they were found rather than moving as things are toggled.
        ConfigSlider {
            text: Translation.tr("Strength")
            stopIndicatorValues: (root.decoDefaults.blurSize !== undefined && root.decoDefaults.blurPasses !== undefined)
                ? [root.blurStrengthOf(root.decoDefaults.blurSize, root.decoDefaults.blurPasses)] : []
            buttonIcon: "lens_blur"
            usePercentTooltip: false
            enabled: root.blurEnabled
            opacity: root.blurEnabled ? 1 : 0.5
            from: 1
            to: root.blurLadder.length
            value: root.blurStrengthOf(root.blurSizeValue, root.blurPassesValue)
            onMoved: {
                const step = Math.max(1, Math.min(root.blurLadder.length, Math.round(value)));
                const pair = root.blurLadder[step - 1];
                if (pair[0] === root.blurSizeValue && pair[1] === root.blurPassesValue) return;
                root.blurSizeValue = pair[0];
                root.blurPassesValue = pair[1];
                root.queueDecoration("blurSize", pair[0]);
                root.queueDecoration("blurPasses", pair[1]);
            }
            StyledToolTip { text: Translation.tr("How deep the frost goes. Deeper costs more to draw.") }
        }

        ConfigSlider {
            text: Translation.tr("Noise")
            stopIndicatorValues: root.defaultMark("blurNoise")
            buttonIcon: "grain"
            enabled: root.blurEnabled
            opacity: root.blurEnabled ? 1 : 0.5
            from: 0.0
            to: 0.1
            value: root.blurNoiseValue
            onMoved: {
                if (Math.abs(value - root.blurNoiseValue) < 0.005) return;
                root.blurNoiseValue = value;
                root.queueDecoration("blurNoise", value.toFixed(2));
            }
            StyledToolTip { text: Translation.tr("Grain over the blur, which hides the banding a heavy blur can leave") }
        }

        ConfigSlider {
            text: Translation.tr("Saturation")
            stopIndicatorValues: root.defaultMark("blurVibrancy")
            buttonIcon: "palette"
            enabled: root.blurEnabled
            opacity: root.blurEnabled ? 1 : 0.5
            from: 0.0
            to: 1.0
            value: root.blurVibrancyValue
            onMoved: {
                if (Math.abs(value - root.blurVibrancyValue) < 0.005) return;
                root.blurVibrancyValue = value;
                root.queueDecoration("blurVibrancy", value.toFixed(2));
            }
            StyledToolTip { text: Translation.tr("How much color the blur keeps from what is behind it") }
        }

        ConfigSwitch {
            id: swBlurXray
            buttonIcon: "layers_clear"
            text: Translation.tr("Blur through to the wallpaper") + " (xray)"
            checked: root.blurXrayEnabled
            animateChanges: root._decoReady
            enabled: root.blurEnabled
            opacity: root.blurEnabled ? 1 : 0.5
            onCheckedChanged: {
                if (!root._decoReady) return;
                root.blurXrayEnabled = checked;
                root.setDecoration([`blurXray=${checked}`]);
            }
            StyledToolTip {
                text: Translation.tr("Blur what is on the desktop rather than the windows stacked underneath")
            }
        }
    }

    // ── Dim ───────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "brightness_medium"
        title: Translation.tr("Window dim")

        ConfigSwitch {
            id: swDimInactive
            buttonIcon: "brightness_medium"
            text: Translation.tr("Unfocused windows")
            checked: root.dimInactiveEnabled
            animateChanges: root._decoReady
            onCheckedChanged: {
                if (!root._decoReady) return;
                root.dimInactiveEnabled = checked;
                root.setDecoration([`dimInactive=${checked}`]);
            }
        }

        ConfigSlider {
            text: Translation.tr("Amount")
            stopIndicatorValues: root.defaultMark("dimStrength")
            buttonIcon: "gradient"
            enabled: root.dimInactiveEnabled
            opacity: root.dimInactiveEnabled ? 1 : 0.5
            from: 0.0
            to: 0.8
            value: root.dimStrengthValue
            onMoved: {
                if (Math.abs(value - root.dimStrengthValue) < 0.005) return;
                root.dimStrengthValue = value;
                root.queueDecoration("dimStrength", value.toFixed(2));
            }
        }
    }

    // The focused and the unfocused border share one section: each lane is
    // the same switches, colors and sliders against its own config object,
    // and the lane's own toggle carries its name, so the pair reads as two
    // halves of one setting rather than two settings.
    component BorderGradientLane: ColumnLayout {
        id: bgSection
        required property var gradientOpts
        required property string switchLabel
        required property string switchIcon
        property int defaultStrength: 50
        spacing: 0
        Layout.fillWidth: true

        // A clicked ConfigSwitch has lost its `checked:` binding, so a reset
        // that only changes the config leaves these two showing the old state.
        function rearm() {
            laneSwitch.checked = Qt.binding(() => bgSection.gradientOpts.enable);
            customSwitch.checked = Qt.binding(() => bgSection.gradientOpts.custom);
        }

        // Drawn from the palette's primary and tertiary, so it is re-derived
        // from whatever the wallpaper produced instead of drifting out of step
        // with everything around it. That pair is not offered as a choice: the
        // other roles sit too close together to read as a gradient, so picking
        // between them is the long way round to no visible difference. Anyone
        // who wants a specific pair wants colours, which is the switch below.
        ConfigSwitch {
            id: laneSwitch
            buttonIcon: bgSection.switchIcon
            text: bgSection.switchLabel
            checked: bgSection.gradientOpts.enable
            onCheckedChanged: bgSection.gradientOpts.enable = checked
            StyledToolTip {
                text: Translation.tr("Off leaves the border the color the palette picked for it")
            }
        }

        // Everything below the toggle belongs to it: inset behind a rail,
        // so which border a slider moves is read from the shape of the
        // section rather than remembered.
        RowLayout {
            visible: bgSection.gradientOpts.enable
            Layout.fillWidth: true
            Layout.leftMargin: 18
            spacing: 6

            Rectangle {
                Layout.fillHeight: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                implicitWidth: 2
                radius: 1
                color: CF.ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.5)
            }

            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true

                ConfigSwitch {
                    buttonIcon: "palette"
                    text: Translation.tr("Choose the colors myself")
                    id: customSwitch
                    checked: bgSection.gradientOpts.custom
                    onCheckedChanged: bgSection.gradientOpts.custom = checked
                    StyledToolTip {
                        text: Translation.tr("Fixed colors stay put when the wallpaper changes")
                    }
                }

                ColorField {
                    text: Translation.tr("From")
                    buttonIcon: "trip_origin"
                    visible: bgSection.gradientOpts.custom
                    value: bgSection.gradientOpts.customFrom
                    onEdited: newValue => bgSection.gradientOpts.customFrom = newValue
                }

                ColorField {
                    text: Translation.tr("To")
                    buttonIcon: "adjust"
                    visible: bgSection.gradientOpts.custom
                    value: bgSection.gradientOpts.customTo
                    onEdited: newValue => bgSection.gradientOpts.customTo = newValue
                }

                ConfigSlider {
                    text: Translation.tr("Angle")
                    stopIndicatorValues: [90]
                    buttonIcon: "rotate_right"
                    usePercentTooltip: false
                    from: 0
                    to: 360
                    value: bgSection.gradientOpts.angle
                    onMoved: {
                        const stepped = Math.round(value / 5) * 5;
                        if (stepped === bgSection.gradientOpts.angle) return;
                        bgSection.gradientOpts.angle = stepped;
                    }
                }

                ConfigSlider {
                    text: Translation.tr("Strength")
                    stopIndicatorValues: [bgSection.defaultStrength]
                    buttonIcon: "opacity"
                    from: 10
                    to: 100
                    value: bgSection.gradientOpts.opacity
                    onMoved: {
                        const stepped = Math.round(value);
                        if (stepped === bgSection.gradientOpts.opacity) return;
                        bgSection.gradientOpts.opacity = stepped;
                    }
                    StyledToolTip { text: Translation.tr("How solid the border is against what is behind it") }
                }
            }
        }
    }

    // ── Border color ─────────────────────────────────────────────────────────
    ContentSection {
        icon: "gradient"
        title: Translation.tr("Window border color")

        BorderGradientLane {
            id: activeBorderLane
            switchLabel: Translation.tr("Active border")
            switchIcon: "select_window"
            gradientOpts: Config.options.appearance.borderGradient
        }

        BorderGradientLane {
            id: inactiveBorderLane
            switchLabel: Translation.tr("Inactive border")
            switchIcon: "select_window_2"
            defaultStrength: 15
            gradientOpts: Config.options.appearance.borderGradientInactive
        }
    }

    // ── Shadow ────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "ev_shadow"
        title: Translation.tr("Window shadow")

        ConfigSlider {
            text: Translation.tr("Size")
            stopIndicatorValues: root.defaultMark("shadowRange")
            buttonIcon: "photo_size_select_large"
            usePercentTooltip: false
            enabled: root.shadowsEnabled
            opacity: root.shadowsEnabled ? 1 : 0.5
            from: 1
            to: 60
            value: root.shadowRangeValue
            onMoved: {
                const stepped = Math.round(value);
                if (stepped === root.shadowRangeValue) return;
                root.shadowRangeValue = stepped;
                root.queueDecoration("shadowRange", stepped);
            }
            StyledToolTip { text: Translation.tr("How far the shadow spreads from the window") }
        }

        ConfigSlider {
            text: Translation.tr("Falloff")
            stopIndicatorValues: root.defaultMark("shadowRenderPower")
            buttonIcon: "gradient"
            usePercentTooltip: false
            enabled: root.shadowsEnabled
            opacity: root.shadowsEnabled ? 1 : 0.5
            from: 1
            to: 4
            value: root.shadowRenderPowerValue
            onMoved: {
                const stepped = Math.round(value);
                if (stepped === root.shadowRenderPowerValue) return;
                root.shadowRenderPowerValue = stepped;
                root.queueDecoration("shadowRenderPower", stepped);
            }
            StyledToolTip { text: Translation.tr("How sharply the shadow fades out at its edge") }
        }

        // Size and falloff only shape the shadow; how much of it can be seen
        // at all is the alpha of its color, which is what this slider carries.
        // The hue is kept from whatever the color already is, so a theme that
        // tints its shadow keeps the tint while the darkness moves.
        ConfigSlider {
            text: Translation.tr("Darkness")
            stopIndicatorValues: root.decoDefaults.shadowColor !== undefined
                ? [root.shadowAlphaOf(root.decoDefaults.shadowColor)] : []
            buttonIcon: "contrast"
            enabled: root.shadowsEnabled
            opacity: root.shadowsEnabled ? 1 : 0.5
            from: 0
            to: 100
            value: root.shadowAlphaOf(root.shadowColorValue)
            onMoved: {
                const stepped = Math.round(value);
                if (stepped === root.shadowAlphaOf(root.shadowColorValue)) return;
                const alpha = Math.round(stepped * 2.55).toString(16).padStart(2, "0");
                root.shadowColorValue = `rgba(${root.shadowRgbOf(root.shadowColorValue)}${alpha})`;
                root.queueDecoration("shadowColor", root.shadowColorValue);
            }
            StyledToolTip { text: Translation.tr("How dark the shadow is. Faint shadows barely change with size.") }
        }

        ConfigSlider {
            text: Translation.tr("Offset X")
            stopIndicatorValues: root.decoDefaults.shadowOffset !== undefined
                ? [root.decoDefaults.shadowOffset[0]] : []
            buttonIcon: "swap_horiz"
            usePercentTooltip: false
            enabled: root.shadowsEnabled
            opacity: root.shadowsEnabled ? 1 : 0.5
            from: -30
            to: 30
            value: root.shadowOffsetXValue
            onMoved: {
                const stepped = Math.round(value);
                if (stepped === root.shadowOffsetXValue) return;
                root.shadowOffsetXValue = stepped;
                root.queueDecoration("shadowOffset", `${stepped},${root.shadowOffsetYValue}`);
            }
            StyledToolTip { text: Translation.tr("How far the shadow sits to the side of its window") }
        }

        ConfigSlider {
            text: Translation.tr("Offset Y")
            stopIndicatorValues: root.decoDefaults.shadowOffset !== undefined
                ? [root.decoDefaults.shadowOffset[1]] : []
            buttonIcon: "swap_vert"
            usePercentTooltip: false
            enabled: root.shadowsEnabled
            opacity: root.shadowsEnabled ? 1 : 0.5
            from: -30
            to: 30
            value: root.shadowOffsetYValue
            onMoved: {
                const stepped = Math.round(value);
                if (stepped === root.shadowOffsetYValue) return;
                root.shadowOffsetYValue = stepped;
                root.queueDecoration("shadowOffset", `${root.shadowOffsetXValue},${stepped}`);
            }
            StyledToolTip { text: Translation.tr("How far the shadow drops below its window") }
        }
    }

    // ── Animations ────────────────────────────────────────────────────────────
    ContentSection {
        icon: "animation"
        title: Translation.tr("Window animations")

        // A profile is the whole set at once — curves, speeds and styles are
        // tuned against each other, so they travel together rather than as
        // fourteen separate knobs.
        ConfigRow {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            enabled: root.animationsEnabled
            opacity: root.animationsEnabled ? 1 : 0.5
            OptionalMaterialSymbol {
                icon: "auto_awesome_motion"
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 6
                text: Translation.tr("Style")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledComboBox {
                textRole: "displayName"
                Layout.fillWidth: false
                Layout.preferredWidth: 220
                model: root.animationProfiles
                currentIndex: root.animationProfiles.findIndex(p => p.value === root.animationProfileValue)
                onActivated: index => {
                    const chosen = root.animationProfiles[index].value;
                    if (chosen === root.animationProfileValue) return;
                    root.animationProfileValue = chosen;
                    root.setDecoration([`animationProfile=${chosen}`]);
                }
            }
        }
    }

    // ── Reset ─────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "settings_backup_restore"
        title: Translation.tr("Reset")

        ConfigRow {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            RippleButtonWithIcon {
                materialIcon: "settings_backup_restore"
                mainText: Translation.tr("Reset window settings")
                onClicked: root.resetWindowSections()
                StyledToolTip {
                    text: Translation.tr("Every window section above goes back to how a fresh install has it")
                }
            }
        }
    }

    // ── System look (app / icon / cursor themes) ──────────────────────────────
    ContentSection {
        icon: "palette"
        title: Translation.tr("System look")
        Layout.fillWidth: true

        ConfigRow {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            OptionalMaterialSymbol {
                icon: "widgets"
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 6
                text: Translation.tr("App style")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledComboBox {
                id: gtkThemeCombo
                textRole: "displayName"
                Layout.fillWidth: false
                Layout.preferredWidth: 220
                model: root.sysGtkThemes.map(t => ({
                    displayName: t.replace(/-/g, " ").replace(/\b\w/g, c => c.toUpperCase()),
                    value: t
                }))
                currentIndex: root.sysGtkThemes.indexOf(root.sysCurrentGtk)
                onActivated: index => root.applySystemLook("gtk", model[index].value)
            }
        }

        ConfigRow {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            OptionalMaterialSymbol {
                icon: "interests"
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 6
                text: Translation.tr("Icons")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledComboBox {
                id: iconThemeCombo
                textRole: "displayName"
                Layout.fillWidth: false
                Layout.preferredWidth: 220
                model: root.sysIconThemes.map(t => ({
                    displayName: t.replace(/-/g, " ").replace(/\b\w/g, c => c.toUpperCase()),
                    value: t
                }))
                currentIndex: root.sysIconThemes.indexOf(root.sysCurrentIcon)
                onActivated: index => root.applySystemLook("icon", model[index].value)
            }
        }

        ConfigRow {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            OptionalMaterialSymbol {
                icon: "mouse"
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 6
                text: Translation.tr("Mouse cursor")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledComboBox {
                id: cursorThemeCombo
                textRole: "displayName"
                Layout.fillWidth: false
                Layout.preferredWidth: 220
                model: root.sysCursorThemes.map(t => ({
                    displayName: t.replace(/-/g, " ").replace(/\b\w/g, c => c.toUpperCase()),
                    value: t
                }))
                currentIndex: root.sysCursorThemes.indexOf(root.sysCurrentCursor)
                onActivated: index => root.applySystemLook("cursor", model[index].value)
            }
        }
    }

    // ── Cursor ────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "highlight_mouse_cursor"
        title: Translation.tr("Cursor")

        ConfigRow {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            OptionalMaterialSymbol {
                icon: "straighten"
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 6
                text: Translation.tr("Cursor Size")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledComboBox {
                textRole: "displayName"
                Layout.fillWidth: false
                Layout.preferredWidth: 220
                model: root.cursorSizeOptions
                currentIndex: {
                    const exact = model.findIndex(item => item.value === root.cursorSize)
                    if (exact !== -1) return exact
                    // The saved size may be one this theme can't draw, in which
                    // case show the entry it is actually being drawn at rather
                    // than a size that isn't among the choices.
                    let nearest = 0
                    for (let i = 1; i < model.length; i++)
                        if (Math.abs(model[i].value - root.cursorSize) < Math.abs(model[nearest].value - root.cursorSize))
                            nearest = i
                    return nearest
                }
                onActivated: index => root.applyCursorSize(model[index].value)
            }
        }

        // Whether a cursor can be drawn at more than one size is decided by how
        // its theme was built. Some hold one size and stay that size whatever
        // is asked of them, by anything asking — the compositor included — so
        // there is nothing to be done here except say so. Carried the same way
        // the Themes page carries its notices, so the settings speak alike.
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            radius: Appearance.rounding.small
            color: Qt.rgba(Appearance.m3colors.m3primary.r, Appearance.m3colors.m3primary.g, Appearance.m3colors.m3primary.b, 0.12)
            implicitHeight: cursorNoteRow.implicitHeight + 16
            RowLayout {
                id: cursorNoteRow
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                MaterialSymbol {
                    text: "info"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.m3colors.m3primary
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: Translation.tr("Not every cursor theme can be resized. One built at a single size stays that size whichever you pick here.")
                }
            }
        }
    }

    // ── Fonts ─────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "text_format"
        title: Translation.tr("Fonts")

        ContentSubsection {
            title: Translation.tr("Main font")
            tooltip: Translation.tr("Used for general UI text")

            FontPicker {
                value: Config.options.appearance.fonts.main
                onFontSelected: family => {
                    Config.options.appearance.fonts.main = family;
                    gtkFontDebounce.restart();
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Numbers font")
            tooltip: Translation.tr("Used for displaying numbers")

            FontPicker {
                value: Config.options.appearance.fonts.numbers
                onFontSelected: family => {
                    Config.options.appearance.fonts.numbers = family;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Title font")
            tooltip: Translation.tr("Used for headings and titles")

            FontPicker {
                value: Config.options.appearance.fonts.title
                onFontSelected: family => {
                    Config.options.appearance.fonts.title = family;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Monospace font")
            tooltip: Translation.tr("Used for code and terminal")

            FontPicker {
                value: Config.options.appearance.fonts.monospace
                onFontSelected: family => {
                    Config.options.appearance.fonts.monospace = family;
                    gtkFontDebounce.restart();
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Nerd font icons")
            tooltip: Translation.tr("Font used for Nerd Font icons")

            FontPicker {
                value: Config.options.appearance.fonts.iconNerd
                onFontSelected: family => {
                    Config.options.appearance.fonts.iconNerd = family;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Reading font")
            tooltip: Translation.tr("Used for reading large blocks of text")

            FontPicker {
                value: Config.options.appearance.fonts.reading
                onFontSelected: family => {
                    Config.options.appearance.fonts.reading = family;
                    gtkFontDebounce.restart();
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Expressive font")
            tooltip: Translation.tr("Used for decorative/expressive text")

            FontPicker {
                value: Config.options.appearance.fonts.expressive
                onFontSelected: family => {
                    Config.options.appearance.fonts.expressive = family;
                }
            }
        }
    }

    // ── Window rules (per-app exceptions to the window sections) ──────────────
    // Last on purpose: the list grows without pushing anything below it, and
    // the sections above stay where muscle memory expects them.
    WindowRulesSection {}
}
