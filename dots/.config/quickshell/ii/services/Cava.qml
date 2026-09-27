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

    // Visualizers that come and go with what is on screen, such as the one
    // on the sidebar's media page, count themselves in here while they are
    // shown. They only want bars while the music is actually playing.
    property int viewers: 0
    function addViewer() {
        root.viewers += 1;
    }
    function removeViewer() {
        root.viewers = Math.max(0, root.viewers - 1);
    }

    Process {
        id: cavaProc
        running: (Config.options.background.widgets.visualizer.enable
            && MprisController.activePlayer !== null)
            || (root.viewers > 0 && (MprisController.activePlayer?.isPlaying ?? false))
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
