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

    Component.onCompleted: decoReader.running = true

    Connections {
        target: Config
        function onThemeApplyInProgressChanged() {
            if (Config.themeApplyInProgress) return
            decoReader.running = false
            decoReader.running = true
        }
    }

    function runPy(py, args) {
        Quickshell.execDetached(["python3", "-c", py, ...args])
    }

    function setHyprKeyword(keyword, value) {
        const firstColon = keyword.indexOf(":");
        if (firstColon < 0) {
            console.warn("setHyprKeyword: keyword has no section:", keyword);
            return;
        }
        const section = keyword.substring(0, firstColon);
        // Remaining leaf may still contain `:` (e.g. "decoration:blur:enabled"
        // → leaf "blur:enabled"); luaConfigValueName already converts `:`→`.`
        // for stored keys, so we normalize the leaf the same way before
        // bracket-string indexing.
        const leaf = keyword.substring(firstColon + 1).replace(/:/g, ".");
        let luaVal;
        const v = String(value);
        if (v === "true" || v === "false") {
            luaVal = v;
        } else if (/^-?\d+(?:\.\d+)?$/.test(v)) {
            luaVal = v;
        } else {
            luaVal = `"${v.replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;
        }
        const expr = `hl.config({ ${section} = { ["${leaf}"] = ${luaVal} } })`;
        Quickshell.execDetached(["hyprctl", "eval", expr]);
    }

    Process {
        id: decoReader
        command: ["cat", root.generalConf]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => decoReader.buf += data + "\n" }
        onExited: {
            let text = decoReader.buf;
            // Lua format: `animations = { enabled = true, ... }`.
            // Block-opener regexes use `(?m)^\s*KEY\s*=\s*\{` so a doc
            // comment that happens to mention "animations = {" doesn't
            // shadow the real block (Lua comments start with `--` which
            // doesn't match `\s*`). Same anchor for blur, shadow, rounding.
            let animMatch = text.match(/^\s*animations\s*=\s*\{[\s\S]*?enabled\s*=\s*(\w+)/m);
            if (animMatch) root.animationsEnabled = animMatch[1] === "true" || animMatch[1] === "1";
            let blurMatch = text.match(/^\s*blur\s*=\s*\{[\s\S]*?enabled\s*=\s*(\w+)/m);
            if (blurMatch) root.blurEnabled = blurMatch[1] === "true" || blurMatch[1] === "1";
            let shadowMatch = text.match(/^\s*shadow\s*=\s*\{[\s\S]*?enabled\s*=\s*(\w+)/m);
            if (shadowMatch) root.shadowsEnabled = shadowMatch[1] === "true" || shadowMatch[1] === "1";
            // Lua comment marker is `--` instead of hyprlang's `#`
            let borderMatch = text.match(/^(\s*)(--\s*)?border_size\s*=/m);
            root.bordersEnabled = borderMatch ? !borderMatch[2] : false;
            let roundMatch = text.match(/^\s*rounding\s*=\s*(\d+)/m);
            if (roundMatch) root.roundCornersEnabled = parseInt(roundMatch[1]) > 0;
            root._decoReady = true;
        }
    }

    function decoSetBlockEnabled(blockName, enabled) {
        let val = enabled ? "true" : "false";
        // Block shape in Lua: `<blockName> = { ... enabled = ... }`. The `=`
        // between block name and `{` is captured to allow whitespace variations.
        // Block opener anchored at line start (re.M) so a doc comment that
        // mentions `<block> = {` cannot shadow the real config block.
        let py =
            "import sys, re\n" +
            "block, val, conf = sys.argv[1], sys.argv[2], sys.argv[3]\n" +
            "text = open(conf).read()\n" +
            "pattern = r'(?ms)^(\\s*' + re.escape(block) + r'\\s*=\\s*' + chr(123) + r'[^' + chr(125) + r']*?)(enabled\\s*=\\s*)\\w+'\n" +
            "text = re.sub(pattern, r'\\1\\2' + val, text, count=1)\n" +
            "open(conf, 'w').write(text)\n";
        runPy(py, [blockName, val, root.generalConf])
    }

    function decoSetBordersEnabled(enabled) {
        // Lua nested-table form: `col = { active_border = "...", inactive_border = "..." }`
        // so the field names are bare inside `col`, no `col.` prefix.
        let fields = ["border_size", "active_border", "inactive_border", "resize_on_border"];
        let py =
            "import sys, re\n" +
            "enable = sys.argv[1] == '1'\n" +
            "conf = sys.argv[2]\n" +
            "fields = sys.argv[3].split(',')\n" +
            "lines = open(conf).readlines()\n" +
            "result = []\n" +
            "for line in lines:\n" +
            "    stripped = line.lstrip()\n" +
            "    for f in fields:\n" +
            "        if enable:\n" +
            "            if stripped.startswith('-- ' + f + ' ') or stripped.startswith('--' + f + ' ') or stripped.startswith('-- ' + f + '=') or stripped.startswith('--' + f + '='):\n" +
            "                indent = line[:len(line) - len(line.lstrip())]\n" +
            "                line = indent + stripped.lstrip('- ')\n" +
            "                break\n" +
            "        else:\n" +
            "            if stripped.startswith(f + ' ') or stripped.startswith(f + '='):\n" +
            "                indent = line[:len(line) - len(line.lstrip())]\n" +
            "                line = indent + '-- ' + stripped\n" +
            "                break\n" +
            "    if stripped.startswith('gaps_in'):\n" +
            "        indent = line[:len(line) - len(line.lstrip())]\n" +
            "        line = indent + 'gaps_in = ' + ('4' if enable else '0') + ',\\n'\n" +
            "    elif stripped.startswith('gaps_out'):\n" +
            "        indent = line[:len(line) - len(line.lstrip())]\n" +
            "        line = indent + 'gaps_out = ' + ('5' if enable else '0') + ',\\n'\n" +
            "    result.append(line)\n" +
            "open(conf, 'w').writelines(result)\n";
        runPy(py, [enabled ? "1" : "0", root.generalConf, fields.join(",")])
        if (enabled) {
            setHyprKeyword("general:border_size", "4");
            setHyprKeyword("general:col.active_border", "rgba(0DB7D455)");
            setHyprKeyword("general:col.inactive_border", "rgba(31313600)");
            setHyprKeyword("general:resize_on_border", "true");
            setHyprKeyword("general:gaps_in", "4");
            setHyprKeyword("general:gaps_out", "5");
        } else {
            setHyprKeyword("general:border_size", "0");
            setHyprKeyword("general:resize_on_border", "false");
            setHyprKeyword("general:gaps_in", "0");
            setHyprKeyword("general:gaps_out", "0");
        }
    }

    function decoSetRoundCornersEnabled(enabled) {
        let val = enabled ? "10" : "0";
        // Multiline-anchored pattern (`(?m)^\s*rounding`) so a doc-comment
        // like `-- rounding = 10` doesn't get rewritten in place of the
        // real key inside the decoration table.
        let py =
            "import sys, re\n" +
            "val, conf = sys.argv[1], sys.argv[2]\n" +
            "text = open(conf).read()\n" +
            "text = re.sub(r'(?m)^(\\s*rounding\\s*=\\s*)\\d+', r'\\g<1>' + val, text, count=1)\n" +
            "open(conf, 'w').write(text)\n";
        runPy(py, [val, root.generalConf])
        setHyprKeyword("decoration:rounding", val);
        if (!enabled) {
            root.previousCornerStyle = Config.options.bar.cornerStyle;
            Config.options.bar.cornerStyle = 2;
        } else {
            Config.options.bar.cornerStyle = root.previousCornerStyle;
        }
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
            Quickshell.execDetached(["hyprctl", "setcursor", value, "24"]);
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
        Quickshell.execDetached(["bash", "-c",
            "theme=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null); theme=${theme#\\'}; theme=${theme%\\'}; [ -n \"$theme\" ] || theme=Bibata-Modern-Classic; hyprctl setcursor \"$theme\" \"$0\"",
            String(size)])
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
                    root.decoSetBlockEnabled("animations", checked);
                    root.setHyprKeyword("animations:enabled", checked ? "true" : "false");
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
                    root.decoSetBlockEnabled("blur", checked);
                    root.setHyprKeyword("decoration:blur:enabled", checked ? "true" : "false");
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
                    root.decoSetBlockEnabled("shadow", checked);
                    root.setHyprKeyword("decoration:shadow:enabled", checked ? "true" : "false");
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
                    root.decoSetBordersEnabled(checked);
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
                    root.decoSetRoundCornersEnabled(checked);
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
                model: [
                    { displayName: Translation.tr("Small"),          value: 16 },
                    { displayName: Translation.tr("Default"),        value: 24 },
                    { displayName: Translation.tr("Large"),          value: 32 },
                    { displayName: Translation.tr("Larger"),         value: 48 },
                    { displayName: Translation.tr("Largest"),        value: 64 },
                ]
                currentIndex: {
                    const idx = model.findIndex(item => item.value === root.cursorSize)
                    return idx !== -1 ? idx : 1
                }
                onActivated: index => root.applyCursorSize(model[index].value)
            }
        }

        ConfigRow {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            OptionalMaterialSymbol {
                icon: "vibration"
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 6
                text: Translation.tr("Shake to Locate")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledComboBox {
                textRole: "displayName"
                Layout.fillWidth: false
                Layout.preferredWidth: 220
                model: [
                    { displayName: Translation.tr("Disabled"),       value: "off" },
                    { displayName: Translation.tr("Magnifier Zoom"),  value: "zoom" },
                    { displayName: Translation.tr("Cursor Grows"),    value: "grow" },
                ]
                currentIndex: {
                    const idx = model.findIndex(item => item.value === Config.options.cursor.shakeMode)
                    return idx !== -1 ? idx : 0
                }
                onActivated: index => {
                    Config.options.cursor.shakeMode = model[index].value
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
