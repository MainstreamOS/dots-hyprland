import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import qs.modules.common.functions

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Hyprland

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")

    Layout.fillHeight: true
    implicitWidth: rowLayout.implicitWidth + rowLayout.spacing * 2
    implicitHeight: Appearance.sizes.baseBarHeight

    // What the controls popup centers on. The slot hands over the whole pill
    // where media shares one with resources — the two read as a single
    // control there, so the popup follows their combined width.
    readonly property Item popupAnchorItem: parent?.popupAnchor ?? root

    Timer {
        running: activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: activePlayer.positionChanged()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
        onPressed: (event) => {
            if (event.button === Qt.MiddleButton) {
                activePlayer.togglePlaying();
            } else if (event.button === Qt.BackButton) {
                activePlayer.previous();
            } else if (event.button === Qt.ForwardButton) {
                activePlayer.next();
            } else if (event.button === Qt.RightButton) {
                GlobalStates.mediaWidgetItem = root.popupAnchorItem;
                GlobalStates.toggleReceiveView();
            } else if (event.button === Qt.LeftButton) {
                GlobalStates.mediaWidgetItem = root.popupAnchorItem;
                GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
            }
        }
    }

    MediaTransferDropArea {
        anchors.fill: parent
        popupAnchorItem: root.popupAnchorItem
    }

    RowLayout { // Real content
        id: rowLayout

        spacing: 4
        anchors.fill: parent

        ClippedFilledCircularProgress {
            id: mediaCircProg
            Layout.alignment: Qt.AlignVCenter
            lineWidth: Appearance.rounding.unsharpen
            value: LocalSend.receiveSessionActive ? LocalSend.receiveProgressFraction
                : activePlayer?.position / activePlayer?.length
            implicitSize: 20
            colPrimary: LocalSend.receiveActive ? Appearance.colors.colPrimary
                : Appearance.colors.colOnSecondaryContainer
            enableAnimation: false

            Item {
                anchors.centerIn: parent
                width: mediaCircProg.implicitSize
                height: mediaCircProg.implicitSize

                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 1
                    text: LocalSend.receiveActive ? "download"
                        : activePlayer?.isPlaying ? "pause" : "music_note"
                    iconSize: Appearance.font.pixelSize.normal
                    color: LocalSend.receiveActive ? Appearance.colors.colPrimary
                        : Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }

        StyledText {
            visible: Config.options.bar.verbose
            width: rowLayout.width - (CircularProgress.size + rowLayout.spacing * 2)
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true // Ensures the text takes up available space
            Layout.rightMargin: rowLayout.spacing
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight // Truncates the text on the right
            color: Appearance.colors.colOnLayer1
            text: `${cleanedTitle}${activePlayer?.trackArtist ? ' • ' + activePlayer.trackArtist : ''}`
        }

    }

}
