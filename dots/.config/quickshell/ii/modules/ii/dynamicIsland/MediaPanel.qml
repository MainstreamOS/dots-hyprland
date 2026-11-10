import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.mediaControls

ColumnLayout {
    id: root
    readonly property bool busy: playerSelector.popup.visible
    spacing: 8 * Appearance.sizes.islandScale
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: {
            if (!IslandPanels.enabled("localsend")) return;
            GlobalStates.mediaTransferActive = false;
            GlobalStates.mediaReceiveActive = true;
            IslandState.beginTransfer();
            GlobalStates.mediaControlsOpen = true;
            if (!LocalSend.receiveActive) LocalSend.startReceive();
        }
    }
    Loader {
        Layout.fillWidth: true
        Layout.preferredHeight: active ? Appearance.sizes.mediaControlsHeight * Appearance.sizes.islandScale : 0
        active: !!IslandState.player
        sourceComponent: PlayerControl {
            player: IslandState.player
            prefetchedArt: IslandState.mediaCoverArt
            radius: Appearance.rounding.large * Appearance.sizes.islandScale
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 140 * Appearance.sizes.islandScale
        visible: IslandState.mediaDiscoveryComplete && !IslandState.player
        MaterialSymbol { Layout.alignment: Qt.AlignHCenter; text: "music_note"; iconSize: 42 * Appearance.sizes.islandScale; color: Appearance.barStripContent.colPrimary }
        StyledText { Layout.alignment: Qt.AlignHCenter; text: Translation.tr("No media playing"); color: Appearance.barStripContent.colOnLayer0; font.pixelSize: Appearance.font.basePixelSize.large * Appearance.sizes.islandScale }
        StyledText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: Translation.tr("Play music or video in a browser, Spotify, VLC, or an MPRIS-enabled player."); color: Appearance.barStripContent.colOnSurfaceVariant }
    }
    MediaPlayerSelector {
        id: playerSelector
        popupAbove: true
        players: IslandState.players
        player: IslandState.player
        Layout.fillWidth: true
        Layout.leftMargin: Appearance.sizes.elevationMargin * Appearance.sizes.islandScale
        Layout.rightMargin: Appearance.sizes.elevationMargin * Appearance.sizes.islandScale
        onPlayerSelected: player => IslandState.preferredPlayer = player.dbusName
    }
}
