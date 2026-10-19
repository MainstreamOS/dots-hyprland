import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

StyledComboBox {
    id: root
    property var players: []
    property var player: null
    property bool popupAbove: false
    signal playerSelected(var player)

    visible: players.length > 1
    textRole: "title"
    buttonAppIcon: root.player ? AppSearch.guessIcon(root.player.desktopEntry || root.player.identity) : ""
    displayText: StringUtils.cleanMusicTitle(root.player?.trackTitle) || root.player?.identity || ""
    model: root.players.map(p => ({
        appIcon: AppSearch.guessIcon(p.desktopEntry || p.identity),
        title: StringUtils.cleanMusicTitle(p.trackTitle) || p.identity || ""
    }))
    currentIndex: root.players.indexOf(root.player)
    // Rebuilding the model for a new title must not move the choice to its first row.
    onModelChanged: Qt.callLater(root.followPlayer)
    function followPlayer() {
        root.currentIndex = Qt.binding(() => root.players.indexOf(root.player));
    }
    onActivated: index => {
        if (root.players[index]) root.playerSelected(root.players[index]);
    }
    popup.y: root.popupAbove ? -popup.height - 4 : root.height + 4
    popup.height: Math.min(Appearance.sizes.mediaControlsHeight, popup.contentItem.implicitHeight + popup.topPadding + popup.bottomPadding)
}
