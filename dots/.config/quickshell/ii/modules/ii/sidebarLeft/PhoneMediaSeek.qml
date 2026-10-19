import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtMultimedia

// The seek bar and time of a clip on the conversation's player.
RowLayout {
    id: root
    required property MediaPlayer player
    // Whether the player holds this clip.
    required property bool current
    property var attachment: null
    property real duration: 0
    property color contentColor: Appearance.colors.colOnLayer1

    readonly property bool playing: root.current && root.player.playbackState === MediaPlayer.PlayingState
    readonly property real totalDuration: (root.current && root.player.duration > 0)
        ? root.player.duration
        : (root.duration > 0 ? root.duration : Phone.durationFor(root.attachment))
    readonly property real currentPosition: root.current ? root.player.position : 0

    spacing: 4

    StyledSlider {
        Layout.fillWidth: true
        Layout.preferredHeight: 24
        configuration: StyledSlider.Configuration.Wavy
        animateWave: root.playing
        highlightColor: root.contentColor
        handleColor: root.contentColor
        trackColor: ColorUtils.transparentize(root.contentColor, 0.7)
        enabled: root.current && root.totalDuration > 0
        usePercentTooltip: false
        tooltipContent: StringUtils.friendlyTimeForSeconds(value * root.totalDuration / 1000)
        value: (root.current && root.totalDuration > 0) ? root.currentPosition / root.totalDuration : 0
        onMoved: {
            if (root.current && root.totalDuration > 0)
                root.player.position = value * root.totalDuration;
        }
    }

    StyledText {
        visible: root.totalDuration > 0
        text: StringUtils.friendlyTimeForSeconds((root.playing || (root.current && root.currentPosition > 0) ? root.currentPosition : root.totalDuration) / 1000)
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.features: { "tnum": 1 }
        color: root.contentColor
    }
}
