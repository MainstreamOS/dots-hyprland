import QtQuick
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions

Process {
    id: root

    required property var target
    property string context: ""
    property int textLimit: 50000
    property string requestedContext: ""
    property string previousText: ""
    property int selectionStart: 0
    property int selectionEnd: 0

    signal filesReady(var paths)
    signal failed(string message)
    signal truncated()

    function request(plainText: bool): void {
        if (root.running || !root.target.enabled || root.target.readOnly)
            return;
        root.requestedContext = root.context;
        root.previousText = root.target.text;
        root.selectionStart = root.target.selectionStart;
        root.selectionEnd = root.target.selectionEnd;
        const args = ["python3", FileUtils.trimFileProtocol(`${Directories.scriptPath}/clipboard/paste.py`),
            "--cache", FileUtils.trimFileProtocol(Directories.cache), "--text-limit", String(root.textLimit)];
        if (plainText)
            args.push("--plain");
        root.exec(args);
    }

    stdout: StdioCollector {
        onStreamFinished: {
            if (root.requestedContext !== root.context || !root.target.enabled || root.target.readOnly)
                return;
            let result;
            try {
                result = JSON.parse(text);
            } catch (error) {
                root.failed(Translation.tr("Could not read the clipboard. Try copying it again."));
                return;
            }
            if (result.error) {
                root.failed(Translation.tr("Could not read the clipboard. Try copying it again."));
            } else if (result.files?.length > 0) {
                root.filesReady(result.files);
            } else if (typeof result.text === "string" && root.target.text === root.previousText
                && root.target.selectionStart === root.selectionStart && root.target.selectionEnd === root.selectionEnd) {
                // An edit or a moved cursor while the clipboard was being read
                // must not replace text at the old selection.
                if (root.selectionEnd > root.selectionStart)
                    root.target.remove(root.selectionStart, root.selectionEnd);
                root.target.insert(root.selectionStart, result.text);
                if (result.truncated)
                    root.truncated();
            }
        }
    }
}
