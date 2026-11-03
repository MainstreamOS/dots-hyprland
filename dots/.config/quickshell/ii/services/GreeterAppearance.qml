pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    property int clockSize: 100
    property string error: ""
    property bool themeAvailable: false
    property bool helperAvailable: false
    readonly property bool available: themeAvailable && helperAvailable
    readonly property bool busy: applyDelay.running || writer.running
    property int confirmedSize: 100

    function readClockSize(text, fallback) {
        let section = "General";
        let value = fallback;
        for (const line of text.split(/\r?\n/)) {
            const header = line.match(/^\s*\[([^\]]+)\]\s*(?:[;#].*)?$/);
            if (header) section = header[1];
            const match = section === "General" ? line.match(/^\s*clockSize\s*=\s*(\d+)\s*$/) : null;
            if (match) value = Math.max(50, Math.min(200, Number(match[1])));
        }
        return value;
    }

    function readSettings() {
        root.themeAvailable = root.readClockSize(defaults.text(), -1) !== -1;
        if (root.busy) return;
        root.confirmedSize = root.readClockSize(overrides.text(), root.readClockSize(defaults.text(), 100));
        root.clockSize = root.confirmedSize;
    }

    function setClockSize(value) {
        if (!root.available || !Number.isFinite(value)) return;
        const percent = Math.round(Math.max(50, Math.min(200, value)));
        if (percent === root.clockSize && !root.error.length) return;
        root.clockSize = percent;
        root.error = "";
        applyDelay.restart();
    }

    function applyNext() {
        if (writer.running || root.clockSize === root.confirmedSize) return;
        root.error = "";
        writer.sentSize = root.clockSize;
        writer.command = ["pkexec", "/usr/local/bin/sddm-bg-helper", "--clock-size", String(writer.sentSize)];
        writer.running = true;
    }

    FileView {
        id: defaults
        path: "/usr/share/sddm/themes/pixie/theme.conf"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: Qt.callLater(root.readSettings)
        onLoadFailed: Qt.callLater(root.readSettings)
    }
    FileView {
        id: overrides
        path: "/usr/share/sddm/themes/pixie/theme.conf.user"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: Qt.callLater(root.readSettings)
        onLoadFailed: Qt.callLater(root.readSettings)
    }
    Process {
        command: ["/usr/local/bin/sddm-bg-helper", "--supports-clock-size"]
        running: true
        onExited: code => root.helperAvailable = code === 0
    }
    Timer {
        id: applyDelay
        interval: 250
        onTriggered: root.applyNext()
    }
    Process {
        id: writer
        property int sentSize: 100
        onExited: code => {
            if (code === 0) {
                root.confirmedSize = sentSize;
            } else {
                root.error = Translation.tr("Could not update the login clock size.");
                if (root.clockSize === sentSize) root.clockSize = root.confirmedSize;
            }
            if (root.clockSize !== root.confirmedSize && root.clockSize !== sentSize) {
                applyDelay.restart();
            } else {
                overrides.reload();
            }
        }
    }
}
