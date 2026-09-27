import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    Loader {
        id: wallpaperSelectorLoader
        active: GlobalStates.wallpaperSelectorOpen

        sourceComponent: PanelWindow {
            id: panelWindow
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
            // The screen is chosen before the window exists, so the picker is
            // sized for it from the first frame: the monitor it picks for, or
            // the focused one. Opened any other way, the compositor places it.
            screen: GlobalStates.wallpaperSelectorScreen

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:wallpaperSelector"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors.top: true
            margins {
                top: Config?.options.bar.vertical ? Appearance.sizes.hyprlandGapsOut : Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut
            }

            mask: Region {
                item: content
            }

            // A portrait screen is narrower than the picker is wide, so there
            // it takes the screen's width and grows down into the height it
            // has instead, short of whatever holds the bottom edge.
            readonly property var targetScreen: GlobalStates.wallpaperSelectorScreen ?? panelWindow.screen
            readonly property real screenWidth: panelWindow.targetScreen?.width ?? Appearance.sizes.wallpaperSelectorWidth
            readonly property real screenHeight: panelWindow.targetScreen?.height ?? Appearance.sizes.wallpaperSelectorHeight
            readonly property real bottomClearance: (HyprlandData.monitors.find(m => m.name === panelWindow.targetScreen?.name)?.reserved?.[3] ?? 0)
                + Appearance.sizes.hyprlandGapsOut
            implicitWidth: Math.min(Appearance.sizes.wallpaperSelectorWidth, panelWindow.screenWidth - Appearance.sizes.hyprlandGapsOut * 2)
            implicitHeight: panelWindow.screenHeight > panelWindow.screenWidth
                ? Math.min(Appearance.sizes.wallpaperSelectorHeight * 1.6,
                    panelWindow.screenHeight - panelWindow.margins.top - panelWindow.bottomClearance)
                : Appearance.sizes.wallpaperSelectorHeight

            Component.onCompleted: {
                GlobalFocusGrab.addDismissable(panelWindow);
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.wallpaperSelectorOpen = false;
                }
            }

            WallpaperSelectorContent {
                id: content
                anchors {
                    fill: parent
                }
            }
        }
    }

    // A monitor's own picture is drawn by the background layer as a still,
    // so the picker leaves videos out while it chooses one.
    Binding {
        target: Wallpapers
        property: "imagesOnly"
        value: GlobalStates.wallpaperSelectorMonitor !== ""
    }

    // The monitor it was opened for can stop being one with a picture of its
    // own while the picker is up, by becoming the default monitor or being
    // unplugged. The picker closes then rather than refusing every pick, and
    // does not turn to the main wallpaper, where the next click would retheme.
    readonly property bool monitorTargetGone: GlobalStates.wallpaperSelectorOpen
        && GlobalStates.wallpaperSelectorMonitor !== ""
        && !MonitorWallpapers.isOtherMonitor(GlobalStates.wallpaperSelectorMonitor)
    onMonitorTargetGoneChanged: if (root.monitorTargetGone) GlobalStates.wallpaperSelectorOpen = false

    function toggleWallpaperSelector() {
        if (Config.options.wallpaperSelector.useSystemFileDialog) {
            Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode);
            return;
        }
        if (!GlobalStates.wallpaperSelectorOpen)
            GlobalStates.wallpaperSelectorScreen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null;
        GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen
    }

    IpcHandler {
        target: "wallpaperSelector"

        function toggle(): void {
            root.toggleWallpaperSelector();
        }

        function random(): void {
            Wallpapers.randomFromCurrentFolder();
        }
    }

    GlobalShortcut {
        name: "wallpaperSelectorToggle"
        description: "Toggle wallpaper selector"
        onPressed: {
            root.toggleWallpaperSelector();
        }
    }

    GlobalShortcut {
        name: "wallpaperSelectorRandom"
        description: "Select random wallpaper in current folder"
        onPressed: {
            Wallpapers.randomFromCurrentFolder();
        }
    }
}
