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
import Quickshell
import Quickshell.Services.Mpris

Item {
    id: root

    property real radius: Appearance.rounding.medium
    property real targetWidth: 440
    property real targetHeight: 160

    width: targetWidth
    height: targetHeight

    readonly property string uiState: {
        if (LocalSend.receiveError.length > 0) return "error";
        if (LocalSend.receiveSessionActive) return "receiving";
        if (LocalSend.receiveLastCount > 0) return "done";
        return "waiting";
    }

    component ActionButton: RippleButton {
        id: actionButton
        property bool filled: false
        property string label: ""
        implicitWidth: actionButtonText.implicitWidth + (filled ? 26 : 22)
        implicitHeight: 28
        buttonRadius: Appearance.rounding.small
        colBackground: filled ? root.blendedColors.colPrimary : Qt.rgba(0, 0, 0, 0)
        colBackgroundHover: filled ? root.blendedColors.colPrimaryHover
            : ColorUtils.transparentize(root.blendedColors.colSecondaryContainerHover, 0.5)
        colRipple: filled ? root.blendedColors.colPrimaryActive
            : ColorUtils.transparentize(root.blendedColors.colSecondaryContainerActive, 0.4)
        contentItem: StyledText {
            id: actionButtonText
            anchors.centerIn: parent
            text: actionButton.label
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: actionButton.filled ? Font.DemiBold : Font.Normal
            color: actionButton.filled ? root.blendedColors.colOnPrimary : root.blendedColors.colOnLayer0
        }
    }

    // Mirror PlayerControl's art-derived background so this panel reads as
    // a continuation of the music player, not a separate widget.
    property MprisPlayer activePlayer: MprisController.activePlayer
    property var artUrl: activePlayer?.trackArtUrl ?? ""
    property string artFileName: artUrl && String(artUrl).length > 0 ? Qt.md5(String(artUrl)) : ""
    property string artFilePath: artFileName.length > 0 ? `${Directories.coverArt}/${artFileName}` : ""
    property string displayedArtFilePath: (root.visible && artFilePath.length > 0) ? Qt.resolvedUrl(artFilePath) : ""

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
                    text: "download"
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.blendedColors.colOnLayer0
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.uiState === "receiving"
                        ? (LocalSend.receiveSender.length > 0
                            ? Translation.tr("Receiving from %1").arg(LocalSend.receiveSender)
                            : Translation.tr("Receiving…"))
                        : Translation.tr("Receive via LocalSend")
                    elide: Text.ElideMiddle
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: root.blendedColors.colOnLayer0
                }
                MaterialSymbol {
                    visible: root.uiState === "waiting"
                    text: "progress_activity"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.blendedColors.colSubtext
                    NumberAnimation on rotation {
                        from: 0; to: 360
                        loops: Animation.Infinite
                        duration: 1500
                        running: root.uiState === "waiting" && root.visible
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
                    if (root.uiState === "receiving") return receivingComp;
                    if (root.uiState === "done") return doneComp;
                    if (root.uiState === "error") return errorComp;
                    return waitingComp;
                }
            }

            Component {
                id: waitingComp
                ColumnLayout {
                    spacing: 4

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Visible to nearby devices as \"%1\"").arg(LocalSend.receiveAlias)
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.blendedColors.colOnLayer0
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        text: Translation.tr("Incoming files are automatically saved to the Downloads folder")
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.blendedColors.colSubtext
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Item { Layout.fillWidth: true }

                        ActionButton {
                            label: Translation.tr("Hide")
                            onClicked: GlobalStates.mediaControlsOpen = false
                        }
                        ActionButton {
                            filled: true
                            label: Translation.tr("Turn off")
                            onClicked: LocalSend.stopReceive()
                        }
                    }
                }
            }

            Component {
                id: receivingComp
                ColumnLayout {
                    spacing: 8
                    Item { Layout.fillHeight: true }
                    StyledText {
                        Layout.fillWidth: true
                        text: LocalSend.receiveSender.length > 0
                            ? Translation.tr("Receiving from %1…").arg(LocalSend.receiveSender)
                            : Translation.tr("Receiving…")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: root.blendedColors.colSubtext
                        elide: Text.ElideRight
                    }
                    StyledProgressBar {
                        Layout.fillWidth: true
                        wavy: true
                        highlightColor: root.blendedColors.colPrimary
                        trackColor: root.blendedColors.colSecondaryContainer
                        value: LocalSend.receiveProgressFraction
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            Component {
                id: doneComp
                ColumnLayout {
                    spacing: 4

                    Item { Layout.fillHeight: true }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8
                        MaterialSymbol {
                            text: "check_circle"
                            iconSize: Appearance.font.pixelSize.huge
                            color: root.blendedColors.colPrimary
                        }
                        StyledText {
                            text: LocalSend.receiveLastCount === 1
                                ? Translation.tr("Received 1 file")
                                : Translation.tr("Received %1 files").arg(LocalSend.receiveLastCount)
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.weight: Font.DemiBold
                            color: root.blendedColors.colOnLayer0
                        }
                    }
                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Item { Layout.fillWidth: true }

                        ActionButton {
                            label: Translation.tr("Keep receiving")
                            onClicked: LocalSend.receiveClearDone()
                        }
                        ActionButton {
                            filled: true
                            label: Translation.tr("Open folder")
                            onClicked: Quickshell.execDetached(["xdg-open", LocalSend.receiveDir])
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
                            text: Translation.tr("Receiving failed")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: root.blendedColors.colOnLayer0
                            elide: Text.ElideRight
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        text: LocalSend.receiveError || Translation.tr("Unknown error")
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.blendedColors.colSubtext
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        ActionButton {
                            label: Translation.tr("Dismiss")
                            onClicked: {
                                LocalSend.dismissReceiveError();
                                GlobalStates.mediaControlsOpen = false;
                            }
                        }
                    }
                }
            }
        }
    }
}
