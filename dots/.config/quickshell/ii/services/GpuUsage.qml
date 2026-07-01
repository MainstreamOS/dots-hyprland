pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // dGPU Properties
    property string dGpuName: ""
    property string dGpuVendor: ""
    property bool dGpuAvailable: false
    property double dGpuUsage: 0
    property double dGpuVramUsage: 0
    property double dGpuTemperature: 0
    property double dGpuVramUsedGB: 0
    property double dGpuVramTotalGB: 0
    property double dGpuPower: 0
    property double dGpuPowerLimit: 0
    property double dGpuFanUsage: 0
    property double dGpuFanRpm: 0
    property double dGpuTempJunction: 0
    property double dGpuTempMem: 0

    // iGPU Properties
    property string iGpuName: ""
    property string iGpuVendor: ""
    property bool iGpuAvailable: false
    property double iGpuUsage: 0
    property double iGpuVramUsage: 0
    property double iGpuTemperature: 0
    property double iGpuVramUsedGB: 0
    property double iGpuVramTotalGB: 0

    // Display strings
    property string maxAvailableIGpuString: "\n" + iGpuName
    property string maxAvailableDGpuString: "\n" + dGpuName

    // History for graphing
    property list<real> iGpuUsageHistory: []
    property list<real> dGpuUsageHistory: []
    readonly property int historyLength: Config?.options.resources.historyLength ?? 60

    function updateiGpuUsageHistory() {
        iGpuUsageHistory = [...iGpuUsageHistory, iGpuUsage]
        if (iGpuUsageHistory.length > historyLength) {
            iGpuUsageHistory.shift()
        }
    }

    function updatedGpuUsageHistory() {
        dGpuUsageHistory = [...dGpuUsageHistory, dGpuUsage]
        if (dGpuUsageHistory.length > historyLength) {
            dGpuUsageHistory.shift()
        }
    }

    // Poll only while something actually displays the data: the bar resources
    // widget (with a GPU layout selected) or the overlay resources widget
    // (open or pinned). Mirrors the users' own Loader/visible gates.
    readonly property bool barWatching: Config.options.bar.resources.enable
        && Config.options.bar.resources.gpuLayout !== -1
        && GlobalStates.barOpen && !GlobalStates.screenLocked
    readonly property bool overlayWatching: Persistent.states.overlay.open.includes("resources")
        && (GlobalStates.overlayOpen || Persistent.states.overlay.resources.pinned)

    Timer {
        interval: Config.options?.resources?.updateInterval ?? 3000
        running: (Config.options?.resources?.enableGpu !== false)
            && (root.barWatching || root.overlayWatching)
            && (root.iGpuAvailable || root.dGpuAvailable)
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root.iGpuAvailable) iGpuinfoProc.running = true;
            if (root.dGpuAvailable) dGpuinfoProc.running = true;
        }
    }

    Process {
        id: dGpuinfoProc
        command: ["bash", "-c", `${Directories.scriptPath}/gpu/get_dgpuinfo.sh`.replace(/file:\/\//, "")]
        running: true
        environment: {
            "AMD_GPU_CARD": Config.options?.resources?.gpu?.dgpuCard || "",
            "INTEL_GPU_CARD": Config.options?.resources?.gpu?.dgpuCard || ""
        }

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text)

                    // Empty object means no GPU detected
                    dGpuAvailable = Object.keys(data).length > 0

                    if (dGpuAvailable) {
                        dGpuVendor = data.vendor || ""
                        dGpuName = Config.options?.resources?.gpu?.dgpuName || data.name || "dGPU"
                        dGpuUsage = (data.usagePercent ?? 0) / 100
                        dGpuVramUsedGB = data.vramUsedGB ?? 0
                        dGpuVramTotalGB = data.vramTotalGB ?? 0
                        dGpuVramUsage = dGpuVramTotalGB > 0 ? (dGpuVramUsedGB / dGpuVramTotalGB) : 0

                        dGpuTemperature = data.tempEdgeC ?? 0
                        dGpuTempJunction = data.tempJunctionC ?? 0
                        dGpuTempMem = data.tempMemC ?? 0

                        dGpuFanRpm = data.fanRpm ?? 0
                        dGpuFanUsage = data.fanPercent ?? 0

                        dGpuPower = data.powerW ?? 0
                        dGpuPowerLimit = data.powerLimitW ?? 0

                        maxAvailableDGpuString = "\n" + dGpuName

                    }
                } catch (e) {
                    console.error("Failed to parse dGPU JSON:", e, "Raw output:", this.text)
                    dGpuAvailable = false
                }

                // Update history after data is processed
                root.updatedGpuUsageHistory()
            }
        }
    }

    Process {
        id: iGpuinfoProc
        command: ["bash", "-c", `${Directories.scriptPath}/gpu/get_igpuinfo.sh`.replace(/file:\/\//, "")]
        running: true
        environment: {
            "AMD_GPU_CARD": Config.options?.resources?.gpu?.igpuCard || "",
            "INTEL_GPU_CARD": Config.options?.resources?.gpu?.igpuCard || ""
        }

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text)

                    // Empty object means no GPU detected
                    iGpuAvailable = Object.keys(data).length > 0

                    if (iGpuAvailable) {
                        iGpuVendor = data.vendor || ""
                        iGpuName = Config.options?.resources?.gpu?.igpuName || data.name || "iGPU"

                        iGpuUsage = (data.usagePercent ?? 0) / 100
                        iGpuVramUsedGB = data.vramUsedGB ?? 0
                        iGpuVramTotalGB = data.vramTotalGB ?? 0
                        iGpuVramUsage = iGpuVramTotalGB > 0 ? (iGpuVramUsedGB / iGpuVramTotalGB) : 0

                        iGpuTemperature = data.tempEdgeC ?? 0
                    }
                } catch (e) {
                    console.error("Failed to parse iGPU JSON:", e, "Raw output:", this.text)
                    iGpuAvailable = false
                }

                // Update history after data is processed
                root.updateiGpuUsageHistory()
            }
        }
    }
}
