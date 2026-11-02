.pragma library

function phones(devices) {
    return devices.filter(d => !d.type || d.type === "phone" || d.type === "tablet");
}

function selectedDevice(devices, current, preferred) {
    if (devices.some(d => d.id === current)) return current;
    if (devices.some(d => d.id === preferred)) return preferred;
    return (devices.find(d => d.reachable) ?? devices[0])?.id ?? "";
}

function introduction(devices, bluetoothPhones, seenServices, seenBluetooth) {
    devices = phones(devices);
    if (!seenServices && devices.some(d => d.reachable)) return "services";
    if (!seenBluetooth && bluetoothPhones.length && !devices.some(d => d.reachable)) return "bluetooth";
    return "";
}
