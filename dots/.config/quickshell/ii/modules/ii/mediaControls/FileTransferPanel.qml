pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.Mpris

Item {
    id: root

    property var fileUrls: []
    property real radius: Appearance.rounding.medium
    property real targetWidth: 440
    property real targetHeight: 160

    width: targetWidth
    height: targetHeight

    readonly property var fileNames: (fileUrls ?? []).map(u => {
        const path = String(u).replace(/^file:\/\//, "");
        try { return decodeURIComponent(path.split("/").pop() ?? ""); }
        catch (e) { return path.split("/").pop() ?? ""; }
    })
    readonly property string fileSummary: {
        if (fileNames.length === 0) return Translation.tr("No files");
        if (fileNames.length === 1) return fileNames[0];
        return Translation.tr("%1 files").arg(fileNames.length);
    }

    property int selectedIndex: -1

    // Mirror PlayerControl's art-derived background so this panel reads as
    // a continuation of the music player, not a separate widget.
    property MprisPlayer activePlayer: MprisController.activePlayer
    property var artUrl: activePlayer?.trackArtUrl ?? ""
    property string artFileName: artUrl && String(artUrl).length > 0 ? Qt.md5(String(artUrl)) : ""
    property string artFilePath: artFileName.length > 0 ? `${Directories.coverArt}/${artFileName}` : ""
    property string displayedArtFilePath: artFilePath.length > 0 ? Qt.resolvedUrl(artFilePath) : ""

    property color artDominantColor: ColorUtils.mix(
        (colorQuantizer?.colors[0] ?? Appearance.colors.colPrimary),
        Appearance.colors.colPrimaryContainer, 0.8
    ) || Appearance.m3colors.m3secondaryContainer

    ColorQuantizer {
        id: colorQuantizer
        source: root.displayedArtFilePath
        depth: 0
        rescaleSize: 1
    }

    property QtObject blendedColors: AdaptedMaterialScheme {
        color: root.artDominantColor
    }

    // Discovery runs continuously while the panel is open; clearing the
    // device list on drop would wipe devices that the running discover.py
    // already emitted (it dedupes by fingerprint and won't re-emit). We
    // only reset selection if it points beyond the current list.
    Connections {
        target: LocalSend
        function onDevicesChanged() {
            if (root.selectedIndex < 0 && LocalSend.devices.length === 1) {
                root.selectedIndex = 0;
            } else if (root.selectedIndex >= LocalSend.devices.length) {
                root.selectedIndex = LocalSend.devices.length > 0 ? 0 : -1;
            }
        }
    }

    StyledRectangularShadow {
        target: bg
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        color: ColorUtils.applyAlpha(root.blendedColors.colLayer0, 1)
        radius: root.radius

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: bg.width
                height: bg.height
                radius: bg.radius
            }
        }

        Image {
            id: blurredArt
            anchors.fill: parent
            source: root.displayedArtFilePath
            sourceSize.width: bg.width
            sourceSize.height: bg.height
            fillMode: Image.PreserveAspectCrop
            cache: false
            antialiasing: true
            asynchronous: true

            layer.enabled: true
            layer.effect: StyledBlurEffect {
                source: blurredArt
            }

            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(root.blendedColors.colLayer0, 0.3)
                radius: bg.radius
            }
        }

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "send"
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.blendedColors.colOnLayer0
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.fileNames.length > 0
                        ? root.fileSummary
                        : Translation.tr("Send via LocalSend")
                    elide: Text.ElideMiddle
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: root.blendedColors.colOnLayer0
                }
                MaterialSymbol {
                    visible: LocalSend.discovering
                    text: "progress_activity"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.blendedColors.colSubtext
                    NumberAnimation on rotation {
                        from: 0; to: 360
                        loops: Animation.Infinite
                        duration: 1500
                        running: LocalSend.discovering
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Appearance.colors.colOutlineVariant
                opacity: 0.4
            }

            Loader {
                id: bodyLoader
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: {
                    if (LocalSend.state === LocalSend.stateSending) return sendingComp;
                    if (LocalSend.state === LocalSend.stateSent) return sentComp;
                    if (LocalSend.state === LocalSend.stateError) return errorComp;
                    return idleComp;
                }
            }

            Component {
                id: idleComp
                ColumnLayout {
                    spacing: 4

                    StyledText {
                        Layout.fillWidth: true
                        // Only shown in the empty state so "Send to:" doesn't
                        // eat vertical room once devices have been discovered.
                        visible: LocalSend.devices.length === 0
                        text: LocalSend.discovering
                            ? Translation.tr("Searching for devices…")
                            : Translation.tr("No devices found")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.blendedColors.colSubtext
                    }

                    Flickable {
                        id: deviceFlickable
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // Only clip when the list actually overflows. With clip
                        // off (or with breathing room) the toggled row's rounded
                        // bg renders without its top/bottom edges getting
                        // shaved by the Flickable boundary.
                        clip: deviceColumn.implicitHeight > height
                        contentWidth: width
                        contentHeight: deviceColumn.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; opacity: 0.6 }

                        ColumnLayout {
                            id: deviceColumn
                            width: deviceFlickable.width
                            spacing: 2

                            Item { Layout.fillWidth: true; Layout.preferredHeight: 2 }

                            Repeater {
                                model: LocalSend.devices
                                delegate: RippleButton {
                                    id: deviceBtn
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: 32
                                    buttonRadius: Appearance.rounding.small
                                    toggled: root.selectedIndex === index
                                    colBackground: Qt.rgba(0, 0, 0, 0)
                                    colBackgroundHover: ColorUtils.transparentize(root.blendedColors.colSecondaryContainerHover, 0.5)
                                    colRipple: ColorUtils.transparentize(root.blendedColors.colSecondaryContainerActive, 0.4)
                                    colBackgroundToggled: root.blendedColors.colSecondaryContainer
                                    colBackgroundToggledHover: root.blendedColors.colSecondaryContainerHover
                                    colRippleToggled: root.blendedColors.colSecondaryContainerActive
                                    onClicked: root.selectedIndex = index

                                    contentItem: RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        MaterialSymbol {
                                            text: {
                                                switch (deviceBtn.modelData.deviceType) {
                                                case "mobile": return "phone_android";
                                                case "desktop": return "desktop_windows";
                                                case "web": return "language";
                                                case "headless": return "smart_display";
                                                case "server": return "dns";
                                                default: return "devices";
                                                }
                                            }
                                            iconSize: Appearance.font.pixelSize.normal
                                            color: deviceBtn.toggled
                                                ? root.blendedColors.colOnSecondaryContainer
                                                : root.blendedColors.colOnLayer0
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: deviceBtn.modelData.alias || deviceBtn.modelData.address
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            color: deviceBtn.toggled
                                                ? root.blendedColors.colOnSecondaryContainer
                                                : root.blendedColors.colOnLayer0
                                        }
                                        StyledText {
                                            text: deviceBtn.modelData.address
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: root.blendedColors.colSubtext
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true; Layout.preferredHeight: 2 }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Item { Layout.fillWidth: true }

                        RippleButton {
                            implicitWidth: cancelText.implicitWidth + 22
                            implicitHeight: 28
                            buttonRadius: Appearance.rounding.small
                            colBackground: Qt.rgba(0, 0, 0, 0)
                            colBackgroundHover: ColorUtils.transparentize(root.blendedColors.colSecondaryContainerHover, 0.5)
                            colRipple: ColorUtils.transparentize(root.blendedColors.colSecondaryContainerActive, 0.4)
                            onClicked: GlobalStates.mediaControlsOpen = false
                            contentItem: StyledText {
                                id: cancelText
                                anchors.centerIn: parent
                                text: Translation.tr("Cancel")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: root.blendedColors.colOnLayer0
                            }
                        }

                        RippleButton {
                            id: sendBtn
                            enabled: root.selectedIndex >= 0
                                && root.fileUrls.length > 0
                            implicitWidth: sendText.implicitWidth + 26
                            implicitHeight: 28
                            buttonRadius: Appearance.rounding.small
                            opacity: enabled ? 1.0 : 0.5
                            colBackground: root.blendedColors.colPrimary
                            colBackgroundHover: root.blendedColors.colPrimaryHover
                            colRipple: root.blendedColors.colPrimaryActive
                            onClicked: {
                                if (!enabled) return;
                                const dev = LocalSend.devices[root.selectedIndex];
                                if (!dev) return;
                                LocalSend.send(dev, root.fileUrls);
                            }
                            contentItem: StyledText {
                                id: sendText
                                anchors.centerIn: parent
                                text: Translation.tr("Send")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: root.blendedColors.colOnPrimary
                            }
                        }
                    }
                }
            }

            Component {
                id: sendingComp
                ColumnLayout {
                    spacing: 8
                    Item { Layout.fillHeight: true }
                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const dev = LocalSend.currentDevice;
                            const name = dev ? (dev.alias || dev.address) : "";
                            return name.length > 0
                                ? Translation.tr("Sending to %1…").arg(name)
                                : Translation.tr("Sending…");
                        }
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.blendedColors.colSubtext
                        elide: Text.ElideRight
                    }
                    StyledProgressBar {
                        Layout.fillWidth: true
                        wavy: true
                        highlightColor: root.blendedColors.colPrimary
                        trackColor: root.blendedColors.colSecondaryContainer
                        value: LocalSend.progressFraction
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            Component {
                id: sentComp
                Item {
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        MaterialSymbol {
                            text: "check_circle"
                            iconSize: Appearance.font.pixelSize.huge
                            color: root.blendedColors.colPrimary
                        }
                        StyledText {
                            text: Translation.tr("Sent")
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            color: root.blendedColors.colOnLayer0
                        }
                    }
                }
            }

            Component {
                id: errorComp
                ColumnLayout {
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol {
                            text: "error"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colError
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Failed")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: root.blendedColors.colOnLayer0
                            elide: Text.ElideRight
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        text: LocalSend.lastError || Translation.tr("Unknown error")
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.blendedColors.colSubtext
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        RippleButton {
                            implicitWidth: dismissText.implicitWidth + 22
                            implicitHeight: 26
                            buttonRadius: Appearance.rounding.small
                            colBackground: Qt.rgba(0, 0, 0, 0)
                            colBackgroundHover: ColorUtils.transparentize(root.blendedColors.colSecondaryContainerHover, 0.5)
                            colRipple: ColorUtils.transparentize(root.blendedColors.colSecondaryContainerActive, 0.4)
                            onClicked: {
                                LocalSend.reset();
                                GlobalStates.mediaControlsOpen = false;
                            }
                            contentItem: StyledText {
                                id: dismissText
                                anchors.centerIn: parent
                                text: Translation.tr("Dismiss")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: root.blendedColors.colOnLayer0
                            }
                        }
                    }
                }
            }
        }
    }
}
