import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

WindowDialog {
    id: root
    backgroundHeight: 600

    ShownWifiNetworks {
        id: shownNetworks
    }

    WindowDialogTitle {
        text: Translation.tr("Connect to Wi-Fi")
    }
    WindowDialogSeparator {
        visible: !Network.wifiScanning
    }
    StyledIndeterminateProgressBar {
        visible: Network.wifiScanning
        Layout.fillWidth: true
        Layout.topMargin: -8
        Layout.bottomMargin: -8
        Layout.leftMargin: -Appearance.rounding.large
        Layout.rightMargin: -Appearance.rounding.large
    }
    // A grouped list, as in the Dynamic Island: rows 2 px apart, the group's ends rounded by the clip.
    ClippingRectangle {
        Layout.fillHeight: true
        Layout.fillWidth: true
        radius: Appearance.rounding.normal - 3
        color: "transparent"
        ListView {
            anchors.fill: parent
            clip: true
            spacing: 2

            model: ScriptModel {
                values: shownNetworks.networks
            }
            delegate: WifiNetworkItem {
                required property WifiAccessPoint modelData
                wifiNetwork: modelData
                width: ListView.view.width
            }
        }
    }
    WindowDialogSeparator {}
    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                CF.Session.openSettings("WifiConfig.qml");
                GlobalStates.sidebarRightOpen = false;
            }
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}