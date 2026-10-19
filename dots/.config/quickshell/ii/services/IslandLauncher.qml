pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs
import qs.modules.common

Singleton {
    id: root
    readonly property bool enabled: Appearance.sizes.barIsIsland && Config.options.bar.island.appDrawer
    readonly property string focusedScreen: Hyprland.focusedMonitor?.name ?? ""
    readonly property bool available: enabled && GlobalStates.barOpen && !GlobalStates.screenLocked
        && Quickshell.screens.some(screen => screen.name === focusedScreen)
        && (!Config.options.bar.screenList.length || Config.options.bar.screenList.includes(focusedScreen))
        && !Hyprland.workspaces.values.some(workspace => workspace.monitor?.name === focusedScreen && workspace.active
            && workspace.toplevels.values.some(toplevel => toplevel.wayland?.fullscreen))
    property bool opened: false
    property string screenName: ""
    signal focusRequested()

    function open(): bool {
        if (!available || GlobalStates.wallpaperSelectorOpen || GlobalStates.sessionOpen) return false;
        GlobalStates.overviewOpen = false;
        screenName = focusedScreen;
        opened = true;
        focusRequested();
        return true;
    }

    function close(): void {
        opened = false;
    }

    // False lets the existing launcher handle a screen with no visible island.
    function toggle(): bool {
        if (opened) {
            close();
            return true;
        }
        return open();
    }

    onAvailableChanged: if (!available) close()
    onFocusedScreenChanged: if (opened && focusedScreen !== screenName) close()
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() { if (GlobalStates.overviewOpen) root.close(); }
        function onSidebarLeftOpenChanged() { if (GlobalStates.sidebarLeftOpen) root.close(); }
        function onSidebarRightOpenChanged() { if (GlobalStates.sidebarRightOpen) root.close(); }
        function onSessionOpenChanged() { if (GlobalStates.sessionOpen) root.close(); }
    }
}
