pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar

ColumnLayout {
    id: root
    property var contentColors: Appearance.islandContent
    spacing: 6
    readonly property bool showUtilButtons: Config.options.bar.utilButtons.showScreenSnip
        || Config.options.bar.utilButtons.showScreenRecord
        || Config.options.bar.utilButtons.showColorPicker
        || Config.options.bar.utilButtons.showKeyboardToggle
        || Config.options.bar.utilButtons.showMicToggle
        || Config.options.bar.utilButtons.showDarkModeToggle
        || Config.options.bar.utilButtons.showPerformanceProfileToggle
    readonly property real bottomBarHeight: showUtilButtons ? (utilButtonsContainer.implicitHeight + spacing) : 0
    implicitHeight: Math.min(208, metrics.implicitHeight
        + (batteryStrip.visible ? batteryStrip.implicitHeight + spacing : 0)
        + (showUtilButtons ? bottomBarHeight : 0))
    readonly property var batteries: {
        const entries = [];
        if (Battery.available) entries.push({
            id: "computer", label: Translation.tr("Computer"), symbol: "battery_android_full",
            percentage: Battery.percentage, state: Battery.chargeState, power: Battery.energyRate,
            time: Battery.isCharging ? Battery.timeToFull : Battery.timeToEmpty, source: ""
        });
        // A charge of -1 is a phone without a battery report, not an empty one.
        const peers = Phone.devices.filter(d => d.reachable && d.charge >= 0 && d.charge <= 100);
        for (const device of peers) entries.push({
            id: "kde:" + device.id, label: device.name || Translation.tr("Phone"),
            symbol: device.type === "computer" ? "laptop" : device.type === "tablet" ? "tablet_android" : "smartphone",
            percentage: device.charge / 100,
            state: device.charging ? UPowerDeviceState.Charging : device.charge >= 100 ? UPowerDeviceState.FullyCharged : UPowerDeviceState.Discharging,
            power: 0, time: 0, source: Phone.backendName
        });
        const kdePhones = peers.some(d => ["phone", "tablet"].includes(d.type));
        for (const device of UPower.devices.values) {
            if (!device.ready || !device.isPresent || device.isLaptopBattery
                || [UPowerDeviceType.Unknown, UPowerDeviceType.LinePower].includes(device.type)) continue;
            const bluetooth = device.nativePath.startsWith("/org/bluez/");
            if (bluetooth && !Bluetooth.devices.values.some(d => d.dbusPath === device.nativePath && d.connected)) continue;
            if (kdePhones && [UPowerDeviceType.Phone, UPowerDeviceType.Tablet].includes(device.type)) continue;
            const symbol = device.type === UPowerDeviceType.Phone ? "smartphone"
                : device.type === UPowerDeviceType.Tablet ? "tablet_android"
                : device.type === UPowerDeviceType.Mouse ? "mouse"
                : device.type === UPowerDeviceType.Keyboard ? "keyboard"
                : [UPowerDeviceType.Headset, UPowerDeviceType.Headphones, UPowerDeviceType.OtherAudio].includes(device.type) ? "headphones"
                : device.type === UPowerDeviceType.GamingInput ? "sports_esports" : "battery_android_full";
            entries.push({id: device.nativePath, label: device.model || Translation.tr("Device battery"), symbol,
                percentage: device.percentage, state: device.state, power: device.changeRate,
                time: device.state === UPowerDeviceState.Charging ? device.timeToFull : device.timeToEmpty,
                source: bluetooth ? Translation.tr("Bluetooth") : Translation.tr("Battery")});
        }
        return entries;
    }
    readonly property bool showIGpu: Config.options.resources.enableGpu
        && Config.options.resources.gpu.bar.showIGpu && GpuUsage.iGpuAvailable
        && [1, 2].includes(Config.options.bar.resources.gpuLayout)
    readonly property bool showDGpu: Config.options.resources.enableGpu
        && Config.options.resources.gpu.bar.showDGpu && GpuUsage.dGpuAvailable
        && [0, 2].includes(Config.options.bar.resources.gpuLayout)
    readonly property bool watching: visible && (QsWindow.window?.visible ?? false)
    property bool registered: false
    function updateWatcher() {
        if (registered === watching) return;
        ResourceUsage.islandWatchers += watching ? 1 : -1;
        GpuUsage.islandWatchers += watching ? 1 : -1;
        registered = watching;
    }
    onWatchingChanged: updateWatcher()
    Component.onCompleted: updateWatcher()
    Component.onDestruction: {
        if (registered) {
            ResourceUsage.islandWatchers = Math.max(0, ResourceUsage.islandWatchers - 1);
            GpuUsage.islandWatchers = Math.max(0, GpuUsage.islandWatchers - 1);
        }
    }
    function gb(kb) { return (kb / 1048576).toFixed(1) + " GB"; }
    function load(usage) {
        return (usage > 0.8 ? Translation.tr("High") : usage > 0.4 ? Translation.tr("Medium") : Translation.tr("Low"))
            + " (" + Math.round(usage * 100) + "%)";
    }
    BatteryStrip {
        id: batteryStrip
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        Layout.minimumHeight: implicitHeight
        Layout.maximumHeight: implicitHeight
        visible: entries.length > 0
        entries: root.batteries
        contentColors: root.contentColors
    }
    StyledFlickable {
        id: metricsScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: metrics.implicitHeight
        contentWidth: width
        contentHeight: metrics.implicitHeight
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ColumnLayout {
            id: metrics
            width: metricsScroll.width
            spacing: root.spacing

            Rectangle {
                id: resourceSection
                Layout.fillWidth: true
                implicitHeight: sectionContent.implicitHeight + 20
                radius: Appearance?.rounding?.normal ?? 17
                color: Appearance.surfaces.raised
                Accessible.role: Accessible.Button
                Accessible.name: Translation.tr("Task Manager")
                Accessible.onPressAction: Session.launchTaskManager()

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Session.launchTaskManager()
                }

                ColumnLayout {
                    id: sectionContent
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Repeater {
                            model: [
                                {
                                    show: true,
                                    symbol: "memory",
                                    label: Translation.tr("RAM"),
                                    readings: [
                                        {icon: "clock_loader_60", label: Translation.tr("Used:"), value: root.gb(ResourceUsage.memoryUsed)},
                                        {icon: "check_circle", label: Translation.tr("Free:"), value: root.gb(ResourceUsage.memoryFree)},
                                        {icon: "empty_dashboard", label: Translation.tr("Total:"), value: root.gb(ResourceUsage.memoryTotal)}
                                    ]
                                },
                                {
                                    show: ResourceUsage.swapTotal > 0,
                                    symbol: "swap_horiz",
                                    label: Translation.tr("Swap"),
                                    readings: [
                                        {icon: "clock_loader_60", label: Translation.tr("Used:"), value: root.gb(ResourceUsage.swapUsed)},
                                        {icon: "check_circle", label: Translation.tr("Free:"), value: root.gb(ResourceUsage.swapFree)},
                                        {icon: "empty_dashboard", label: Translation.tr("Total:"), value: root.gb(ResourceUsage.swapTotal)}
                                    ]
                                },
                                {
                                    show: true,
                                    symbol: "planner_review",
                                    label: Translation.tr("CPU"),
                                    readings: [
                                        {icon: "bolt", label: Translation.tr("Load:"), value: Math.round(ResourceUsage.cpuUsage * 100) + "%"},
                                        {icon: "planner_review", label: Translation.tr("Freq:"), value: ResourceUsage.cpuFreqency.toFixed(2) + " GHz"},
                                        {icon: "thermometer", label: Translation.tr("Temp:"), value: Math.round(ResourceUsage.cpuTemperature) + " °C"}
                                    ]
                                }
                            ]

                            ColumnLayout {
                                id: colLayout
                                required property var modelData
                                visible: colLayout.modelData.show !== false
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.minimumWidth: 0
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 5
                                    MaterialSymbol {
                                        text: colLayout.modelData.symbol
                                        iconSize: 16
                                        color: root.contentColors.colOnSurfaceVariant
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: colLayout.modelData.label
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        color: root.contentColors.colOnSurfaceVariant
                                        elide: Text.ElideRight
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Repeater {
                                        model: colLayout.modelData.readings
                                        RowLayout {
                                            id: rowItem
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 4
                                            visible: rowItem.modelData.show !== false

                                            MaterialSymbol {
                                                text: rowItem.modelData.icon
                                                iconSize: 13
                                                color: root.contentColors.colOnSurfaceVariant
                                            }
                                            StyledText {
                                                text: rowItem.modelData.label
                                                font.pixelSize: 11
                                                color: root.contentColors.colOnSurfaceVariant
                                            }
                                            Item {
                                                Layout.fillWidth: true
                                            }
                                            StyledText {
                                                text: rowItem.modelData.value
                                                font.pixelSize: 11
                                                font.weight: Font.Medium
                                                color: root.contentColors.colOnLayer0
                                                horizontalAlignment: Text.AlignRight
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16
                        visible: root.showIGpu || root.showDGpu

                        Repeater {
                            model: [
                                {
                                    show: root.showIGpu,
                                    symbol: "empty_dashboard",
                                    label: "IGPU",
                                    readings: [
                                        {icon: "bolt", label: Translation.tr("Load:"), value: root.load(GpuUsage.iGpuUsage), show: Config.options.resources.gpu.bar.iGpu.showUsage},
                                        {icon: "clock_loader_60", label: Translation.tr("VRAM:"), value: GpuUsage.iGpuVramUsedGB.toFixed(1) + " / " + GpuUsage.iGpuVramTotalGB.toFixed(1) + " GB", show: Config.options.resources.gpu.bar.iGpu.showVram},
                                        {icon: "thermometer", label: Translation.tr("Temp:"), value: GpuUsage.iGpuTemperature + " °C", show: Config.options.resources.gpu.bar.iGpu.showTemp}
                                    ]
                                },
                                {
                                    show: root.showDGpu,
                                    symbol: "empty_dashboard",
                                    label: "DGPU",
                                    readings: [
                                        {icon: "bolt", label: Translation.tr("Load:"), value: root.load(GpuUsage.dGpuUsage), show: Config.options.resources.gpu.bar.dGpu.showUsage},
                                        {icon: "clock_loader_60", label: Translation.tr("VRAM:"), value: GpuUsage.dGpuVramUsedGB.toFixed(1) + " / " + GpuUsage.dGpuVramTotalGB.toFixed(1) + " GB", show: Config.options.resources.gpu.bar.dGpu.showVram},
                                        {icon: "thermometer", label: Translation.tr("Temp:"), value: GpuUsage.dGpuTemperature + " °C", show: Config.options.resources.gpu.bar.dGpu.showTemp}
                                    ]
                                }
                            ]

                            ColumnLayout {
                                id: gpuColLayout
                                required property var modelData
                                visible: gpuColLayout.modelData.show !== false
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.minimumWidth: 0
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 5
                                    MaterialSymbol {
                                        text: gpuColLayout.modelData.symbol
                                        iconSize: 16
                                        color: root.contentColors.colOnSurfaceVariant
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: gpuColLayout.modelData.label
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        color: root.contentColors.colOnSurfaceVariant
                                        elide: Text.ElideRight
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    Repeater {
                                        model: gpuColLayout.modelData.readings
                                        RowLayout {
                                            id: gpuRowItem
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 4
                                            visible: gpuRowItem.modelData.show !== false

                                            MaterialSymbol {
                                                text: gpuRowItem.modelData.icon
                                                iconSize: 13
                                                color: root.contentColors.colOnSurfaceVariant
                                            }
                                            StyledText {
                                                text: gpuRowItem.modelData.label
                                                font.pixelSize: 11
                                                color: root.contentColors.colOnSurfaceVariant
                                            }
                                            Item {
                                                Layout.fillWidth: true
                                            }
                                            StyledText {
                                                text: gpuRowItem.modelData.value
                                                font.pixelSize: 11
                                                font.weight: Font.Medium
                                                color: root.contentColors.colOnLayer0
                                                horizontalAlignment: Text.AlignRight
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    Rectangle {
        id: utilButtonsContainer
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: utilButtons.implicitWidth + 20
        implicitHeight: 28
        radius: 14
        color: Appearance.surfaces.raised
        visible: root.showUtilButtons

        UtilButtons {
            id: utilButtons
            contentColors: root.contentColors
            anchors.centerIn: parent
        }
    }
}
