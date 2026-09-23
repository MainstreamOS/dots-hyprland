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

    readonly property string customDir: `${CF.FileUtils.trimFileProtocol(Directories.config)}/hypr/custom`
    readonly property string customGeneralConf: `${root.customDir}/general.lua`
    readonly property string customKeybindsConf: `${CF.FileUtils.trimFileProtocol(Directories.config)}/hypr/custom/keybinds.lua`
    // Mirrors whether scrolloverview is currently loaded into Hyprland.
    // Source of truth is `hyprctl plugin list` (read by scrollOverviewStateReader),
    // not the conf file — Hyprland only re-reads `plugin = ...` directives at
    // startup, so the conf and the live state can diverge. The toggle keeps
    // both in sync by calling `hyprctl plugin load/unload` AND editing the conf.
    property bool scrollOverviewEnabled: false
    // Layout values for the scroll-overview, saved one value per file under
    // hypr/custom/ (scrolloverview.layout, .workspace_gap, .scale), which
    // plugins.lua applies on every reload. Defaults match the plugin's
    // compiled-in defaults.
    property int scrollOverviewWorkspaceGap: 100     // pixels between workspace previews
    property real scrollOverviewWorkspaceScale: 0.5  // 0.0–1.0 — overview shrink factor
    property string scrollOverviewLayout: "vertical" // "vertical" | "horizontal" — overview scroll axis

    // Settings one monitor keeps apart from the ones above, saved one line per
    // monitor in hypr/custom/scrolloverview.monitors ("DP-1 layout=vertical
    // scale=0.40"), which plugins.lua hands to the plugin on every reload. A
    // monitor with no line, or a value missing from its line, follows the rest.
    readonly property string scrollOverviewMonitorsFile: `${root.customDir}/scrolloverview.monitors`
    property var scrollOverviewMonitors: ({})
    // The connected monitors, plus any unplugged one that still has settings
    // saved, so those can be seen and cleared.
    readonly property var scrollOverviewMonitorNames: {
        const names = Quickshell.screens.map(s => s.name);
        for (const name in root.scrollOverviewMonitors)
            if (!names.includes(name)) names.push(name);
        return names;
    }

    function parseScrollOverviewMonitors(text) {
        const all = {};
        for (const line of text.split("\n")) {
            const parts = line.trim().split(/\s+/);
            if (parts.length < 2 || !/^[A-Za-z0-9._-]+$/.test(parts[0])) continue;
            const entry = {};
            for (const part of parts.slice(1)) {
                const m = part.match(/^([a-z_]+)=(.+)$/);
                if (!m) continue;
                if (m[1] === "layout" && (m[2] === "vertical" || m[2] === "horizontal")) entry.layout = m[2];
                else if (m[1] === "workspace_gap" && /^\d+$/.test(m[2])) entry.workspace_gap = parseInt(m[2]);
                else if (m[1] === "scale" && /^\d+(?:\.\d+)?$/.test(m[2])) entry.scale = parseFloat(m[2]);
            }
            if (Object.keys(entry).length > 0) all[parts[0]] = entry;
        }
        return all;
    }

    // The plugin forgets its per-monitor settings on every reload and takes them
    // again from plugins.lua, so a reload is what applies the file.
    function writeScrollOverviewMonitors(all) {
        root.scrollOverviewMonitors = all;
        const text = Object.keys(all).sort().map(name => [name].concat(Object.keys(all[name]).sort()
            .map(key => `${key}=${key === "scale" ? Number(all[name][key]).toFixed(2) : all[name][key]}`)).join(" ")).join("\n");
        Quickshell.execDetached(["bash", "-c", 'printf "%s" "$1" > "$0" && hyprctl reload',
            root.scrollOverviewMonitorsFile, text.length > 0 ? text + "\n" : ""]);
    }

    // A null value drops that one setting, so the monitor follows the rest again.
    function setScrollOverviewMonitorKey(output, key, value) {
        if (!/^[A-Za-z0-9._-]+$/.test(output)) return;
        const all = JSON.parse(JSON.stringify(root.scrollOverviewMonitors));
        const entry = all[output] ?? {};
        if (value === null) delete entry[key];
        else entry[key] = value;
        if (Object.keys(entry).length > 0) all[output] = entry;
        else delete all[output];
        root.writeScrollOverviewMonitors(all);
    }

    function clearScrollOverviewMonitor(output) {
        const all = JSON.parse(JSON.stringify(root.scrollOverviewMonitors));
        delete all[output];
        root.writeScrollOverviewMonitors(all);
    }

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
        scrollOverviewMonitorsReader.running = true
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
            scrollOverviewMonitorsReader.running = false
            scrollOverviewMonitorsReader.running = true
        }
    }

    Process {
        id: scrollOverviewMonitorsReader
        command: ["cat", root.scrollOverviewMonitorsFile]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => scrollOverviewMonitorsReader.buf += data + "\n" }
        onExited: root.scrollOverviewMonitors = root.parseScrollOverviewMonitors(scrollOverviewMonitorsReader.buf)
    }

    Process {
        id: scrollOverviewConfReader
        command: ["sh", "-c",
            'for k in layout workspace_gap scale; do printf "%s=" "$k"; cat "$1/scrolloverview.$k" 2>/dev/null; echo; done; echo "--general--"; cat "$2" 2>/dev/null',
            "sh", root.customDir, root.customGeneralConf]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => scrollOverviewConfReader.buf += data + "\n" }
        onExited: {
            // The per-value files are what plugins.lua applies on every
            // reload, so they win. A machine from before the files existed
            // still carries its values in a scrolloverview block in
            // custom/general.lua, which is read only for what no file holds.
            // A value found nowhere leaves the plugin's own default in place.
            const buf = scrollOverviewConfReader.buf;
            const cut = buf.indexOf("--general--\n");
            const files = cut < 0 ? buf : buf.substring(0, cut);
            const general = cut < 0 ? "" : buf.substring(cut + 12);
            const fileValue = key => {
                const m = files.match(new RegExp(`^${key}=(.*)$`, "m"));
                return m && m[1].trim() !== "" ? m[1].trim() : null;
            };
            const blockValue = (key, pattern) => {
                const m = general.match(new RegExp(`scrolloverview\\s*=\\s*\\{[\\s\\S]*?\\b${key}\\s*=\\s*${pattern}`));
                return m ? m[1] : null;
            };
            const gap = fileValue("workspace_gap") ?? blockValue("workspace_gap", "(\\d+)");
            if (gap !== null && /^\d+$/.test(gap)) root.scrollOverviewWorkspaceGap = parseInt(gap);
            const scale = fileValue("scale") ?? blockValue("scale", "(\\d+(?:\\.\\d+)?)");
            if (scale !== null && /^\d+(?:\.\d+)?$/.test(scale)) root.scrollOverviewWorkspaceScale = parseFloat(scale);
            const layout = fileValue("layout") ?? blockValue("layout", '"([a-z]+)"');
            if (layout === "vertical" || layout === "horizontal") root.scrollOverviewLayout = layout;
        }
    }

    // Update one scrolloverview value: live through hl.config, and saved as
    // one file per value under hypr/custom/, which plugins.lua applies on
    // every reload. The plugin reads its config again on every overview
    // open, so the next open shows the new value.
    function setScrollOverviewKey(key, value) {
        setHyprKeyword(`plugin:scrolloverview:${key}`, value.toString())
        runPy("import sys\nopen(sys.argv[2], 'w').write(sys.argv[1] + '\\n')\n",
              [value.toString(), `${root.customDir}/scrolloverview.${key}`])
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

        // A monitor can keep its own layout, gap and scale. Only offered with
        // more than one monitor, or while an unplugged one still has settings.
        ContentSubsection {
            visible: Config.options.bar.hotCorners.trigger === "scrolloverview" && root.scrollOverviewEnabled
                && root.scrollOverviewMonitorNames.length > 1
            title: Translation.tr("Each monitor")

            Repeater {
                model: root.scrollOverviewMonitorNames
                delegate: ColumnLayout {
                    id: monitorBlock
                    required property string modelData
                    readonly property var entry: root.scrollOverviewMonitors[modelData] ?? ({})
                    readonly property var screen: Quickshell.screens.find(s => s.name === modelData) ?? null
                    readonly property int effectiveGap: entry.workspace_gap ?? root.scrollOverviewWorkspaceGap
                    // The plugin keeps a monitor's scale between 10% and 90%, and
                    // turns down a monitor's settings outright past that.
                    readonly property int effectiveScalePercent: Math.max(10, Math.min(90,
                        Math.round((entry.scale ?? root.scrollOverviewWorkspaceScale) * 100)))
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        Layout.topMargin: 6
                        spacing: 8
                        OptionalMaterialSymbol {
                            icon: "monitor"
                            Layout.alignment: Qt.AlignVCenter
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: monitorBlock.modelData
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            elide: Text.ElideRight
                            text: monitorBlock.screen ? (monitorBlock.screen.model ?? "") : Translation.tr("Not connected")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        DialogButton {
                            visible: Object.keys(monitorBlock.entry).length > 0
                            buttonText: Translation.tr("Match the others")
                            onClicked: root.clearScrollOverviewMonitor(monitorBlock.modelData)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
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
                            currentValue: monitorBlock.entry.layout ?? ""
                            onSelected: newValue => root.setScrollOverviewMonitorKey(monitorBlock.modelData, "layout", newValue === "" ? null : newValue)
                            options: [
                                { displayName: Translation.tr("Same as above"), icon: "link",      value: "" },
                                { displayName: Translation.tr("Vertical"),      icon: "view_day",  value: "vertical" },
                                { displayName: Translation.tr("Horizontal"),    icon: "view_week", value: "horizontal" },
                            ]
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigSpinBox {
                            Layout.fillWidth: true
                            icon: "space_bar"
                            text: Translation.tr("Workspace gap")
                            value: monitorBlock.effectiveGap
                            from: 0
                            to: 500
                            stepSize: 10
                            onValueChanged: {
                                if (value === monitorBlock.effectiveGap) return;
                                root.setScrollOverviewMonitorKey(monitorBlock.modelData, "workspace_gap", value);
                            }
                        }
                        ConfigSpinBox {
                            Layout.fillWidth: true
                            icon: "aspect_ratio"
                            text: Translation.tr("Workspace scale")
                            suffix: "%"
                            value: monitorBlock.effectiveScalePercent
                            from: 10
                            to: 90
                            stepSize: 5
                            onValueChanged: {
                                if (value === monitorBlock.effectiveScalePercent) return;
                                root.setScrollOverviewMonitorKey(monitorBlock.modelData, "scale", value / 100);
                            }
                        }
                    }
                }
            }
        }
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
        ConfigSwitch {
            buttonIcon: "apps"
            text: Translation.tr("Open on all apps when off")
            tooltipText: Translation.tr("With the overview switched off there are no workspace previews, so the launcher opens on the full list of apps.\nTurn this off to open on the short list and reach the rest yourself.")
            checked: Config.options.overview.showAllAppsWhenOff
            onCheckedChanged: {
                Config.options.overview.showAllAppsWhenOff = checked;
            }
        }
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
    }

    // ── Left Sidebar ──────────────────────────────────────────────────────────
    ContentSection {
        objectName: "leftSidebarSection"
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
