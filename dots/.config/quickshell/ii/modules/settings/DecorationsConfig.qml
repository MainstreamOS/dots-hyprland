import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF
import qs.modules.common.widgets

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
            if (values.animations !== undefined) root.animationsEnabled = values.animations
            if (values.blur !== undefined) root.blurEnabled = values.blur
            if (values.shadow !== undefined) root.shadowsEnabled = values.shadow
            if (values.borderSize !== undefined) root.bordersEnabled = values.borderSize > 0
            if (values.rounding !== undefined) root.roundCornersEnabled = values.rounding > 0
            root._decoReady = true
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
        title: Translation.tr("Decorations")

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
                Layout.fillWidth: true
                buttonIcon: "border_style"
                text: Translation.tr("Borders")
                checked: root.bordersEnabled
                animateChanges: root._decoReady
                onCheckedChanged: {
                    if (!root._decoReady) return;
                    root.bordersEnabled = checked;
                    root.setDecoration(["borderSize=" + (checked ? 4 : 0),
                                        "resizeOnBorder=" + checked,
                                        "gapsIn=" + (checked ? 4 : 0),
                                        "gapsOut=" + (checked ? 5 : 0)]);
                }
                StyledToolTip {
                    text: Translation.tr("Colored borders around active and inactive windows")
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "rounded_corner"
                text: Translation.tr("Rounded Corners")
                checked: root.roundCornersEnabled
                animateChanges: root._decoReady
                onCheckedChanged: {
                    if (!root._decoReady) return;
                    root.roundCornersEnabled = checked;
                    root.setDecoration(["rounding=" + (checked ? 10 : 0)]);
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
}
