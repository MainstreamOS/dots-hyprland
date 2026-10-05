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
            // Off the default monitor the wallpaper rows are this screen's
            // own: the default monitor's wallpaper is the one the colors come
            // from, and it stays the one Super+W changes.
            readonly property string targetMonitor: menuWindow.screen?.name ?? ""
            readonly property bool forThisScreen: MonitorWallpapers.isOtherMonitor(menuWindow.targetMonitor)
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

            ContextMenuCard {
                id: menuCard

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

                ColumnLayout {
                    id: menuColumn
                    anchors {
                        fill: parent
                        margins: menuCard.padding
                    }
                    spacing: 0

                    // A menu opened on the wallpaper leads with the wallpaper.
                    // The rows for the desktop itself come first and
                    // together, then the pair of strips along its edges, then
                    // the monitor, which is the least desktop thing here.
                    ContextMenuItem {
                        iconName: "image"
                        label: Translation.tr("Change Wallpaper")
                        // On the default monitor this is what Super+W does, so
                        // picking a wallpaper means the same thing here as it
                        // does from the keyboard. On any other monitor it picks
                        // a picture for that screen alone, which leaves the
                        // colors as they are. The system file dialog setting
                        // holds for both.
                        onClicked: menuWindow.changeWallpaper()
                    }

                    // Only once this screen has a picture of its own, so the
                    // row always does something.
                    ContextMenuItem {
                        visible: menuWindow.forThisScreen && MonitorWallpapers.hasPicture(menuWindow.targetMonitor)
                        iconName: "reset_image"
                        label: Translation.tr("Use Main Wallpaper")
                        onClicked: {
                            MonitorWallpapers.clearPicture(menuWindow.targetMonitor);
                            GlobalStates.desktopMenuOpen = false;
                        }
                    }

                    ContextMenuItem {
                        iconName: "dashboard_customize"
                        label: Translation.tr("Personalize Desktop")
                        onClicked: menuWindow.openSettingsPage("BackgroundConfig.qml")
                    }

                    ContextMenuSeparator {}

                    ContextMenuItem {
                        iconName: "toast"
                        // The bar's glyph is a toast, which points the wrong
                        // way for a strip along an edge, so Settings turns it
                        // over. A row here showing it the other way up would
                        // not read as the same thing.
                        iconRotation: 180
                        label: Translation.tr("Personalize Bar")
                        onClicked: menuWindow.openSettingsPage("BarConfig.qml")
                    }

                    ContextMenuItem {
                        iconName: "toast"
                        label: Translation.tr("Personalize Dock")
                        onClicked: menuWindow.openSettingsPage("DockConfig.qml")
                    }

                    ContextMenuSeparator {}

                    ContextMenuItem {
                        iconName: "display_settings"
                        label: Translation.tr("Display Settings")
                        onClicked: menuWindow.openSettingsPage("DisplayConfig.qml")
                    }

                    ContextMenuSeparator {}

                    // On its own at the end, because a theme is the one thing
                    // here that changes everything above it at once.
                    ContextMenuItem {
                        iconName: "style"
                        label: Translation.tr("Switch Theme")
                        onClicked: menuWindow.openSettingsPage("ThemesConfig.qml")
                    }
                }
            }

            // Read before the menu closes, which takes this window with it.
            function changeWallpaper() {
                const monitorName = menuWindow.targetMonitor;
                const screen = menuWindow.screen;
                const forThisScreen = menuWindow.forThisScreen;
                GlobalStates.desktopMenuOpen = false;
                if (!forThisScreen) {
                    Hyprland.dispatch(`hl.dsp.global("quickshell:wallpaperSelectorToggle")`);
                    return;
                }
                if (Config.options.wallpaperSelector.useSystemFileDialog) {
                    MonitorWallpapers.pickWithSystemDialog(monitorName);
                    return;
                }
                GlobalStates.wallpaperSelectorScreen = screen;
                GlobalStates.wallpaperSelectorMonitor = monitorName;
                GlobalStates.wallpaperSelectorOpen = true;
            }

            function openSettingsPage(page) {
                GlobalStates.desktopMenuOpen = false;
                Session.openSettings(page);
            }
        }
    }
}
