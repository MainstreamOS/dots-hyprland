import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.mediaControls

ColumnLayout {
    readonly property bool busy: playerSelector.popup.visible
    spacing: 8
    Loader {
        Layout.fillWidth: true
        Layout.preferredHeight: active ? Appearance.sizes.mediaControlsHeight : 0
        active: !!IslandState.player
        sourceComponent: PlayerControl {
            player: IslandState.player
            radius: Appearance.rounding.large
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 140
        visible: !IslandState.player
        MaterialSymbol { Layout.alignment: Qt.AlignHCenter; text: "music_note"; iconSize: 42; color: Appearance.barStripContent.colPrimary }
        StyledText { Layout.alignment: Qt.AlignHCenter; text: Translation.tr("No media playing"); color: Appearance.barStripContent.colOnLayer0; font.pixelSize: Appearance.font.pixelSize.large }
        StyledText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: Translation.tr("Play music or video in a browser, Spotify, VLC, or an MPRIS-enabled player."); color: Appearance.barStripContent.colOnSurfaceVariant }
    }
    MediaPlayerSelector {
        id: playerSelector
        popupAbove: true
        players: IslandState.players
        player: IslandState.player
        Layout.fillWidth: true
        Layout.leftMargin: Appearance.sizes.elevationMargin
        Layout.rightMargin: Appearance.sizes.elevationMargin
        onPlayerSelected: player => IslandState.preferredPlayer = player.dbusName
    }
}
