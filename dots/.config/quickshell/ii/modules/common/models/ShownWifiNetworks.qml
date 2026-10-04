import QtQuick
import qs.services
import qs.services.network

// The Wi-Fi networks as one view shows them. While one of them asks for a
// password they stay as they are, so the row being typed in keeps its place.
NestableObject {
    id: root

    property var networks: []
    property var savedNetworks: []
    property var availableNetworks: []
    property WifiAccessPoint active: null
    readonly property bool held: root.networks.concat(root.savedNetworks).some(n => n?.askingPassword ?? false)
    readonly property var current: [Network.friendlyWifiNetworks, Network.savedNetworks, Network.availableNetworks, Network.active]

    function update() {
        if (root.held)
            return;
        root.networks = [...Network.friendlyWifiNetworks];
        root.savedNetworks = [...Network.savedNetworks];
        root.availableNetworks = [...Network.availableNetworks];
        root.active = Network.active;
    }

    // Once per turn: one change to the service's lists arrives as several here.
    onCurrentChanged: Qt.callLater(root.update)
    // A turn later: changing the lists from inside held's own change is a binding loop.
    onHeldChanged: Qt.callLater(root.update)
    Component.onCompleted: root.update()
}
