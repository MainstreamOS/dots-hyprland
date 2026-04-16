import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Bluetooth
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
            icon: "bluetooth"
            title: Translation.tr("Bluetooth")

            headerExtra: [
                RippleButton {
                    visible: Bluetooth.defaultAdapter?.enabled ?? false
                    implicitWidth: 90
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: Bluetooth.defaultAdapter?.discovering ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    colBackgroundHover: Bluetooth.defaultAdapter?.discovering ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                    onClicked: {
                        if (Bluetooth.defaultAdapter) {
                            Bluetooth.defaultAdapter.discovering = !Bluetooth.defaultAdapter.discovering;
                        }
                    }

                    contentItem: RowLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: Bluetooth.defaultAdapter?.discovering ? "stop" : "bluetooth_searching"
                            iconSize: 16
                            color: Bluetooth.defaultAdapter?.discovering ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            text: Bluetooth.defaultAdapter?.discovering ? Translation.tr("Stop") : Translation.tr("Scan")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Bluetooth.defaultAdapter?.discovering ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }
                    }
                }
            ]

            ConfigRow {
                ConfigSwitch {
                    text: Translation.tr("Enable Bluetooth")
                    checked: Bluetooth.defaultAdapter?.enabled ?? false
                    onCheckedChanged: {
                        if (Bluetooth.defaultAdapter) {
                            Bluetooth.defaultAdapter.enabled = checked;
                        }
                    }
                }
            }

            // Discoverable toggle
            ConfigRow {
                visible: Bluetooth.defaultAdapter?.enabled ?? false

                ConfigSwitch {
                    text: Translation.tr("Discoverable")
                    checked: Bluetooth.defaultAdapter?.discoverable ?? false
                    onCheckedChanged: {
                        if (Bluetooth.defaultAdapter) {
                            Bluetooth.defaultAdapter.discoverable = checked;
                        }
                    }
                }
            }

            // Pairable toggle
            ConfigRow {
                visible: Bluetooth.defaultAdapter?.enabled ?? false

                ConfigSwitch {
                    text: Translation.tr("Pairable")
                    checked: Bluetooth.defaultAdapter?.pairable ?? false
                    onCheckedChanged: {
                        if (Bluetooth.defaultAdapter) {
                            Bluetooth.defaultAdapter.pairable = checked;
                        }
                    }
                }
            }

            StyledIndeterminateProgressBar {
                visible: Bluetooth.defaultAdapter?.discovering ?? false
                Layout.fillWidth: true
            }
        }

        // Connected devices
        ContentSection {
            icon: "bluetooth_connected"
            title: Translation.tr("Connected Devices")
            visible: (Bluetooth.defaultAdapter?.enabled ?? false) && BluetoothStatus.connectedDevices.length > 0

            Repeater {
                model: BluetoothStatus.connectedDevices

                ConnectivityBluetoothItem {
                    required property var modelData
                    device: modelData
                    Layout.fillWidth: true
                }
            }
        }

        // Paired devices
        ContentSection {
            icon: "bluetooth"
            title: Translation.tr("Paired Devices")
            visible: (Bluetooth.defaultAdapter?.enabled ?? false) && BluetoothStatus.pairedButNotConnectedDevices.length > 0

            Repeater {
                model: BluetoothStatus.pairedButNotConnectedDevices

                ConnectivityBluetoothItem {
                    required property var modelData
                    device: modelData
                    Layout.fillWidth: true
                }
            }
        }

        // Available devices
        ContentSection {
            icon: "devices"
            title: Translation.tr("Available Devices")
            visible: (Bluetooth.defaultAdapter?.enabled ?? false)

            Item {
                visible: BluetoothStatus.friendlyDeviceList.length === 0 && !(Bluetooth.defaultAdapter?.discovering ?? false)
                Layout.fillWidth: true
                Layout.preferredHeight: 160

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 12

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 72
                        implicitHeight: 72
                        radius: 36
                        color: Appearance.colors.colLayer3

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "bluetooth_searching"
                            iconSize: 36
                            color: Appearance.colors.colSubtext
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("No devices found")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Click Scan to discover nearby devices")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            Repeater {
                model: BluetoothStatus.unpairedDevices

                ConnectivityBluetoothItem {
                    required property var modelData
                    device: modelData
                    Layout.fillWidth: true
                }
            }
        }
    }
}
