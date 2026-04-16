pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Qt5Compat.GraphicalEffects

LazyLoader {
    id: root

    property Item anchorTarget
    property bool shown: false

    active: shown

    component: PanelWindow {
        id: popupWindow
        color: "transparent"

        anchors.left: !Config.options.bar.vertical || (Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.right: Config.options.bar.vertical && Config.options.bar.bottom
        anchors.top: Config.options.bar.vertical || (!Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.bottom: !Config.options.bar.vertical && Config.options.bar.bottom

        implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
        implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

        mask: Region {
            item: popupBackground
        }

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        margins {
            left: {
                if (!Config.options.bar.vertical) {
                    let mapped = root.QsWindow?.mapFromItem(
                        root.anchorTarget,
                        (root.anchorTarget.width - popupBackground.implicitWidth) / 2, 0
                    );
                    // Clamp to screen edges
                    let screenW = popupWindow.screen?.width ?? 1920;
                    let x = mapped?.x ?? 0;
                    let maxX = screenW - popupBackground.implicitWidth - Appearance.sizes.elevationMargin * 2;
                    return Math.max(0, Math.min(x, maxX));
                }
                return Appearance.sizes.verticalBarWidth;
            }
            top: {
                if (!Config.options.bar.vertical) return Appearance.sizes.barHeight;
                let mapped = root.QsWindow?.mapFromItem(
                    root.anchorTarget,
                    0, (root.anchorTarget.height - popupBackground.implicitHeight) / 2
                );
                // Clamp to screen edges
                let screenH = popupWindow.screen?.height ?? 1080;
                let y = mapped?.y ?? 0;
                let maxY = screenH - popupBackground.implicitHeight - Appearance.sizes.elevationMargin * 2;
                return Math.max(0, Math.min(y, maxY));
            }
            right: Appearance.sizes.verticalBarWidth
            bottom: Appearance.sizes.barHeight
        }
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        StyledRectangularShadow {
            target: popupBackground
        }

        Rectangle {
            id: popupBackground
            readonly property real margin: 14
            anchors {
                fill: parent
                leftMargin: Appearance.sizes.elevationMargin
                rightMargin: Appearance.sizes.elevationMargin
                topMargin: Appearance.sizes.elevationMargin
                bottomMargin: Appearance.sizes.elevationMargin
            }
            implicitWidth: popupContent.implicitWidth + margin * 2
            implicitHeight: popupContent.implicitHeight + margin * 2
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.small
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            ColumnLayout {
                id: popupContent
                anchors {
                    fill: parent
                    margins: popupBackground.margin
                }
                spacing: 10

                // Header
                RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        text: "volume_up"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: Translation.tr("Audio Output")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: Math.round((Audio.sink?.audio.volume ?? 0) * 100) + "%"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: "monospace"
                        color: Appearance.colors.colSubtext
                    }
                }

                // Master volume slider
                RowLayout {
                    spacing: 8
                    MouseArea {
                        implicitWidth: 24; implicitHeight: 24
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Audio.sink) Audio.sink.audio.muted = !Audio.sink.audio.muted;
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: {
                                if (Audio.sink?.audio.muted) return "volume_off";
                                let vol = Audio.sink?.audio.volume ?? 0;
                                if (vol <= 0) return "volume_mute";
                                if (vol < 0.5) return "volume_down";
                                return "volume_up";
                            }
                            iconSize: 20
                            color: Audio.sink?.audio.muted ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                        }
                    }
                    StyledSlider {
                        Layout.fillWidth: true
                        value: Audio.sink?.audio.volume ?? 0
                        onMoved: { if (Audio.sink) Audio.sink.audio.volume = value; }
                    }
                }

                // Separator
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.5
                }

                // App list
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: appRepeater.count > 0

                    Repeater {
                        id: appRepeater
                        model: ScriptModel { values: Audio.outputAppNodes }
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: appRow.implicitHeight

                            PwObjectTracker { objects: [modelData] }

                            RowLayout {
                                id: appRow
                                anchors { left: parent.left; right: parent.right }
                                spacing: 6

                                MouseArea {
                                    implicitWidth: 28; implicitHeight: 28
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: modelData.audio.muted = !modelData.audio.muted

                                    Image {
                                        id: appIcon
                                        anchors.fill: parent
                                        visible: false
                                        sourceSize: Qt.size(28, 28)
                                        source: {
                                            let icon = AppSearch.guessIcon(modelData?.properties["application.icon-name"] ?? "");
                                            if (AppSearch.iconExists(icon))
                                                return Quickshell.iconPath(icon, "image-missing");
                                            icon = AppSearch.guessIcon(modelData?.properties["node.name"] ?? "");
                                            return Quickshell.iconPath(icon, "image-missing");
                                        }
                                    }
                                    Desaturate {
                                        anchors.fill: appIcon
                                        source: appIcon
                                        desaturation: modelData?.audio.muted ? 1.0 : 0.0
                                        opacity: modelData?.audio.muted ? 0.4 : 1.0
                                    }
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: modelData?.audio.muted ?? false
                                        text: "volume_off"
                                        iconSize: 18
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: -4
                                    StyledText {
                                        Layout.fillWidth: true
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colSubtext
                                        elide: Text.ElideRight
                                        text: {
                                            const app = Audio.appNodeDisplayName(modelData);
                                            const media = modelData.properties["media.name"];
                                            return media != undefined ? `${app} • ${media}` : app;
                                        }
                                    }
                                    StyledSlider {
                                        Layout.fillWidth: true
                                        value: modelData?.audio.volume ?? 0
                                        onMoved: modelData.audio.volume = value
                                        configuration: StyledSlider.Configuration.S
                                    }
                                }
                            }
                        }
                    }
                }

                // Device selector
                StyledComboBox {
                    Layout.fillWidth: true
                    model: Audio.outputDevices.map(node => Audio.friendlyDeviceName(node))
                    currentIndex: Audio.outputDevices.findIndex(item => item.id === Pipewire.defaultAudioSink?.id)
                    onActivated: (index) => {
                        Audio.setDefaultSink(Audio.outputDevices[index]);
                    }
                }

                // Done button
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    RippleButton {
                        implicitWidth: doneText.implicitWidth + 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.small
                        onClicked: root.shown = false
                        contentItem: StyledText {
                            id: doneText
                            anchors.centerIn: parent
                            text: Translation.tr("Done")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
        }
    }
}
