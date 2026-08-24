import QtQuick
import QtQuick.Layouts
import Quickshell
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
                id: dockPositionCombo
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
                    { displayName: Translation.tr("Disable"), icon: "close", value: "none" },
                    { displayName: Translation.tr("Dashes"), icon: "remove", value: "dashes" },
                    { displayName: Translation.tr("Dots"), icon: "more_horiz", value: "dots" }
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
                options: [
                    { displayName: Translation.tr("Hug"), icon: "line_curve", value: "hug" },
                    { displayName: Translation.tr("Float"), icon: "page_header", value: "float" },
                    { displayName: Translation.tr("Rect"), icon: "toolbar", value: "rect" }
                ]
            }
        }

        ConfigSlider {
            text: Translation.tr("Icon size")
            stopIndicatorValues: [Appearance.sizes.dockIconStock]
            buttonIcon: "apps"
            from: 16
            to: 64
            value: Config.options.dock.iconSize < 0 ? 35 : Config.options.dock.iconSize
            onMoved: {
                if (value === Config.options.dock.iconSize)
                    return;
                Config.options.dock.iconSize = value;
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
            onMoved: {
                if (value === Config.options.dock.topRadius)
                    return;
                Config.options.dock.topRadius = value;
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
                if (value === Config.options.dock.radius)
                    return;
                Config.options.dock.radius = value;
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
            stopIndicatorValues: [Appearance.colors.dockStockAlpha]
            buttonIcon: "wallpaper"
            // The track stops where the dock stops being frosted rather than at
            // nothing, so every point along it answers the same way. Running it
            // to zero put a step partway down that no setting explains.
            from: Appearance.colors.dockOpacityFloor
            to: 1
            value: Math.max(Appearance.colors.dockOpacityFloor,
                Config.options.dock.backgroundOpacity < 0
                    ? Appearance.colors.dockStockAlpha : Config.options.dock.backgroundOpacity)
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
            text: Translation.tr("Background")
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

        ConfigResetButton {
            visible: Config.options.dock.backgroundColorDark !== ""
                || Config.options.dock.backgroundColorLight !== ""
            Layout.leftMargin: 8
            Layout.topMargin: 2
            buttonText: Translation.tr("Reset to default colors")
            onClicked: {
                Config.options.dock.backgroundColorDark = ""
                Config.options.dock.backgroundColorLight = ""
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
