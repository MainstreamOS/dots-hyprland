import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "connectivity"

Item {
    id: root

    ContentPage {
        anchors.fill: parent
        forceWidth: true

        ContentSection {
            icon: "wifi"
            title: Translation.tr("Wi-Fi")

            headerExtra: [
                RippleButton {
                    visible: Network.wifiEnabled
                    implicitWidth: 90
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: Network.rescanWifi()

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "refresh"
                            iconSize: 16
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            text: Translation.tr("Scan")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }
            ]

            ConfigRow {
                ConfigSwitch {
                    text: Translation.tr("Enable Wi-Fi")
                    checked: Network.wifiEnabled
                    onCheckedChanged: {
                        Network.enableWifi(checked);
                    }
                }
            }

            StyledIndeterminateProgressBar {
                visible: Network.wifiScanning
                Layout.fillWidth: true
            }
        }

        // Connected network
        ContentSection {
            icon: "wifi"
            title: Translation.tr("Connected")
            visible: Network.wifiEnabled && Network.active !== null

            ConnectivityWifiItem {
                wifiNetwork: Network.active
                Layout.fillWidth: true
            }
        }

        // Saved networks (not active)
        ContentSection {
            icon: "bookmark"
            title: Translation.tr("Saved Networks")
            visible: Network.wifiEnabled && Network.savedNetworks.length > 0

            Repeater {
                model: Network.savedNetworks

                ConnectivityWifiItem {
                    required property var modelData
                    wifiNetwork: modelData
                    Layout.fillWidth: true
                }
            }
        }

        ContentSection {
            icon: "wifi_find"
            title: Translation.tr("Available Networks")
            visible: Network.wifiEnabled

            // Empty state
            ColumnLayout {
                visible: Network.availableNetworks.length === 0 && !Network.wifiScanning
                Layout.fillWidth: true
                Layout.topMargin: 20
                Layout.bottomMargin: 20
                spacing: 8

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 64
                    implicitHeight: 64
                    radius: 32
                    color: Appearance.colors.colLayer3

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "wifi_find"
                        iconSize: 32
                        color: Appearance.colors.colSubtext
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No new networks found")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer2
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Click Scan to search for networks")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }

            // Network list (available = not saved)
            Repeater {
                model: Network.availableNetworks

                ConnectivityWifiItem {
                    required property var modelData
                    wifiNetwork: modelData
                    Layout.fillWidth: true
                }
            }
        }

        ContentSection {
            icon: "wifi_add"
            title: Translation.tr("Hidden Network")
            visible: Network.wifiEnabled

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialTextField {
                    id: hiddenSsidField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Network name (SSID)")
                }

                MaterialTextField {
                    id: hiddenPasswordField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Password (optional)")
                    echoMode: TextInput.Password
                    inputMethodHints: Qt.ImhSensitiveData
                }

                RippleButton {
                    Layout.alignment: Qt.AlignRight
                    implicitWidth: 140
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    enabled: hiddenSsidField.text.length > 0
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover

                    onClicked: {
                        const ssid = hiddenSsidField.text;
                        const password = hiddenPasswordField.text;
                        if (password.length > 0) {
                            Quickshell.execDetached(["nmcli", "dev", "wifi", "connect", ssid, "password", password]);
                        } else {
                            Quickshell.execDetached(["nmcli", "dev", "wifi", "connect", ssid]);
                        }
                        hiddenSsidField.text = "";
                        hiddenPasswordField.text = "";
                    }

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            text: "add"
                            iconSize: 18
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            text: Translation.tr("Connect")
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }
    }
}
