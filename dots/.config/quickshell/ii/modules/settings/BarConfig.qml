import qs
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.bar

ContentPage {
    forceWidth: true
    /*
    ContentSection {
        icon: "notifications"
        title: Translation.tr("Notifications")
        ConfigSwitch {
            buttonIcon: "counter_2"
            text: Translation.tr("Unread indicator: show count")
            checked: Config.options.bar.indicators.notifications.showUnreadCount
            onCheckedChanged: {
                Config.options.bar.indicators.notifications.showUnreadCount = checked;
            }
        }
    }
    */

    // ── Widget layout ─────────────────────────────────────────────────────────
    ContentSection {
        icon: "reorder"
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

                ConfigSelectionArray {
                    currentValue: Config.options.time.dateFormat
                    onSelected: newValue => {
                        Config.options.time.dateFormat = newValue;
                        // Sync related date formats to match the selected order
                        if (newValue === "ddd, dd/MM") {
                            Config.options.time.shortDateFormat = "dd/MM";
                            Config.options.time.dateWithYearFormat = "dd/MM/yyyy";
                        } else {
                            Config.options.time.shortDateFormat = "MM/dd";
                            Config.options.time.dateWithYearFormat = "MM/dd/yyyy";
                        }
                        // Sync to pixie-sddm if installed.
                        Quickshell.execDetached(["bash", "-c", `command -v pixie-sddm-set-state >/dev/null 2>&1 && pixie-sddm-set-state dateFormat ${JSON.stringify(newValue)} || true`]);
                    }
                    options: [
                        { displayName: Translation.tr("Date First dd/MM"),  value: "ddd, dd/MM" },
                        { displayName: Translation.tr("Month First MM/dd"), value: "ddd, MM/dd" },
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
                title: Translation.tr("Bar position")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    onSelected: newValue => {
                        Config.options.bar.bottom = (newValue & 1) !== 0;
                        Config.options.bar.vertical = (newValue & 2) !== 0;
                    }
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
                    ]
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

        ConfigRow {
            
            ContentSubsection {
                title: Translation.tr("Corner style")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.bar.cornerStyle
                    onSelected: newValue => {
                        Config.options.bar.cornerStyle = newValue; // Update local copy
                    }
                    options: [
                        {
                            displayName: Translation.tr("Hug"),
                            icon: "line_curve",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Float"),
                            icon: "page_header",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Rect"),
                            icon: "toolbar",
                            value: 2
                        },
                        {
                            displayName: Translation.tr("Notch"),
                            icon: "call_to_action",
                            value: 3
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Group style")
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
        visible: Appearance.sizes.barFloats
            || !Config.options.bar.borderless
            || Config.options.bar.widgetRadius >= 0
            || Config.options.bar.floatRadius >= 0
            || Config.options.bar.floatWidth >= 0
            || Config.options.bar.notchWidth >= 0


        ConfigSwitch {
            visible: Appearance.sizes.barFloats
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
            visible: Appearance.sizes.barFloats
            stopIndicatorValues: [Appearance.sizes.barFloatWidthMax]
            buttonIcon: "width"
            from: GlobalStates.barFloatMinPercent
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
            visible: !Config.options.bar.borderless
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
            visible: Config.options.bar.widgetRadius >= 0
                || Config.options.bar.floatRadius >= 0
                || Config.options.bar.floatWidth >= 0
                || Config.options.bar.notchWidth >= 0
            Layout.leftMargin: 8
            Layout.topMargin: 2
            buttonText: Translation.tr("Reset to default shape")
            onClicked: {
                Config.options.bar.widgetRadius = -1
                Config.options.bar.floatRadius = -1
                Config.options.bar.floatWidth = -1
                Config.options.bar.notchWidth = -1
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
            checked: Config.options.bar.showBackground
            onCheckedChanged: Config.options.bar.showBackground = checked
        }

        ConfigSlider {
            text: Translation.tr("Background")
            visible: Config.options.bar.showBackground
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
            visible: !Config.options.bar.borderless
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
            visible: !Config.options.bar.borderless
            allowEmpty: true
            buttonIcon: "location_chip"
            value: Appearance.colors.barWidgetPick
            fallback: String(Appearance.colors.colLayer1)
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
            value: Config.options.bar.workspaces.shown
            from: 1
            to: 30
            stepSize: 1
            onValueChanged: {
                Config.options.bar.workspaces.shown = value;
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
        /*
        ContentSubsection {
            title: Translation.tr("Number style")

            ConfigSelectionArray {
                currentValue: JSON.stringify(Config.options.bar.workspaces.numberMap)
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
        */
    }

    ContentSection {
        icon: "widgets"
        title: Translation.tr("Utility buttons")

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

    ContentSection {
        icon: "cloud"
        title: Translation.tr("Weather")
        ConfigRow {
            ConfigSwitch {
                buttonIcon: "assistant_navigation"
                text: Translation.tr("Enable GPS based location")
                checked: Config.options.bar.weather.enableGPS
                onCheckedChanged: {
                    Config.options.bar.weather.enableGPS = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "thermometer"
                text: Translation.tr("Fahrenheit unit")
                checked: Config.options.bar.weather.useUSCS
                onCheckedChanged: {
                    Config.options.bar.weather.useUSCS = checked;
                }
                StyledToolTip {
                    text: Translation.tr("It may take a few seconds to update")
                }
            }
        }
        
        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("City name")
            text: Config.options.bar.weather.city
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.bar.weather.city = text;
            }
        }
        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (m)")
            value: Config.options.bar.weather.fetchInterval
            from: 5
            to: 50
            stepSize: 5
            onValueChanged: {
                Config.options.bar.weather.fetchInterval = value;
            }
        }
    }

    ContentSection {
        icon: "shelf_auto_hide"
        title: Translation.tr("Tray")

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

    /*
    ContentSection {
        icon: "tooltip"
        title: Translation.tr("Tooltips")
        ConfigSwitch {
            buttonIcon: "ads_click"
            text: Translation.tr("Click to show")
            checked: Config.options.bar.tooltips.clickToShow
            onCheckedChanged: {
                Config.options.bar.tooltips.clickToShow = checked;
            }
        }
    }
    */
}
