pragma Singleton

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

// Audio bars from cava for whatever is drawing a visualizer. The process
// runs only while a visualizer is enabled and something is playing, so an
// idle desktop never pays for it, and it is created on first use, so a
// shell without a visualizer never starts it at all.
Singleton {
    id: root
    property list<real> points: []

    Process {
        id: cavaProc
        running: Config.options.background.widgets.visualizer.enable
            && MprisController.activePlayer !== null
        onRunningChanged: {
            if (!cavaProc.running) root.points = [];
        }
        command: ["cava", "-p", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/cava/raw_output_config.txt`]
        stdout: SplitParser {
            onRead: data => {
                root.points = data.split(";").map(p => parseFloat(p.trim())).filter(p => !isNaN(p));
            }
        }
    }
}
