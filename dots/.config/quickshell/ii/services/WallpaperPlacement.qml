pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Where each screen's wallpaper sits, published by the background so a surface
 * in another window can sample the same picture in the same place.
 */
Singleton {
    id: root
    property var screens: ({})
    // Video has no still image for the panel samplers. The compositor is the
    // fallback; still-image panels cover it with their own sampled backdrop.
    readonly property bool needsPanelBlur: Object.keys(screens).length === 0
        || Object.values(screens).some(placement => placement.video)
    // Settings and previews also read this singleton; only the main shell
    // may change the compositor's panel rules.
    property bool _panelBlurEnabled: false
    property bool blurUpdatePending: false
    onNeedsPanelBlurChanged: if (_panelBlurEnabled) blurDelay.restart()
    on_PanelBlurEnabledChanged: if (_panelBlurEnabled) blurDelay.restart()

    function updatePanelBlur() {
        if (!root._panelBlurEnabled) return;
        if (blurWriter.running) {
            root.blurUpdatePending = true;
            return;
        }
        root.blurUpdatePending = false;
        blurWriter.command = ["hyprctl", "eval", 'hl.layer_rule({name="mainstream-panel-blur", enabled='
            + (root.needsPanelBlur ? "false" : "true") + '})'];
        blurWriter.running = true;
    }
    Timer {
        id: blurDelay
        interval: 100
        onTriggered: root.updatePanelBlur()
    }
    Process {
        id: blurWriter
        onExited: {
            if (root.blurUpdatePending) blurDelay.restart();
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root._panelBlurEnabled && event.name === "configreloaded") blurDelay.restart();
        }
    }
    // A swap's picture stays behind a backdrop until the effect has come part of
    // the way, then fades in over this many milliseconds.
    signal freeze(string screenName)
    signal release(string screenName, real fadeMs)

    function publish(screenName, placement) {
        const next = Object.assign({}, root.screens);
        if (placement)
            next[screenName] = placement;
        else
            delete next[screenName];
        root.screens = next;
    }
}
