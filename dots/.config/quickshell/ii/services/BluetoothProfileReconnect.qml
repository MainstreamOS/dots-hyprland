pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.modules.common

Scope {
    id: root
    required property var manager
    required property BluetoothDevice device
    property bool automaticCapable: !(device?.icon ?? "").startsWith("input-")
    readonly property bool automaticReady: manager?.profileReconnectReady && Persistent.ready
        && automaticCapable && device?.paired && device.trusted && !device.blocked
        && device.adapter?.enabled && !manager.reconnectPaused(device.address)
    property int attempts: 0
    property double lastAttempt: 0
    property bool manualRequest: false
    property bool cancelled: false
    readonly property int maxAttempts: 3
    readonly property var retryDelays: [5000, 15000]

    // Kept from creation: the device can already be gone when this is destroyed.
    property string watchedPath: ""
    Component.onCompleted: {
        watchedPath = device.dbusPath;
        manager.profileWatchers[watchedPath] = root;
    }
    Component.onDestruction: {
        if (manager.profileWatchers[watchedPath] === root) delete manager.profileWatchers[watchedPath];
    }
    onAutomaticReadyChanged: {
        if (automaticReady) {
            attempts = 0;
            schedule(500);
        } else cancel();
    }
    function cancel() {
        cancelled = true;
        retry.stop();
        connector.running = false;
    }
    function connectManually() {
        attempts = 0;
        manualRequest = true;
        cancelled = false;
        retry.stop();
        if (!connector.running) run();
    }
    function schedule(delay) {
        if (!automaticReady || connector.running || attempts >= maxAttempts) return;
        cancelled = false;
        manualRequest = false;
        retry.interval = delay;
        retry.restart();
    }
    function run() {
        if (connector.running || (!manualRequest && !automaticReady)) return;
        cancelled = false;
        attempts++;
        lastAttempt = Date.now();
        connector.command = ["python3", Quickshell.shellPath("scripts/bluetooth/connect-device.py"), device.dbusPath]
            .concat(manualRequest ? [] : ["--automatic"]);
        connector.running = true;
    }
    Connections {
        target: root.device
        function onConnectedChanged() {
            if (!root.device.connected) {
                // BlueZ handles link-loss reconnects. Do not turn an external
                // client's deliberate Disconnect into a new connection request.
                retry.stop();
            } else {
                // Heal an incoming control-only link before its idle timeout. A
                // link after a quiet minute gets a fresh attempt budget.
                if (Date.now() - root.lastAttempt >= 60000) root.attempts = 0;
                root.schedule(250);
            }
        }
        function onPairedChanged() {
            if (!root.device.paired) {
                root.cancel();
                root.manager.setReconnectPaused(root.device.address, false);
            }
        }
    }
    Timer { id: retry; onTriggered: root.run() }
    Process {
        id: connector
        stdout: SplitParser {
            onRead: data => {
                try { root.automaticCapable = JSON.parse(data).automatic; }
                catch (error) { console.warn("[Bluetooth profiles] Invalid connection result:", error); }
            }
        }
        stderr: SplitParser { onRead: data => console.warn("[Bluetooth profiles]", data) }
        onExited: exitCode => {
            if (root.cancelled) return;
            if (exitCode !== 0) root.schedule(root.retryDelays[Math.min(Math.max(0, root.attempts - 1), root.retryDelays.length - 1)]);
        }
    }
}
