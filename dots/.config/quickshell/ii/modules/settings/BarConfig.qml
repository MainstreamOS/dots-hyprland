import qs
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.bar
import qs.modules.settings.services

ContentPage {
    id: root
    readonly property bool island: Appearance.sizes.barIsIsland
    readonly property bool phoneConnected: Phone.devices.some(device => device.reachable)
        || Bluetooth.devices.values.some(device => device.connected && device.icon === "phone")

    // Observe KDE Connect while this page is visible. Bluetooth already exposes
    // connected phones, without starting a second copy of the call helper.
    Binding {
        target: Phone
        property: "islandWanted"
        when: root.visible
        value: root.island && Config.options.bar.island.phoneIntegration
    }

    ContentSection {
        icon: "toolbar"
        title: Translation.tr("Desktop bar")
        BarModeChoices {}
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            text: root.island
                ? Translation.tr("Hover over the clock to expand. Use the arrows beside the panel title to change panels; scrolling there switches workspaces.")
                : Translation.tr("Choose a style, arrange your widgets, and access workspaces, media, and system controls from the bar.")
        }
    }
    forceWidth: true
    ContentSection {
        visible: root.island
        icon: "dynamic_feed"
        title: Translation.tr("Dynamic Island")
        ConfigSwitch {
            buttonIcon: "apps"
            text: Translation.tr("Use Dynamic Island as your App Drawer")
            tooltipText: Translation.tr("Press Super to search apps in the island.")
            checked: Config.options.bar.island.appDrawer
            onCheckedChanged: Config.options.bar.island.appDrawer = checked
        }
        ConfigSwitch {
            buttonIcon: "phonelink"
            text: Translation.tr("Connect phone services")
            checked: Config.options.bar.island.phoneIntegration
            onCheckedChanged: Config.options.bar.island.phoneIntegration = checked
        }

        ConfigSwitch {
            visible: Config.options.bar.island.phoneIntegration
            buttonIcon: "notifications_active"
            text: Translation.tr("Show calls, messages, and phone notifications automatically")
            checked: Config.options.bar.island.automaticAlerts
            onCheckedChanged: Config.options.bar.island.automaticAlerts = checked
        }
        ConfigSwitch {
            visible: Config.options.bar.island.phoneIntegration
            buttonIcon: "screen_share"
            text: Translation.tr("Disable calls, messages, and phone notifications while streaming")
            checked: Config.options.bar.island.suppressWhileStreaming
            onCheckedChanged: Config.options.bar.island.suppressWhileStreaming = checked
        }
        Repeater {
            model: [
                {key: "suppressForDiscord", label: Translation.tr("Discord"), icon: "forum"},
                {key: "suppressForObs", label: Translation.tr("OBS Studio"), icon: "videocam"}
            ]
            ConfigSwitch {
                required property var modelData
                visible: Config.options.bar.island.phoneIntegration && Config.options.bar.island.suppressWhileStreaming
                Layout.leftMargin: 24
                buttonIcon: modelData.icon
                text: modelData.label
                checked: Config.options.bar.island[modelData.key]
                onCheckedChanged: Config.options.bar.island[modelData.key] = checked
            }
        }


    }

    ContentSection {
        visible: root.island
        icon: "dashboard_customize"
        title: Translation.tr("Island panels")
        IslandPanelEditor {}
    }

    ContentSection {
        visible: root.island && root.phoneConnected
        icon: "shield_person"
        title: Translation.tr("Contact privacy")
        Repeater {
            model: [
                {key: "showContactName", label: Translation.tr("Show contact name"), icon: "person"},
                {key: "showPhoneNumber", label: Translation.tr("Show phone number"), icon: "call"},
                {key: "showMessage", label: Translation.tr("Show message contents"), icon: "chat"},
                {key: "showContactPicture", label: Translation.tr("Show contact picture"), icon: "account_circle"}
            ]
            ConfigSwitch {
                required property var modelData
                buttonIcon: modelData.icon
                text: modelData.label
                checked: Config.options.bar.island[modelData.key]
                onCheckedChanged: Config.options.bar.island[modelData.key] = checked
            }
        }
    }

    // ── Widget layout ─────────────────────────────────────────────────────────
    ContentSection {
        icon: "reorder"
        visible: !root.island
        title: Translation.tr("Widget layout")

        BarLayoutEditor {}
    }

    // ── Time & Date ───────────────────────────────────────────────────────────
    ContentSection {
        icon: "nest_clock_farsight_analog"
        title: Translation.tr("Time & Date")

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Time Format")

                ConfigSelectionArray {
                    currentValue: Config.options.time.format
                    onSelected: newValue => {
                        if (newValue === "hh:mm") {
                            Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME12\\b/TIME/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);
                        } else {
                            Quickshell.execDetached(["bash", "-c", `sed -i 's/\\TIME\\b/TIME12/' '${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprlock.conf'`]);
                        }
                        // Sync to pixie-sddm if installed (helper upserts a single
                        // key without clobbering other state). Silently no-ops on
                        // boxes that don't have the helper on $PATH.
                        Quickshell.execDetached(["bash", "-c", `command -v pixie-sddm-set-state >/dev/null 2>&1 && pixie-sddm-set-state clockFormat ${JSON.stringify(newValue)} || true`]);
                        Config.options.time.format = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("24h"),       value: "hh:mm"   },
                        { displayName: Translation.tr("12h am/pm"), value: "h:mm ap" },
                        { displayName: Translation.tr("12h AM/PM"), value: "h:mm AP" },
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Date Format")
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: Config.options.time.dateFormat
                    onSelected: newValue => {
                        Config.options.time.dateFormat = newValue;
                        // Sync related date formats to match the selected order
                        if (newValue === "ddd, dd/MM") {
                            Config.options.time.shortDateFormat = "dd/MM";
                            Config.options.time.dateWithYearFormat = "dd/MM/yyyy";
                        } else if (newValue === "ddd, dd.MM") {
                            Config.options.time.shortDateFormat = "dd.MM";
                            Config.options.time.dateWithYearFormat = "dd.MM.yyyy";
                        } else {
                            Config.options.time.shortDateFormat = "MM/dd";
                            Config.options.time.dateWithYearFormat = "MM/dd/yyyy";
                        }
                        // Sync to pixie-sddm if installed.
                        Quickshell.execDetached(["bash", "-c", `command -v pixie-sddm-set-state >/dev/null 2>&1 && pixie-sddm-set-state dateFormat ${JSON.stringify(newValue)} || true`]);
                    }
                    options: [
                        { displayName: Translation.tr("dd/MM"), value: "ddd, dd/MM" },
                        { displayName: Translation.tr("dd.MM"), value: "ddd, dd.MM" },
                        { displayName: Translation.tr("MM/dd"), value: "ddd, MM/dd" },
                    ]
                }
            }
        }
    }

    ContentSection {
        icon: "spoke"
        title: Translation.tr("Positioning")

        ConfigRow {
            ContentSubsection {
                title: root.island ? Translation.tr("Island position") : Translation.tr("Bar position")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    // Through the shared rule, which carries a Hug dock across
                    // to face the bar wherever it goes.
                    onSelected: newValue => Appearance.sizes.placeBar((newValue & 1) !== 0, (newValue & 2) !== 0)
                    options: [
                        {
                            displayName: Translation.tr("Top"),
                            icon: "arrow_upward",
                            value: 0 // bottom: false, vertical: false
                        },
                        {
                            displayName: Translation.tr("Left"),
                            icon: "arrow_back",
                            value: 2 // bottom: false, vertical: true
                        },
                        {
                            displayName: Translation.tr("Bottom"),
                            icon: "arrow_downward",
                            value: 1 // bottom: true, vertical: false
                        },
                        {
                            displayName: Translation.tr("Right"),
                            icon: "arrow_forward",
                            value: 3 // bottom: true, vertical: true
                        }
                    ].filter(option => !root.island || (option.value & 2) === 0)
                }
            }
            ContentSubsection {
                title: Translation.tr("Automatically hide")
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: Config.options.bar.autoHide.enable
                    onSelected: newValue => {
                        Config.options.bar.autoHide.enable = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: false
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: true
                        }
                    ]
                }
            }
        }

        ContentSubsection {
            visible: root.island
            title: Translation.tr("Island style")
            IslandStyleChoices {}
        }

        ConfigSwitch {
            visible: Config.options.bar.autoHide.enable
            buttonIcon: "open_in_full"
            text: Translation.tr("Move windows aside while the hidden bar shows")
            checked: Config.options.bar.autoHide.pushWindows
            onCheckedChanged: Config.options.bar.autoHide.pushWindows = checked
        }

        ConfigRow {
            
            ContentSubsection {
                title: Translation.tr("Corner style")
                visible: !root.island
                Layout.fillWidth: true

                BarStyleChoices {}
            }

            ContentSubsection {
                title: Translation.tr("Group style")
                visible: !root.island
                Layout.fillWidth: false

                ConfigSelectionArray {
                    currentValue: Config.options.bar.borderless
                    onSelected: newValue => {
                        Config.options.bar.borderless = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("Pills"),
                            icon: "location_chip",
                            value: false
                        },
                        {
                            displayName: Translation.tr("Line-separated"),
                            icon: "split_scene",
                            value: true
                        }
                    ]
                }
            }
        }

    }

    // Each radius appears only while the style that gives it a corner to
    // round is the one on screen — a slider for an edge the bar isn't drawing
    // would move nothing.
    ContentSection {
        icon: "rounded_corner"
        title: Translation.tr("Shape")
        // A header over an empty room: with no style that shapes a surface
        // active and Pills off, every control here is put away, so the section
        // goes with them. Unless a radius still holds a non-stock value, which
        // keeps the reset within reach of the state it exists to clear.
        visible: (root.island ? Appearance.sizes.islandShape !== "rect" : Appearance.sizes.barFloats)
            || (!root.island && !Config.options.bar.borderless)
            || (!root.island && Config.options.bar.widgetRadius >= 0)
            || Config.options.bar.floatRadius >= 0
            || (!root.island && (Config.options.bar.floatWidth >= 0 || Config.options.bar.notchWidth >= 0))

        ConfigSwitch {
            visible: Appearance.sizes.barFloats && !root.island
            buttonIcon: "view_column_2"
            text: Translation.tr("Split into three")
            checked: Config.options.bar.floatSplit
            onCheckedChanged: Config.options.bar.floatSplit = checked
        }


        // How much of the screen the strip reaches across. The track stops well
        // short of nothing: past a point the end clusters meet the middle one
        // and the strip has nowhere left to put them.
        ConfigSlider {
            text: Config.options.bar.floatSplit ? Translation.tr("Spread") : Translation.tr("Width")
            visible: Appearance.sizes.barFloats && !root.island
            stopIndicatorValues: [Appearance.sizes.barFloatWidthMax]
            buttonIcon: "width"
            // The floor chases the widgets, so a crowded strip can push it to
            // the ceiling; the track keeps a step of room so it cannot invert.
            from: Math.min(GlobalStates.barFloatMinPercent, Appearance.sizes.barFloatWidthMax - 5)
            to: Appearance.sizes.barFloatWidthMax
            value: Appearance.sizes.barFloatWidth
            onMoved: {
                const stepped = Math.round(value);
                const key = Appearance.sizes.barIsNotch ? "notchWidth" : "floatWidth";
                if (stepped === Config.options.bar[key])
                    return;
                Config.options.bar[key] = stepped;
            }
        }

        ConfigSlider {
            text: Translation.tr("Corner roundness")
            visible: Appearance.sizes.barFloats
            stopIndicatorValues: [Appearance.rounding.barFloatStock]
            buttonIcon: "rounded_corner"
            from: 0
            to: Appearance.rounding.barFloatMax
            value: Appearance.rounding.barFloat
            onMoved: {
                if (value === Config.options.bar.floatRadius)
                    return;
                Config.options.bar.floatRadius = value;
            }
        }

        ConfigSlider {
            text: Translation.tr("Widget pills")
            visible: !root.island && !Config.options.bar.borderless
            stopIndicatorValues: [Appearance.rounding.barWidgetStock]
            buttonIcon: "rounded_corner"
            from: 0
            to: 20
            value: Appearance.rounding.barWidget
            onMoved: {
                if (value === Config.options.bar.widgetRadius)
                    return;
                Config.options.bar.widgetRadius = value;
            }
        }

        // Landing a slider on its mark freezes today's stock number; this
        // hands the radius back to the interface outright, so if what it
        // decides ever moves, a reset bar moves with it. Checked flat rather
        // than by the active style, because a radius set under one style
        // waits out the others.
        ConfigResetButton {
            visible: (!root.island && Config.options.bar.widgetRadius >= 0)
                || Config.options.bar.floatRadius >= 0
                || (!root.island && (Config.options.bar.floatWidth >= 0 || Config.options.bar.notchWidth >= 0))
            Layout.leftMargin: 8
            Layout.topMargin: 2
            buttonText: Translation.tr("Reset to default shape")
            onClicked: {
                if (!root.island) Config.options.bar.widgetRadius = -1
                Config.options.bar.floatRadius = -1
                if (!root.island) {
                    Config.options.bar.floatWidth = -1
                    Config.options.bar.notchWidth = -1
                }
            }
        }
    }

    ContentSection {
        icon: "opacity"
        title: Translation.tr("Transparency")

        // The strip has always been able to go without a background, and the
        // bar reads the setting, but nothing ever offered it. It belongs here
        // beside the slider for the same reason it does on the dock page:
        // wanting no strip at all is a different question from wanting a faint
        // one, and the track below cannot answer it.
        ConfigSwitch {
            buttonIcon: "background_replace"
            text: Translation.tr("Show background")
            visible: !root.island
            checked: Config.options.bar.showBackground
            onCheckedChanged: Config.options.bar.showBackground = checked
        }

        ConfigSlider {
            text: Translation.tr("Background")
            visible: root.island || Config.options.bar.showBackground
            stopIndicatorValues: [Appearance.colors.barStockAlpha]
            buttonIcon: "wallpaper"
            // The strip is given the same blur cutoff as the dock in
            // hypr/hyprland/rules.lua, so its track stops in the same place.
            // Running it to zero put a step partway down that no setting
            // explains: past the cutoff the compositor drops the frosting
            // outright rather than by degrees.
            from: Appearance.colors.surfaceOpacityFloor
            to: 1
            value: Math.max(Appearance.colors.surfaceOpacityFloor,
                Config.options.bar.backgroundOpacity < 0
                    ? Appearance.colors.barStockAlpha : Config.options.bar.backgroundOpacity)
            onMoved: {
                if (Math.abs(value - Config.options.bar.backgroundOpacity) < 0.005)
                    return;
                Config.options.bar.backgroundOpacity = value;
            }
        }

        // Line-separated groups draw nothing behind their widgets, so the pill
        // controls have no surface to act on there and are put away entirely
        // rather than offered in a state that could do nothing.
        ConfigSlider {
            text: Translation.tr("Widget pills")
            visible: !root.island && !Config.options.bar.borderless
            // Where the pills sit before anyone touches this, read from the
            // same value the slider falls back to, so the mark cannot promise
            // a default the track would not actually return to.
            stopIndicatorValues: [Appearance.colors.barWidgetStockAlpha]
            buttonIcon: "location_chip"
            from: 0
            to: 1
            value: Config.options.bar.widgetOpacity < 0
                ? Appearance.colors.barWidgetStockAlpha : Config.options.bar.widgetOpacity
            onMoved: {
                if (Math.abs(value - Config.options.bar.widgetOpacity) < 0.005)
                    return;
                Config.options.bar.widgetOpacity = value;
            }
        }

        // The tracks run zero to one while stock sits below zero, so this is
        // the only road back to "the interface decides" — including for pill
        // state a borderless bar keeps but does not show.
        ConfigResetButton {
            visible: Config.options.bar.backgroundOpacity >= 0
                || Config.options.bar.widgetOpacity >= 0
            Layout.leftMargin: 8
            Layout.topMargin: 2
            buttonText: Translation.tr("Reset to default transparency")
            onClicked: {
                Config.options.bar.backgroundOpacity = -1
                Config.options.bar.widgetOpacity = -1
            }
        }
    }

    ContentSection {
        icon: "palette"
        title: Translation.tr("Colors")

        ColorField {
            text: Translation.tr("Background")
            allowEmpty: true
            buttonIcon: "wallpaper"
            // Edits the slot for the mode on screen; the other mode keeps its
            // own pick, or the palette where none was made.
            value: Appearance.colors.barBackgroundPick
            fallback: String(Appearance.colors.colLayer0)
            onEdited: newValue => {
                if (Appearance.m3colors.darkmode) Config.options.bar.backgroundColorDark = newValue
                else Config.options.bar.backgroundColorLight = newValue
            }
        }

        ColorField {
            text: Translation.tr("Widget pills")
            visible: !root.island && !Config.options.bar.borderless
            allowEmpty: true
            buttonIcon: "location_chip"
            value: Appearance.colors.barWidgetPick
            fallback: String(Appearance.colBarPill)
            onEdited: newValue => {
                if (Appearance.m3colors.darkmode) Config.options.bar.widgetColorDark = newValue
                else Config.options.bar.widgetColorLight = newValue
            }
        }

        // Hands every slot back to the palette in one press, without making
        // someone guess that an emptied box is how you say "no color of my
        // own". Shown whenever any slot is filled — either mode's, either
        // surface's, borderless or not.
        ConfigResetButton {
            visible: Config.options.bar.backgroundColorDark !== ""
                || Config.options.bar.backgroundColorLight !== ""
                || Config.options.bar.widgetColorDark !== ""
                || Config.options.bar.widgetColorLight !== ""
            Layout.leftMargin: 8
            Layout.topMargin: 2
            buttonText: Translation.tr("Reset to default colors")
            onClicked: {
                Config.options.bar.widgetColorDark = ""
                Config.options.bar.widgetColorLight = ""
                Config.options.bar.backgroundColorDark = ""
                Config.options.bar.backgroundColorLight = ""
            }
        }

        SubtleNoticeBox {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            text: Translation.tr("Dark mode and light mode each keep their own colors.")
        }
    }

    ContentSection {
        icon: "workspaces"
        title: Translation.tr("Workspaces")

        ConfigSwitch {
            buttonIcon: "counter_1"
            text: Translation.tr('Always show numbers')
            visible: !root.island
            checked: Config.options.bar.workspaces.alwaysShowNumbers
            onCheckedChanged: {
                Config.options.bar.workspaces.alwaysShowNumbers = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "award_star"
            text: Translation.tr('Show app icons')
            checked: Config.options.bar.workspaces.showAppIcons
            onCheckedChanged: {
                Config.options.bar.workspaces.showAppIcons = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "colors"
            text: Translation.tr('Tint app icons')
            checked: Config.options.bar.workspaces.monochromeIcons
            onCheckedChanged: {
                Config.options.bar.workspaces.monochromeIcons = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "panorama_fish_eye"
            text: Translation.tr('Large circular app icons')
            checked: Config.options.bar.workspaces.circleAppIcons
            onCheckedChanged: {
                Config.options.bar.workspaces.circleAppIcons = checked;
            }
        }

        ConfigSpinBox {
            icon: "view_column"
            text: Translation.tr("Workspaces shown")
            value: root.island ? Math.min(Config.options.bar.workspaces.shown, 10) : Config.options.bar.workspaces.shown
            from: 1
            to: root.island ? 10 : 30
            stepSize: 1
            // The island shows at most 10; showing that cap must not overwrite a larger stored count.
            onValueChanged: {
                if (value !== Math.min(Config.options.bar.workspaces.shown, to)) Config.options.bar.workspaces.shown = value;
            }
        }

        ConfigSpinBox {
            icon: "touch_long"
            text: Translation.tr("Number show delay when pressing Super (ms)")
            value: Config.options.bar.workspaces.showNumberDelay
            from: 0
            to: 1000
            stepSize: 50
            onValueChanged: {
                Config.options.bar.workspaces.showNumberDelay = value;
            }
        }
        ContentSubsection {
            title: Translation.tr("Number style")

            ConfigSelectionArray {
                // A map of plain numbers, the default ["1","2"] among them, shows as Normal.
                currentValue: {
                    const map = Array.from(Config.options.bar.workspaces.numberMap);
                    return map.every((c, i) => c === String(i + 1)) ? '[]' : JSON.stringify(map);
                }
                onSelected: newValue => {
                    Config.options.bar.workspaces.numberMap = JSON.parse(newValue)
                }
                options: [
                    {
                        displayName: Translation.tr("Normal"),
                        icon: "timer_10",
                        value: '[]'
                    },
                    {
                        displayName: Translation.tr("Han chars"),
                        icon: "square_dot",
                        value: '["一","二","三","四","五","六","七","八","九","十","十一","十二","十三","十四","十五","十六","十七","十八","十九","二十"]'
                    },
                    {
                        displayName: Translation.tr("Roman"),
                        icon: "account_balance",
                        value: '["I","II","III","IV","V","VI","VII","VIII","IX","X","XI","XII","XIII","XIV","XV","XVI","XVII","XVIII","XIX","XX"]'
                    }
                ]
            }
        }
    }

    ContentSection {
        icon: "widgets"
        title: Translation.tr("Utility buttons")
        visible: !root.island || IslandPanels.enabled("resources")

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "content_cut"
                text: Translation.tr("Screen snip")
                checked: Config.options.bar.utilButtons.showScreenSnip
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showScreenSnip = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "colorize"
                text: Translation.tr("Color picker")
                checked: Config.options.bar.utilButtons.showColorPicker
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showColorPicker = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "keyboard"
                text: Translation.tr("Keyboard toggle")
                checked: Config.options.bar.utilButtons.showKeyboardToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showKeyboardToggle = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "mic"
                text: Translation.tr("Mic toggle")
                checked: Config.options.bar.utilButtons.showMicToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showMicToggle = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "dark_mode"
                text: Translation.tr("Dark/Light toggle")
                checked: Config.options.bar.utilButtons.showDarkModeToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showDarkModeToggle = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "speed"
                text: Translation.tr("Performance Profile toggle")
                checked: Config.options.bar.utilButtons.showPerformanceProfileToggle
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showPerformanceProfileToggle = checked;
                }
            }
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "videocam"
                text: Translation.tr("Record")
                checked: Config.options.bar.utilButtons.showScreenRecord
                onCheckedChanged: {
                    Config.options.bar.utilButtons.showScreenRecord = checked;
                }
            }
        }
    }

    WeatherSection {}

    ContentSection {
        icon: "shelf_auto_hide"
        title: Translation.tr("Tray")
        visible: !root.island || IslandPanels.enabled("system")

        ConfigSwitch {
            buttonIcon: "keep"
            text: Translation.tr('Make icons pinned by default')
            checked: Config.options.tray.invertPinnedItems
            onCheckedChanged: {
                Config.options.tray.invertPinnedItems = checked;
            }
        }
        
        ConfigSwitch {
            buttonIcon: "colors"
            text: Translation.tr('Tint icons')
            checked: Config.options.tray.monochromeIcons
            onCheckedChanged: {
                Config.options.tray.monochromeIcons = checked;
            }
        }
    }

    ContentSection {
        icon: "notifications"
        title: Translation.tr("Notifications")
        visible: !root.island

        ConfigSwitch {
            buttonIcon: "counter_2"
            text: Translation.tr("Unread indicator: show count")
            checked: Config.options.bar.indicators.notifications.showUnreadCount
            onCheckedChanged: {
                Config.options.bar.indicators.notifications.showUnreadCount = checked;
            }
        }
    }

    ContentSection {
        icon: "tooltip"
        title: Translation.tr("Tooltips")
        visible: !root.island
        ConfigSwitch {
            buttonIcon: "ads_click"
            text: Translation.tr("Click to show")
            checked: Config.options.bar.tooltips.clickToShow
            onCheckedChanged: {
                Config.options.bar.tooltips.clickToShow = checked;
            }
        }
    }
}
