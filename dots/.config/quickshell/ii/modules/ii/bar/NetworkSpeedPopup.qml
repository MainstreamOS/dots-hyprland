import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    readonly property int strength: NetworkUsage.wifiSignal >= 0 ? NetworkUsage.wifiSignal : (Network.active?.strength ?? 0)

    // Taken from the same link as the rows below. Network.materialSymbol
    // reads an idle wired port as connected, and would put a wired icon over
    // a Wi-Fi connection's name.
    readonly property string symbol: !NetworkUsage.onWifi
        ? (NetworkUsage.connectionName !== "" ? "lan" : "link_off")
        : root.strength > 83 ? "signal_wifi_4_bar"
        : root.strength > 67 ? "network_wifi"
        : root.strength > 50 ? "network_wifi_3_bar"
        : root.strength > 33 ? "network_wifi_2_bar"
        : root.strength > 17 ? "network_wifi_1_bar"
        : "signal_wifi_0_bar"

    // The rows below exist from the start; only the card is made on hover, so
    // this is the moment to ask what the connection looks like now.
    onActiveChanged: if (active) NetworkUsage.refreshDetails()

    ColumnLayout {
        id: columnLayout
        anchors.centerIn: parent
        spacing: 4

        // An interface coming or going can move the traffic to another link
        // while the card is up.
        Connections {
            target: NetworkUsage
            enabled: root.active
            function onPhysicalChanged() {
                NetworkUsage.refreshDetails();
            }
        }

        StyledPopupHeaderRow {
            icon: root.symbol
            label: NetworkUsage.connectionName !== "" ? NetworkUsage.connectionName : Translation.tr("Not connected")
        }

        StyledPopupValueRow {
            visible: NetworkUsage.onWifi
            icon: "network_wifi"
            label: Translation.tr("Signal:")
            value: `${root.strength}%`
        }

        StyledPopupValueRow {
            visible: NetworkUsage.ipAddress !== ""
            icon: "router"
            label: Translation.tr("IP address:")
            value: NetworkUsage.ipAddress
        }

        StyledPopupValueRow {
            icon: "arrow_downward"
            label: Translation.tr("Download:")
            value: NetworkUsage.formatRate(NetworkUsage.downloadRate)
        }

        StyledPopupValueRow {
            icon: "arrow_upward"
            label: Translation.tr("Upload:")
            value: NetworkUsage.formatRate(NetworkUsage.uploadRate)
        }
    }
}
