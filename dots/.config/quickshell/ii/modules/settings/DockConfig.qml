import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    forceWidth: true

    ContentSection {
        icon: "call_to_action"
        title: Translation.tr("Behavior")

        // Same row form as the hot corner's Trigger overview: icon, label,
        // dropdown on the right. The bar's own edge is not offered; a saved
        // edge the bar later takes renders flipped to the opposite side.
        ConfigRow {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            OptionalMaterialSymbol {
                icon: "dock_to_bottom"
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 6
                text: Translation.tr("Position")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledComboBox {
                textRole: "displayName"
                Layout.fillWidth: false
                Layout.preferredWidth: 220
                model: [
                    { displayName: Translation.tr("Disabled"), icon: "close", value: "disabled" },
                    { displayName: Translation.tr("Top"), icon: "keyboard_arrow_up", value: "top" },
                    { displayName: Translation.tr("Bottom"), icon: "keyboard_arrow_down", value: "bottom" },
                    { displayName: Translation.tr("Left"), icon: "keyboard_arrow_left", value: "left" },
                    { displayName: Translation.tr("Right"), icon: "keyboard_arrow_right", value: "right" }
                ]
                currentIndex: {
                    // Name the edge the dock actually occupies, not the saved
                    // one: the resolver already flips an edge the bar holds and
                    // already falls back for an unrecognised value.
                    const current = Config.options.dock.enable ? Appearance.sizes.dockEdge : "disabled";
                    const idx = model.findIndex(item => item.value === current);
                    return idx !== -1 ? idx : 0;
                }
                onActivated: index => {
                    const value = model[index].value;
                    if (value === "disabled") {
                        Config.options.dock.enable = false;
                        return;
                    }
                    if (value === Appearance.sizes.barEdge) {
                        // The bar's own edge is on offer like any other, and
                        // asking for it sends the bar across to the far side of
                        // its axis rather than refusing. The bar moves first, so
                        // the two are never both claiming this edge and the dock
                        // is not briefly flipped away from what was just asked.
                        Config.options.bar.bottom = !Config.options.bar.bottom;
                        Config.options.dock.position = value;
                    } else if (!Config.options.dock.enable || value !== Appearance.sizes.dockEdge) {
                        // Re-picking the edge already shown is a no-op, and
                        // writing it would overwrite a saved edge the bar is
                        // only borrowing — the dock would stay put once the bar
                        // moved away.
                        Config.options.dock.position = value;
                    }
                    Config.options.dock.enable = true;
                }
            }
        }

        ConfigRow {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            OptionalMaterialSymbol {
                icon: "counter_1"
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 6
                text: Translation.tr("Window indicators")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledComboBox {
                textRole: "displayName"
                Layout.fillWidth: false
                Layout.preferredWidth: 220
                model: [
                    { displayName: Translation.tr("None"), icon: "block", value: "none" },
                    { displayName: Translation.tr("Dashes"), icon: "remove", value: "dashes" },
                    { displayName: Translation.tr("Dots"), icon: "more_horiz", value: "dots" },
                    { displayName: Translation.tr("Count badge"), icon: "counter_2", value: "badge" }
                ]
                currentIndex: {
                    const idx = model.findIndex(item => item.value === Config.options.dock.indicatorStyle);
                    return idx !== -1 ? idx : 1;
                }
                onActivated: index => { Config.options.dock.indicatorStyle = model[index].value; }
            }
        }

        ConfigRow {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            OptionalMaterialSymbol {
                icon: "animation"
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 6
                text: Translation.tr("Launch animation")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledComboBox {
                textRole: "displayName"
                Layout.fillWidth: false
                Layout.preferredWidth: 220
                model: [
                    { displayName: Translation.tr("None"), icon: "block", value: DockLaunchAnims.AnimType.None },
                    { displayName: Translation.tr("Bounce"), icon: "swap_vert", value: DockLaunchAnims.AnimType.Bounce },
                    { displayName: Translation.tr("Pulse"), icon: "open_in_new", value: DockLaunchAnims.AnimType.Pulse },
                    { displayName: Translation.tr("Pop"), icon: "adjust", value: DockLaunchAnims.AnimType.Pop },
                    { displayName: Translation.tr("Wobble"), icon: "360", value: DockLaunchAnims.AnimType.Wobble }
                ]
                currentIndex: {
                    const idx = model.findIndex(item => item.value === Config.options.dock.launchAnimation);
                    return idx !== -1 ? idx : 1;
                }
                onActivated: index => { Config.options.dock.launchAnimation = model[index].value; }
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
                text: Translation.tr("Hover animation")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledComboBox {
                textRole: "displayName"
                Layout.fillWidth: false
                Layout.preferredWidth: 220
                model: [
                    { displayName: Translation.tr("None"), icon: "block", value: "off" },
                    { displayName: Translation.tr("Magnify"), icon: "zoom_in", value: "magnify" },
                    { displayName: Translation.tr("Glow"), icon: "blur_on", value: "glow" },
                ]
                currentIndex: {
                    const idx = model.findIndex(item => item.value === Config.options.dock.hoverEffect);
                    return idx !== -1 ? idx : 1; // fall back to magnify
                }
                onActivated: index => { Config.options.dock.hoverEffect = model[index].value; }
            }
        }

        // The glow's strength is what that effect is chosen for, so it leads.
        ConfigSlider {
            visible: Config.options.dock.hoverEffect === "glow"
            text: Translation.tr("Glow intensity")
            buttonIcon: "flare"
            stopIndicatorValues: [Appearance.sizes.dockGlowIntensityStock]
            from: 0
            to: 100
            value: Appearance.sizes.dockGlowIntensity
            onMoved: {
                const stepped = Math.round(value);
                if (stepped === Config.options.dock.glowIntensity)
                    return;
                Config.options.dock.glowIntensity = stepped;
            }
        }

        // How far the hovered icon grows. Each effect carries its own stock
        // and range: the wave has room to be dramatic, the glow's lift is an
        // accent and the track keeps it one.
        ConfigSlider {
            visible: Config.options.dock.hoverEffect !== "off"
            text: Translation.tr("Magnify amount")
            buttonIcon: "zoom_in"
            stopIndicatorValues: [Appearance.sizes.dockHoverMagnifyStock]
            from: 0
            to: Appearance.sizes.dockHoverMagnifyMax
            value: Appearance.sizes.dockHoverMagnify
            onMoved: {
                const stepped = Math.round(value);
                const key = Config.options.dock.hoverEffect === "glow" ? "glowMagnify" : "hoverMagnify";
                if (stepped === Config.options.dock[key])
                    return;
                Config.options.dock[key] = stepped;
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
                buttonIcon: "apps"
                text: Translation.tr("Show overview button")
                checked: Config.options.dock.showOverviewButton
                onCheckedChanged: {
                    Config.options.dock.showOverviewButton = checked;
                }
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "keep"
                text: Translation.tr("Pinned on startup")
                checked: Config.options.dock.pinnedOnStartup
                onCheckedChanged: {
                    Config.options.dock.pinnedOnStartup = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "keep"
                text: Translation.tr("Show pin button")
                checked: Config.options.dock.showPinButton
                onCheckedChanged: {
                    Config.options.dock.showPinButton = checked;
                }
            }
        }

        ConfigRow {
            uniform: true
            Layout.fillWidth: true
            ConfigSwitch {
                buttonIcon: "volume_up"
                text: Translation.tr("Right-click volume control")
                checked: Config.options.dock.contextMenuVolume.enable
                onCheckedChanged: {
                    Config.options.dock.contextMenuVolume.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Shows a volume slider and mute toggle in the dock context menu for apps currently outputting audio.")
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: groupingSelector.implicitHeight

                ConfigSelectionArray {
                    id: groupingSelector
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: Config.options.dock.contextMenuVolume.enable
                    opacity: enabled ? 1.0 : 0.4
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    currentValue: Config.options.dock.contextMenuVolume.grouping
                    onSelected: newValue => {
                        Config.options.dock.contextMenuVolume.grouping = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Per app"),    value: "perApp"    },
                        { displayName: Translation.tr("Per window"), value: "perStream" },
                    ]
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

    ContentSection {
        icon: "rounded_corner"
        title: Translation.tr("Shape")

        ContentSubsection {
            title: Translation.tr("Corner style")
            ConfigSelectionArray {
                currentValue: Config.options.dock.cornerStyle
                onSelected: newValue => { Config.options.dock.cornerStyle = newValue; }
                // Last, and named the same as the bar's, because it is the same
                // shape: set down on the edge with a curve leaving each end.
                // The stored value stays "hug" so a config or a theme written
                // before the rename still selects it.
                options: [
                    { displayName: Translation.tr("Float"), icon: "page_header", value: "float" },
                    { displayName: Translation.tr("Rect"), icon: "toolbar", value: "rect" },
                    { displayName: Translation.tr("Notch"), icon: "call_to_action", value: "hug" }
                ]
            }
        }

        ConfigSlider {
            text: Translation.tr("Icon size")
            stopIndicatorValues: [Appearance.sizes.dockIconStock]
            buttonIcon: "apps"
            from: 16
            to: 64
            value: Appearance.sizes.dockIconSize
            // Whole pixels only. The raw slider value is continuous, so every
            // frame of a drag would otherwise re-decode every icon on the dock
            // at a new fractional size and recommit the layer-shell surface.
            onMoved: {
                const stepped = Math.round(value);
                if (stepped === Config.options.dock.iconSize)
                    return;
                Config.options.dock.iconSize = stepped;
            }
        }

        ConfigSlider {
            text: Translation.tr("Top roundness")
            visible: Config.options.dock.cornerStyle !== "float"
            stopIndicatorValues: [Appearance.rounding.dockTopStock]
            buttonIcon: "border_top"
            from: 0
            to: Appearance.rounding.dockRoundMax
            value: Appearance.rounding.dockTop
            // A radius is whole pixels; a fractional one discards the cached
            // shadow texture and re-triangulates the corner shapes per frame.
            onMoved: {
                const stepped = Math.round(value);
                if (stepped === Config.options.dock.topRadius)
                    return;
                Config.options.dock.topRadius = stepped;
            }
        }

        ConfigSlider {
            text: Translation.tr("Corner roundness")
            visible: Config.options.dock.cornerStyle !== "rect"
            stopIndicatorValues: [Appearance.rounding.dockCornerStock]
            buttonIcon: "rounded_corner"
            from: 0
            to: Appearance.rounding.dockRoundMax
            value: Appearance.rounding.dock
            onMoved: {
                const stepped = Math.round(value);
                if (stepped === Config.options.dock.radius)
                    return;
                Config.options.dock.radius = stepped;
            }
        }



        ConfigResetButton {
            visible: Config.options.dock.iconSize >= 0
                || Config.options.dock.radius >= 0
                || Config.options.dock.topRadius >= 0
            Layout.leftMargin: 8
            Layout.topMargin: 2
            buttonText: Translation.tr("Reset to default shape")
            onClicked: {
                Config.options.dock.iconSize = -1
                Config.options.dock.radius = -1
                Config.options.dock.topRadius = -1
            }
        }
    }

    ContentSection {
        icon: "opacity"
        title: Translation.tr("Transparency")

        ConfigSwitch {
            buttonIcon: "background_replace"
            text: Translation.tr("Show background")
            checked: Config.options.dock.showBackground
            onCheckedChanged: Config.options.dock.showBackground = checked
        }

        ConfigSlider {
            text: Translation.tr("Background")
            visible: Config.options.dock.showBackground
            stopIndicatorValues: [Appearance.colors.layer0StockAlpha]
            buttonIcon: "wallpaper"
            // The track stops where the dock stops being frosted rather than at
            // nothing, so every point along it answers the same way. Running it
            // to zero put a step partway down that no setting explains.
            from: Appearance.colors.surfaceOpacityFloor
            to: 1
            value: Math.max(Appearance.colors.surfaceOpacityFloor,
                Config.options.dock.backgroundOpacity < 0
                    ? Appearance.colors.layer0StockAlpha : Config.options.dock.backgroundOpacity)
            onMoved: {
                if (Math.abs(value - Config.options.dock.backgroundOpacity) < 0.005)
                    return;
                Config.options.dock.backgroundOpacity = value;
            }
        }

        ConfigResetButton {
            visible: Config.options.dock.backgroundOpacity >= 0
            Layout.leftMargin: 8
            Layout.topMargin: 2
            buttonText: Translation.tr("Reset to default transparency")
            onClicked: Config.options.dock.backgroundOpacity = -1
        }
    }

    ContentSection {
        icon: "palette"
        title: Translation.tr("Colors")

        ColorField {
            text: Translation.tr("Dock background")
            allowEmpty: true
            buttonIcon: "wallpaper"
            // Edits the slot for the mode on screen; the other mode keeps its
            // own pick, or the palette where none was made.
            value: Appearance.colors.dockPick
            fallback: String(Appearance.colors.colLayer0)
            onEdited: newValue => {
                if (Appearance.m3colors.darkmode) Config.options.dock.backgroundColorDark = newValue
                else Config.options.dock.backgroundColorLight = newValue
            }
        }

        ColorField {
            visible: Config.options.dock.indicatorStyle === "badge"
            text: Translation.tr("Badge text")
            allowEmpty: true
            buttonIcon: "format_color_text"
            value: Appearance.colors.dockBadgeTextPick
            fallback: String(Appearance.m3colors.m3onPrimary)
            onEdited: newValue => {
                if (Appearance.m3colors.darkmode) Config.options.dock.badgeTextColorDark = newValue
                else Config.options.dock.badgeTextColorLight = newValue
            }
        }

        ColorField {
            visible: Config.options.dock.indicatorStyle === "badge"
            text: Translation.tr("Badge background")
            allowEmpty: true
            buttonIcon: "counter_2"
            value: Appearance.colors.dockBadgePick
            fallback: String(Appearance.colors.colPrimary)
            onEdited: newValue => {
                if (Appearance.m3colors.darkmode) Config.options.dock.badgeColorDark = newValue
                else Config.options.dock.badgeColorLight = newValue
            }
        }

        ColorField {
            visible: Config.options.dock.hoverEffect === "glow"
            text: Translation.tr("Glow color")
            allowEmpty: true
            buttonIcon: "blur_on"
            value: Appearance.colors.dockGlowPick
            fallback: String(Appearance.m3colors.m3primaryFixed)
            onEdited: newValue => {
                if (Appearance.m3colors.darkmode) Config.options.dock.glowColorDark = newValue
                else Config.options.dock.glowColorLight = newValue
            }
        }

        ConfigResetButton {
            visible: Config.options.dock.backgroundColorDark !== ""
                || Config.options.dock.backgroundColorLight !== ""
                || Config.options.dock.badgeColorDark !== ""
                || Config.options.dock.badgeColorLight !== ""
                || Config.options.dock.badgeTextColorDark !== ""
                || Config.options.dock.badgeTextColorLight !== ""
                || Config.options.dock.glowColorDark !== ""
                || Config.options.dock.glowColorLight !== ""
            Layout.leftMargin: 8
            Layout.topMargin: 2
            buttonText: Translation.tr("Reset to default colors")
            onClicked: {
                Config.options.dock.backgroundColorDark = ""
                Config.options.dock.backgroundColorLight = ""
                Config.options.dock.badgeColorDark = ""
                Config.options.dock.badgeColorLight = ""
                Config.options.dock.badgeTextColorDark = ""
                Config.options.dock.badgeTextColorLight = ""
                Config.options.dock.glowColorDark = ""
                Config.options.dock.glowColorLight = ""
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
}
