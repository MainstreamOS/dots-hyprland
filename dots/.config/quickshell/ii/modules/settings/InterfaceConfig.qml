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

    readonly property string customGeneralConf: `${CF.FileUtils.trimFileProtocol(Directories.config)}/hypr/custom/general.lua`
    readonly property string customKeybindsConf: `${CF.FileUtils.trimFileProtocol(Directories.config)}/hypr/custom/keybinds.lua`
    // Mirrors whether scrolloverview is currently loaded into Hyprland.
    // Source of truth is `hyprctl plugin list` (read by scrollOverviewStateReader),
    // not the conf file — Hyprland only re-reads `plugin = ...` directives at
    // startup, so the conf and the live state can diverge. The toggle keeps
    // both in sync by calling `hyprctl plugin load/unload` AND editing the conf.
    property bool scrollOverviewEnabled: false
    // Layout values for the scroll-overview, also persisted in the
    // scrolloverview block of custom/general.lua. Defaults match the
    // plugin's compiled-in defaults.
    property int scrollOverviewWorkspaceGap: 100     // pixels between workspace previews
    property real scrollOverviewWorkspaceScale: 0.5  // 0.0–1.0 — overview shrink factor
    property string scrollOverviewLayout: "vertical" // "vertical" | "horizontal" — overview scroll axis

    function runPy(py, args) {
        Quickshell.execDetached(["python3", "-c", py, ...args])
    }

    // Apply a single config value live. In Hyprland 0.55 Lua mode `hyprctl
    // keyword` is hard-gated to Legacy ("keyword can't work with non-legacy
    // parsers. Use eval."), so we go through `hyprctl eval` + `hl.config()`
    // instead. The Lua config manager looks up keys in m_configValues under
    // dot-form names (luaConfigValueName converts `:` → `.`), so we split the
    // hyprlang colon-form on the FIRST colon and put everything after it
    // inside a single bracket-string key — handles `general:border_size`
    // (one segment after section) and `general:col.active_border` /
    // `decoration:blur:enabled` (dots and extra colons in the leaf) uniformly.
    //
    // Value coercion to Lua literal:
    //   "true"/"false"             → boolean
    //   integer or float string     → numeric literal
    //   everything else             → quoted string (backslashes + quotes escaped)
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

    // ── Lock timeout ─────────────────────────────────────────────────────────
    property bool lockEnabled: true
    property int lockSecs: 300
    property bool _lockReaderFinished: false

    readonly property string hyprIdleConf: `${CF.FileUtils.trimFileProtocol(Directories.config)}/hypr/hypridle.conf`

    Component.onCompleted: {
        lockTimeoutReader.running = true
        scrollOverviewConfReader.running = true
        scrollOverviewStateReader.running = true
    }

    // When a theme apply finishes, the shared state file flips back to "idle"
    // and Config.themeApplyInProgress goes false. Re-read the hypr confs so the
    // decoration switches reflect whatever the applied theme restored.
    Connections {
        target: Config
        function onThemeApplyInProgressChanged() {
            if (Config.themeApplyInProgress) return
            scrollOverviewConfReader.running = false
            scrollOverviewConfReader.running = true
            scrollOverviewStateReader.running = false
            scrollOverviewStateReader.running = true
        }
    }

    Process {
        id: scrollOverviewConfReader
        command: ["cat", root.customGeneralConf]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => scrollOverviewConfReader.buf += data + "\n" }
        onExited: {
            // Pull current scrolloverview values from the plugin config
            // block. In Lua the block is `scrolloverview = { ... }` (with `=`
            // before the table brace). Lazy [\s\S]*? skips nested blocks
            // (e.g. `shadow = {}`). If a value isn't present we leave the
            // default in place — the plugin uses the same defaults internally.
            // (Title bars enabled-state is read by services/TitleBars.qml.)
            let gapMatch = scrollOverviewConfReader.buf.match(/scrolloverview\s*=\s*\{[\s\S]*?\bworkspace_gap\s*=\s*(\d+)/);
            if (gapMatch) root.scrollOverviewWorkspaceGap = parseInt(gapMatch[1]);
            // scale is a float (e.g. 0.5) — accept optional decimal part
            let scaleMatch = scrollOverviewConfReader.buf.match(/scrolloverview\s*=\s*\{[\s\S]*?\bscale\s*=\s*(\d+(?:\.\d+)?)/);
            if (scaleMatch) root.scrollOverviewWorkspaceScale = parseFloat(scaleMatch[1]);
            // layout is a quoted Lua string: layout = "vertical" | "horizontal".
            let layoutMatch = scrollOverviewConfReader.buf.match(/scrolloverview\s*=\s*\{[\s\S]*?\blayout\s*=\s*"([a-z]+)"/);
            if (layoutMatch) root.scrollOverviewLayout = layoutMatch[1];
        }
    }

    // Update one scrolloverview value. Live effect via setHyprKeyword which
    // routes through `hyprctl eval` + hl.config (Lua-mode replacement for the
    // Legacy-only `hyprctl keyword`). The plugin re-reads its config pointer
    // on every overview construction, so the next open picks up the new
    // value. Persistence via Python regex on custom/general.lua — replaces
    // an existing line in the `scrolloverview = { ... }` table, or inserts
    // one right after the opening brace if no line exists yet. Handles integers,
    // floats, bools, and quoted strings (e.g. layout = "vertical").
    // Inserted lines get a trailing comma to stay valid Lua table syntax.
    function setScrollOverviewKey(key, value) {
        setHyprKeyword(`plugin:scrolloverview:${key}`, value.toString())
        // Lua-format the value for persistence: integers/floats/bools verbatim,
        // anything else gets quoted as a Lua string (e.g. layout = "vertical").
        const raw = value.toString();
        const luaVal = (raw === "true" || raw === "false" || /^-?\d+(?:\.\d+)?$/.test(raw))
            ? raw
            : `"${raw.replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;
        // Block-opener pattern requires `^[ \t]*scrolloverview = {` at line
        // start (re.M flag) so a doc comment like
        // `-- scrolloverview = { gesture_distance = ... }` can't shadow the
        // real block. re.S keeps `[\s\S]*?` matching newlines inside the
        // block so the key can be located across multiple lines.
        let py =
            "import re, sys\n" +
            "key, val, conf = sys.argv[1], sys.argv[2], sys.argv[3]\n" +
            "try:\n" +
            "    text = open(conf).read()\n" +
            "except FileNotFoundError:\n" +
            "    sys.exit(0)\n" +
            "pattern = r'(^[ \\t]*scrolloverview[ \\t]*=[ \\t]*\\{[\\s\\S]*?[ \\t]*)' + re.escape(key) + r'([ \\t]*=[ \\t]*)(?:\"[^\"]*\"|-?[\\d.]+|true|false)'\n" +
            "new_text, count = re.subn(pattern, r'\\1' + key + r'\\g<2>' + val, text, count=1, flags=re.M|re.S)\n" +
            "if count == 0:\n" +
            "    new_text = re.sub(r'(?m)^([ \\t]*)scrolloverview([ \\t]*=[ \\t]*\\{)', r'\\1scrolloverview\\2\\n            ' + key + ' = ' + val + ',', text, count=1)\n" +
            "open(conf, 'w').write(new_text)\n";
        runPy(py, [key, luaVal, root.customGeneralConf])
    }

    // Live source of truth for whether scrolloverview is loaded into Hyprland.
    // Plugins persist in custom/general.lua via `hl.plugin.load("...so")`,
    // but Hyprland only re-reads that at startup, so checking the file alone
    // can lie (e.g. directive removed but plugin still loaded from a previous
    // session, or vice versa). hyprctl plugin list is canonical.
    Process {
        id: scrollOverviewStateReader
        command: ["hyprctl", "plugin", "list"]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => scrollOverviewStateReader.buf += data + "\n" }
        onExited: {
            root.scrollOverviewEnabled = /^Plugin\s+scrolloverview\b/m.test(scrollOverviewStateReader.buf);
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

    // ── Left Hot Corner ──────────────────────────────────────────────────────
    ContentSection {
        icon: "ads_click"
        title: Translation.tr("Left Hot Corner")

        // Ripple Animation — top-level toggle for the corner ripple cascade.
        // Applies to both the "Scrolling Overview" and "Default Overview"
        // trigger paths (both fire the ripple before opening). Hidden only
        // when trigger is "Off" since the corner is disabled entirely there.
        // Visible regardless of whether the scroll-overview plugin is loaded
        // so the toggle can be pre-configured.
        ConfigSwitch {
            Layout.fillWidth: true
            visible: Config.options.bar.hotCorners.trigger !== "off"
            buttonIcon: "blur_circular"
            text: Translation.tr("Ripple Animation")
            checked: Config.options.bar.hotCorners.animationEnabled
            onCheckedChanged: {
                if (checked === Config.options.bar.hotCorners.animationEnabled) return;
                Config.options.bar.hotCorners.animationEnabled = checked;
            }
        }

        // Master picker for what the top-left hot corner opens.
        // "Scrolling Overview" runs the ripple-then-dispatch flow for the
        // scroll-overview plugin; "Default Overview" toggles the built-in
        // dots overview directly (no ripple — it has its own animation);
        // "Off" disables the MouseArea so left-clicks fall through to the
        // bar's left-side area like any normal part of the bar.
        ConfigRow {
            // Match the icon left-edge of sibling ConfigSwitch rows in
            // this section. ConfigSwitch wraps its content in a
            // RippleButton (Button), which adds Qt's default left
            // padding (~6px) before the icon. A bare ConfigRow doesn't,
            // so without these margins the trigger row's icon would
            // sit flush against the left edge while the Ripple
            // Animation icon directly above is offset by Button's
            // leftPadding.
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            OptionalMaterialSymbol {
                icon: "drag_click"
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 6   // match ConfigSwitch's contentItem RowLayout spacing (10) minus ConfigRow's default (4)
                text: Translation.tr("Trigger overview")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledComboBox {
                id: hotCornerTriggerCombo
                textRole: "displayName"
                Layout.fillWidth: false
                Layout.preferredWidth: 220
                model: [
                    { displayName: Translation.tr("Off"),                icon: "block",     value: "off" },
                    { displayName: Translation.tr("Default Overview"),   icon: "grid_view", value: "default" },
                    { displayName: Translation.tr("Scrolling Overview"), icon: "view_day",  value: "scrolloverview" },
                ]
                currentIndex: {
                    const idx = model.findIndex(item => item.value === Config.options.bar.hotCorners.trigger);
                    return idx !== -1 ? idx : 0; // default to "off"
                }
                onActivated: index => {
                    Config.options.bar.hotCorners.trigger = model[index].value;
                }
            }
        }

        // Scrolling Overview — workspace gap and scale tuning. The previous
        // master Enable switch here is gone: the hl.plugin.load directive
        // ships active in dots/.config/hypr/custom/general.lua, the post-install
        // builds + installs the .so on every install path, and the corner
        // Trigger overview dropdown above already handles whether the
        // plugin is the active hot-corner action. Whether to *use* the
        // overview is up to the dropdown; once trigger == "scrolloverview"
        // is selected, the plugin's tuning knobs below are exposed.
        ContentSubsection {
            visible: Config.options.bar.hotCorners.trigger === "scrolloverview"
            title: Translation.tr("Scrolling Overview")

        // Layout — vertical (workspaces stacked, scroll up/down) vs horizontal
        // (scroll left/right). Maps to the plugin:scrolloverview:layout string.
        // Only render once the plugin is actually loaded (driven by
        // `hyprctl -i 0 plugin list` via scrollOverviewStateReader); hides
        // during the brief gap on first install before the .so loads.
        RowLayout {
            visible: root.scrollOverviewEnabled
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            // Match ConfigSwitch's vertical padding (implicitHeight: content + 8*2)
            // so the selector has the same top/bottom breathing room as the
            // Per app/Per window selector, which inherits it from its paired switch.
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            OptionalMaterialSymbol {
                icon: "splitscreen"
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 6
                text: Translation.tr("Layout")
                color: Appearance.colors.colOnSecondaryContainer
            }
            ConfigSelectionArray {
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignVCenter
                currentValue: root.scrollOverviewLayout
                onSelected: newValue => {
                    if (newValue === root.scrollOverviewLayout) return;
                    root.scrollOverviewLayout = newValue;
                    root.setScrollOverviewKey("layout", newValue);
                }
                options: [
                    { displayName: Translation.tr("Vertical"),   icon: "view_day",  value: "vertical" },
                    { displayName: Translation.tr("Horizontal"), icon: "view_week", value: "horizontal" },
                ]
            }
        }

        // Workspace gap and scale. topMargin lifts the inter-setting gap to 6
        // (subsection spacing 2 + 4) so it matches the Ripple Animation /
        // Trigger overview spacing in the section above.
        ConfigRow {
            visible: root.scrollOverviewEnabled
            uniform: true
            ConfigSpinBox {
                Layout.fillWidth: true
                icon: "space_bar"
                text: Translation.tr("Workspace gap")
                value: root.scrollOverviewWorkspaceGap
                from: 0
                to: 500
                stepSize: 10
                onValueChanged: {
                    if (value === root.scrollOverviewWorkspaceGap) return;
                    root.scrollOverviewWorkspaceGap = value;
                    root.setScrollOverviewKey("workspace_gap", value);
                }
                MouseArea {
                    id: workspaceGapHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    StyledToolTip {
                        extraVisibleCondition: workspaceGapHover.containsMouse
                        text: Translation.tr("Pixels between workspace previews in the overview. Default 100.")
                    }
                }
            }
            ConfigSpinBox {
                Layout.fillWidth: true
                icon: "aspect_ratio"
                text: Translation.tr("Workspace scale")
                suffix: "%"
                value: Math.round(root.scrollOverviewWorkspaceScale * 100)
                from: 10
                to: 100
                stepSize: 5
                onValueChanged: {
                    const newScale = value / 100;
                    if (Math.abs(newScale - root.scrollOverviewWorkspaceScale) < 0.001) return;
                    root.scrollOverviewWorkspaceScale = newScale;
                    // Pass with 2-decimal precision; toFixed gives "0.50" / "1.00"
                    root.setScrollOverviewKey("scale", newScale.toFixed(2));
                }
                MouseArea {
                    id: workspaceScaleHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    StyledToolTip {
                        extraVisibleCondition: workspaceScaleHover.containsMouse
                        text: Translation.tr("How much each workspace preview shrinks in the overview. Lower = more workspaces fit on screen. Default 50%.")
                    }
                }
            }
        }

        } // end of Scrolling Overview ContentSubsection
    }

    ContentSection {
        icon: "overview_key"
        title: Translation.tr("Launcher Overview")

        ConfigSwitch {
            buttonIcon: "check"
            text: Translation.tr("Enable")
            checked: Config.options.overview.enable
            onCheckedChanged: {
                Config.options.overview.enable = checked;
            }
        }
        /*
        ConfigSwitch {
            buttonIcon: "center_focus_strong"
            text: Translation.tr("Center icons")
            checked: Config.options.overview.centerIcons
            onCheckedChanged: {
                Config.options.overview.centerIcons = checked;
            }
        }
        */
        ConfigSpinBox {
            icon: "loupe"
            text: Translation.tr("Size (%)")
            value: Config.options.overview.size
            from: 25
            to: 100
            stepSize: 5
            onValueChanged: {
                Config.options.overview.size = value;
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
        ContentSubsection {
            title: Translation.tr("Performance")

            ConfigSwitch {
                buttonIcon: "speed"
                text: Translation.tr("Pre-load overview")
                tooltipText: Translation.tr("Disable for competitive gaming")
                checked: Config.options.overview.keepSurfaceAlive
                onCheckedChanged: {
                    Config.options.overview.keepSurfaceAlive = checked;
                }
            }
        }
        /*
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
        */
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

        ConfigSwitch {
            buttonIcon: "monitor"
            text: Translation.tr("Force specific monitor")
            checked: Config.options.notifications.forceMonitor.enable
            onCheckedChanged: {
                Config.options.notifications.forceMonitor.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("If you have multiple monitors and want notifications to only show on one of them, enable this and enter the monitor name below (e.g., eDP-1)")
            }
        }

        ConfigRow {
            enabled: Config.options.notifications.forceMonitor.enable
            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Monitor name to show notifications on (e.g., eDP-1)")
                text: Config.options.notifications.forceMonitor.name
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.notifications.forceMonitor.name = text;
                }
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

}
