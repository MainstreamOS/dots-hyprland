pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    readonly property int stateIdle: 0
    readonly property int stateSending: 1
    readonly property int stateSent: 2
    readonly property int stateError: 3

    property var devices: []
    property bool discovering: false

    property int state: root.stateIdle
    property real progressFraction: 0
    property string lastError: ""
    property string currentSessionId: ""
    property var currentDevice: null

    signal completed()
    signal failed(string message)

    // Discovery is driven by the binding on discoverProc.running below — it
    // runs continuously while the file-transfer picker is visible. This
    // function just clears the cached device list so the UI shows a fresh
    // sweep; the running discoverProc immediately re-populates it.
    function refreshDevices() {
        root.devices = [];
    }

    function send(device, files) {
        if (sendProc.running) return false;
        if (!device || !files || files.length === 0) return false;
        root.state = root.stateSending;
        root.progressFraction = 0;
        root.currentSessionId = "";
        root.lastError = "";
        root.currentDevice = device;
        const protocol = device.protocol || "http";
        let cmd = ["python3",
            FileUtils.trimFileProtocol(`${Directories.scriptPath}/localsend/send.py`),
            String(protocol), String(device.address), String(device.port)];
        for (const f of files) cmd.push(String(f));
        sendProc.command = cmd;
        sendProc.running = true;
        return true;
    }

    function cancel() {
        if (sendProc.running) sendProc.running = false;
        root.state = root.stateIdle;
        root.progressFraction = 0;
        root.lastError = "";
    }

    function reset() {
        root.state = root.stateIdle;
        root.progressFraction = 0;
        root.lastError = "";
        root.currentSessionId = "";
        root.currentDevice = null;
    }

    // Discovery runs continuously while the device picker is on screen and
    // we're not actively sending. The script keeps a UDP multicast listener
    // open and broadcasts an announce every 2s, so devices accumulate as
    // they reply (catches the case where a phone's announce missed the
    // initial 2s window).
    Process {
        id: discoverProc
        command: ["python3",
            FileUtils.trimFileProtocol(`${Directories.scriptPath}/localsend/discover.py`)]
        running: GlobalStates.mediaTransferActive && root.state === root.stateIdle
        onRunningChanged: {
            root.discovering = running;
            if (running) {
                // Fresh sweep each time discovery activates so a stale list
                // from a prior session doesn't leak into the new one.
                root.devices = [];
            }
        }
        stdout: SplitParser {
            onRead: (line) => {
                const trimmed = line.trim();
                if (!trimmed) return;
                try {
                    const dev = JSON.parse(trimmed);
                    let next = root.devices.slice();
                    next.push(dev);
                    root.devices = next;
                } catch (e) {
                    console.warn("[LocalSend] discovery parse error:", trimmed, e);
                }
            }
        }
    }

    Process {
        id: sendProc
        command: []
        running: false
        stdout: SplitParser {
            onRead: (line) => {
                const trimmed = line.trim();
                if (!trimmed) return;
                if (trimmed.startsWith("SESSION:")) {
                    root.currentSessionId = trimmed.slice(8);
                } else if (trimmed.startsWith("PROGRESS:")) {
                    const parts = trimmed.slice(9).split(":");
                    const sent = parseInt(parts[0]);
                    const total = parseInt(parts[1]);
                    if (Number.isFinite(sent) && Number.isFinite(total) && total > 0) {
                        root.progressFraction = Math.max(0, Math.min(1, sent / total));
                    }
                } else if (trimmed === "ALL_DONE") {
                    root.progressFraction = 1.0;
                    root.state = root.stateSent;
                    root.completed();
                } else if (trimmed.startsWith("ERROR:")) {
                    root.lastError = trimmed.slice(6);
                    root.state = root.stateError;
                    root.failed(root.lastError);
                } else if (trimmed.startsWith("FILE_DONE:")) {
                    // No-op for now.
                }
            }
        }
        stderr: SplitParser {
            onRead: (line) => console.warn("[LocalSend.send]", line)
        }
        onExited: (exitCode, exitStatus) => {
            if (root.state === root.stateSending) {
                root.lastError = `process exited (code ${exitCode})`;
                root.state = root.stateError;
                root.failed(root.lastError);
            }
        }
    }
}
