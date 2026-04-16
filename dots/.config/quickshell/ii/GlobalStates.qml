import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property bool hdrActive: false
    property bool barOpen: true
    property bool crosshairOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool mediaControlsOpen: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false
    property string openFolderId: ""  // Set by dock to open a folder in the app drawer

    onSidebarRightOpenChanged: {
        if (GlobalStates.sidebarRightOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }

    // ── HDR detection: poll hyprctl for active HDR color management ──
    Process {
        id: hdrCheckProc
        command: ["hyprctl", "monitors", "-j"]
        property string output: ""
        stdout: SplitParser {
            onRead: data => hdrCheckProc.output += data
        }
        onExited: {
            try {
                let monitors = JSON.parse(hdrCheckProc.output);
                root.hdrActive = monitors.some(m =>
                    m.colorManagementPreset === "hdr" || m.colorManagementPreset === "hdredid"
                );
            } catch(e) {
                root.hdrActive = false;
            }
            hdrCheckProc.output = "";
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" || event.name === "monitoraddedv2" || event.name === "monitorremoved")
                hdrCheckProc.running = true;
        }
    }

    Component.onCompleted: hdrCheckProc.running = true

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"

        onPressed: {
            root.superDown = true
        }
        onReleased: {
            root.superDown = false
        }
    }
}