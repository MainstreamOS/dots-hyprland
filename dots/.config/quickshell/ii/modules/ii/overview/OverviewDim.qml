import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    // One dim per screen: surfaces are torn down and rebuilt with their
    // output, so a DP re-train across suspend/DPMS can't orphan the window.
    Variants {
        model: Quickshell.screens

    PanelWindow {
        id: dimWindow
        required property ShellScreen modelData
        screen: modelData
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(dimWindow.screen)
        property bool monitorIsFocused: ((Hyprland.focusedMonitor?.id ?? monitor?.id) === monitor?.id)
        // The dock is raised above the dim and takes its colors from this
        // very answer, so the two change together.
        readonly property bool dimShown: GlobalStates.overviewOpen && dimWindow.monitorIsFocused && dimWindow.width > 1
        readonly property string screenName: modelData?.name ?? ""
        onDimShownChanged: GlobalStates.setLauncherDim(dimWindow.screenName, dimWindow.dimShown)
        // Track the configured extent: shrinking the layer surface takes another
        // compositor configure.
        readonly property bool surfaceShown: visible && width > 1 && height > 1
        property string registeredScreen: ""
        Component.onCompleted: {
            registeredScreen = screenName;
            GlobalStates.launcherDimWindows = Object.assign({}, GlobalStates.launcherDimWindows, {[registeredScreen]: dimWindow});
        }
        Component.onDestruction: {
            if (GlobalStates.launcherDimWindows[registeredScreen] === dimWindow) {
                const windows = Object.assign({}, GlobalStates.launcherDimWindows);
                delete windows[registeredScreen];
                GlobalStates.launcherDimWindows = windows;
                GlobalStates.setLauncherDim(registeredScreen, false);
            }
        }

        WlrLayershell.namespace: "quickshell:overviewDim"
        // Use Overlay layer (not Top) so the dim stays visible during fullscreen
        // apps. See the matching comment in Overview.qml for the full reasoning.
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        // Keep a faint base for compositor blur, including the original
        // black underlay. A closed one-pixel surface stays fully clear.
        color: dimWindow.surfaceShown ? Qt.rgba(0, 0, 0, 0.01) : "transparent"
        // The layer is click-through by design (empty mask). The size alone turns
        // the blur on and off: closed it is kept to one pixel, and only the screen
        // that shows it spans, including the dim's closing fade.
        readonly property bool spanning: (GlobalStates.overviewOpen && dimWindow.monitorIsFocused) || dimTint.opacity > 0
        visible: (Config.options.overview.keepSurfaceAlive ?? true)
            || spanning

        anchors {
            top: dimWindow.spanning
            bottom: dimWindow.spanning
            left: dimWindow.spanning
            right: dimWindow.spanning
        }
        implicitWidth: 1
        implicitHeight: 1

        Rectangle {
            id: dimTint
            anchors.fill: parent
            color: Appearance.launcherDimColor
            opacity: dimWindow.dimShown ? Appearance.launcherDimOpacity : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this, { alwaysRunToEnd: false })
            }
        }

        // Purely visual — all input passes through
        mask: Region {}
    }

    }   // end Variants
}
