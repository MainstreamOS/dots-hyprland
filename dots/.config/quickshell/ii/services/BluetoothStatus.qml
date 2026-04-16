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

    // Track the order in which devices are first discovered
    property var discoveryOrder: ({})
    property int discoveryCounter: 0

    function trackDiscoveryOrder(devices) {
        let changed = false;
        for (const d of devices) {
            const addr = d.address;
            if (addr && !(addr in discoveryOrder)) {
                discoveryOrder[addr] = discoveryCounter++;
                changed = true;
            }
        }
        if (changed)
            discoveryOrderChanged();
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
