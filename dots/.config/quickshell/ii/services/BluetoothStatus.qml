pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property BluetoothDevice firstActiveDevice: Bluetooth.defaultAdapter?.devices.values.find(device => device.connected) ?? null
    readonly property int activeDeviceCount: Bluetooth.defaultAdapter?.devices.values.filter(device => device.connected).length ?? 0
    readonly property bool connected: Bluetooth.devices.values.some(d => d.connected)

    // BlueZ restores the adapter state at login but does not request a new
    // connection to remembered devices. Ask trusted audio devices once during
    // shell startup, after bluetoothd has had a chance to populate the device
    // list. Input devices must manage their own reconnects.

    function reconnectTrustedAudioDevicesAtStartup() {
        startupReconnectTimer.restart();
    }

    function isAudioDevice(device) {
        return (device.icon ?? "").toLowerCase().includes("audio");
    }

    Timer {
        id: startupReconnectTimer
        interval: 4000
        repeat: false

        onTriggered: {
            for (const device of Bluetooth.devices.values) {
                if (device.trusted && isAudioDevice(device) && !device.connected)
                    device.connect();
            }
        }
    }

    // The order devices were first seen in, so a list of them can hold still
    // while a scan keeps turning up more.
    //
    // Deliberately not announced when it grows. The only thing that reads it is
    // the sort below, which runs inside the same list this is filled from — so
    // saying it changed would tell that list to build itself again, and building
    // it is what fills this in the first place. Every newly seen address would
    // start the round again, and while a scan is running they arrive constantly.
    // Nothing outside that list looks at this, so nothing needs telling; the
    // sort is reading what was recorded moments earlier in its own run.
    property var discoveryOrder: ({})
    property int discoveryCounter: 0

    function trackDiscoveryOrder(devices) {
        for (const d of devices) {
            const addr = d.address;
            if (addr && !(addr in discoveryOrder))
                discoveryOrder[addr] = discoveryCounter++;
        }
    }

    function sortFunction(a, b) {
        // Ones with meaningful names before MAC addresses
        const macRegex = /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/;
        const aIsMac = macRegex.test(a.name);
        const bIsMac = macRegex.test(b.name);
        if (aIsMac !== bIsMac)
            return aIsMac ? 1 : -1;

        // Alphabetical by name
        return a.name.localeCompare(b.name);
    }

    function discoveryOrderSort(a, b) {
        const aOrder = discoveryOrder[a.address] ?? Number.MAX_SAFE_INTEGER;
        const bOrder = discoveryOrder[b.address] ?? Number.MAX_SAFE_INTEGER;
        return aOrder - bOrder;
    }

    property list<var> connectedDevices: Bluetooth.devices.values.filter(d => d.connected).sort(sortFunction)
    property list<var> pairedButNotConnectedDevices: Bluetooth.devices.values.filter(d => d.paired && !d.connected).sort(sortFunction)
    property list<var> unpairedDevices: {
        trackDiscoveryOrder(Bluetooth.devices.values);
        return Bluetooth.devices.values.filter(d => !d.paired && !d.connected).sort(discoveryOrderSort);
    }
    property list<var> friendlyDeviceList: [
        ...connectedDevices,
        ...pairedButNotConnectedDevices,
        ...unpairedDevices
    ]
}
