//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.services
import qs.services.network
import qs.modules.common
import qs.modules.common.widgets
import "modules/settings/connectivity"

ApplicationWindow {
    id: root
    visible: true
    width: 700
    height: 800
    minimumWidth: 500
    minimumHeight: 600
    title: "Welcome"
    color: Appearance.m3colors.m3surfaceContainerLow

    // ── Monitor data ──
    property var monitors: []
    property var pendingChanges: ({})
    property string monitorsConfPath: `${Quickshell.env("HOME")}/.config/hypr/monitors.conf`

    function refreshMonitors() {
        monitorProc.running = true;
    }

    function parseMode(modeStr) {
        let match = modeStr.match(/^(\d+)x(\d+)@([\d.]+)Hz$/);
        if (!match) return null;
        return {
            width: parseInt(match[1]),
            height: parseInt(match[2]),
            refreshRate: parseFloat(match[3]),
            label: `${match[1]}x${match[2]} @ ${parseFloat(match[3]).toFixed(2)} Hz`
        };
    }

    function snapScale(scale) {
        const knownScales = [1.0, 1.25, 1.5, 5/3, 1.875, 2.0];
        return knownScales.reduce((prev, curr) =>
            Math.abs(curr - scale) < Math.abs(prev - scale) ? curr : prev);
    }

    function initPending(monitor) {
        let name = monitor.name;
        if (!pendingChanges[name]) {
            pendingChanges[name] = {
                width: monitor.width,
                height: monitor.height,
                refreshRate: monitor.refreshRate,
                scale: monitor.scale,
            };
        }
    }

    function updatePending(monName, key, value) {
        let p = Object.assign({}, pendingChanges[monName] ?? {});
        p[key] = value;
        pendingChanges[monName] = p;
        pendingChanges = Object.assign({}, pendingChanges);
    }

    function updatePendingBatch(monName, obj) {
        let p = Object.assign({}, pendingChanges[monName] ?? {}, obj);
        pendingChanges[monName] = p;
        pendingChanges = Object.assign({}, pendingChanges);
    }

    function applyMonitorChanges(monitorName) {
        let lines = [];
        monitors.forEach(mon => {
            let p = pendingChanges[mon.name] ?? {};
            let m = Object.assign({}, mon, p);
            let snapped = snapScale(m.scale);
            const scaleMap = { 1.0: "1", 1.25: "1.25", 1.5: "1.5", 2.0: "2" };
            let scale = scaleMap[snapped] ?? snapped.toFixed(4);
            let mode = `${m.width}x${m.height}@${m.refreshRate.toFixed(6)}`;
            lines.push(`monitor = ${mon.name}, ${mode}, 0x0, ${scale}`);
        });
        let fileContent = lines.join("\n") + "\n";
        let escaped = fileContent
            .replace(/\\/g, "\\\\")
            .replace(/'/g, "\\'")
            .replace(/\n/g, "\\n");
        let py =
            "path = '" + root.monitorsConfPath + "'\n" +
            "content = '" + escaped + "'\n" +
            "open(path, 'w').write(content)\n";
        writeProc.command = ["python3", "-c", py];
        writeProc.running = false;
        writeProc.running = true;
    }

    Process {
        id: monitorProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                try {
                    let parsed = JSON.parse(data);
                    root.monitors = parsed;
                    parsed.forEach(m => root.initPending(m));
                } catch (e) {}
            }
        }
    }

    Process {
        id: writeProc
        onExited: reloadProc.running = true
    }

    Process {
        id: reloadProc
        command: ["hyprctl", "reload"]
        onExited: Qt.callLater(root.refreshMonitors)
    }

    Component.onCompleted: refreshMonitors()

    // ── Main content ──
    ColumnLayout {
        anchors {
            fill: parent
            margins: root.width > 600 ? 40 : 20
        }
        spacing: 0

        // Centered content (no outer scroll)
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                id: contentColumn
                width: Math.min(parent.width, 600)
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    horizontalCenter: parent.horizontalCenter
                }
                spacing: 20

                // ── Welcome header ──
                StyledText {
                    text: Translation.tr("Welcome")
                    font.pixelSize: 32
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    Layout.alignment: Qt.AlignHCenter
                }

                    // ── Internet notice ──
                    NoticeBox {
                        Layout.fillWidth: true
                        materialIcon: "wifi"
                        text: Translation.tr("An internet connection is required for full installation. Please connect to Wi-Fi below before starting the installer.")
                    }

                    // ── Display section ──
                    ContentSection {
                        icon: "monitor"
                        title: Translation.tr("Display")

                        Repeater {
                            model: root.monitors

                            delegate: ColumnLayout {
                                id: monDelegate
                                required property var modelData
                                required property int index

                                property var mon: modelData
                                property string monName: mon.name
                                property var pending: root.pendingChanges[monName] ?? {}

                                property var modeModel: {
                                    let seen = new Set();
                                    let out = [];
                                    (mon.availableModes || []).forEach(modeStr => {
                                        let m = root.parseMode(modeStr);
                                        if (!m) return;
                                        let key = `${m.width}x${m.height}@${Math.round(m.refreshRate)}`;
                                        if (seen.has(key)) return;
                                        seen.add(key);
                                        out.push(m);
                                    });
                                    out.sort((a, b) => {
                                        let pd = (b.width * b.height) - (a.width * a.height);
                                        return pd !== 0 ? pd : b.refreshRate - a.refreshRate;
                                    });
                                    return out;
                                }

                                Layout.fillWidth: true
                                spacing: 0

                                // Monitor name label (only if multiple monitors)
                                StyledText {
                                    visible: root.monitors.length > 1
                                    text: monDelegate.monName
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colSubtext
                                    Layout.bottomMargin: 4
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: modeScaleColumn.implicitHeight
                                    radius: Appearance.rounding.normal
                                    color: Appearance.colors.colLayer2

                                    ColumnLayout {
                                        id: modeScaleColumn
                                        anchors { left: parent.left; right: parent.right }
                                        spacing: 0

                                        // ── Mode row ──
                                        Item {
                                            id: modeRow
                                            Layout.fillWidth: true
                                            implicitHeight: 44
                                            property bool popupOpen: modePopup.visible

                                            Rectangle {
                                                anchors.fill: parent
                                                topLeftRadius: Appearance.rounding.normal
                                                topRightRadius: Appearance.rounding.normal
                                                color: modeArea.containsMouse ? Appearance.colors.colLayer3 : "transparent"
                                                Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                                            }

                                            RowLayout {
                                                anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                                                spacing: 8
                                                StyledText {
                                                    text: Translation.tr("Mode")
                                                    font.pixelSize: Appearance.font.pixelSize.normal
                                                    color: Appearance.colors.colOnLayer2
                                                }
                                                Item { Layout.fillWidth: true }
                                                StyledText {
                                                    text: {
                                                        let p = monDelegate.pending;
                                                        let m = monDelegate.mon;
                                                        return `${p.width ?? m.width}×${p.height ?? m.height} @ ${(p.refreshRate ?? m.refreshRate).toFixed(2)} Hz`;
                                                    }
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    color: Appearance.colors.colSubtext
                                                }
                                                MaterialSymbol {
                                                    text: "keyboard_arrow_down"
                                                    iconSize: Appearance.font.pixelSize.larger
                                                    color: Appearance.colors.colSubtext
                                                    rotation: modeRow.popupOpen ? 180 : 0
                                                    Behavior on rotation { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                                                }
                                            }

                                            MouseArea {
                                                id: modeArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: modePopup.visible ? modePopup.close() : modePopup.open()
                                            }

                                            Popup {
                                                id: modePopup
                                                y: modeRow.height + 4
                                                width: modeRow.width
                                                padding: 8
                                                enter: Transition { PropertyAnimation { properties: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                                                exit:  Transition { PropertyAnimation { properties: "opacity"; to: 0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                                                background: Item {
                                                    StyledRectangularShadow { target: modeBg }
                                                    Rectangle { id: modeBg; anchors.fill: parent; radius: Appearance.rounding.normal; color: Appearance.m3colors.m3surfaceContainerHigh }
                                                }
                                                contentItem: ListView {
                                                    implicitHeight: Math.min(contentHeight, 300)
                                                    clip: true
                                                    spacing: 2
                                                    model: monDelegate.modeModel
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        required property int index
                                                        width: ListView.view.width
                                                        height: 36
                                                        radius: Appearance.rounding.small
                                                        property bool isCurrent: {
                                                            let p = monDelegate.pending;
                                                            let m = monDelegate.mon;
                                                            return modelData.width === (p.width ?? m.width) &&
                                                                   modelData.height === (p.height ?? m.height) &&
                                                                   Math.abs(modelData.refreshRate - (p.refreshRate ?? m.refreshRate)) < 0.1;
                                                        }
                                                        color: modeDlgMouse.containsMouse
                                                            ? (isCurrent ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover)
                                                            : (isCurrent ? Appearance.colors.colSecondaryContainer : "transparent")
                                                        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                                                        StyledText {
                                                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                                                            text: modelData.label
                                                            font.pixelSize: Appearance.font.pixelSize.normal
                                                            color: isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                                                        }
                                                        MouseArea {
                                                            id: modeDlgMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                root.updatePendingBatch(monDelegate.monName, {
                                                                    width: modelData.width,
                                                                    height: modelData.height,
                                                                    refreshRate: modelData.refreshRate,
                                                                });
                                                                modePopup.close();
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.m3colors.m3outlineVariant; opacity: 0.5 }

                                        // ── Scale row ──
                                        Item {
                                            id: scaleRow
                                            Layout.fillWidth: true
                                            implicitHeight: 44
                                            property bool popupOpen: scalePopup.visible
                                            property var scaleOptions: [
                                                { label: "100%", value: 1.0   },
                                                { label: "125%", value: 1.25  },
                                                { label: "150%", value: 1.5   },
                                                { label: "167%", value: 5/3   },
                                                { label: "188%", value: 1.875 },
                                                { label: "200%", value: 2.0   },
                                            ]

                                            Rectangle {
                                                anchors.fill: parent
                                                bottomLeftRadius: Appearance.rounding.normal
                                                bottomRightRadius: Appearance.rounding.normal
                                                color: scaleArea.containsMouse ? Appearance.colors.colLayer3 : "transparent"
                                                Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                                            }

                                            RowLayout {
                                                anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                                                spacing: 8
                                                StyledText {
                                                    text: Translation.tr("Scale")
                                                    font.pixelSize: Appearance.font.pixelSize.normal
                                                    color: Appearance.colors.colOnLayer2
                                                }
                                                Item { Layout.fillWidth: true }
                                                StyledText {
                                                    text: `${Math.round((monDelegate.pending.scale ?? monDelegate.mon.scale) * 100)}%`
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    color: Appearance.colors.colSubtext
                                                }
                                                MaterialSymbol {
                                                    text: "keyboard_arrow_down"
                                                    iconSize: Appearance.font.pixelSize.larger
                                                    color: Appearance.colors.colSubtext
                                                    rotation: scaleRow.popupOpen ? 180 : 0
                                                    Behavior on rotation { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                                                }
                                            }

                                            MouseArea {
                                                id: scaleArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: scalePopup.visible ? scalePopup.close() : scalePopup.open()
                                            }

                                            Popup {
                                                id: scalePopup
                                                y: scaleRow.height + 4
                                                width: scaleRow.width
                                                padding: 8
                                                enter: Transition { PropertyAnimation { properties: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                                                exit:  Transition { PropertyAnimation { properties: "opacity"; to: 0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                                                background: Item {
                                                    StyledRectangularShadow { target: scaleBg }
                                                    Rectangle { id: scaleBg; anchors.fill: parent; radius: Appearance.rounding.normal; color: Appearance.m3colors.m3surfaceContainerHigh }
                                                }
                                                contentItem: ListView {
                                                    implicitHeight: contentHeight
                                                    clip: true
                                                    spacing: 2
                                                    model: scaleRow.scaleOptions
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        required property int index
                                                        width: ListView.view.width
                                                        height: 36
                                                        radius: Appearance.rounding.small
                                                        property bool isCurrent: Math.abs((monDelegate.pending.scale ?? monDelegate.mon.scale) - modelData.value) < 0.001
                                                        color: scaleDlgMouse.containsMouse
                                                            ? (isCurrent ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover)
                                                            : (isCurrent ? Appearance.colors.colSecondaryContainer : "transparent")
                                                        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                                                        StyledText {
                                                            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                                                            text: modelData.label
                                                            font.pixelSize: Appearance.font.pixelSize.normal
                                                            color: isCurrent ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                                                        }
                                                        MouseArea {
                                                            id: scaleDlgMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                root.updatePending(monDelegate.monName, "scale", modelData.value);
                                                                scalePopup.close();
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Apply button
                                RippleButton {
                                    Layout.alignment: Qt.AlignRight
                                    Layout.topMargin: 8
                                    implicitWidth: applyRow.implicitWidth + 24
                                    implicitHeight: 36
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colPrimary
                                    colBackgroundHover: Appearance.colors.colPrimaryHover

                                    onClicked: root.applyMonitorChanges(monDelegate.monName)

                                    contentItem: RowLayout {
                                        id: applyRow
                                        anchors.centerIn: parent
                                        spacing: 6
                                        MaterialSymbol {
                                            text: "check"
                                            iconSize: 18
                                            color: Appearance.colors.colOnPrimary
                                        }
                                        StyledText {
                                            text: root.monitors.length > 1
                                                ? Translation.tr("Apply %1").arg(monDelegate.monName)
                                                : Translation.tr("Apply")
                                            color: Appearance.colors.colOnPrimary
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Wi-Fi section ──
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
                                onCheckedChanged: Network.enableWifi(checked)
                            }
                        }

                        StyledIndeterminateProgressBar {
                            visible: Network.wifiScanning
                            Layout.fillWidth: true
                        }

                        // Connected network
                        ConnectivityWifiItem {
                            visible: Network.wifiEnabled && Network.active !== null
                            wifiNetwork: Network.active ?? null
                            Layout.fillWidth: true
                        }

                        // Available networks (scrollable, fills remaining space)
                        Rectangle {
                            visible: Network.wifiEnabled && Network.availableNetworks.length > 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 80
                            radius: Appearance.rounding.small
                            color: "transparent"
                            clip: true

                            Flickable {
                                id: wifiFlickable
                                anchors.fill: parent
                                contentHeight: wifiListColumn.implicitHeight
                                clip: true
                                flickableDirection: Flickable.VerticalFlick
                                boundsBehavior: Flickable.StopAtBounds

                                ColumnLayout {
                                    id: wifiListColumn
                                    width: wifiFlickable.width
                                    spacing: 4

                                    Repeater {
                                        model: Network.availableNetworks

                                        ConnectivityWifiItem {
                                            required property var modelData
                                            wifiNetwork: modelData
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                ScrollBar.vertical: ScrollBar {
                                    policy: ScrollBar.AsNeeded
                                }
                            }
                        }

                        // Empty state
                        ColumnLayout {
                            visible: Network.wifiEnabled && Network.availableNetworks.length === 0 && !Network.wifiScanning && Network.active === null
                            Layout.fillWidth: true
                            Layout.topMargin: 10
                            Layout.bottomMargin: 10
                            spacing: 8

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 48
                                implicitHeight: 48
                                radius: 24
                                color: Appearance.colors.colLayer3

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "wifi_find"
                                    iconSize: 24
                                    color: Appearance.colors.colSubtext
                                }
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("No networks found — click Scan")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }

    }

    // ── Start Install button (floating over content) ──
    RippleButton {
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 24
        }
        z: 10
        implicitWidth: 220
        implicitHeight: 48
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover

        onClicked: {
            Quickshell.execDetached(["sudo", "-E", "calamares"]);
            Qt.quit();
        }

        contentItem: RowLayout {
            anchors.centerIn: parent
            spacing: 8
            MaterialSymbol {
                text: "install_desktop"
                iconSize: 22
                color: Appearance.colors.colOnPrimary
            }
            StyledText {
                text: Translation.tr("Start Install")
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnPrimary
            }
        }
    }
}
