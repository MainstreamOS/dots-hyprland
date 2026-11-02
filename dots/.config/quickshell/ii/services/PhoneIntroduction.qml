pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs.modules.common
import "PhoneSetup.js" as Setup

Singleton {
    id: root
    // Settings also reads phone services; only the main shell announces them.
    property bool enabled: false
    readonly property bool ready: enabled && Config.ready && Persistent.ready
        && Config.options.sidebar.phone.enable && Phone.installed
    readonly property var bluetoothPhones: Bluetooth.devices.values.filter(d =>
        d.paired && d.connected && String(d.icon ?? "").startsWith("phone"))
    property string pendingKind: ""
    property int attempts: 0

    onReadyChanged: root.schedule()
    onBluetoothPhonesChanged: root.schedule()
    Connections {
        target: Phone
        function onDevicesChanged() { root.schedule(); }
    }

    function schedule(): void {
        if (root.ready && !notifier.running) settle.restart();
    }

    function showIntroduction(): void {
        if (!root.ready || notifier.running) return;
        const kind = Setup.introduction(Phone.devices, root.bluetoothPhones,
            Persistent.states.phone.introducedServices, Persistent.states.phone.introducedBluetooth);
        if (!kind) return;
        const peer = Phone.devices.find(d => d.reachable);
        const lines = [];
        if (kind === "services") {
            if (peer.plugins?.includes("kdeconnect_sms") && peer.plugins?.includes("kdeconnect_contacts"))
                lines.push(Translation.tr("Messages and contacts: open Phone in the left sidebar."));
            else lines.push(Translation.tr("Open Phone in the left sidebar to see the available features."));
            if (peer.plugins?.includes("kdeconnect_share"))
                lines.push(Translation.tr("To send a file, drop it onto the Phone tab."));
            lines.push(Translation.tr("Keep both devices on the same Wi-Fi and allow sharing in KDE Connect on your phone."));
        } else {
            lines.push(Translation.tr("For calls, enable phone calls in your phone's Bluetooth settings."));
            lines.push(Translation.tr("For messages and files, open KDE Connect on your phone and pair with this computer over Wi-Fi."));
        }
        root.pendingKind = kind;
        root.attempts++;
        notifier.command = ["notify-send", "-a", "Mainstream", "-i", "smartphone",
            "--print-id", "-A", "open=" + Translation.tr("Open Phone"),
            Translation.tr("Your phone is connected"), lines.map(line => "• " + line).join("\n")];
        notifier.running = true;
    }

    Timer { id: settle; interval: 2500; onTriggered: root.showIntroduction() }
    Process {
        id: notifier
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (/^[1-9][0-9]*$/.test(line)) {
                    // Persist only once the notification server accepts the notice.
                    if (root.pendingKind === "services") {
                        Persistent.states.phone.introducedServices = true;
                        if (root.bluetoothPhones.length) Persistent.states.phone.introducedBluetooth = true;
                    } else Persistent.states.phone.introducedBluetooth = true;
                } else if (line === "open") SidebarLeftTabs.showTab("phone");
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0 && root.attempts < 3) settle.restart();
        }
    }
}
