import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

// One voice note through scripts/phone/voice-recorder.py. A stopped note is
// handed back with the target it was started for, so a view that moved on
// cannot send it elsewhere; a canceled note is deleted.
Process {
    id: root
    property bool recording: false
    property int seconds: 0
    property var target: null
    property bool sendOnStop: false
    property string recordedPath: ""
    signal finished(string path, var target)

    command: ["python3", "-u", FileUtils.trimFileProtocol(`${Directories.scriptPath}/phone/voice-recorder.py`)]

    function start(target): void {
        root.target = target;
        root.sendOnStop = false;
        root.recordedPath = "";
        root.seconds = 0;
        root.recording = true;
        root.running = true;
    }
    function stopAndSend(): void {
        if (!root.recording) return;
        root.sendOnStop = true;
        root.running = false;
    }
    function cancel(): void {
        if (!root.recording) return;
        root.sendOnStop = false;
        root.running = false;
        root.recording = false;
    }

    stdout: SplitParser {
        onRead: line => {
            const trimmed = line.trim();
            if (trimmed.startsWith("RECORDING:")) {
                const sec = parseInt(trimmed.substring(10));
                if (!isNaN(sec)) root.seconds = sec;
            } else if (trimmed.startsWith("DONE:")) {
                root.recordedPath = trimmed.substring(5).trim();
            }
        }
    }
    onExited: exitCode => {
        root.recording = false;
        const path = root.recordedPath;
        if (root.sendOnStop && path.length > 0) root.finished(path, root.target);
        else if (path.length > 0) Quickshell.execDetached(["rm", "-f", "--", path]);
        root.sendOnStop = false;
        root.recordedPath = "";
    }
}
