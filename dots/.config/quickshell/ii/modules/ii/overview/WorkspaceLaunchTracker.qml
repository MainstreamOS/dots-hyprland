import qs
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Scope {
    id: root
    property int pendingCount: 0
    property bool ready: false
    property bool keepAlive: GlobalStates.overviewOpen
    property var outbox: []
    property var commands: ({})
    property var windows: ({})
    signal windowResolved(string address, int workspace, int currentWorkspace)

    function send(message) {
        if (ready) worker.write(JSON.stringify(message) + "\n");
        else outbox = outbox.concat([message]);
    }

    function launch(entry, workspace) {
        if (!entry?.command?.length || workspace <= 0) return;
        const token = Quickshell.instanceId + "-" + Date.now() + "-" + Math.random().toString(36).slice(2);
        const parts = ["env", "MAINSTREAM_LAUNCH_ID=" + token].concat(Array.from(entry.command));
        const command = parts.map(p => "'" + String(p).replace(/'/g, "'\\''") + "'").join(" ");
        const lua = command.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n").replace(/\r/g, "\\r");
        commands[token] = `hl.dsp.exec_cmd("${lua}", { workspace = "${workspace} silent" })`;
        pendingCount++;
        send({ event: "launch", token, workspace, id: entry.id ?? "", startupClass: entry.startupClass ?? "",
            executable: entry.command[0] });
    }

    function classify(address) {
        if (!worker.running) return false;
        windows[address] = true;
        send({ event: "window", address });
        return true;
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen) {
                idle.stop();
                root.keepAlive = true;
            } else idle.restart();
        }
    }
    Timer { id: idle; interval: 1000; onTriggered: root.keepAlive = false }

    Process {
        id: worker
        command: ["python3", Quickshell.shellPath("scripts/overview/launch-tracker.py")]
        running: root.keepAlive || root.pendingCount > 0 || root.outbox.length > 0
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                let reply;
                try { reply = JSON.parse(line); }
                catch (error) { console.warn("Workspace launch tracker:", error); return; }
                if (reply.event === "ready") {
                    root.ready = true;
                    const queued = root.outbox;
                    root.outbox = [];
                    for (const message of queued) root.send(message);
                } else if (reply.event === "registered") {
                    const command = root.commands[reply.token];
                    delete root.commands[reply.token];
                    if (command) Hyprland.dispatch(command);
                } else if (reply.event === "count") {
                    root.pendingCount = reply.count;
                } else if (reply.event === "window") {
                    delete root.windows[reply.address];
                    root.windowResolved(reply.address, reply.workspace, reply.currentWorkspace);
                }
            }
        }
        onExited: (code, status) => root.workerExited(code)
        property bool didStart: false
        onStarted: didStart = true
        onRunningChanged: {
            if (running) didStart = false;
            else if (!didStart) Qt.callLater(() => {
                if (!worker.running) root.workerExited(-1);
            });
        }
    }

    function workerExited(code): void {
        root.ready = false;
        for (const address of Object.keys(root.windows)) root.windowResolved(address, 0, 0);
        root.windows = {};
        // Keep a failed helper from swallowing a launch or a dismiss.
        for (const command of Object.values(root.commands)) Hyprland.dispatch(command);
        root.commands = {};
        root.outbox = [];
        root.pendingCount = 0;
        if (code !== 0) console.warn("Workspace launch tracker exited:", code);
    }
}
