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

    // ── Decorations state ──────────────────────────────────────────────────────
    readonly property string generalConf: `${CF.FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprland/general.conf`
    readonly property string customGeneralConf: `${CF.FileUtils.trimFileProtocol(Directories.config)}/hypr/custom/general.conf`
    property bool animationsEnabled: true
    property bool blurEnabled: true
    property bool shadowsEnabled: true
    property bool bordersEnabled: true
    property bool roundCornersEnabled: true
    property bool titleBarsEnabled: false
    property int previousCornerStyle: Config.options.bar.cornerStyle
    property bool _decoReady: false

    // ── Lock timeout ─────────────────────────────────────────────────────────
    property bool lockEnabled: true
    property int lockSecs: 300
    property bool _lockReaderFinished: false

    readonly property string hyprIdleConf: `${CF.FileUtils.trimFileProtocol(Directories.config)}/hypr/hypridle.conf`

    Component.onCompleted: {
        lockTimeoutReader.running = true
        decoReader.running = true
        titleBarReader.running = true
    }

    Process {
        id: titleBarReader
        command: ["cat", root.customGeneralConf]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => titleBarReader.buf += data + "\n" }
        onExited: {
            // Enabled when the plugin = .../hyprbars.so line exists and is NOT commented out
            root.titleBarsEnabled = /^[ \t]*plugin[ \t]*=[ \t]*.*hyprbars\.so/m.test(titleBarReader.buf);
        }
    }

    Process {
        id: decoReader
        command: ["cat", root.generalConf]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => decoReader.buf += data + "\n" }
        onExited: {
            let text = decoReader.buf;
            let animMatch = text.match(/animations\s*\{[\s\S]*?enabled\s*=\s*(\w+)/);
            if (animMatch) root.animationsEnabled = animMatch[1] === "true" || animMatch[1] === "1";
            let blurMatch = text.match(/blur\s*\{[\s\S]*?enabled\s*=\s*(\w+)/);
            if (blurMatch) root.blurEnabled = blurMatch[1] === "true" || blurMatch[1] === "1";
            let shadowMatch = text.match(/shadow\s*\{[\s\S]*?enabled\s*=\s*(\w+)/);
            if (shadowMatch) root.shadowsEnabled = shadowMatch[1] === "true" || shadowMatch[1] === "1";
            let borderMatch = text.match(/^(\s*)(#\s*)?border_size\s*=/m);
            root.bordersEnabled = borderMatch ? !borderMatch[2] : false;
            let roundMatch = text.match(/^\s*rounding\s*=\s*(\d+)/m);
            if (roundMatch) root.roundCornersEnabled = parseInt(roundMatch[1]) > 0;
            root._decoReady = true;
        }
    }

    function decoSetBlockEnabled(blockName, enabled) {
        let val = enabled ? "true" : "false";
        let py =
            "import sys, re\n" +
            "block, val, conf = sys.argv[1], sys.argv[2], sys.argv[3]\n" +
            "text = open(conf).read()\n" +
            "pattern = r'(' + re.escape(block) + r'\\s*' + chr(123) + r'[^' + chr(125) + r']*?)(enabled\\s*=\\s*)\\w+'\n" +
            "text = re.sub(pattern, r'\\1\\2' + val, text, count=1)\n" +
            "open(conf, 'w').write(text)\n";
        Quickshell.execDetached(["python3", "-c", py, blockName, val, root.generalConf]);
    }

    function decoSetBordersEnabled(enabled) {
        let fields = ["border_size", "col.active_border", "col.inactive_border", "resize_on_border"];
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
            "            if stripped.startswith('# ' + f + ' ') or stripped.startswith('#' + f + ' ') or stripped.startswith('# ' + f + '=') or stripped.startswith('#' + f + '='):\n" +
            "                indent = line[:len(line) - len(line.lstrip())]\n" +
            "                line = indent + stripped.lstrip('# ')\n" +
            "                break\n" +
            "        else:\n" +
            "            if stripped.startswith(f + ' ') or stripped.startswith(f + '='):\n" +
            "                indent = line[:len(line) - len(line.lstrip())]\n" +
            "                line = indent + '# ' + stripped\n" +
            "                break\n" +
            "    if stripped.startswith('gaps_in'):\n" +
            "        indent = line[:len(line) - len(line.lstrip())]\n" +
            "        line = indent + 'gaps_in = ' + ('4' if enable else '0') + '\\n'\n" +
            "    elif stripped.startswith('gaps_out'):\n" +
            "        indent = line[:len(line) - len(line.lstrip())]\n" +
            "        line = indent + 'gaps_out = ' + ('5' if enable else '0') + '\\n'\n" +
            "    result.append(line)\n" +
            "open(conf, 'w').writelines(result)\n";
        Quickshell.execDetached(["python3", "-c", py, enabled ? "1" : "0", root.generalConf, fields.join(",")]);
        if (enabled) {
            Quickshell.execDetached(["hyprctl", "keyword", "general:border_size", "4"]);
            Quickshell.execDetached(["hyprctl", "keyword", "general:col.active_border", "rgba(0DB7D455)"]);
            Quickshell.execDetached(["hyprctl", "keyword", "general:col.inactive_border", "rgba(31313600)"]);
            Quickshell.execDetached(["hyprctl", "keyword", "general:resize_on_border", "true"]);
            Quickshell.execDetached(["hyprctl", "keyword", "general:gaps_in", "4"]);
            Quickshell.execDetached(["hyprctl", "keyword", "general:gaps_out", "5"]);
        } else {
            Quickshell.execDetached(["hyprctl", "keyword", "general:border_size", "0"]);
            Quickshell.execDetached(["hyprctl", "keyword", "general:resize_on_border", "false"]);
            Quickshell.execDetached(["hyprctl", "keyword", "general:gaps_in", "0"]);
            Quickshell.execDetached(["hyprctl", "keyword", "general:gaps_out", "0"]);
        }
    }

    function decoSetRoundCornersEnabled(enabled) {
        let val = enabled ? "10" : "0";
        let py =
            "import sys, re\n" +
            "val, conf = sys.argv[1], sys.argv[2]\n" +
            "text = open(conf).read()\n" +
            "text = re.sub(r'(rounding\\s*=\\s*)\\d+', r'\\g<1>' + val, text, count=1)\n" +
            "open(conf, 'w').write(text)\n";
        Quickshell.execDetached(["python3", "-c", py, val, root.generalConf]);
        Quickshell.execDetached(["hyprctl", "keyword", "decoration:rounding", val]);
        if (!enabled) {
            root.previousCornerStyle = Config.options.bar.cornerStyle;
            Config.options.bar.cornerStyle = 2;
        } else {
            Config.options.bar.cornerStyle = root.previousCornerStyle;
        }
    }

    Process {
        id: lockTimeoutReader
        command: ["awk",
            "/timeout[[:space:]]*=/{for(i=1;i<=NF;i++)if($i~/^[0-9]+$/){t=$i;break}} /on-timeout.*lock-session/{print t; exit}",
            hyprIdleConf
        ]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => lockTimeoutReader.buf += data }
        onExited: (code) => {
            const v = parseInt(lockTimeoutReader.buf.trim())
            if (!isNaN(v)) {
                if (v === 0 || v >= 599940) {
                    lockEnabled = false
                } else {
                    lockEnabled = true
                    lockSecs = v
                }
            }
            _lockReaderFinished = true
        }
    }

    function applyLockTimeout(enabled, secs) {
        const timeout = enabled ? secs : 599940
        const awkProg = [
            "BEGIN{il=0; m=0}",
            "/^listener/ && /\\{/{il=1; m=0; block=$0; next}",
            "il{block=block\"\\n\"$0; if($0 ~ /on-timeout.*lock-session/){m=1}; if($0 ~ /\\}/){if(m){sub(/timeout[ \\t]*=[ \\t]*[0-9]+/,\"timeout = " + timeout + "\",block)}; print block; il=0; next}}",
            "il==0{print}",
        ].join("; ")
        Quickshell.execDetached(["bash", "-c",
            "awk '" + awkProg + "' '" + hyprIdleConf + "' > '" + hyprIdleConf + ".tmp' && mv '" + hyprIdleConf + ".tmp' '" + hyprIdleConf + "' && pkill -x hypridle; hypridle &"
        ])
    }

    /*
    ContentSection {
        icon: "keyboard"
        title: Translation.tr("Cheat sheet")

        ContentSubsection {
            title: Translation.tr("Super key symbol")
            tooltip: Translation.tr("You can also manually edit cheatsheet.superKey")
            ConfigSelectionArray {
                currentValue: Config.options.cheatsheet.superKey
                onSelected: newValue => {
                    Config.options.cheatsheet.superKey = newValue;
                }
                // Use a nerdfont to see the icons
                options: ([
                  "󰖳", "", "󰨡", "", "󰌽", "󰣇", "", "", "", 
                  "", "", "󱄛", "", "", "", "⌘", "󰀲", "󰟍", ""
                ]).map(icon => { return {
                  displayName: icon,
                  value: icon
                  }
                })
            }
        }

        ConfigSwitch {
            buttonIcon: "󰘵"
            text: Translation.tr("Use macOS-like symbols for mods keys")
            checked: Config.options.cheatsheet.useMacSymbol
            onCheckedChanged: {
                Config.options.cheatsheet.useMacSymbol = checked;
            }
            StyledToolTip {
                text: Translation.tr("e.g. 󰘴  for Ctrl, 󰘵  for Alt, 󰘶  for Shift, etc")
            }
        }

        ConfigSwitch {
            buttonIcon: "󱊶"
            text: Translation.tr("Use symbols for function keys")
            checked: Config.options.cheatsheet.useFnSymbol
            onCheckedChanged: {
                Config.options.cheatsheet.useFnSymbol = checked;
            }
            StyledToolTip {
              text: Translation.tr("e.g. 󱊫 for F1, 󱊶  for F12")
            }
        }
        ConfigSwitch {
            buttonIcon: "󰍽"
            text: Translation.tr("Use symbols for mouse")
            checked: Config.options.cheatsheet.useMouseSymbol
            onCheckedChanged: {
                Config.options.cheatsheet.useMouseSymbol = checked;
            }
            StyledToolTip {
              text: Translation.tr("Replace 󱕐   for \"Scroll ↓\", 󱕑   \"Scroll ↑\", L󰍽   \"LMB\", R󰍽   \"RMB\", 󱕒   \"Scroll ↑/↓\" and ⇞/⇟ for \"Page_↑/↓\"")
            }
        }
        ConfigSwitch {
            buttonIcon: "highlight_keyboard_focus"
            text: Translation.tr("Split buttons")
            checked: Config.options.cheatsheet.splitButtons
            onCheckedChanged: {
                Config.options.cheatsheet.splitButtons = checked;
            }
            StyledToolTip {
                text: Translation.tr("Display modifiers and keys in multiple keycap (e.g., \"Ctrl + A\" instead of \"Ctrl A\" or \"󰘴 + A\" instead of \"󰘴 A\")")
            }

        }

        ConfigSpinBox {
            text: Translation.tr("Keybind font size")
            value: Config.options.cheatsheet.fontSize.key
            from: 8
            to: 30
            stepSize: 1
            onValueChanged: {
                Config.options.cheatsheet.fontSize.key = value;
            }
        }
        ConfigSpinBox {
            text: Translation.tr("Description font size")
            value: Config.options.cheatsheet.fontSize.comment
            from: 8
            to: 30
            stepSize: 1
            onValueChanged: {
                Config.options.cheatsheet.fontSize.comment = value;
            }
        }
    }
    */

    // ── Decorations ──────────────────────────────────────────────────────────
    ContentSection {
        icon: "auto_awesome"
        title: Translation.tr("Decorations")

        ConfigRow {
            uniform: true
            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "animation"
                text: Translation.tr("Animations")
                checked: root.animationsEnabled
                onCheckedChanged: {
                    if (!root._decoReady) return;
                    root.animationsEnabled = checked;
                    root.decoSetBlockEnabled("animations", checked);
                    Quickshell.execDetached(["hyprctl", "keyword", "animations:enabled", checked ? "true" : "false"]);
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
                onCheckedChanged: {
                    if (!root._decoReady) return;
                    root.blurEnabled = checked;
                    root.decoSetBlockEnabled("blur", checked);
                    Quickshell.execDetached(["hyprctl", "keyword", "decoration:blur:enabled", checked ? "true" : "false"]);
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
                onCheckedChanged: {
                    if (!root._decoReady) return;
                    root.shadowsEnabled = checked;
                    root.decoSetBlockEnabled("shadow", checked);
                    Quickshell.execDetached(["hyprctl", "keyword", "decoration:shadow:enabled", checked ? "true" : "false"]);
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
                onCheckedChanged: {
                    if (!root._decoReady) return;
                    root.roundCornersEnabled = checked;
                    root.decoSetRoundCornersEnabled(checked);
                }
                StyledToolTip {
                    text: Translation.tr("Rounded corners on windows and the bar")
                }
            }
            ConfigSwitch {
                buttonIcon: "title"
                text: Translation.tr("Title Bars")
                checked: root.titleBarsEnabled
                onCheckedChanged: {
                    if (!root._decoReady) return;
                    root.titleBarsEnabled = checked;
                    // Toggle by commenting/uncommenting the plugin = .../hyprbars.so line
                    // in custom/general.conf. No hyprpm needed — Hyprland loads the .so
                    // directly when the directive is present and uncommented.
                    let py =
                        "import re, sys\n" +
                        "enable = sys.argv[1] == '1'\n" +
                        "conf = sys.argv[2]\n" +
                        "text = open(conf).read()\n" +
                        "if enable:\n" +
                        "    text = re.sub(r'^([ \\t]*)#[ \\t]*(plugin[ \\t]*=[ \\t]*.*hyprbars\\.so)', r'\\1\\2', text, flags=re.M)\n" +
                        "else:\n" +
                        "    text = re.sub(r'^([ \\t]*)(plugin[ \\t]*=[ \\t]*.*hyprbars\\.so)', r'\\1# \\2', text, flags=re.M)\n" +
                        "open(conf, 'w').write(text)\n";
                    Quickshell.execDetached(["python3", "-c", py, checked ? "1" : "0", root.customGeneralConf]);
                    Quickshell.execDetached(["hyprctl", "reload"]);
                }
                StyledToolTip {
                    text: Translation.tr("Show title bars on windows")
                }
            }
        }
    }

    ContentSection {
        icon: "call_to_action"
        title: Translation.tr("Dock")

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable")
            checked: Config.options.dock.enable
            onCheckedChanged: {
                Config.options.dock.enable = checked;
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "highlight_mouse_cursor"
                text: Translation.tr("Hover to reveal")
                checked: Config.options.dock.hoverToReveal
                onCheckedChanged: {
                    Config.options.dock.hoverToReveal = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "keep"
                text: Translation.tr("Pinned on startup")
                checked: Config.options.dock.pinnedOnStartup
                onCheckedChanged: {
                    Config.options.dock.pinnedOnStartup = checked;
                }
            }
        }
        ConfigSwitch {
            buttonIcon: "colors"
            text: Translation.tr("Tint app icons")
            checked: Config.options.dock.monochromeIcons
            onCheckedChanged: {
                Config.options.dock.monochromeIcons = checked;
            }
        }
    }

    /*
    ContentSection {
        icon: "notifications"
        title: Translation.tr("Notifications")

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Timeout duration (if not defined by notification) (ms)")
            value: Config.options.notifications.timeout
            from: 1000
            to: 60000
            stepSize: 1000
            onValueChanged: {
                Config.options.notifications.timeout = value;
            }
        }
    }

    ContentSection {
        icon: "select_window"
        title: Translation.tr("Overlay: General")

        ConfigSwitch {
            buttonIcon: "high_density"
            text: Translation.tr("Enable opening zoom animation")
            checked: Config.options.overlay.openingZoomAnimation
            onCheckedChanged: {
                Config.options.overlay.openingZoomAnimation = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "texture"
            text: Translation.tr("Darken screen")
            checked: Config.options.overlay.darkenScreen
            onCheckedChanged: {
                Config.options.overlay.darkenScreen = checked;
            }
        }
    }

    ContentSection {
        icon: "point_scan"
        title: Translation.tr("Overlay: Crosshair")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Crosshair code (in Valorant's format)")
            text: Config.options.crosshair.code
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.crosshair.code = text;
            }
        }

        RowLayout {
            StyledText {
                Layout.leftMargin: 10
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallie
                text: Translation.tr("Press Super+G to open the overlay and pin the crosshair")
            }
            Item {
                Layout.fillWidth: true
            }
            RippleButtonWithIcon {
                id: editorButton
                buttonRadius: Appearance.rounding.full
                materialIcon: "open_in_new"
                mainText: Translation.tr("Open editor")
                onClicked: {
                    Qt.openUrlExternally(`https://www.vcrdb.net/builder?c=${Config.options.crosshair.code}`);
                }
                StyledToolTip {
                    text: "www.vcrdb.net"
                }
            }
        }
    }

    ContentSection {
        icon: "point_scan"
        title: Translation.tr("Overlay: Floating Image")

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Image source")
            text: Config.options.overlay.floatingImage.imageSource
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.overlay.floatingImage.imageSource = text;
            }
        }
    }

    ContentSection {
        icon: "screenshot_frame_2"
        title: Translation.tr("Region selector (screen snipping/Google Lens)")

        ContentSubsection {
            title: Translation.tr("Hint target regions")
            ConfigRow {
                ConfigSwitch {
                    buttonIcon: "select_window"
                    text: Translation.tr('Windows')
                    checked: Config.options.regionSelector.targetRegions.windows
                    onCheckedChanged: {
                        Config.options.regionSelector.targetRegions.windows = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "right_panel_open"
                    text: Translation.tr('Layers')
                    checked: Config.options.regionSelector.targetRegions.layers
                    onCheckedChanged: {
                        Config.options.regionSelector.targetRegions.layers = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "nearby"
                    text: Translation.tr('Content')
                    checked: Config.options.regionSelector.targetRegions.content
                    onCheckedChanged: {
                        Config.options.regionSelector.targetRegions.content = checked;
                    }
                    StyledToolTip {
                        text: Translation.tr("Could be images or parts of the screen that have some containment.\nMight not always be accurate.\nThis is done with an image processing algorithm run locally and no AI is used.")
                    }
                }
            }
        }
        
        ContentSubsection {
            title: Translation.tr("Google Lens")
            
            ConfigSelectionArray {
                currentValue: Config.options.search.imageSearch.useCircleSelection ? "circle" : "rectangles"
                onSelected: newValue => {
                    Config.options.search.imageSearch.useCircleSelection = (newValue === "circle");
                }
                options: [
                    { icon: "activity_zone", value: "rectangles", displayName: Translation.tr("Rectangular selection") },
                    { icon: "gesture", value: "circle", displayName: Translation.tr("Circle to Search") }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Rectangular selection")

            ConfigSwitch {
                buttonIcon: "point_scan"
                text: Translation.tr("Show aim lines")
                checked: Config.options.regionSelector.rect.showAimLines
                onCheckedChanged: {
                    Config.options.regionSelector.rect.showAimLines = checked;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Circle selection")
            
            ConfigSpinBox {
                icon: "eraser_size_3"
                text: Translation.tr("Stroke width")
                value: Config.options.regionSelector.circle.strokeWidth
                from: 1
                to: 20
                stepSize: 1
                onValueChanged: {
                    Config.options.regionSelector.circle.strokeWidth = value;
                }
            }

            ConfigSpinBox {
                icon: "screenshot_frame_2"
                text: Translation.tr("Padding")
                value: Config.options.regionSelector.circle.padding
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.regionSelector.circle.padding = value;
                }
            }
        }
    }
    */
    // ── Left Sidebar ──────────────────────────────────────────────────────────
    ContentSection {
        icon: "side_navigation"
        mirrorIcon: true
        title: Translation.tr("Left Sidebar")

        ConfigRow {
            ColumnLayout {
                ContentSubsectionLabel {
                    text: Translation.tr("AI")
                }
                ConfigSelectionArray {
                    currentValue: Config.options.policies.ai
                    onSelected: newValue => {
                        Config.options.policies.ai = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("No"),         icon: "close",              value: 0 },
                        { displayName: Translation.tr("Yes"),        icon: "check",              value: 1 },
                        { displayName: Translation.tr("Local only"), icon: "sync_saved_locally", value: 2 }
                    ]
                }
            }
            ColumnLayout {
                ContentSubsectionLabel {
                    text: Translation.tr("Wallpaper Browser")
                }
                ConfigSelectionArray {
                    currentValue: Config.options.policies.wallpaperBrowser
                    onSelected: newValue => {
                        Config.options.policies.wallpaperBrowser = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("No"),  icon: "close", value: 0 },
                        { displayName: Translation.tr("Yes"), icon: "check", value: 1 }
                    ]
                }
            }
            ColumnLayout {
                ContentSubsectionLabel {
                    text: Translation.tr("Translator")
                }
                ConfigSelectionArray {
                    currentValue: Config.options.sidebar.translator.enable ? 1 : 0
                    onSelected: newValue => {
                        Config.options.sidebar.translator.enable = (newValue === 1);
                    }
                    options: [
                        { displayName: Translation.tr("No"),  icon: "close", value: 0 },
                        { displayName: Translation.tr("Yes"), icon: "check", value: 1 }
                    ]
                }
            }
        }
    }

    // ── Right Sidebar ─────────────────────────────────────────────────────────
    ContentSection {
        icon: "side_navigation"
        title: Translation.tr("Right Sidebar")
        /*
        ConfigSwitch {
            buttonIcon: "memory"
            text: Translation.tr('Keep right sidebar loaded')
            checked: Config.options.sidebar.keepRightSidebarLoaded
            onCheckedChanged: {
                Config.options.sidebar.keepRightSidebarLoaded = checked;
            }
            StyledToolTip {
                text: Translation.tr("When enabled keeps the content of the right sidebar loaded to reduce the delay when opening,\nat the cost of around 15MB of consistent RAM usage. Delay significance depends on your system's performance.\nUsing a custom kernel like linux-cachyos might help")
            }
        }

        ConfigSwitch {
            buttonIcon: "translate"
            text: Translation.tr('Enable translator')
            checked: Config.options.sidebar.translator.enable
            onCheckedChanged: {
                Config.options.sidebar.translator.enable = checked;
            }
        }
        */
        ContentSubsection {
            title: Translation.tr("Quick toggles")
            
            ConfigSelectionArray {
                Layout.fillWidth: false
                currentValue: Config.options.sidebar.quickToggles.style
                onSelected: newValue => {
                    Config.options.sidebar.quickToggles.style = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Classic"),
                        icon: "password_2",
                        value: "classic"
                    },
                    {
                        displayName: Translation.tr("Android"),
                        icon: "action_key",
                        value: "android"
                    }
                ]
            }

            ConfigSpinBox {
                enabled: Config.options.sidebar.quickToggles.style === "android"
                icon: "splitscreen_left"
                text: Translation.tr("Columns")
                value: Config.options.sidebar.quickToggles.android.columns
                from: 1
                to: 8
                stepSize: 1
                onValueChanged: {
                    Config.options.sidebar.quickToggles.android.columns = value;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Sliders")

            ConfigSwitch {
                buttonIcon: "check"
                text: Translation.tr("Enable")
                checked: Config.options.sidebar.quickSliders.enable
                onCheckedChanged: {
                    Config.options.sidebar.quickSliders.enable = checked;
                }
            }
            
            ConfigSwitch {
                buttonIcon: "brightness_6"
                text: Translation.tr("Brightness")
                enabled: Config.options.sidebar.quickSliders.enable
                checked: Config.options.sidebar.quickSliders.showBrightness
                onCheckedChanged: {
                    Config.options.sidebar.quickSliders.showBrightness = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "volume_up"
                text: Translation.tr("Volume")
                enabled: Config.options.sidebar.quickSliders.enable
                checked: Config.options.sidebar.quickSliders.showVolume
                onCheckedChanged: {
                    Config.options.sidebar.quickSliders.showVolume = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "mic"
                text: Translation.tr("Microphone")
                enabled: Config.options.sidebar.quickSliders.enable
                checked: Config.options.sidebar.quickSliders.showMic
                onCheckedChanged: {
                    Config.options.sidebar.quickSliders.showMic = checked;
                }
            }
        }
        /*
        ContentSubsection {
            title: Translation.tr("Corner open")
            tooltip: Translation.tr("Allows you to open sidebars by clicking or hovering screen corners regardless of bar position")
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "check"
                    text: Translation.tr("Enable")
                    checked: Config.options.sidebar.cornerOpen.enable
                    onCheckedChanged: {
                        Config.options.sidebar.cornerOpen.enable = checked;
                    }
                }
            }
            ConfigSwitch {
                buttonIcon: "highlight_mouse_cursor"
                text: Translation.tr("Hover to trigger")
                checked: Config.options.sidebar.cornerOpen.clickless
                onCheckedChanged: {
                    Config.options.sidebar.cornerOpen.clickless = checked;
                }

                StyledToolTip {
                    text: Translation.tr("When this is off you'll have to click")
                }
            }
            Row {
                ConfigSwitch {
                    enabled: !Config.options.sidebar.cornerOpen.clickless
                    text: Translation.tr("Force hover open at absolute corner")
                    checked: Config.options.sidebar.cornerOpen.clicklessCornerEnd
                    onCheckedChanged: {
                        Config.options.sidebar.cornerOpen.clicklessCornerEnd = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("When the previous option is off and this is on,\nyou can still hover the corner's end to open sidebar,\nand the remaining area can be used for volume/brightness scroll")
                    }
                }
                ConfigSpinBox {
                    icon: "arrow_cool_down"
                    text: Translation.tr("with vertical offset")
                    value: Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset
                    from: 0
                    to: 20
                    stepSize: 1
                    onValueChanged: {
                        Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset = value;
                    }
                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        StyledToolTip {
                            extraVisibleCondition: mouseArea.containsMouse
                            text: Translation.tr("Why this is cool:\nFor non-0 values, it won't trigger when you reach the\nscreen corner along the horizontal edge, but it will when\nyou do along the vertical edge")
                        }
                    }
                }
            }
            
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "vertical_align_bottom"
                    text: Translation.tr("Place at bottom")
                    checked: Config.options.sidebar.cornerOpen.bottom
                    onCheckedChanged: {
                        Config.options.sidebar.cornerOpen.bottom = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Place the corners to trigger at the bottom")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "unfold_more_double"
                    text: Translation.tr("Value scroll")
                    checked: Config.options.sidebar.cornerOpen.valueScroll
                    onCheckedChanged: {
                        Config.options.sidebar.cornerOpen.valueScroll = checked;
                    }

                    StyledToolTip {
                        text: Translation.tr("Brightness and volume")
                    }
                }
            }
            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Visualize region")
                checked: Config.options.sidebar.cornerOpen.visualize
                onCheckedChanged: {
                    Config.options.sidebar.cornerOpen.visualize = checked;
                }
            }
            ConfigRow {
                ConfigSpinBox {
                    icon: "arrow_range"
                    text: Translation.tr("Region width")
                    value: Config.options.sidebar.cornerOpen.cornerRegionWidth
                    from: 1
                    to: 300
                    stepSize: 1
                    onValueChanged: {
                        Config.options.sidebar.cornerOpen.cornerRegionWidth = value;
                    }
                }
                ConfigSpinBox {
                    icon: "height"
                    text: Translation.tr("Region height")
                    value: Config.options.sidebar.cornerOpen.cornerRegionHeight
                    from: 1
                    to: 300
                    stepSize: 1
                    onValueChanged: {
                        Config.options.sidebar.cornerOpen.cornerRegionHeight = value;
                    }
                }
            }
        }
        */

        ContentSubsection {
            title: Translation.tr("Timer")

            ConfigSpinBox {
                icon: "target"
                text: Translation.tr("Focus (min)")
                value: Config.options.time.pomodoro.focus / 60
                from: 1
                to: 120
                stepSize: 5
                onValueChanged: {
                    Config.options.time.pomodoro.focus = value * 60;
                }
            }
            ConfigSpinBox {
                icon: "coffee"
                text: Translation.tr("Break (min)")
                value: Config.options.time.pomodoro.breakTime / 60
                from: 1
                to: 60
                stepSize: 1
                onValueChanged: {
                    Config.options.time.pomodoro.breakTime = value * 60;
                }
            }
            ConfigSpinBox {
                icon: "weekend"
                text: Translation.tr("Long break (min)")
                value: Config.options.time.pomodoro.longBreak / 60
                from: 1
                to: 60
                stepSize: 5
                onValueChanged: {
                    Config.options.time.pomodoro.longBreak = value * 60;
                }
            }
            ConfigSpinBox {
                icon: "repeat"
                text: Translation.tr("Cycles before long break")
                value: Config.options.time.pomodoro.cyclesBeforeLongBreak
                from: 1
                to: 10
                stepSize: 1
                onValueChanged: {
                    Config.options.time.pomodoro.cyclesBeforeLongBreak = value;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Alarms")

            ConfigSwitch {
                buttonIcon: "av_timer"
                text: Translation.tr("Pomodoro")
                checked: Config.options.sounds.pomodoro
                onCheckedChanged: {
                    Config.options.sounds.pomodoro = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "timer"
                text: Translation.tr("Timer")
                checked: Config.options.sounds.timer
                onCheckedChanged: {
                    Config.options.sounds.timer = checked;
                }
            }
        }
    }

    // ── Lock screen ───────────────────────────────────────────────────────────
    ContentSection {
        icon: "lock"
        title: Translation.tr("Lock screen")
        /*
        ConfigSwitch {
            buttonIcon: "water_drop"
            text: Translation.tr('Use Hyprlock (instead of Quickshell)')
            checked: Config.options.lock.useHyprlock
            onCheckedChanged: {
                Config.options.lock.useHyprlock = checked;
            }
            StyledToolTip {
                text: Translation.tr("If you want to somehow use fingerprint unlock...")
            }
        }
        */
        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "timer"
            text: Translation.tr("Automatic Lock")
            checked: lockEnabled
            onCheckedChanged: {
                lockEnabled = checked
                if (_lockReaderFinished) applyLockTimeout(checked, lockSecs)
            }
        }
        ConfigRow {
            enabled: lockEnabled
            StyledText {
                text: Translation.tr("Delay")
                font.pixelSize: Appearance.font.pixelSize.normal
                color: lockEnabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                Layout.fillWidth: true
            }
            StyledComboBox {
                enabled: lockEnabled
                textRole: "displayName"
                model: [
                    { displayName: Translation.tr("1 minute"),   seconds: 60   },
                    { displayName: Translation.tr("2 minutes"),  seconds: 120  },
                    { displayName: Translation.tr("5 minutes"),  seconds: 300  },
                    { displayName: Translation.tr("10 minutes"), seconds: 600  },
                    { displayName: Translation.tr("15 minutes"), seconds: 900  },
                    { displayName: Translation.tr("30 minutes"), seconds: 1800 }
                ]
                currentIndex: {
                    const idx = model.findIndex(item => item.seconds === lockSecs)
                    return idx !== -1 ? idx : 2
                }
                onActivated: index => {
                    lockSecs = model[index].seconds
                    applyLockTimeout(lockEnabled, model[index].seconds)
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "account_circle"
            text: Translation.tr('Launch on startup')
            checked: Config.options.lock.launchOnStartup
            onCheckedChanged: {
                Config.options.lock.launchOnStartup = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Security")

            ConfigSwitch {
                buttonIcon: "settings_power"
                text: Translation.tr('Require password to power off/restart')
                checked: Config.options.lock.security.requirePasswordToPower
                onCheckedChanged: {
                    Config.options.lock.security.requirePasswordToPower = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Remember that on most devices one can always hold the power button to force shutdown\nThis only makes it a tiny bit harder for accidents to happen")
                }
            }

            ConfigSwitch {
                buttonIcon: "key_vertical"
                text: Translation.tr('Also unlock keyring')
                checked: Config.options.lock.security.unlockKeyring
                onCheckedChanged: {
                    Config.options.lock.security.unlockKeyring = checked;
                }
                StyledToolTip {
                    text: Translation.tr("This is usually safe and needed for your browser and AI sidebar anyway\nMostly useful for those who use lock on startup instead of a display manager that does it (GDM, SDDM, etc.)")
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Style: general")
            /*
            ConfigSwitch {
                buttonIcon: "center_focus_weak"
                text: Translation.tr('Center clock')
                checked: Config.options.lock.centerClock
                onCheckedChanged: {
                    Config.options.lock.centerClock = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "info"
                text: Translation.tr('Show "Locked" text')
                checked: Config.options.lock.showLockedText
                onCheckedChanged: {
                    Config.options.lock.showLockedText = checked;
                }
            }
            */
            ConfigSwitch {
                buttonIcon: "shapes"
                text: Translation.tr('Use varying shapes for password characters')
                checked: Config.options.lock.materialShapeChars
                onCheckedChanged: {
                    Config.options.lock.materialShapeChars = checked;
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Style: Blurred")

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr('Enable blur')
                checked: Config.options.lock.blur.enable
                onCheckedChanged: {
                    Config.options.lock.blur.enable = checked;
                }
            }
            /*
            ConfigSpinBox {
                icon: "loupe"
                text: Translation.tr("Extra wallpaper zoom (%)")
                value: Config.options.lock.blur.extraZoom * 100
                from: 1
                to: 150
                stepSize: 2
                onValueChanged: {
                    Config.options.lock.blur.extraZoom = value / 100;
                }
            }
            */
        }
    }

    /*
    ContentSection {
        icon: "voting_chip"
        title: Translation.tr("On-screen display")

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Timeout (ms)")
            value: Config.options.osd.timeout
            from: 100
            to: 3000
            stepSize: 100
            onValueChanged: {
                Config.options.osd.timeout = value;
            }
        }
    }

    ContentSection {
        icon: "overview_key"
        title: Translation.tr("Overview")

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable")
            checked: Config.options.overview.enable
            onCheckedChanged: {
                Config.options.overview.enable = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "center_focus_strong"
            text: Translation.tr("Center icons")
            checked: Config.options.overview.centerIcons
            onCheckedChanged: {
                Config.options.overview.centerIcons = checked;
            }
        }
        ConfigSpinBox {
            icon: "loupe"
            text: Translation.tr("Scale (%)")
            value: Config.options.overview.scale * 100
            from: 1
            to: 100
            stepSize: 1
            onValueChanged: {
                Config.options.overview.scale = value / 100;
            }
        }
        ConfigRow {
            uniform: true
            ConfigSpinBox {
                icon: "splitscreen_bottom"
                text: Translation.tr("Rows")
                value: Config.options.overview.rows
                from: 1
                to: 20
                stepSize: 1
                onValueChanged: {
                    Config.options.overview.rows = value;
                }
            }
            ConfigSpinBox {
                icon: "splitscreen_right"
                text: Translation.tr("Columns")
                value: Config.options.overview.columns
                from: 1
                to: 20
                stepSize: 1
                onValueChanged: {
                    Config.options.overview.columns = value;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSelectionArray {
                currentValue: Config.options.overview.orderRightLeft
                onSelected: newValue => {
                    Config.options.overview.orderRightLeft = newValue
                }
                options: [
                    {
                        displayName: Translation.tr("Left to right"),
                        icon: "arrow_forward",
                        value: 0
                    },
                    {
                        displayName: Translation.tr("Right to left"),
                        icon: "arrow_back",
                        value: 1
                    }
                ]
            }
            ConfigSelectionArray {
                currentValue: Config.options.overview.orderBottomUp
                onSelected: newValue => {
                    Config.options.overview.orderBottomUp = newValue
                }
                options: [
                    {
                        displayName: Translation.tr("Top-down"),
                        icon: "arrow_downward",
                        value: 0
                    },
                    {
                        displayName: Translation.tr("Bottom-up"),
                        icon: "arrow_upward",
                        value: 1
                    }
                ]
            }
        }
    }

    ContentSection {
        icon: "wallpaper_slideshow"
        title: Translation.tr("Wallpaper selector")

        ConfigSwitch {
            buttonIcon: "ad"
            text: Translation.tr('Use system file picker')
            checked: Config.options.wallpaperSelector.useSystemFileDialog
            onCheckedChanged: {
                Config.options.wallpaperSelector.useSystemFileDialog = checked;
            }
        }
    }
    */
    ContentSection {
        icon: "text_format"
        title: Translation.tr("Fonts")

        ContentSubsection {
            title: Translation.tr("Main font")
            tooltip: Translation.tr("Used for general UI text")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Font family name (e.g., Google Sans Flex)")
                text: Config.options.appearance.fonts.main
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
                    Config.options.appearance.fonts.main = text;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Numbers font")
            tooltip: Translation.tr("Used for displaying numbers")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Font family name")
                text: Config.options.appearance.fonts.numbers
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
                    Config.options.appearance.fonts.numbers = text;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Title font")
            tooltip: Translation.tr("Used for headings and titles")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Font family name")
                text: Config.options.appearance.fonts.title
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
                    Config.options.appearance.fonts.title = text;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Monospace font")
            tooltip: Translation.tr("Used for code and terminal")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Font family name (e.g., JetBrains Mono NF)")
                text: Config.options.appearance.fonts.monospace
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
                    Config.options.appearance.fonts.monospace = text;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Nerd font icons")
            tooltip: Translation.tr("Font used for Nerd Font icons")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Font family name (e.g., JetBrains Mono NF)")
                text: Config.options.appearance.fonts.iconNerd
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
                    Config.options.appearance.fonts.iconNerd = text;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Reading font")
            tooltip: Translation.tr("Used for reading large blocks of text")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Font family name (e.g., Readex Pro)")
                text: Config.options.appearance.fonts.reading
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
                    Config.options.appearance.fonts.reading = text;
                }
            }
        }

        ContentSubsection {
            title: Translation.tr("Expressive font")
            tooltip: Translation.tr("Used for decorative/expressive text")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Font family name (e.g., Space Grotesk)")
                text: Config.options.appearance.fonts.expressive
                wrapMode: TextEdit.NoWrap
                onTextChanged: {
                    Config.options.appearance.fonts.expressive = text;
                }
            }
        }
    }

}
