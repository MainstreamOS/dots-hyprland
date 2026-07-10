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

    readonly property bool receiveActive: receiveProc.running
    property bool receiveSessionActive: false
    property real receiveProgressFraction: 0
    property string receiveSender: ""
    property string receiveAlias: ""
    property string receiveError: ""
    property int receiveLastCount: 0
    readonly property string receiveDir: FileUtils.trimFileProtocol(Directories.downloads)

    signal completed()
    signal failed(string message)
    signal receiveCompleted(int fileCount)

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

    function startReceive() {
        if (receiveProc.running) return;
        _clearReceiveSession();
        root.receiveSender = "";
        root.receiveError = "";
        root.receiveLastCount = 0;
        receiveProc.running = true;
    }

    function stopReceive() {
        if (!receiveProc.running) return;
        receiveProc.running = false;
        _clearReceiveSession();
        root.receiveLastCount = 0;
    }

    function receiveClearDone() {
        root.receiveLastCount = 0;
    }

    function dismissReceiveError() {
        root.receiveError = "";
    }

    function _clearReceiveSession() {
        root.receiveSessionActive = false;
        root.receiveProgressFraction = 0;
    }

    function _parseFraction(payload) {
        const parts = payload.split(":");
        const done = parseInt(parts[0]);
        const total = parseInt(parts[1]);
        if (!Number.isFinite(done) || !Number.isFinite(total) || total <= 0) return -1;
        return Math.max(0, Math.min(1, done / total));
    }

    // Receiver runs only while the user arms it from the bar media widget.
    // Every incoming session is auto-accepted for as long as it runs; this
    // service only tracks state — the media popup reacts to it and owns
    // when the ReceivePanel is shown.
    Process {
        id: receiveProc
        command: ["python3",
            FileUtils.trimFileProtocol(`${Directories.scriptPath}/localsend/receive.py`),
            root.receiveDir]
        stdout: SplitParser {
            onRead: (line) => {
                const trimmed = line.trim();
                if (!trimmed) return;
                if (trimmed.startsWith("PROGRESS:")) {
                    const fraction = root._parseFraction(trimmed.slice(9));
                    if (fraction >= 0) root.receiveProgressFraction = fraction;
                } else if (trimmed.startsWith("READY:")) {
                    root.receiveAlias = trimmed.slice(6);
                } else if (trimmed.startsWith("SESSION:")) {
                    root.receiveSender = trimmed.slice(8);
                    root.receiveSessionActive = true;
                    root.receiveProgressFraction = 0;
                    root.receiveLastCount = 0;
                } else if (trimmed.startsWith("SESSION_DONE:")) {
                    root.receiveLastCount = parseInt(trimmed.slice(13)) || 0;
                    root._clearReceiveSession();
                    root.receiveCompleted(root.receiveLastCount);
                } else if (trimmed.startsWith("CANCELLED")) {
                    root._clearReceiveSession();
                } else if (trimmed.startsWith("ERROR:")) {
                    root._clearReceiveSession();
                    root.receiveError = trimmed.slice(6);
                }
            }
        }
        stderr: SplitParser {
            onRead: (line) => console.warn("[LocalSend.receive]", line)
        }
        onExited: (exitCode, exitStatus) => {
            root._clearReceiveSession();
        }
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
                    const fraction = root._parseFraction(trimmed.slice(9));
                    if (fraction >= 0) root.progressFraction = fraction;
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
