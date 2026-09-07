pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// The menu a right click on the desktop opens. It is mapped only while it
// is open, and only the card takes input, so the desktop underneath keeps
// behaving as it does the rest of the time.
Scope {
    id: root

    Loader {
        // Gone while the screen is locked, the way every other panel is:
        // an Overlay surface would otherwise keep showing through the lock.
        active: GlobalStates.desktopMenuOpen && !GlobalStates.screenLocked

        sourceComponent: PanelWindow {
            id: menuWindow

            screen: GlobalStates.desktopMenuScreen ?? Quickshell.screens[0]
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:desktopMenu"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            // Spans the screen so the card can sit wherever the click landed,
            // while the mask keeps every other pixel click-through.
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            mask: Region {
                item: menuCard
            }

            Component.onCompleted: GlobalFocusGrab.addDismissable(menuWindow)
            Component.onDestruction: GlobalFocusGrab.removeDismissable(menuWindow)
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.desktopMenuOpen = false;
                }
            }

            // Darker than the shared default, which is faint enough to vanish
            // over a bright wallpaper. Deeper rather than wider on purpose:
            // the card is kept one elevation margin from the screen edges, so
            // a larger blur would be cut off exactly where the menu is most
            // likely to open.
            StyledRectangularShadow {
                target: menuCard
                color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.4)
            }

            Rectangle {
                id: menuCard
                property real padding: 4

                // The card grows right and down from the click, and to the
                // other side of it when that edge is too close. Sliding it
                // back instead would drop it under the waiting pointer,
                // where the click that means "never mind" hits a row.
                function place(at, extent, limit) {
                    const margin = Appearance.sizes.elevationMargin;
                    const flipped = (at + extent + margin > limit) ? at - extent : at;
                    return Math.round(Math.max(margin, Math.min(flipped, limit - extent - margin)));
                }
                x: menuCard.place(GlobalStates.desktopMenuX, width, menuWindow.width)
                y: menuCard.place(GlobalStates.desktopMenuY, height, menuWindow.height)
                implicitWidth: menuColumn.implicitWidth + padding * 2
                implicitHeight: menuColumn.implicitHeight + padding * 2
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.normal

                ColumnLayout {
                    id: menuColumn
                    anchors {
                        fill: parent
                        margins: menuCard.padding
                    }
                    spacing: 0

                    // A menu opened on the wallpaper leads with the wallpaper.
                    // The two rows for the desktop itself come first and
                    // together, then the pair of strips along its edges, then
                    // the monitor, which is the least desktop thing here.
                    DesktopMenuItem {
                        iconName: "image"
                        label: Translation.tr("Change Wallpaper")
                        // What Super+W does, so picking a wallpaper means the
                        // same thing here as it does from the keyboard, the
                        // system file dialog setting included.
                        onClicked: {
                            GlobalStates.desktopMenuOpen = false;
                            Hyprland.dispatch(`hl.dsp.global("quickshell:wallpaperSelectorToggle")`);
                        }
                    }

                    DesktopMenuItem {
                        iconName: "dashboard_customize"
                        label: Translation.tr("Personalize Desktop")
                        onClicked: menuWindow.openSettingsPage("BackgroundConfig.qml")
                    }

                    ContextMenuSeparator {}

                    DesktopMenuItem {
                        iconName: "toast"
                        iconRotation: 180
                        label: Translation.tr("Personalize Bar")
                        onClicked: menuWindow.openSettingsPage("BarConfig.qml")
                    }

                    DesktopMenuItem {
                        iconName: "toast"
                        label: Translation.tr("Personalize Dock")
                        onClicked: menuWindow.openSettingsPage("DockConfig.qml")
                    }

                    ContextMenuSeparator {}

                    DesktopMenuItem {
                        iconName: "display_settings"
                        label: Translation.tr("Display Settings")
                        onClicked: menuWindow.openSettingsPage("DisplayConfig.qml")
                    }

                    ContextMenuSeparator {}

                    // On its own at the end, because a theme is the one thing
                    // here that changes everything above it at once.
                    DesktopMenuItem {
                        iconName: "style"
                        label: Translation.tr("Switch Theme")
                        onClicked: menuWindow.openSettingsPage("ThemesConfig.qml")
                    }
                }
            }

            function openSettingsPage(page) {
                GlobalStates.desktopMenuOpen = false;
                Quickshell.execDetached(["sh", "-c",
                    `QS_SETTINGS_PAGE=${page} quickshell -p '`
                    + StringUtils.shellSingleQuoteEscape(Directories.settingsAppPath) + "'"]);
            }
        }
    }

    // Same row as the dock's own context menu, so both menus read alike.
    component DesktopMenuItem: RippleButton {
        id: menuItemRoot
        property string iconName
        // The bar's glyph is a toast, which points the wrong way for a strip
        // along an edge, so Settings turns it over. A row here showing it the
        // other way up would not read as the same thing.
        property int iconRotation: 0
        property string label
        Layout.fillWidth: true
        implicitHeight: 36
        implicitWidth: Math.max(itemRow.implicitWidth + 20, 200)
        buttonRadius: Appearance.rounding.small

        contentItem: RowLayout {
            id: itemRow
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 14
            }
            spacing: 8

            MaterialSymbol {
                text: menuItemRoot.iconName
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3onSurface
                rotation: menuItemRoot.iconRotation
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                Layout.fillWidth: true
                text: menuItemRoot.label
                horizontalAlignment: Text.AlignLeft
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.m3colors.m3onSurface
            }
        }
    }
}
