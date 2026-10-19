import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtMultimedia

// A voice message or audio clip in a conversation, played in place.
RowLayout {
    id: root
    required property var attachment
    // The conversation's one player, and whether it holds this clip.
    required property MediaPlayer player
    required property bool current
    property color contentColor: Appearance.colors.colOnLayer1
    signal toggle()

    readonly property bool playing: root.current && root.player.playbackState === MediaPlayer.PlayingState
    readonly property bool fetching: Phone.attachmentBusy(root.attachment?.uid ?? "")

    spacing: 4

    RippleButton {
        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        colBackground: ColorUtils.transparentize(root.contentColor, 0.88)
        colBackgroundHover: ColorUtils.transparentize(root.contentColor, 0.8)
        onClicked: root.toggle()
        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                visible: !root.fetching
                text: root.playing ? "pause" : "play_arrow"
                fill: 1
                iconSize: Appearance.font.pixelSize.larger
                color: root.contentColor
            }
            MaterialLoadingIndicator {
                anchors.centerIn: parent
                visible: root.fetching
                implicitSize: 24
                loading: visible
            }
        }
        StyledToolTip {
            text: root.playing ? Translation.tr("Pause") : Translation.tr("Play")
        }
    }

    PhoneMediaSeek {
        Layout.fillWidth: true
        player: root.player
        current: root.current
        attachment: root.attachment
        contentColor: root.contentColor
    }

    PhoneSaveButton {
        attachment: root.attachment
        iconColor: root.contentColor
    }
}
