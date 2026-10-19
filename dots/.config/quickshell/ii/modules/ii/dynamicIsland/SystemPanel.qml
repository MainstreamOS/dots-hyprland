pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Widgets
import Quickshell.Services.UPower
import qs
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models.quickToggles
import qs.modules.ii.bar
import qs.modules.ii.sidebarRight.bluetoothDevices

ColumnLayout {
    id: root
    property var screen
    readonly property bool isLaptop: UPower.displayDevice?.isLaptopBattery ?? false
    readonly property var brightness: isLaptop ? Brightness.getMonitorForScreen(screen) : null
    property bool wifiDrawerOpen: false
    property bool wifiDrawerPasswordFocused: false
    property bool bluetoothDrawerOpen: false
    readonly property BluetoothAdapter bluetoothAdapter: Bluetooth.defaultAdapter
    property BluetoothAdapter discoveryAdapter: null
    property bool nightLightDrawerOpen: false
    property bool audioDrawerOpen: false
    readonly property bool busy: tray.trayOverflowOpen || !!tray.activeMenu || root.audioDrawerOpen || root.wifiDrawerOpen || root.bluetoothDrawerOpen || root.nightLightDrawerOpen
    readonly property bool needsKeyboardFocus: (root.wifiDrawerOpen && (shownNetworks.held || root.wifiDrawerPasswordFocused)) ?? false
    readonly property color elevatedSurface: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer0, 0.92)
    spacing: 6

    // A network asked for a password releases its prompt when the drawer closes or
    // the panel goes away, so the shared access point and network list are not held.
    function releasePasswordPrompts(): void {
        wifiDrawerPasswordFocused = false;
        shownNetworks.networks.forEach(n => {
            if (n && n.askingPassword) n.askingPassword = false;
        });
    }
    onWifiDrawerOpenChanged: if (!wifiDrawerOpen) releasePasswordPrompts()
    function stopBluetoothDiscovery(): void {
        if (discoveryAdapter) discoveryAdapter.discovering = false;
        discoveryAdapter = null;
    }
    function updateBluetoothDiscovery(): void {
        const adapter = root.visible && root.bluetoothDrawerOpen && root.bluetoothAdapter?.enabled
            ? root.bluetoothAdapter : null;
        if (discoveryAdapter && discoveryAdapter !== adapter) stopBluetoothDiscovery();
        if (adapter && !adapter.discovering) {
            discoveryAdapter = adapter;
            adapter.discovering = true;
        }
    }
    onBluetoothDrawerOpenChanged: updateBluetoothDiscovery()
    onBluetoothAdapterChanged: updateBluetoothDiscovery()
    onVisibleChanged: updateBluetoothDiscovery()
    Connections {
        target: root.bluetoothAdapter
        function onEnabledChanged() { root.updateBluetoothDiscovery(); }
    }
    Component.onDestruction: {
        releasePasswordPrompts();
        stopBluetoothDiscovery();
    }

    RowLayout {
        id: topRow
        Layout.fillWidth: true
        spacing: 6

        SystemTile {
            id: networkTile
            Layout.fillWidth: true
            symbol: Network.materialSymbol
            text: Network.ethernet ? Translation.tr("Ethernet") : Translation.tr("Wi-Fi")
            subtitle: Network.networkName || (Network.wifiEnabled ? Translation.tr("Not connected") : Translation.tr("Off"))
            opensPanel: true
            expanded: root.wifiDrawerOpen
            highlighted: root.wifiDrawerOpen || Network.ethernet || (Network.wifiEnabled && (Network.wifiStatus === "connected" || !!Network.active))
            onClicked: {
                root.nightLightDrawerOpen = false;
                root.bluetoothDrawerOpen = false;
                if (root.audioDrawerOpen) root.audioDrawerOpen = false;
                if (!Network.wifiEnabled && !Network.ethernet) {
                    Network.enableWifi(true);
                    Network.rescanWifi();
                }
                root.wifiDrawerOpen = !root.wifiDrawerOpen;
                if (root.wifiDrawerOpen) {
                    Network.rescanWifi();
                }
            }
            iconAction: () => Network.toggleWifi()
            altAction: () => {
                Quickshell.execDetached(["bash", "-c", `${Network.ethernet ? Config.options.apps.networkEthernet : Config.options.apps.network}`]);
            }
        }

        SystemTile {
            id: audioTile
            Layout.fillWidth: true
            symbol: Audio.sink?.audio?.muted ? "volume_off" : "speaker"
            text: Translation.tr("Audio output")
            subtitle: Audio.sink ? Audio.friendlyDeviceName(Audio.sink) : Translation.tr("No output")
            opensPanel: true
            expanded: root.audioDrawerOpen
            highlighted: root.audioDrawerOpen || (Audio.sink && !Audio.sink.audio?.muted)
            onClicked: {
                root.nightLightDrawerOpen = false;
                root.bluetoothDrawerOpen = false;
                if (root.wifiDrawerOpen) root.wifiDrawerOpen = false;
                root.audioDrawerOpen = !root.audioDrawerOpen;
            }
            iconAction: () => Audio.toggleMute()
            altAction: () => {
                Quickshell.execDetached(["bash", "-c", Config.options.apps.volumeMixer]);
            }
        }
    }

    Rectangle {
        id: audioDrawer
        Layout.fillWidth: true
        implicitHeight: 158
        radius: Appearance?.rounding?.normal ?? 17
        color: root.elevatedSurface
        visible: root.audioDrawerOpen

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                spacing: 6

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Audio Output")
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurfaceVariant
                    verticalAlignment: Text.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    padding: 0
                    buttonRadius: 6
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)
                    Accessible.name: Translation.tr("Volume mixer")
                    onClicked: {
                        Quickshell.execDetached(["bash", "-c", Config.options.apps.volumeMixer]);
                    }
                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "tune"
                        iconSize: 15
                        color: Appearance.colors.colOnLayer1
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    padding: 0
                    buttonRadius: 6
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)
                    Accessible.name: Translation.tr("Close audio output")
                    onClicked: root.audioDrawerOpen = false
                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "keyboard_arrow_up"
                        iconSize: 17
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            ClippingRectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: (Appearance?.rounding?.normal ?? 17) - 3
                color: "transparent"

                StyledListView {
                    id: outputListView
                    anchors.fill: parent
                    clip: true
                    spacing: 2
                    model: root.audioDrawerOpen ? Audio.outputDevices : null

                ScrollBar.vertical: StyledScrollBar {
                    active: hovered || pressed || outputListView.moving || outputListView.flicking || outputListView.wheelScrolling
                }

                Timer {
                    id: wheelScrollTimer
                    interval: 400
                    onTriggered: outputListView.wheelScrolling = false
                }

                WheelHandler {
                    target: outputListView
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : (event.pixelDelta.y !== 0 ? event.pixelDelta.y : 0);
                        if (delta === 0) return;
                        outputListView.wheelScrolling = true;
                        wheelScrollTimer.restart();
                        const factor = Math.abs(delta) >= 120 ? 42 : 20;
                        const step = (delta / (Math.abs(delta) >= 120 ? 120 : 40)) * factor;
                        const maxY = Math.max(0, outputListView.contentHeight - outputListView.height);
                        outputListView.contentY = Math.max(0, Math.min(maxY, outputListView.contentY - step));
                        event.accepted = true;
                    }
                }

                delegate: ItemDelegate {
                    id: itemDelegate
                    width: ListView.view ? ListView.view.width : (audioDrawer.width - 16)
                    implicitHeight: 32
                padding: 0
                leftPadding: 8
                rightPadding: 8

                required property var modelData
                required property int index
                readonly property bool isCurrent: modelData?.id === Audio.sink?.id
                readonly property int totalCount: Audio.outputDevices.length

                property color color: {
                    if (isCurrent) {
                        if (itemDelegate.down) return Appearance.colors.colPrimaryContainerActive;
                        if (itemDelegate.hovered) return Appearance.colors.colPrimaryContainerHover;
                        return Appearance.colors.colPrimaryContainer;
                    } else {
                        if (itemDelegate.down) return Appearance.colors.colLayer2Active;
                        if (itemDelegate.hovered) return Appearance.colors.colLayer2Hover;
                        return ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5);
                    }
                }
                property color colText: isCurrent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1

                background: Rectangle {
                    anchors.fill: parent
                    topLeftRadius: itemDelegate.index === 0 ? (Appearance?.rounding?.normal ?? 17) - 3 : 4
                    topRightRadius: itemDelegate.index === 0 ? (Appearance?.rounding?.normal ?? 17) - 3 : 4
                    bottomLeftRadius: itemDelegate.index === itemDelegate.totalCount - 1 ? (Appearance?.rounding?.normal ?? 17) - 3 : 4
                    bottomRightRadius: itemDelegate.index === itemDelegate.totalCount - 1 ? (Appearance?.rounding?.normal ?? 17) - 3 : 4
                    color: itemDelegate.color

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        cursorShape: Qt.PointingHandCursor
                    }
                }

                contentItem: RowLayout {
                    spacing: 8

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        radius: itemDelegate.isCurrent ? (Appearance?.rounding?.verysmall ?? 8) : height / 2
                        color: itemDelegate.isCurrent
                            ? Appearance.colors.colPrimary
                            : ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)

                        MaterialSymbol {
                            anchors.fill: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: {
                                const name = (Audio.friendlyDeviceName(itemDelegate.modelData) || "").toLowerCase();
                                const raw = (itemDelegate.modelData?.description || itemDelegate.modelData?.name || "").toLowerCase();
                                const str = name + " " + raw;
                                if (str.includes("headphone") || str.includes("headset") || str.includes("fifine") || str.includes("airpod") || str.includes("buds")) return "headphones";
                                if (str.includes("bluetooth") || str.includes("bluez")) return "bluetooth_audio";
                                if (str.includes("hdmi") || str.includes("displayport") || str.includes("monitor") || str.includes("tv")) return "tv";
                                return "speaker";
                            }
                            iconSize: 15
                            color: itemDelegate.isCurrent ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        color: itemDelegate.colText
                        text: Audio.friendlyDeviceName(itemDelegate.modelData)
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 12
                        font.weight: itemDelegate.isCurrent ? Font.DemiBold : Font.Normal
                    }

                    Rectangle {
                        visible: itemDelegate.isCurrent
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        radius: 10
                        color: Appearance.colors.colPrimary

                        MaterialSymbol {
                            anchors.fill: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "check"
                            iconSize: 13
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }

                onClicked: {
                    Audio.setDefaultSink(modelData);
                }
            }

            StyledText {
                visible: !Audio.outputDevices.length
                anchors.centerIn: parent
                text: Translation.tr("No output devices")
                font.pixelSize: 12
                color: Appearance.colors.colSubtext
            }
        }
    }
}
}

    ShownWifiNetworks {
        id: shownNetworks
    }

    Rectangle {
        id: wifiDrawer
        Layout.fillWidth: true
        implicitHeight: 158
        radius: Appearance?.rounding?.normal ?? 17
        color: root.elevatedSurface
        visible: root.wifiDrawerOpen

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                spacing: 6

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Wi-Fi Networks")
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurfaceVariant
                    verticalAlignment: Text.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    padding: 0
                    buttonRadius: 6
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)
                    Accessible.name: Translation.tr("Rescan Wi-Fi networks")
                    onClicked: Network.rescanWifi()
                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "refresh"
                        iconSize: 15
                        color: Appearance.colors.colOnLayer1
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    padding: 0
                    buttonRadius: 6
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)
                    Accessible.name: Translation.tr("Network settings")
                    onClicked: {
                        root.wifiDrawerOpen = false;
                        Session.openSettings("WifiConfig.qml");
                    }
                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "settings"
                        iconSize: 15
                        color: Appearance.colors.colOnLayer1
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    padding: 0
                    buttonRadius: 6
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)
                    Accessible.name: Translation.tr("Close Wi-Fi networks")
                    onClicked: root.wifiDrawerOpen = false
                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "keyboard_arrow_up"
                        iconSize: 17
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            StyledIndeterminateProgressBar {
                visible: Network.wifiScanning
                Layout.fillWidth: true
                Layout.preferredHeight: 2
            }

            ClippingRectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: (Appearance?.rounding?.normal ?? 17) - 3
                color: "transparent"

                StyledListView {
                    id: wifiListView
                    anchors.fill: parent
                    clip: true
                    spacing: 2
                    model: root.wifiDrawerOpen ? shownNetworks.networks : null
                    // The network asking for a password sits in the middle of the drawer, also while
                    // its prompt opens and the list around it changes.
                    property Item promptItem: null
                    function centerPrompt(): void {
                        if (!promptItem || userScrolling) return;
                        const maxY = originY + Math.max(0, contentHeight - height);
                        contentY = Math.max(originY, Math.min(maxY, promptItem.y + (promptItem.height - height) / 2));
                    }
                    onContentHeightChanged: centerPrompt()

                ScrollBar.vertical: StyledScrollBar {
                    active: hovered || pressed || wifiListView.moving || wifiListView.flicking || wifiListView.wheelScrolling
                }

                Timer {
                    id: wifiWheelScrollTimer
                    interval: 400
                    onTriggered: wifiListView.wheelScrolling = false
                }

                WheelHandler {
                    target: wifiListView
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : (event.pixelDelta.y !== 0 ? event.pixelDelta.y : 0);
                        if (delta === 0) return;
                        wifiListView.wheelScrolling = true;
                        wifiWheelScrollTimer.restart();
                        const factor = Math.abs(delta) >= 120 ? 42 : 20;
                        const step = (delta / (Math.abs(delta) >= 120 ? 120 : 40)) * factor;
                        const maxY = Math.max(0, wifiListView.contentHeight - wifiListView.height);
                        wifiListView.contentY = Math.max(0, Math.min(maxY, wifiListView.contentY - step));
                        event.accepted = true;
                    }
                }

                delegate: ItemDelegate {
                    id: wifiItem
                    width: ListView.view ? ListView.view.width : (wifiDrawer.width - 16)
                    implicitHeight: wifiItem.askingPassword ? (itemContentLayout.implicitHeight + topPadding + bottomPadding) : 32
                    padding: 0
                    topPadding: wifiItem.askingPassword ? 10 : 0
                    bottomPadding: wifiItem.askingPassword ? 10 : 0
                    leftPadding: 8
                    rightPadding: 8

                    required property WifiAccessPoint modelData
                    required property int index
                    readonly property bool isCurrent: modelData?.active ?? false
                    readonly property bool isConnecting: Network.wifiConnectTarget === modelData && !isCurrent
                    readonly property int totalCount: shownNetworks.networks.length
                    readonly property bool askingPassword: modelData?.askingPassword ?? false
                    onAskingPasswordChanged: {
                        if (askingPassword) wifiListView.promptItem = wifiItem;
                        else if (wifiListView.promptItem === wifiItem) wifiListView.promptItem = null;
                        Qt.callLater(wifiListView.centerPrompt);
                    }
                    onHeightChanged: if (askingPassword) Qt.callLater(wifiListView.centerPrompt)

                    property color itemColor: {
                        if (isCurrent) {
                            if (wifiItem.down) return Appearance.colors.colPrimaryContainerActive;
                            if (wifiItem.hovered) return Appearance.colors.colPrimaryContainerHover;
                            return Appearance.colors.colPrimaryContainer;
                        } else {
                            if (wifiItem.down) return Appearance.colors.colLayer2Active;
                            if (wifiItem.hovered) return Appearance.colors.colLayer2Hover;
                            return ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5);
                        }
                    }
                    property color itemColText: isCurrent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1

                    background: Rectangle {
                        anchors.fill: parent
                        topLeftRadius: wifiItem.index === 0 ? (Appearance?.rounding?.normal ?? 17) - 3 : 4
                        topRightRadius: wifiItem.index === 0 ? (Appearance?.rounding?.normal ?? 17) - 3 : 4
                        bottomLeftRadius: wifiItem.index === wifiItem.totalCount - 1 ? (Appearance?.rounding?.normal ?? 17) - 3 : 4
                        bottomRightRadius: wifiItem.index === wifiItem.totalCount - 1 ? (Appearance?.rounding?.normal ?? 17) - 3 : 4
                        color: wifiItem.itemColor

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            cursorShape: Qt.PointingHandCursor
                        }
                    }

                    contentItem: ColumnLayout {
                        id: itemContentLayout
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                radius: wifiItem.isCurrent ? (Appearance?.rounding?.verysmall ?? 8) : height / 2
                                color: wifiItem.isCurrent
                                    ? Appearance.colors.colPrimary
                                    : ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)

                                MaterialSymbol {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    property int strength: wifiItem.modelData?.strength ?? 0
                                    text: strength > 80 ? "signal_wifi_4_bar" : strength > 60 ? "network_wifi_3_bar" : strength > 40 ? "network_wifi_2_bar" : strength > 20 ? "network_wifi_1_bar" : "signal_wifi_0_bar"
                                    iconSize: 16
                                    color: wifiItem.isCurrent ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                                }
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                                color: wifiItem.itemColText
                                text: wifiItem.modelData?.ssid || Translation.tr("Hidden Network")
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 12
                                font.weight: wifiItem.isCurrent ? Font.DemiBold : Font.Normal
                            }

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                visible: (wifiItem.modelData?.isSecure || false) && !wifiItem.isCurrent
                                text: "lock"
                                iconSize: 13
                                color: Appearance.colors.colSubtext
                            }

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                visible: wifiItem.isConnecting
                                text: "settings_ethernet"
                                iconSize: 14
                                color: Appearance.colors.colPrimary
                            }

                            Rectangle {
                                visible: wifiItem.isCurrent
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 20
                                radius: 10
                                color: Appearance.colors.colPrimary

                                MaterialSymbol {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "check"
                                    iconSize: 13
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: wifiItem.askingPassword
                            spacing: 6

                            StyledText {
                                visible: (wifiItem.modelData?.connectionError ?? "").length > 0
                                text: wifiItem.modelData?.connectionError ?? ""
                                font.pixelSize: 10
                                color: Appearance.colors.colError
                                Layout.fillWidth: true
                            }

                            ToolbarTextField {
                                id: pwdField
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                implicitHeight: 30
                                padding: 8
                                colBackground: Appearance.colors.colLayer1
                                radius: Appearance.rounding.small
                                placeholderText: Translation.tr("Password")
                                echoMode: TextInput.Password
                                inputMethodHints: Qt.ImhSensitiveData
                                onActiveFocusChanged: root.wifiDrawerPasswordFocused = activeFocus
                                onAccepted: {
                                    Network.changePassword(wifiItem.modelData, pwdField.text);
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: pwdField.radius
                                    color: "transparent"
                                    border.width: 1
                                    border.color: pwdField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Item { Layout.fillWidth: true }

                                DialogButton {
                                    buttonText: Translation.tr("Cancel")
                                    implicitHeight: 24
                                    onClicked: {
                                        wifiItem.modelData.askingPassword = false;
                                        wifiItem.modelData.connectionError = "";
                                        pwdField.text = "";
                                    }
                                }

                                DialogButton {
                                    buttonText: Translation.tr("Connect")
                                    implicitHeight: 24
                                    colBackground: Appearance.colors.colPrimary
                                    colBackgroundHover: Appearance.colors.colPrimaryHover
                                    colText: Appearance.colors.colOnPrimary
                                    colEnabled: Appearance.colors.colOnPrimary
                                    onClicked: {
                                        Network.changePassword(wifiItem.modelData, pwdField.text);
                                    }
                                }
                            }
                        }
                    }

                    onClicked: {
                        if (!wifiItem.askingPassword) {
                            Network.connectToWifiNetwork(modelData);
                        }
                    }
                }

                StyledText {
                    visible: !shownNetworks.networks.length
                    anchors.centerIn: parent
                    text: Network.wifiScanning ? Translation.tr("Scanning for networks…") : Translation.tr("No Wi-Fi networks found")
                    font.pixelSize: 12
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}

    RowLayout {
        id: secondRow
        Layout.fillWidth: true
        spacing: 6
        visible: !root.wifiDrawerOpen && !root.audioDrawerOpen && !root.bluetoothDrawerOpen && !root.nightLightDrawerOpen

        SystemTile {
            id: bluetoothTile
            Layout.fillWidth: true
            symbol: "bluetooth"
            text: Translation.tr("Bluetooth")
            subtitle: BluetoothStatus.firstActiveDevice?.name || (BluetoothStatus.enabled ? Translation.tr("On") : Translation.tr("Off"))
            opensPanel: true
            expanded: root.bluetoothDrawerOpen
            highlighted: root.bluetoothDrawerOpen || BluetoothStatus.enabled
            onClicked: {
                root.nightLightDrawerOpen = false;
                root.bluetoothDrawerOpen = !root.bluetoothDrawerOpen;
                if (root.bluetoothDrawerOpen) BluetoothStatus.setEnabled(true);
            }
            iconAction: () => BluetoothStatus.toggle()
            altAction: () => Session.openSettings("BluetoothConfig.qml")
        }

        // The sidebar's Night Light toggle, so both places behave alike.
        NightLightToggle { id: nightLight }
        SystemTile {
            id: nightLightTile
            Layout.fillWidth: true
            symbol: nightLight.icon
            text: nightLight.name
            subtitle: nightLight.statusText
            opensPanel: true
            expanded: root.nightLightDrawerOpen
            highlighted: root.nightLightDrawerOpen || nightLight.toggled
            onClicked: root.nightLightDrawerOpen = !root.nightLightDrawerOpen
            iconAction: () => nightLight.mainAction()
            altAction: () => Session.openSettings("DisplayConfig.qml", "nightLightSection")
        }
    }

    Rectangle {
        id: bluetoothDrawer
        Layout.fillWidth: true
        implicitHeight: 158
        radius: Appearance?.rounding?.normal ?? 17
        color: root.elevatedSurface
        visible: root.bluetoothDrawerOpen

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                spacing: 6

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Bluetooth")
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    padding: 0
                    buttonRadius: 6
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)
                    Accessible.name: Translation.tr("Settings")
                    onClicked: Session.openSettings("BluetoothConfig.qml")
                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "settings"
                        iconSize: 15
                        color: Appearance.colors.colOnLayer1
                    }
                }

                RippleButton {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    padding: 0
                    buttonRadius: 6
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)
                    Accessible.name: Translation.tr("Close")
                    onClicked: root.bluetoothDrawerOpen = false
                    contentItem: MaterialSymbol {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "keyboard_arrow_up"
                        iconSize: 17
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            ClippingRectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: (Appearance?.rounding?.normal ?? 17) - 3
                color: "transparent"

                StyledListView {
                    id: bluetoothList
                    anchors.fill: parent
                    clip: true
                    spacing: 2
                    animateAppearance: false
                    model: ScriptModel {
                        values: root.bluetoothDrawerOpen ? BluetoothStatus.friendlyDeviceList : []
                    }
                    delegate: BluetoothDeviceItem {
                        required property BluetoothDevice modelData
                        device: modelData
                        width: Math.max(0, ListView.view.width - 8)
                        compact: true
                        contentColors: Appearance.colors
                    }
                    ScrollBar.vertical: StyledScrollBar {
                        policy: ScrollBar.AlwaysOn
                        topPadding: 0
                        bottomPadding: 0
                        active: hovered || pressed || bluetoothList.moving || bluetoothList.flicking || bluetoothList.wheelScrolling
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: BluetoothStatus.friendlyDeviceList.length === 0
                    text: Translation.tr("No devices found")
                    font.pixelSize: 12
                    color: Appearance.colors.colSubtext
                }
                StyledIndeterminateProgressBar {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    visible: root.bluetoothAdapter?.discovering ?? false
                }
            }
        }
    }

    Rectangle {
        id: nightLightDrawer
        Layout.fillWidth: true
        implicitHeight: 158
        radius: Appearance?.rounding?.normal ?? 17
        color: root.elevatedSurface
        visible: root.nightLightDrawerOpen

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                spacing: 6

                StyledText {
                    text: Translation.tr("Night Light")
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurfaceVariant
                }

                Item { Layout.fillWidth: true }

                IslandButton {
                    implicitWidth: 22
                    implicitHeight: 22
                    symbol: "settings"
                    Accessible.name: Translation.tr("Settings")
                    onClicked: Session.openSettings("DisplayConfig.qml", "nightLightSection")
                }
                IslandButton {
                    implicitWidth: 22
                    implicitHeight: 22
                    symbol: "keyboard_arrow_up"
                    Accessible.name: Translation.tr("Close")
                    onClicked: root.nightLightDrawerOpen = false
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: [
                        { value: "disabled", label: Translation.tr("Disabled") },
                        { value: "automatic", label: Translation.tr("Automatic") },
                        { value: "manual", label: Translation.tr("Set hours") },
                        { value: "enabled", label: Translation.tr("Enabled") }
                    ]
                    IslandButton {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 28
                        compact: true
                        text: modelData.label
                        highlighted: Config.options.light.night.mode === modelData.value
                        onClicked: Hyprsunset.applyNightLightMode(modelData.value)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: Config.options.light.night.mode === "manual"
                spacing: 6
                StyledText {
                    text: Translation.tr("Turn on") + " · " + DateTime.formatTimeOfDay(Config.options.light.night.from)
                    font.pixelSize: 11
                    color: Appearance.colors.colSubtext
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: Translation.tr("Turn off") + " · " + DateTime.formatTimeOfDay(Config.options.light.night.to)
                    font.pixelSize: 11
                    color: Appearance.colors.colSubtext
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    MaterialSymbol {
                        text: "thermostat"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Intensity")
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: Math.round(Config.options.light.night.colorTemperature) + " K"
                        font.pixelSize: 12
                        color: Appearance.colors.colSubtext
                    }
                }

                StyledSlider {
                    id: nightLightIntensity
                    Layout.fillWidth: true
                    implicitHeight: 26
                    configuration: StyledSlider.Configuration.XS
                    showHandle: false
                    from: 6500
                    to: 1200
                    stepSize: 50
                    stopIndicatorValues: [5000, to]
                    value: Config.options.light.night.colorTemperature
                    Accessible.name: Translation.tr("Intensity")
                    tooltipContent: Math.round(value) + " K"
                    onMoved: Config.options.light.night.colorTemperature = Math.round(value)
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        visible: !root.wifiDrawerOpen && !root.audioDrawerOpen && !root.bluetoothDrawerOpen && !root.nightLightDrawerOpen

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 36
            topLeftRadius: Appearance?.rounding?.normal ?? 17
            topRightRadius: Appearance?.rounding?.normal ?? 17
            bottomLeftRadius: 4
            bottomRightRadius: 4
            color: root.elevatedSurface

            ControlWheel {
                enabled: Audio.ready && !!Audio.sink?.audio
                onStepped: direction => direction > 0 ? Audio.incrementVolume() : Audio.decrementVolume()
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 10
                spacing: 8

                RippleButton {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    topPadding: 0
                    bottomPadding: 0
                    buttonRadius: height / 2
                    buttonRadiusPressed: Appearance?.rounding?.verysmall ?? 8
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)
                    Accessible.name: Translation.tr("Mute volume")
                    onClicked: Audio.toggleMute()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                StyledText {
                    Layout.preferredWidth: 54
                    text: Translation.tr("Volume")
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                StyledSlider {
                    Layout.fillWidth: true
                    implicitHeight: 26
                    configuration: StyledSlider.Configuration.XS
                    showHandle: false
                    wheelEnabled: false
                    from: 0; to: 1; value: Audio.value
                    enabled: Audio.ready
                    Accessible.name: Translation.tr("Volume")
                    onMoved: Audio.sink.audio.volume = value
                }

                StyledText {
                    Layout.preferredWidth: 36
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(Audio.value * 100) + "%"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: Appearance.colors.colSubtext
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 36
            topLeftRadius: 4
            topRightRadius: 4
            bottomLeftRadius: Appearance?.rounding?.normal ?? 17
            bottomRightRadius: Appearance?.rounding?.normal ?? 17
            color: root.elevatedSurface

            ControlWheel {
                enabled: !root.isLaptop || !!root.brightness
                onStepped: direction => {
                    if (root.isLaptop) root.brightness.setBrightness(Math.max(0, Math.min(1, root.brightness.brightness + direction * 0.05)));
                    else Hyprsunset.setGamma(Hyprsunset.gamma + direction * 5);
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 10
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: height / 2
                    color: "transparent"
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.isLaptop ? "brightness_6" : "tonality"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                    }
                }

                StyledText {
                    Layout.preferredWidth: 54
                    text: root.isLaptop ? Translation.tr("Brightness") : Translation.tr("Gamma")
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }

                StyledSlider {
                    Layout.fillWidth: true
                    implicitHeight: 26
                    configuration: StyledSlider.Configuration.XS
                    showHandle: false
                    wheelEnabled: false
                    from: root.isLaptop ? 0 : Hyprsunset.gammaLowerLimit
                    to: root.isLaptop ? 1 : 100
                    stopIndicatorValues: [to]
                    value: root.isLaptop ? root.brightness?.brightness ?? 0 : Hyprsunset.gamma
                    enabled: !root.isLaptop || !!root.brightness
                    Accessible.name: root.isLaptop ? Translation.tr("Brightness") : Translation.tr("Gamma")
                    tooltipContent: (root.isLaptop ? Math.round(value * 100) : Math.round(value)) + "%"
                    onMoved: {
                        if (root.isLaptop) root.brightness.setBrightness(value);
                        else Hyprsunset.setGamma(Math.round(value));
                    }
                }

                StyledText {
                    Layout.preferredWidth: 36
                    horizontalAlignment: Text.AlignRight
                    text: (root.isLaptop ? Math.round((root.brightness?.brightness ?? 0) * 100) : Hyprsunset.gamma) + "%"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    Rectangle {
        id: trayContainer
        property bool expanded: false
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: Math.min(root.width, trayRow.implicitWidth + 20)
        implicitHeight: 28
        radius: height / 2
        color: root.elevatedSurface
        visible: !root.wifiDrawerOpen && !root.audioDrawerOpen && !root.bluetoothDrawerOpen && !root.nightLightDrawerOpen
            && (tray.pinnedItems.length > 0 || tray.unpinnedItems.length > 0)
        onVisibleChanged: if (!visible) expanded = false

        RowLayout {
            id: trayRow
            anchors.centerIn: parent
            width: Math.max(0, Math.min(implicitWidth, parent.width - 20))
            spacing: 4

            Flickable {
                Layout.fillWidth: true
                Layout.preferredWidth: tray.implicitWidth
                Layout.preferredHeight: tray.implicitHeight
                contentWidth: tray.width
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                interactive: contentWidth > width

                SysTray {
                    id: tray
                    showSeparator: false
                    showOverflowMenu: false
                    pinnedItems: trayContainer.expanded
                        ? TrayService.pinnedItems.concat(TrayService.unpinnedItems)
                        : TrayService.pinnedItems
                    onUnpinnedItemsChanged: if (!unpinnedItems.length) trayContainer.expanded = false
                }
            }

            RippleButton {
                visible: tray.unpinnedItems.length > 0
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                topPadding: 0
                bottomPadding: 0
                buttonRadius: height / 2
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                Accessible.name: trayContainer.expanded
                    ? Translation.tr("Hide tray icons") : Translation.tr("Show hidden tray icons")
                onClicked: trayContainer.expanded = !trayContainer.expanded

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: trayContainer.expanded ? "chevron_left" : "chevron_right"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
