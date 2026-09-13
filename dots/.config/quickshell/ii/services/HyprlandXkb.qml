pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common

/**
 * Exposes the active Hyprland Xkb keyboard layout name and code for indicators.
 */
Singleton {
    id: root
    // You can read these
    property list<string> layoutCodes: []
    property var cachedLayoutCodes: ({})
    property string currentLayoutName: ""
    property string currentLayoutCode: ""
    // For the service
    property var baseLayoutFilePath: "/usr/share/X11/xkb/rules/base.lst"

    // Re-reads the layout list from Hyprland. Settings calls this after it
    // applies a new list with hyprctl eval, which rebuilds the keymaps without
    // a config reload.
    function refresh() {
        refreshTimer.restart();
    }

    // Update the layout code according to the layout name (Hyprland gives the name not the code)
    onCurrentLayoutNameChanged: root.updateLayoutCode()
    function updateLayoutCode() {
        if (cachedLayoutCodes.hasOwnProperty(currentLayoutName)) {
            root.currentLayoutCode = cachedLayoutCodes[currentLayoutName];
        } else {
            getLayoutProc.running = true;
        }
    }

    // Get the layout code from the base.lst file by grabbing the line with the current layout name
    Process {
        id: getLayoutProc
        command: ["cat", root.baseLayoutFilePath]

        stdout: StdioCollector {
            id: layoutCollector

            onStreamFinished: {
                const lines = layoutCollector.text.split("\n");
                const targetDescription = root.currentLayoutName;
                const foundLine = lines.find(line => {
                    // Skip comment lines and empty lines
                    if (!line.trim() || line.trim().startsWith('!'))
                        return false;

                    // Match layout: (whitespace + ) key + whitespace + description
                    const matchLayout = line.match(/^\s*(\S+)\s+(.+)$/);
                    if (matchLayout && matchLayout[2] === targetDescription) {
                        root.cachedLayoutCodes[matchLayout[2]] = matchLayout[1];
                        root.currentLayoutCode = matchLayout[1];
                        return true;
                    }

                    // Match variant: (whitespace + ) variant + whitespace + key + whitespace + description
                    const matchVariant = line.match(/^\s*(\S+)\s+(\S+)\s+(.+)$/);
                    if (matchVariant && matchVariant[3] === targetDescription) {
                        const complexLayout = matchVariant[2] + matchVariant[1];
                        root.cachedLayoutCodes[matchVariant[3]] = complexLayout;
                        root.currentLayoutCode = complexLayout;
                        return true;
                    }
                    
                    return false;
                });
            }
        }
    }

    // A layout change reaches here once per keyboard, and a mouse or a headset
    // with a key interface counts as one, so a burst of a dozen events is
    // normal. They collapse into a single devices query.
    Timer {
        id: refreshTimer
        interval: 150
        onTriggered: {
            fetchLayoutsProc.running = false;
            fetchLayoutsProc.running = true;
        }
    }

    // Find out available layouts and current active layout
    Process {
        id: fetchLayoutsProc
        running: true
        command: ["hyprctl", "-j", "devices"]

        stdout: StdioCollector {
            id: devicesCollector
            onStreamFinished: {
                try {
                    const keyboards = JSON.parse(devicesCollector.text)["keyboards"] || [];
                    const hyprlandKeyboard = keyboards.find(kb => kb.main === true) || keyboards[0];
                    if (!hyprlandKeyboard)
                        return;
                    root.layoutCodes = (hyprlandKeyboard["layout"] || "").split(",").filter(Boolean);
                    root.currentLayoutName = hyprlandKeyboard["active_keymap"];
                } catch (e) {
                    console.warn("[HyprlandXkb] Could not read keyboards:", e);
                }
            }
        }
    }

    // Update the layout name when it changes
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") {
                // A keymap event while only one layout is known means the list
                // itself changed: an eval or a keyword rebuilds the keymaps with
                // no reload, and so does a keyboard being plugged in.
                if (root.layoutCodes.length <= 1)
                    root.refresh();

                const dataString = event.data;
                root.currentLayoutName = dataString.substring(dataString.indexOf(",") + 1);

                // Update layout for on-screen keyboard (osk)
                Config.options.osk.layout = root.currentLayoutName.split(" (")[0];
            } else if (event.name == "configreloaded") {
                // A reload whose layout list did not change carries no keymap
                // event, so ask rather than wait for one.
                root.refresh();
            }
        }
    }
}
