pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// A message's link card (YouTube, TikTok, Instagram, Facebook or a web page), with inline video.
ClippingRectangle {
    id: root

    required property string url
    property bool outgoing: false
    property MediaPlayer player: null
    property bool fullscreen: false
    signal fullscreenRequested()
    signal reactRequested()

    readonly property var preview: LinkPreviewService.getPreview(root.url)
    readonly property bool hasThumb: !!(root.preview && root.preview.thumbnail && root.preview.thumbnail.length > 0)
    readonly property bool isVideo: !!(root.preview && (root.preview.media_type === "video" || root.preview.playable))
    readonly property bool isInstagram: !!(root.preview && root.preview.provider === "Instagram")
    readonly property bool isTikTok: !!(root.preview && root.preview.provider === "TikTok")
    readonly property bool isYouTube: !!(root.preview && root.preview.provider === "YouTube")

    readonly property string mediaUid: "link:" + root.url
    readonly property bool current: !!(root.player && root.player.uid === root.mediaUid)
    readonly property bool playing: root.current && root.player.playbackState === MediaPlayer.PlayingState
    readonly property bool started: root.current && root.player.hasVideo

    property bool resolvingStream: false

    readonly property real aspect: {
        if (root.started) {
            if (videoOut.videoSink && videoOut.videoSink.videoSize.width > 0 && videoOut.videoSink.videoSize.height > 0) {
                return videoOut.videoSink.videoSize.width / videoOut.videoSink.videoSize.height;
            }
            const r = videoOut.sourceRect;
            if (r.width > 0 && r.height > 0) return r.width / r.height;
        }
        if (root.preview?.aspect_ratio && root.preview.aspect_ratio > 0) {
            return root.preview.aspect_ratio;
        }
        if (thumbImg.implicitWidth > 0 && thumbImg.implicitHeight > 0) {
            return thumbImg.implicitWidth / thumbImg.implicitHeight;
        }
        if (root.isTikTok || (root.preview?.url && (root.preview.url.includes("/shorts/") || root.preview.url.includes("/reel/")))) {
            return 9 / 16;
        }
        return 16 / 9;
    }

    readonly property bool isVerticalVideo: root.isVideo && root.aspect < 0.95

    function attachPlayer(): void {
        if (root.current && root.player && !root.fullscreen) {
            root.player.videoOutput = videoOut;
        }
    }
    onCurrentChanged: root.attachPlayer()
    onFullscreenChanged: {
        if (!root.fullscreen) root.attachPlayer();
    }
    Component.onCompleted: root.attachPlayer()

    function togglePlayback(): void {
        if (!root.player) {
            Qt.openUrlExternally(root.url);
            return;
        }

        if (root.current && root.player.source.toString().length > 0) {
            if (root.player.playbackState === MediaPlayer.PlayingState) {
                root.player.pause();
            } else {
                if (root.player.duration > 0 && root.player.position >= root.player.duration) {
                    root.player.setPosition(0);
                }
                root.player.play();
            }
            return;
        }

        root.player.stop();
        root.player.source = "";
        root.player.videoOutput = videoOut;
        root.player.uid = root.mediaUid;
        root.resolvingStream = true;

        LinkPreviewService.fetchStream(root.url, (streamUrl) => {
            if (!root || !root.player) return;
            root.resolvingStream = false;
            if (root.player.uid !== root.mediaUid) return;
            if (streamUrl && streamUrl.length > 0) {
                const s = String(streamUrl);
                const finalUrl = (s.startsWith("file://") || s.startsWith("http://") || s.startsWith("https://"))
                    ? s : FileUtils.fileUrl(s);
                root.player.source = finalUrl;
                root.player.play();
            } else {
                // A link that cannot be played here opens in the browser.
                Qt.openUrlExternally(root.url);
            }
        });
    }

    property real maxCardWidth: 280

    readonly property real availableW: {
        if (root.maxCardWidth > 0) return root.maxCardWidth;
        if (root.width > 0) return root.width;
        if (parent && parent.width > 0) return parent.width;
        return 280;
    }

    readonly property real targetWidth: {
        if (root.isVerticalVideo) {
            // Portrait video may be taller, up to 440 px.
            const maxH = 440;
            return Math.min(root.availableW, Math.round(maxH * root.aspect));
        }
        return root.availableW;
    }

    readonly property real targetHeight: {
        if (root.isVideo || root.hasThumb) {
            return Math.round(root.targetWidth / root.aspect);
        }
        if (root.isInstagram) return 72;
        return 0;
    }

    Layout.fillWidth: true
    Layout.preferredWidth: root.targetWidth
    implicitWidth: root.targetWidth
    implicitHeight: mainCol.implicitHeight
    radius: Appearance.rounding.normal - 2
    clip: true

    color: root.outgoing
        ? ColorUtils.transparentize(Appearance.colors.colLayer0, 0.5)
        : ColorUtils.transparentize(Appearance.colors.colLayer0, 0.25)
    border.width: 1
    border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.7)

    ColumnLayout {
        id: mainCol
        width: parent.width
        spacing: 0

        Rectangle {
            id: bannerArea
            Layout.fillWidth: true
            Layout.preferredHeight: root.targetHeight
            color: "black"
            visible: Layout.preferredHeight > 0
            clip: true

            Rectangle {
                anchors.fill: parent
                visible: root.isInstagram && !root.hasThumb && !root.started
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#833ab4" }
                    GradientStop { position: 0.5; color: "#fd1d1d" }
                    GradientStop { position: 1.0; color: "#fcb045" }
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 8
                    MaterialSymbol {
                        text: "photo_camera"
                        iconSize: 28
                        color: "white"
                    }
                    StyledText {
                        text: root.preview?.title || Translation.tr("Instagram Reel")
                        textFormat: Text.PlainText
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        color: "white"
                    }
                }
            }

            Image {
                id: thumbImg
                anchors.fill: parent
                visible: root.hasThumb && !root.started
                source: root.hasThumb ? FileUtils.fileUrl(root.preview.thumbnail) : ""
                fillMode: root.isVerticalVideo ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                asynchronous: true
                sourceSize.width: 600
            }

            // Keeps the badges readable on light thumbnails.
            Rectangle {
                anchors.fill: parent
                visible: thumbImg.visible && thumbImg.status === Image.Ready
                gradient: Gradient {
                    GradientStop { position: 0.0; color: ColorUtils.transparentize("black", 0.6) }
                    GradientStop { position: 0.25; color: "transparent" }
                    GradientStop { position: 0.75; color: "transparent" }
                    GradientStop { position: 1.0; color: ColorUtils.transparentize("black", 0.4) }
                }
            }

            VideoOutput {
                id: videoOut
                anchors.fill: parent
                visible: root.started
                fillMode: VideoOutput.PreserveAspectCrop
            }

            MouseArea {
                id: bannerMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
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
                        if (root.isVideo) {
                            root.togglePlayback();
                        } else {
                            Qt.openUrlExternally(root.url);
                        }
                    }
                }
            }

            Rectangle {
                id: playPauseBtn
                anchors.centerIn: parent
                implicitWidth: 46
                implicitHeight: 46
                radius: Appearance.rounding.full
                color: ColorUtils.transparentize("black", bannerMouse.containsMouse ? 0.35 : 0.5)
                visible: (root.isVideo && !root.playing)
                    || (root.playing && bannerMouse.containsMouse)
                    || root.resolvingStream
                z: 4

                scale: bannerMouse.pressed ? 0.92 : (bannerMouse.containsMouse ? 1.06 : 1.0)
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: root.playing ? 0 : 1.5
                    visible: !root.resolvingStream
                    text: root.playing ? "pause" : "play_arrow"
                    iconSize: 28
                    color: "white"
                    fill: 1
                }

                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: root.resolvingStream
                    implicitSize: 26
                    loading: visible
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 6
                implicitHeight: 22
                implicitWidth: provRow.implicitWidth + 12
                radius: Appearance.rounding.full
                color: root.isYouTube ? "#e52d27"
                    : root.isTikTok ? "#010101"
                    : root.isInstagram ? "#c13584"
                    : ColorUtils.transparentize("black", 0.45)
                visible: !root.started
                z: 3

                Row {
                    id: provRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.isYouTube ? "play_circle"
                            : root.isTikTok ? "music_note"
                            : root.isInstagram ? "photo_camera" : "language"
                        iconSize: 13
                        color: "white"
                        fill: 1
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.preview?.provider || Translation.tr("Web")
                        textFormat: Text.PlainText
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: "white"
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 6
                implicitHeight: 18
                implicitWidth: durText.implicitWidth + 8
                radius: Appearance.rounding.small
                color: ColorUtils.transparentize("black", 0.45)
                visible: !root.started && (root.preview?.duration ?? 0) > 0
                z: 3

                StyledText {
                    id: durText
                    anchors.centerIn: parent
                    text: StringUtils.friendlyTimeForSeconds(root.preview?.duration ?? 0)
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    color: "white"
                }
            }

            RippleButton {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 4
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize("black", 0.45)
                z: 5
                onClicked: Qt.openUrlExternally(root.url)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "open_in_new"
                    iconSize: 16
                    color: "white"
                }
                StyledToolTip {
                    text: Translation.tr("Open in browser")
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            Layout.topMargin: 4
            visible: root.started
            spacing: 2

            RippleButton {
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: Appearance.rounding.full
                onClicked: root.togglePlayback()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.playing ? "pause" : "play_arrow"
                    iconSize: 18
                    color: root.outgoing ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                    fill: 1
                }
                StyledToolTip {
                    text: root.playing ? Translation.tr("Pause") : Translation.tr("Play")
                }
            }

            PhoneMediaSeek {
                Layout.fillWidth: true
                player: root.player
                current: root.current
                duration: (root.preview?.duration ?? 0) * 1000
                contentColor: root.outgoing ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
            }

            RippleButton {
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: Appearance.rounding.full
                onClicked: root.fullscreenRequested()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "fullscreen"
                    iconSize: 18
                    color: root.outgoing ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                }
                StyledToolTip {
                    text: Translation.tr("Full screen")
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: textCol.implicitHeight + 14
            color: "transparent"

            MouseArea {
                id: cardMetaMouse
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
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
                        Qt.openUrlExternally(root.url);
                    }
                }
            }

            ColumnLayout {
                id: textCol
                anchors.fill: parent
                anchors.margins: 7
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.preview?.domain || root.preview?.provider || "link"
                    textFormat: Text.PlainText
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.outgoing
                        ? ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.35)
                        : ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.35)
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.preview?.title || root.preview?.domain || root.url
                    textFormat: Text.PlainText
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: root.outgoing ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: (root.preview?.description ?? "").length > 0 && root.preview.description !== root.preview.title
                    text: root.preview?.description ?? ""
                    textFormat: Text.PlainText
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.outgoing
                        ? ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.35)
                        : ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.35)
                    wrapMode: Text.Wrap
                    maximumLineCount: 1
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !root.preview
                    spacing: 6
                    MaterialLoadingIndicator {
                        implicitSize: 14
                        loading: visible
                    }
                    StyledText {
                        text: Translation.tr("Loading preview...")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: root.outgoing
                            ? ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.35)
                            : ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.35)
                    }
                }
            }
        }
    }
}
