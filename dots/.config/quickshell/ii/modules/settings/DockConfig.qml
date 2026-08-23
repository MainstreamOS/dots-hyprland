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
        title: Translation.tr("Dock")

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

        ContentSubsection {
            title: Translation.tr("Launch animation")
            ConfigSelectionArray {
                currentValue: Config.options.dock.launchAnimation
                onSelected: newValue => {
                    Config.options.dock.launchAnimation = newValue;
                }
                options: [
                    { displayName: Translation.tr("None"), icon: "block", value: DockLaunchAnims.AnimType.None },
                    { displayName: Translation.tr("Bounce"), icon: "swap_vert", value: DockLaunchAnims.AnimType.Bounce },
                    { displayName: Translation.tr("Pulse"), icon: "open_in_new", value: DockLaunchAnims.AnimType.Pulse },
                    { displayName: Translation.tr("Pop"), icon: "adjust", value: DockLaunchAnims.AnimType.Pop },
                    { displayName: Translation.tr("Wobble"), icon: "360", value: DockLaunchAnims.AnimType.Wobble }
                ]
            }
        }
    }
}
