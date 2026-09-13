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
    // The keyboard whose layout the bar reports: the one Hyprland calls main,
    // unless that is an input method's virtual keyboard, which forwards keys a
    // group behind and must never be the one followed; then the first real
    // keyboard. Every other device is kept on its index.
    property string mainKeyboardName: ""
    property int mainLayoutIndex: 0
    // What the previous devices query found in effect. The event path updates
    // currentLayoutName ahead of the query, so a switch is judged against this.
    property string fetchedLayoutName: ""

    // Re-reads the layout list from Hyprland, coalescing a burst of events.
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

    // The layout you switch to leads the list: shortly after a switch, localed
    // is told the active layout leads, so the login screen and the next session
    // start in it. Debounced past the per-keyboard burst.
    Timer {
        id: rememberTimer
        interval: 600
        onTriggered: Quickshell.execDetached(["python3", Quickshell.shellPath("scripts/keyboard/write-layouts.py"), "--from-hyprland", "--lead-active", "--localed-only"])
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
                    const keyboards = (JSON.parse(devicesCollector.text)["keyboards"] || []).filter(kb => !(kb["name"] || "").startsWith("hl-virtual"));
                    const main = keyboards.find(kb => kb.main === true) || keyboards[0];
                    if (!main)
                        return;
                    const previousName = root.fetchedLayoutName;
                    root.fetchedLayoutName = main["active_keymap"];
                    root.mainKeyboardName = main["name"] || "";
                    root.mainLayoutIndex = main["active_layout_index"] || 0;
                    root.layoutCodes = (main["layout"] || "").split(",").filter(Boolean);
                    root.currentLayoutName = main["active_keymap"];
                    // The layout you switch to leads the list: a fetch that finds
                    // the real keyboard on a different layout than last time is
                    // the one sure sign of a switch, whichever device spoke first.
                    if (previousName && previousName !== root.currentLayoutName && root.layoutCodes.length > 1)
                        rememberTimer.restart();

                    // A keyboard plugged in after a switch starts on the first
                    // layout while the others are elsewhere, and the switch
                    // bind would then walk them apart for good. Any device
                    // with the same list but a different index is put on the
                    // main keyboard's.
                    for (const kb of keyboards) {
                        const name = kb["name"] || "";
                        if (kb === main || name.startsWith("hl-virtual") || kb["layout"] !== main["layout"])
                            continue;
                        if ((kb["active_layout_index"] || 0) !== root.mainLayoutIndex)
                            Quickshell.execDetached(["hyprctl", "switchxkblayout", name, String(root.mainLayoutIndex)]);
                    }
                } catch (e) {
                }
            }
        }
    }

    // Update the layout name when it changes
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") {
                // One devices query per burst, whatever caused it: a switch, an
                // eval, a keyboard plugged in.
                root.refresh();

                const dataString = event.data;
                const eventName = dataString.substring(dataString.indexOf(",") + 1);
                const device = dataString.substring(0, dataString.indexOf(","));
                if (root.mainKeyboardName && device !== root.mainKeyboardName)
                    return;
                root.currentLayoutName = eventName;

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
