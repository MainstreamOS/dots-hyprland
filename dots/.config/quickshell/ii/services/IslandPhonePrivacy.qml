pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common

Singleton {
    id: root
    readonly property bool monitoring: Appearance.sizes.barIsIsland && Config.options.bar.island.phoneIntegration
        && Config.options.bar.island.suppressWhileStreaming
        && (Config.options.bar.island.suppressForDiscord || Config.options.bar.island.suppressForObs)
    property list<string> runningApps: []
    readonly property bool suppressed: monitoring && (
        (Config.options.bar.island.suppressForDiscord && runningApps.includes("discord"))
        || (Config.options.bar.island.suppressForObs && runningApps.includes("obs"))
        || ToplevelManager.toplevels.values.some(window => {
            const app = root.application(window.appId);
            return (app === "discord" && Config.options.bar.island.suppressForDiscord)
                || (app === "obs" && Config.options.bar.island.suppressForObs);
        }))

    function application(name) {
        const id = String(name || "").toLowerCase().replace(/\.desktop$/, "");
        if (/^(discord(?:-?(?:ptb|canary))?|com\.discordapp\.discord(?:ptb|canary)?)$/.test(id)) return "discord";
        if (/^(obs(?:-studio)?|com\.obsproject\.studio)$/.test(id)) return "obs";
        return "";
    }
    onMonitoringChanged: {
        if (monitoring) scan.running = true;
        else runningApps = [];
    }
    Component.onCompleted: if (monitoring) scan.running = true

    // A tray-only Discord instance has no toplevel. Native and Flatpak builds
    // use the same executable names; only poll while this protection is enabled.
    Timer {
        interval: 2000
        repeat: true
        running: root.monitoring
        onTriggered: if (!scan.running) scan.running = true
    }
    Process {
        id: scan
        command: ["pgrep", "-i", "-x", "-l", "discord|discord-?ptb|discord-?canary|obs|obs-studio"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.monitoring) return;
                root.runningApps = [...new Set(text.trim().split("\n")
                    .map(line => root.application(line.replace(/^\s*\d+\s+/, ""))).filter(app => app))];
            }
        }
    }
}
