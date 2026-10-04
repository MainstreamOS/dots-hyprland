pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import "network-rates.js" as Rates

/**
 * Live download and upload speeds for the bar's network widget, and the
 * details its hover card shows. Read it from the bar alone: Settings and the
 * Welcome app keep a GlobalStates whose bar is never put away, so reading it
 * there would start the polling in those processes too.
 */
Singleton {
    id: root

    // Bytes per second, over every link with hardware behind it.
    property real downloadRate: 0
    property real uploadRate: 0

    // The connection traffic goes out by, as last asked.
    property string connectionName: ""
    property string ipAddress: ""
    property bool onWifi: false
    property int wifiSignal: -1

    // Interfaces with hardware behind them, or null until the first answer.
    property var physical: null
    property string interfaceNames: ""
    property var lastReading: null

    // Poll only while a bar holds the widget. The bars share one layout
    // and are loaded on these same conditions, so no widget has to sign in.
    // A slot a narrow screen hides still counts: telling it apart would cost
    // more than one small read a second.
    readonly property bool watching: ObjectUtils.layoutHasEnabledWidget(Config.options.bar.layout, "network")
        && GlobalStates.barOpen && !GlobalStates.screenLocked

    function formatRate(bytesPerSecond) {
        return Rates.formatRate(bytesPerSecond);
    }

    function formatRateShort(bytesPerSecond) {
        return Rates.formatRateShort(bytesPerSecond);
    }

    // Asked by the hover card rather than kept up in the background: an
    // address or a signal only matters while someone is reading it.
    function refreshDetails() {
        detailsProc.running = true;
    }

    function sample(text) {
        if (!root.watching)
            return;
        const counters = Rates.parseCounters(text);
        const names = Object.keys(counters).sort().join(" ");
        if (names !== root.interfaceNames) {
            root.interfaceNames = names;
            physicalProc.running = true;
        }
        root.lastReading = Rates.advance(root.lastReading, counters, Date.now(),
            Rates.countedInterfaces(counters, root.physical));
        root.downloadRate = root.lastReading.download;
        root.uploadRate = root.lastReading.upload;
    }

    Timer {
        // Every second rather than at the resources interval: a speed shown
        // three seconds late is the speed of something already finished.
        interval: 1000
        running: root.watching
        repeat: true
        triggeredOnStart: true
        onTriggered: netDev.reload()
    }

    FileView {
        id: netDev
        path: "/proc/net/dev"
        // reload() hands back the previous read until the new one lands, so
        // the sample is taken here, timed by when the numbers arrived.
        onLoaded: root.sample(netDev.text())
    }

    // Read again whenever an interface comes or goes.
    Process {
        id: physicalProc
        command: ["sh", "-c", "for i in /sys/class/net/*; do [ -e \"$i/device\" ] && echo \"${i##*/}\"; done"]
        stdout: StdioCollector {
            onStreamFinished: root.physical = text.split("\n").filter(name => name !== "")
        }
    }

    Process {
        id: detailsProc
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        // --rescan no reads what NetworkManager already knows; hovering must
        // never set off a Wi-Fi scan.
        command: ["sh", "-c", "ip -j -4 route show default; echo ---; ip -j -6 route show default; echo ---; ip -j addr show scope global; echo ---; nmcli -t -f DEVICE,TYPE,NAME connection show --active; echo ---; nmcli -t -f IN-USE,SIGNAL,DEVICE device wifi list --rescan no"]
        stdout: StdioCollector {
            onStreamFinished: {
                const details = Rates.readDetails(text, root.physical);
                root.connectionName = details.name;
                root.ipAddress = details.address;
                root.onWifi = details.wifi;
                root.wifiSignal = details.signal;
            }
        }
    }
}
