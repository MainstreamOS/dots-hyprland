pragma Singleton
pragma ComponentBehavior: Bound

// Took many bits from https://github.com/caelestia-dots/shell (GPLv3)

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common
import qs.services.network
import "network-rates.js" as Rates

/**
 * Network service with nmcli.
 */
Singleton {
    id: root

    property bool wifi: true
    property bool ethernet: false

    property bool wifiEnabled: false
    property bool wifiScanning: false
    property bool wifiConnecting: connectProc.running
    property WifiAccessPoint wifiConnectTarget
    readonly property list<WifiAccessPoint> wifiNetworks: []
    // A network joined on a Steam Frame adapter is only shown when the computer's own card has none.
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n.active && !n.onFrameAdapter)
        ?? wifiNetworks.find(n => n.active) ?? null

    // Steam's profile for the Steam Frame adapter's link to the headset, never the user's network.
    readonly property string frameProfileName: "Steam Frame Wireless Adapter"
    // Found by USB id, so even with Wi-Fi off or Steam closed.
    property var frameAdapters: []
    readonly property bool frameAdapterPresent: frameAdapters.length > 0
    // Wi-Fi devices on Steam's link, and Frame adapters left out because the
    // computer has a Wi-Fi card of its own.
    property var frameLinkDevices: []
    property var hiddenWifiDevices: []
    // Cards a scan may use while a Frame adapter is in: a scan takes the adapter
    // off the headset's channel, and back-to-back scans have hung it.
    property var scanDevices: []
    property WifiAccessPoint frameProfile: null
    // The headset's hotspot, from Steam's profile. Kept after a forget, since it
    // is still the headset and never a network to join.
    property string frameSsid: ""
    
    // Saved connection names (SSIDs with profiles)
    property var savedConnectionNames: new Set()
    
    // Sorted once per scan, not from a binding: a binding that sorts on
    // strength would rebuild the list, and every row with it, on every scan.
    property var friendlyWifiNetworks: []
    // Steam's profile is not named after its network, so no scan matches it. It is
    // added by name so it can be deleted, which has fixed a headset that would not pair.
    readonly property list<var> savedNetworks: friendlyWifiNetworks.filter(n => n.isSaved && !n.active)
        .concat(frameProfile ? [frameProfile] : [])
    readonly property list<var> availableNetworks: friendlyWifiNetworks.filter(n => !n.isSaved && !n.active)
    // The last scan as nmcli gave it, kept so the list can be redone when a
    // device joins or leaves Steam's link without asking nmcli again.
    property var scanRows: []
    // The list waits for the first status, which says which devices are Steam's.
    property bool devicesKnown: false

    function reorderNetworks() {
        const before = root.friendlyWifiNetworks;
        // Only when the networks or the connected one change. Two networks a
        // few dBm apart swap on nearly every scan, and each swap cost a full
        // row rebuild. Signal bars still update live inside each row.
        const namesNow = wifiNetworks.map(n => n.ssid).sort().join("\u0000");
        const namesBefore = before.map(n => n.ssid).sort().join("\u0000");
        const activeNow = (wifiNetworks.find(n => n.active) ?? null);
        const activeBefore = (before.find(n => n.active) ?? null);
        if (namesNow === namesBefore && activeNow === activeBefore)
            return;
        // A prompt is open, and the password being typed lives in a row.
        if (before.some(n => n.askingPassword))
            return;
        root.friendlyWifiNetworks = [...wifiNetworks].sort((a, b) => {
            if (a.active && !b.active)
                return -1;
            if (!a.active && b.active)
                return 1;
            return b.strength - a.strength;
        });
    }
    
    property string wifiStatus: "disconnected"

    property string networkName: ""
    property int networkStrength: root.active?.strength ?? 0
    property string materialSymbol: root.ethernet
        ? "lan"
        : (root.wifiEnabled && root.wifiStatus === "connected")
            ? (
                (root.active?.strength ?? 0) > 83 ? "signal_wifi_4_bar" :
                (root.active?.strength ?? 0) > 67 ? "network_wifi" :
                (root.active?.strength ?? 0) > 50 ? "network_wifi_3_bar" :
                (root.active?.strength ?? 0) > 33 ? "network_wifi_2_bar" :
                (root.active?.strength ?? 0) > 17 ? "network_wifi_1_bar" :
                "signal_wifi_0_bar"
            )
            : (root.wifiStatus === "connecting")
                ? "signal_wifi_statusbar_not_connected"
                : (root.wifiStatus === "disconnected")
                    ? "wifi_find"
                    : (root.wifiStatus === "disabled")
                        ? "signal_wifi_off"
                        : "signal_wifi_bad"

    // Control
    // Settings shows this warning on the page, so it passes quiet.
    function enableWifi(enabled = true, quiet = false): void {
        const cmd = enabled ? "on" : "off";
        enableWifiProc.exec(["nmcli", "radio", "wifi", cmd]);
        if (!enabled && !quiet && root.frameAdapterPresent)
            Quickshell.execDetached(["notify-send", Translation.tr("Wi-Fi turned off"), Translation.tr("Turning Wi-Fi off also turns off the wireless adapter for the Steam Frame (experimental), so the headset cannot stream through it until Wi-Fi is back on."), "-a", "Shell"]);
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }

    function rescanWifi(): void {
        wifiScanning = true;
        rescanProcess.running = true;
    }

    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        // Steam brings its link up by itself, on the adapter, when the headset is near.
        if (accessPoint === root.frameProfile)
            return;
        accessPoint.askingPassword = false;
        root.wifiConnectTarget = accessPoint;
        // We use this instead of `nmcli connection up SSID` because this also creates a connection profile
        connectProc.exec(["nmcli", "dev", "wifi", "connect", accessPoint.ssid])

    }

    function disconnectWifiNetwork(): void {
        if (active) disconnectProc.exec(["nmcli", "connection", "down", active.ssid]);
    }

    function forgetWifiNetwork(accessPoint: WifiAccessPoint): void {
        // Use a proper process to ensure the deletion completes before refreshing
        forgetProc.exec(["nmcli", "connection", "delete", accessPoint.ssid]);
    }

    function openPublicWifiPortal() {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]) // From some StackExchange thread, seems to work
    }

    function changePassword(network: WifiAccessPoint, password: string, username = ""): void {
        // TODO: enterprise wifi with username
        network.askingPassword = false;
        network.connectionError = ""; // Clear previous errors
        root.wifiConnectTarget = network;
        // Try to update saved password first, then connect
        // This handles both: 1) saved networks with changed passwords, 2) new networks
        changePasswordProc.exec({
            "environment": {
                "PASSWORD": password,
                "SSID": network.ssid
            },
            // First try to modify existing profile, if that fails (no profile exists), 
            // create new connection with password
            "command": ["bash", "-c", `
                if nmcli connection show "$SSID" &>/dev/null; then
                    # Profile exists - update password and reconnect
                    nmcli connection modify "$SSID" wifi-sec.psk "$PASSWORD" && \
                    nmcli connection up "$SSID"
                else
                    # No profile - create new connection
                    nmcli dev wifi connect "$SSID" password "$PASSWORD"
                fi
            `]
        })
        connectionTimeoutTimer.restart(); // Start timeout
    }

    function cancelConnection(): void {
        if (root.wifiConnectTarget) {
            root.wifiConnectTarget.askingPassword = false;
            root.wifiConnectTarget.connectionError = "";
        }
        connectionTimeoutTimer.stop();
        connectProc.signal(15); // SIGTERM
        changePasswordProc.signal(15);
        root.wifiConnectTarget = null;
    }

    Process {
        id: enableWifiProc
    }

    Process {
        id: connectProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: SplitParser {
            onRead: line => {
                // print(line)
                getNetworks.running = true
            }
        }
        stderr: SplitParser {
            onRead: line => {
                // print("err:", line)
                if (line.includes("Secrets were required") && root.wifiConnectTarget) {
                    root.wifiConnectTarget.askingPassword = true
                }
            }
        }
        // Only for a network that plausibly wants one: a failure alone also
        // covers a network that is just out of range, which needs no password.
        onExited: (exitCode, exitStatus) => {
            const target = root.wifiConnectTarget;
            if (target && exitCode !== 0 && !target.askingPassword)
                target.askingPassword = target.isSecure && !target.isSaved;
            root.wifiConnectTarget = null
        }
        // onExited never fires if the command cannot start at all.
        onRunningChanged: {
            if (!running && root.wifiConnectTarget)
                root.wifiConnectTarget = null;
        }
    }

    Process {
        id: disconnectProc
        stdout: SplitParser {
            onRead: getNetworks.running = true
        }
    }

    Process {
        id: forgetProc
        onExited: {
            // Refresh saved connections and network list after deletion
            getSavedConnections.running = true;
        }
    }

    Process {
        id: changePasswordProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stderr: SplitParser {
            onRead: line => {
                // Capture common error messages
                if (root.wifiConnectTarget) {
                    if (line.includes("Secrets were required") || line.includes("No secrets")) {
                        root.wifiConnectTarget.connectionError = "Wrong password";
                        root.wifiConnectTarget.askingPassword = true;
                    } else if (line.includes("Not authorized") || line.includes("not authorized")) {
                        root.wifiConnectTarget.connectionError = "Not authorized";
                    } else if (line.includes("No network")) {
                        root.wifiConnectTarget.connectionError = "Network not found";
                    } else if (line.includes("timeout") || line.includes("Timeout")) {
                        root.wifiConnectTarget.connectionError = "Connection timed out";
                    }
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            connectionTimeoutTimer.stop();
            if (exitCode === 0 && root.wifiConnectTarget) {
                // Success - clear any error
                root.wifiConnectTarget.connectionError = "";
            }
            // Refresh networks after connection attempt
            getNetworks.running = true;
            root.wifiConnectTarget = null;
        }
    }

    Timer {
        id: connectionTimeoutTimer
        interval: 30000 // 30 seconds timeout
        onTriggered: {
            if (root.wifiConnectTarget) {
                root.wifiConnectTarget.connectionError = "Connection timed out";
                root.wifiConnectTarget.askingPassword = false;
            }
            changePasswordProc.signal(15); // SIGTERM
            root.wifiConnectTarget = null;
        }
    }

    Process {
        id: rescanProcess
        command: root.frameAdapterPresent
            ? ["sh", "-c", "for i in \"$@\"; do nmcli dev wifi list --rescan yes ifname \"$i\" > /dev/null & done; wait", "sh"].concat(root.scanDevices)
            : ["nmcli", "dev", "wifi", "list", "--rescan", "yes"]
        // Output unused: getNetworks reads the fields this service wants once
        // per scan, so the list is not rebuilt once per network in range.
        onExited: {
            wifiScanning = false;
            getNetworks.running = true;
        }
    }

    // Status update
    function update() {
        updateStatus.running = true;
    }

    Process {
        id: subscriber
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: root.update()
        }
    }

    function applyStatus(text) {
        const parts = text.split(/^--(?:devices|active|connectivity)--$/m);
        const adapters = (parts[0] ?? "").split("\n").filter(name => name.length > 0);
        const devices = Rates.terseRows(parts[1]).map(f => ({ device: f[0], type: f[1] ?? "", state: f[2] ?? "", connection: f[3] ?? "" }));
        const [connectivity, radio] = Rates.terseRows(parts[3])[0] ?? []; // none, limited, full
        root.wifiEnabled = radio === "enabled";
        const isAdapter = name => adapters.includes(name);
        const wifiDevices = devices.filter(d => d.type === "wifi");
        const ownCards = wifiDevices.filter(d => !isAdapter(d.device)).map(d => d.device);
        const frameLink = wifiDevices.filter(d => d.connection === root.frameProfileName).map(d => d.device);
        const hidden = wifiDevices.filter(d => ownCards.length > 0 && isAdapter(d.device)
            && (d.connection === "" || frameLink.includes(d.device))).map(d => d.device);
        const ignored = name => frameLink.includes(name) || hidden.includes(name);
        const scanDevices = wifiDevices.filter(d => !ignored(d.device)).map(d => d.device);
        if (scanDevices.join(" ") !== root.scanDevices.join(" "))
            root.scanDevices = scanDevices;

        const firstStatus = !root.devicesKnown;
        if (firstStatus || adapters.join(" ") !== root.frameAdapters.join(" ")
                || frameLink.join(" ") !== root.frameLinkDevices.join(" ")
                || hidden.join(" ") !== root.hiddenWifiDevices.join(" ")) {
            root.frameAdapters = adapters;
            root.frameLinkDevices = frameLink;
            root.hiddenWifiDevices = hidden;
            root.devicesKnown = true;
            root.applyScan();
            // Steam made its profile after the saved list was read, as on a first pairing.
            if (frameLink.length > 0 && !root.frameProfile)
                getSavedConnections.running = true;
        }
        // The first list waits for this, since it must not scan when a Frame adapter is in.
        if (firstStatus)
            getNetworks.running = true;

        // The best state of any card wins, so a second card that is idle or
        // retrying cannot cover a connected one.
        const rank = ["disabled", "disconnected", "connecting", "connected"];
        let best = -1;
        for (const d of wifiDevices) {
            if (ignored(d.device))
                continue;
            const state = d.state.includes("disconnected") ? "disconnected"
                : d.state.includes("connected") ? "connected"
                : d.state.includes("connecting") ? "connecting"
                : d.state.includes("unavailable") ? "disabled" : "";
            best = Math.max(best, rank.indexOf(state));
        }
        let wifiStatus = best >= 0 ? rank[best] : "disconnected";
        if (wifiStatus === "connected" && connectivity === "limited")
            wifiStatus = "limited";
        root.wifiStatus = wifiStatus;
        root.wifi = wifiStatus === "connected";
        root.ethernet = devices.some(d => d.type === "ethernet" && d.state.includes("connected"));

        const connections = Rates.parseConnections(parts[2])
            .filter(c => c.name !== root.frameProfileName && !ignored(c.device));
        const ownWifi = connections.find(c => ownCards.includes(c.device));
        const first = connections[0];
        root.networkName = (first && isAdapter(first.device) && ownWifi ? ownWifi.name : first?.name) ?? "";
    }

    // One pass for status and name, so both judge the same devices.
    Process {
        id: updateStatus
        running: true
        command: ["sh", "-c", "for d in /sys/class/net/*; do [ -r \"$d/device/uevent\" ] || continue; "
            + "while read -r l; do case \"$l\" in PRODUCT=28de/2432/*) echo \"${d##*/}\" ;; esac; done < \"$d/device/uevent\"; done; "
            + "echo --devices--; nmcli -t -f DEVICE,TYPE,STATE,CONNECTION d status; "
            + "echo --active--; nmcli -t -f DEVICE,TYPE,NAME c show --active; "
            + "echo --connectivity--; nmcli -t -f CONNECTIVITY,WIFI g"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: root.applyStatus(this.text)
        }
    }

    // Fetch saved Wi-Fi connection names
    Process {
        id: getSavedConnections
        running: true
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                const savedNames = new Set();
                text.trim().split("\n").forEach(line => {
                    const parts = line.split(":");
                    if (parts[1] === "802-11-wireless") {
                        savedNames.add(parts[0]);
                    }
                });
                root.savedConnectionNames = savedNames;
                root.syncFrameProfile();
                // Redone from the last scan: asking nmcli again could start a scan.
                root.applyScan();
            }
        }
    }

    function syncFrameProfile() {
        const saved = root.savedConnectionNames.has(root.frameProfileName);
        if (saved)
            getFrameSsid.running = true;
        if (saved && !root.frameProfile) {
            // The headset's hotspot is on 6 GHz, where Wi-Fi allows only WPA3.
            root.frameProfile = apComp.createObject(root, {
                lastIpcObject: { active: false, strength: 0, frequency: 0, ssid: root.frameProfileName, bssid: "", security: "WPA3", isSaved: true }
            });
        } else if (!saved && root.frameProfile) {
            const gone = root.frameProfile;
            root.frameProfile = null;
            gone.destroy();
        }
    }

    Process {
        id: getFrameSsid
        command: ["nmcli", "-g", "802-11-wireless.ssid", "connection", "show", "id", root.frameProfileName]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                const ssid = (Rates.terseRows(this.text)[0] ?? [""])[0];
                if (ssid.length > 0 && ssid !== root.frameSsid) {
                    root.frameSsid = ssid;
                    root.applyScan();
                }
            }
        }
    }

    // Networks only a hidden Frame adapter sees are left out, and so is the
    // headset's hotspot whichever card sees it, since only Steam can join it.
    function applyScan() {
        if (!root.devicesKnown)
            return;
        const hotspots = new Set(root.scanRows.filter(n => n.active && root.frameLinkDevices.includes(n.device)).map(n => n.ssid));
        if (root.frameSsid.length > 0)
            hotspots.add(root.frameSsid);
        const allNetworks = root.scanRows
            .filter(n => n.ssid && n.ssid.length > 0 && !root.hiddenWifiDevices.includes(n.device) && !hotspots.has(n.ssid))
            .map(n => Object.assign({}, n, {
                onFrameAdapter: root.frameAdapters.includes(n.device),
                isSaved: root.savedConnectionNames.has(n.ssid)
            }));

        // Group networks by SSID and prioritize connected ones
        const networkMap = new Map();
        for (const network of allNetworks) {
            const existing = networkMap.get(network.ssid);
            if (!existing) {
                networkMap.set(network.ssid, network);
            } else {
                // Prioritize active/connected networks
                if (network.active && !existing.active) {
                    networkMap.set(network.ssid, network);
                } else if (!network.active && !existing.active) {
                    // If both are inactive, keep the one with better signal
                    if (network.strength > existing.strength) {
                        networkMap.set(network.ssid, network);
                    }
                }
                // If existing is active and new is not, keep existing
            }
        }

        const wifiNetworks = Array.from(networkMap.values());

        const rNetworks = root.wifiNetworks;

        // Matched by name, since the list above is one entry per name. Radio
        // and band change whenever the strongest radio does, and matching on
        // them would rebuild the object, taking the password prompt with it.
        const stillThere = ssid => wifiNetworks.some(n => n.ssid === ssid);
        // A network being joined stays until it is done with.
        const inUse = ap => ap.askingPassword || ap === root.wifiConnectTarget;

        const gone = rNetworks.filter(rn => !stillThere(rn.ssid) && !inUse(rn));
        for (const network of gone)
            rNetworks.splice(rNetworks.indexOf(network), 1).forEach(n => n.destroy());

        for (const network of wifiNetworks) {
            const match = rNetworks.find(n => n.ssid === network.ssid);
            if (match) {
                match.lastIpcObject = network;
            } else {
                rNetworks.push(apComp.createObject(root, {
                    lastIpcObject: network
                }));
            }
        }

        root.reorderNetworks();
    }

    Process {
        id: getNetworks
        // --rescan auto scans every card once the list is 30 s old, the Frame
        // adapter included, so it is off while one is plugged in.
        property string rescan: "auto"
        command: ["nmcli", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY,DEVICE", "d", "w", "list", "--rescan", root.frameAdapterPresent ? "no" : getNetworks.rescan]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                const PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED";
                const rep = new RegExp("\\\\:", "g");
                const rep2 = new RegExp(PLACEHOLDER, "g");

                root.scanRows = text.trim().split("\n").map(n => {
                    const net = n.replace(rep, PLACEHOLDER).split(":");
                    return {
                        active: net[0] === "yes",
                        strength: parseInt(net[1]),
                        frequency: parseInt(net[2]),
                        ssid: net[3],
                        bssid: net[4]?.replace(rep2, ":") ?? "",
                        security: net[5] || "",
                        device: net[6] ?? ""
                    };
                });
                root.applyScan();
            }
        }
    }

    Component {
        id: apComp

        WifiAccessPoint {}
    }
}
