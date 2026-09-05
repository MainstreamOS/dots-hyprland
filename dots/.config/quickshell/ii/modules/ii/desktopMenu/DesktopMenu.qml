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

            StyledRectangularShadow {
                target: menuCard
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

                    DesktopMenuItem {
                        iconName: "display_settings"
                        label: Translation.tr("Display Settings")
                        onClicked: menuWindow.openSettingsPage("DisplayConfig.qml")
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
