pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs.modules.common
import "PhoneIdentity.js" as Identity

/**
 * Calls over Bluetooth hands-free (PipeWire or oFono) and iPhone alerts
 * (ANCS), through scripts/phone/calls.py. KDE Connect events come from Phone.
 */
Singleton {
    id: root

    // Set while phone services are on, so calls reach the Dynamic Island or the bar's pop-ups.
    property bool alertsWanted: false
    property var calls: []
    property var messages: []
    property var notifications: []
    property var devices: []
    // A dormant watcher has no live calls. A newly started one reports after
    // it has queried the backends.
    readonly property bool ready: root.receivedSnapshot
        || (!watcher.wanted && (!root.alertsWanted || root.probeCompleted))
    property bool receivedSnapshot: false
    property bool probeCompleted: false
    property string error: ""
    property string dialNumber: ""
    property string dialError: ""
    readonly property bool dialing: dialProcess.running || dialConfirmation.running
    readonly property bool canDial: root.devices.some(d => d.backend !== "iPhone notification sharing")
    readonly property string helper: Quickshell.shellPath("scripts/phone/calls.py")
    readonly property bool pairedBluetoothPhone: Bluetooth.devices.values.some(device =>
        device.paired && String(device.icon ?? "").startsWith("phone"))
    readonly property string connectedPeers: Bluetooth.devices.values
        .filter(device => device.paired && device.connected).map(device => device.dbusPath).sort().join(" ")
    property bool telephonyAvailable: false

    // Some Bluetooth devices have no phone icon. Ask the actual backends
    // before starting a resident watcher, and recheck after profiles settle.
    onConnectedPeersChanged: if (probeTimer.running) probe.running = true
    Timer {
        id: probeTimer
        interval: 20000
        repeat: true
        triggeredOnStart: true
        running: Config.ready && root.alertsWanted && !root.pairedBluetoothPhone && !root.devices.length
        onTriggered: probe.running = true
    }
    Process {
        id: probe
        command: ["python3", root.helper, "available"]
        onExited: exitCode => {
            root.telephonyAvailable = exitCode === 0;
            root.probeCompleted = true;
        }
    }

    function dial(number): bool {
        if (root.dialing || root.calls.length) return false;
        const clean = String(number || "").trim();
        if (!clean) return false;
        root.dialNumber = clean;
        root.dialError = "";
        dialProcess.command = ["python3", root.helper, "dial", clean];
        dialConfirmation.restart();
        dialProcess.running = true;
        return true;
    }

    // Answer ("positive") or decline/hang up ("negative") a call or iPhone alert.
    function action(id, name): void {
        if (actionProcess.running || !id) return;
        actionProcess.command = ["python3", root.helper, "action", id, name];
        root.error = "";
        actionProcess.running = true;
    }

    onCallsChanged: if (root.calls.some(c => Identity.numberMatches(c.number, root.dialNumber))) dialConfirmation.stop()

    Timer {
        id: dialConfirmation
        interval: 20000
        onTriggered: {
            if (!root.calls.some(c => Identity.numberMatches(c.number, root.dialNumber)))
                root.dialError = Translation.tr("The phone has not confirmed the call. Check your phone before trying again.");
        }
    }
    Process {
        id: dialProcess
        stderr: SplitParser { onRead: data => console.warn("[Phone calls dial]", data) }
        onExited: exitCode => {
            if (exitCode !== 0 && !root.calls.some(c => Identity.numberMatches(c.number, root.dialNumber))) {
                dialConfirmation.stop();
                root.dialError = Translation.tr("Unable to start the call. Connect your phone over Bluetooth and try again.");
            }
        }
    }
    Process {
        id: actionProcess
        stderr: SplitParser { onRead: data => console.warn("[Phone calls action]", data) }
        onExited: exitCode => {
            if (exitCode === 2)
                root.error = Translation.tr("The phone did not respond in time. Check the call on your phone.");
            else if (exitCode !== 0)
                root.error = Translation.tr("Unable to complete this action. Check your phone connection and try again.");
        }
    }
    Process {
        id: watcher
        readonly property bool wanted: Config.ready && ((root.alertsWanted && (root.pairedBluetoothPhone || root.telephonyAvailable))
            || Phone.userRequested || root.dialing || root.calls.length > 0)
        running: wanted && !restart.running
        onStarted: root.receivedSnapshot = false
        command: ["python3", root.helper, "watch"]
        stdout: SplitParser {
            onRead: data => {
                try {
                    const value = JSON.parse(data);
                    // Each line carries the whole state; keep unchanged lists so their readers stay put.
                    for (const name of ["calls", "messages", "notifications", "devices"]) {
                        const next = value[name] ?? [];
                        if (JSON.stringify(next) !== JSON.stringify(root[name])) root[name] = next;
                    }
                    root.error = value.error ?? "";
                    root.receivedSnapshot = true;
                } catch (error) {
                    console.warn("[Phone calls] Invalid helper data:", error);
                }
            }
        }
        stderr: SplitParser { onRead: data => console.warn("[Phone calls]", data) }
        onExited: {
            root.calls = [];
            root.messages = [];
            root.notifications = [];
            root.devices = [];
            root.receivedSnapshot = true;
            if (wanted) {
                root.error = Translation.tr("Phone connection interrupted. Reconnecting…");
                restart.restart();
            }
        }
    }
    Timer { id: restart; interval: 5000 }
}
