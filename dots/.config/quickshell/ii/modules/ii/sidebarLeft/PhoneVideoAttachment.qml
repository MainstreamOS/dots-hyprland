import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell.Widgets

// A video in a conversation: its thumbnail until played, then the video
// itself in the same place.
ColumnLayout {
    id: root
    required property var attachment
    // The conversation's one player, and whether it holds this video.
    required property MediaPlayer player
    required property bool current
    property real frameWidth: 240
    property color contentColor: Appearance.colors.colOnLayer1
    // The conversation is showing this video full width instead.
    property bool fullscreen: false
    signal toggle()
    signal fullscreenRequested()
    signal reactRequested()

    readonly property bool playing: root.current && root.player.playbackState === MediaPlayer.PlayingState
    readonly property bool fetching: Phone.attachmentBusy(root.attachment?.uid ?? "")
    // Showing frames rather than the thumbnail.
    readonly property bool started: root.current && root.player.hasVideo
    readonly property real videoDuration: (root.current && root.player.duration > 0)
        ? root.player.duration
        : Phone.durationFor(root.attachment)
    // Width over height, from the video once it plays, else from its thumbnail.
    readonly property real aspect: {
        const size = videoOut.videoSink.videoSize;
        if (root.started && size.width > 0 && size.height > 0) return size.width / size.height;
        const r = videoOut.sourceRect;
        if (root.started && r.width > 0 && r.height > 0) return r.width / r.height;
        if (thumb.implicitWidth > 0 && thumb.implicitHeight > 0) return thumb.implicitWidth / thumb.implicitHeight;
        return 16 / 9;
    }

    // The player draws into whichever video holds it; a recreated delegate,
    // or one back from full width, takes it back.
    function attach(): void {
        if (root.current && !root.fullscreen) root.player.videoOutput = videoOut;
    }
    onCurrentChanged: root.attach()
    onFullscreenChanged: root.attach()
    Component.onCompleted: root.attach()

    spacing: 4

    ClippingRectangle {
        Layout.preferredWidth: root.frameWidth
        Layout.preferredHeight: Math.max(100, Math.min(320, root.frameWidth / root.aspect))
        radius: Appearance.rounding.normal
        color: "black"
        scale: frameMouse.pressed ? 0.97 : 1
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Image {
            id: thumb
            anchors.fill: parent
            visible: !root.started
            readonly property string localVideoPath: root.attachment?.path
                || (root.attachment?.uid ? Phone.attachmentFiles[root.attachment.uid] : "")
                || ""
            readonly property string thumbPath: (root.attachment?.thumb ?? "").length > 0
                ? root.attachment.thumb
                : (Phone.attachmentThumbs[root.attachment?.uid ?? ""] ?? "")
            source: thumbPath.length > 0 ? FileUtils.fileUrl(thumbPath) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 400

            function probeIfNeeded(): void {
                if (thumbPath.length === 0 && localVideoPath.length > 0) {
                    Phone.probeFile(localVideoPath, root.attachment?.uid ?? "");
                }
            }
            onThumbPathChanged: probeIfNeeded()
            onLocalVideoPathChanged: probeIfNeeded()
            Component.onCompleted: probeIfNeeded()
        }
        MaterialSymbol {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 8
            visible: !root.started && (thumb.status !== Image.Ready || thumb.thumbPath.length === 0)
            text: "movie"
            iconSize: 24
            color: ColorUtils.transparentize("white", 0.4)
        }
        VideoOutput {
            id: videoOut
            anchors.fill: parent
            visible: root.started
            fillMode: VideoOutput.PreserveAspectFit
        }

        Rectangle {
            anchors.centerIn: parent
            implicitWidth: 48
            implicitHeight: 48
            radius: Appearance.rounding.full
            color: ColorUtils.transparentize("black", 0.45)
            visible: !root.playing
            MaterialSymbol {
                anchors.centerIn: parent
                visible: !root.fetching
                text: "play_arrow"
                fill: 1
                iconSize: 32
                color: "white"
            }
            MaterialLoadingIndicator {
                anchors.centerIn: parent
                visible: root.fetching
                implicitSize: 32
                loading: visible
            }
        }

        MouseArea {
            id: frameMouse
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            pressAndHoldInterval: 350
            property bool held: false
            onPressed: mouse => {
                held = false;
                if (mouse.button === Qt.RightButton) {
                    root.reactRequested();
                }
            }
            onPressAndHold: {
                held = true;
                root.reactRequested();
            }
            onCanceled: held = false
            onClicked: mouse => {
                if (held) return;
                if (mouse.button === Qt.LeftButton) {
                    root.toggle();
                }
            }
        }

        PhoneVideoCornerButton {
            visible: root.started
            iconName: "fullscreen"
            tip: Translation.tr("Full screen")
            onClicked: root.fullscreenRequested()
        }

        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: 6
            visible: !root.started && root.videoDuration > 0
            radius: Appearance.rounding.small
            color: ColorUtils.transparentize("black", 0.45)
            implicitHeight: 20
            implicitWidth: durText.implicitWidth + 12

            StyledText {
                id: durText
                anchors.centerIn: parent
                text: StringUtils.friendlyTimeForSeconds(root.videoDuration / 1000)
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                font.features: { "tnum": 1 }
                color: "white"
            }
        }
    }

    RowLayout {
        Layout.preferredWidth: root.frameWidth
        spacing: 2

        RippleButton {
            implicitWidth: 28
            implicitHeight: 28
            buttonRadius: Appearance.rounding.full
            colBackground: ColorUtils.transparentize(root.contentColor, 0.88)
            colBackgroundHover: ColorUtils.transparentize(root.contentColor, 0.8)
            onClicked: root.toggle()
            contentItem: Item {
                anchors.fill: parent
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !root.fetching
                    text: root.playing ? "pause" : "play_arrow"
                    iconSize: 18
                    color: root.contentColor
                    fill: 1
                }
                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: root.fetching
                    implicitSize: 18
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

        RippleButton {
            implicitWidth: 28
            implicitHeight: 28
            buttonRadius: Appearance.rounding.full
            onClicked: {
                if (root.playing) root.player.pause();
                Phone.useAttachment(root.attachment, "open");
            }
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "open_in_new"
                iconSize: Appearance.font.pixelSize.normal
                color: root.contentColor
            }
            StyledToolTip {
                text: Translation.tr("Open in your video player")
            }
        }

        PhoneSaveButton {
            attachment: root.attachment
            iconColor: root.contentColor
        }
    }
}
