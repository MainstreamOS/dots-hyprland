pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Simple polled resource usage service with RAM, Swap, and CPU usage.
 */
Singleton {
    id: root
    property real memoryTotal: 1
    property real memoryFree: 0
    property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal
    property real swapTotal: 1
    property real swapFree: 0
    property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0
    property real cpuUsage: 0
    property double cpuFreqency: 0

    property var previousCpuStats
    property double cpuTemperature: 0

    property string maxAvailableMemoryString: kbToGbString(ResourceUsage.memoryTotal)
    property string maxAvailableSwapString: kbToGbString(ResourceUsage.swapTotal)
    property string maxAvailableCpuString: "--"

    readonly property int historyLength: Config?.options.resources.historyLength ?? 60
    property list<real> cpuUsageHistory: []
    property list<real> memoryUsageHistory: []
    property list<real> swapUsageHistory: []
    property real diskTotal: 1
    property real diskUsed: 0
    property real diskFree: 0
    property real diskUsedPercentage: diskTotal > 0 ? diskUsed / diskTotal : 0
    property list<real> diskUsageHistory: []

    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB";
    }

    function updateMemoryUsageHistory() {
        memoryUsageHistory = [...memoryUsageHistory, memoryUsedPercentage];
        if (memoryUsageHistory.length > historyLength) {
            memoryUsageHistory.shift();
        }
    }
    function updateSwapUsageHistory() {
        swapUsageHistory = [...swapUsageHistory, swapUsedPercentage];
        if (swapUsageHistory.length > historyLength) {
            swapUsageHistory.shift();
        }
    }
    function updateCpuUsageHistory() {
        cpuUsageHistory = [...cpuUsageHistory, cpuUsage];
        if (cpuUsageHistory.length > historyLength) {
            cpuUsageHistory.shift();
        }
    }

    function updateDiskUsageHistory() {
        diskUsageHistory = [...diskUsageHistory, diskUsedPercentage];
        if (diskUsageHistory.length > historyLength) {
            diskUsageHistory.shift();
        }
    }

    function updateHistories() {
        updateMemoryUsageHistory();
        updateSwapUsageHistory();
        updateCpuUsageHistory();
        updateDiskUsageHistory();
    }

    Process {
        id: diskProc
        command: ["sh", "-c", "df -k / | awk 'NR==2{print $2,$3,$4}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(" ").map(Number);
                if (parts.length >= 3 && parts[0] > 0) {
                    root.diskTotal = parts[0];
                    root.diskUsed = parts[1];
                    root.diskFree = parts[2];
                }
            }
        }
    }

    // Poll only while something actually displays the data: the bar resources
    // widget or the overlay resources widget (open or pinned). Mirrors the
    // users' own Loader/visible gates.
    readonly property bool barWatching: ObjectUtils.layoutHasEnabledWidget(Config.options.bar.layout, "resources")
        && GlobalStates.barOpen && !GlobalStates.screenLocked
    readonly property bool overlayWatching: Persistent.states.overlay.open.includes("resources")
        && (GlobalStates.overlayOpen || Persistent.states.overlay.resources.pinned)
    // The desktop resources widget is a third reader, hidden with the lock screen.
    readonly property bool desktopWatching: Config.options.background.widgets.resources.enable && !GlobalStates.screenLocked

    Timer {
        interval: Config.options?.resources?.updateInterval ?? 3000
        running: root.barWatching || root.overlayWatching || root.desktopWatching
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            // Reload files
            fileMeminfo.reload();
            fileStat.reload();
            fileCpuinfo.reload();

            // Parse memory and swap usage
            const textMeminfo = fileMeminfo.text();
            memoryTotal = Number(textMeminfo.match(/MemTotal: *(\d+)/)?.[1] ?? 1);
            memoryFree = Number(textMeminfo.match(/MemAvailable: *(\d+)/)?.[1] ?? 0);
            swapTotal = Number(textMeminfo.match(/SwapTotal: *(\d+)/)?.[1] ?? 1);
            swapFree = Number(textMeminfo.match(/SwapFree: *(\d+)/)?.[1] ?? 0);

            // Parse CPU usage
            const textStat = fileStat.text();
            const cpuLine = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/);
            if (cpuLine) {
                const stats = cpuLine.slice(1).map(Number);
                const total = stats.reduce((a, b) => a + b, 0);
                const idle = stats[3];

                if (previousCpuStats) {
                    const totalDiff = total - previousCpuStats.total;
                    const idleDiff = idle - previousCpuStats.idle;
                    cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0;
                }

                previousCpuStats = {
                    total,
                    idle
                };
            }

            // Parse CPU frequency
            const cpuInfo = fileCpuinfo.text();
            // The first tick can land before the file has been read.
            const cpuCoreFrequencies = (cpuInfo.match(/cpu MHz\s+:\s+(\d+\.\d+)\n/g) ?? []).map(x => Number(x.match(/\d+\.\d+/)));
            if (cpuCoreFrequencies.length > 0) {
                const cpuCoreFreqencyAvg = cpuCoreFrequencies.reduce((a, b) => a + b, 0) / cpuCoreFrequencies.length;
                cpuFreqency = cpuCoreFreqencyAvg / 1000;
            }
            

            //read cpu temp
            tempProc.running = true
            diskProc.running = true

            root.updateHistories();
        }
    }

    Process {
        id: findCpuMaxFreqProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        command: ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                root.maxAvailableCpuString = (parseFloat(outputCollector.text) / 1000).toFixed(0) + " GHz"
            }
        }
    }

    FileView {
        id: fileMeminfo
        path: "/proc/meminfo"
    }
    FileView {
        id: fileCpuinfo
        path: "/proc/cpuinfo"
    }
    FileView {
        id: fileStat
        path: "/proc/stat"
      }


    Process { // only run this once
      id: fileCreationtempProc
      running: true
      command: ["bash", "-c", `${Directories.scriptPath}/cpu/coretemp.sh`.replace(/file:\/\//, "")]
    }
    
      Process { // only run this once
      id: tempProc
      running: true
      command: ["bash", "-c", "cat /tmp/quickshell/coretemp"]
      stdout: StdioCollector {
        onStreamFinished: {
                cpuTemperature = Number(this.text) / 1000;

            }
        }

    }

}
