pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// The left sidebar's Media tab: the active player's art, controls and synced
// lyrics, from pctrade's end4-pC.
Item {
    id: root

    // Whether this page is what is on screen right now. The sidebar sets it.
    // Nothing that costs anything, from downloads and decoding to timers,
    // lyrics lookups and audio capture, runs without it.
    property bool shown: false

    readonly property MprisPlayer player: MprisController.activePlayer
    readonly property bool hasPlayer: root.player !== null
    readonly property bool isPlaying: root.player?.isPlaying ?? false
    readonly property var players: Array.from(MprisController.players)

    readonly property bool showLyrics: Config.options.sidebar.media.showLyrics
    readonly property bool artColors: Config.options.sidebar.media.artColors
    readonly property bool blurredBackground: Config.options.sidebar.media.blurredBackground

    function showChanged() {
        // Art whose download failed gets another try each time the page opens.
        if (root.shown)
            root.artRefetchedFor = "";
        root.updateArt();
        if (root.shown) {
            // With no text field to take the keyboard, the page holds it
            // itself, so Escape and the sidebar's shortcuts still reach it.
            root.forceActiveFocus();
        } else {
            artMenu.close();
        }
    }
    onShownChanged: root.showChanged()
    Component.onCompleted: {
        if (root.shown)
            root.showChanged();
    }

    // ---- art ----

    readonly property string artUrl: root.player?.trackArtUrl ?? ""
    readonly property string artFilePath: `${Directories.coverArt}/${Qt.md5(root.artUrl)}`
    // Only ever given art while the page is shown, so a hidden page neither
    // downloads nor decodes anything.
    property string displayedArt: ""
    // Follows the path rather than the address: the path is worked out from
    // the address, and read while the address is still changing it names
    // the previous song's art. A hidden page lets the old art go, or an image
    // built while it is hidden would decode the previous song's cover.
    onArtFilePathChanged: {
        if (root.shown) {
            staleArtTimer.restart();
            root.updateArt();
        } else {
            root.displayedArt = "";
        }
    }

    // Art that takes a while to arrive leaves the placeholder up meanwhile,
    // rather than the previous song's cover under the new song's title. Art
    // that arrives sooner than this swaps straight across.
    Timer {
        id: staleArtTimer
        interval: 400
        onTriggered: {
            if (root.displayedArt !== "" && root.displayedArt !== `file://${root.artFilePath}` && root.displayedArt !== root.artUrl)
                root.displayedArt = "";
        }
    }

    // The cached copy is always tried first, so art that failed to load was
    // either never fetched or has since been cleared from the folder. Either
    // way it is fetched, but only once until it loads, so a file that is
    // there and will not decode is not fetched over and over.
    property string artRefetchedFor: ""
    function artFailed() {
        const failed = root.displayedArt;
        root.displayedArt = "";
        if (failed === `file://${root.artFilePath}` && root.artRefetchedFor !== root.artFilePath) {
            root.artRefetchedFor = root.artFilePath;
            root.fetchArt();
        }
    }
    function artLoaded() {
        root.artRefetchedFor = "";
    }

    function updateArt() {
        if (!root.shown)
            return;
        if (root.artUrl.length === 0) {
            root.displayedArt = "";
            return;
        }
        if (root.artUrl.startsWith("file://")) {
            root.displayedArt = root.artUrl;
            return;
        }
        // Art fetched before shows straight away instead of after the
        // downloader has looked for it. Art that is not there yet fails to
        // load, and artFailed fetches it.
        root.displayedArt = `file://${root.artFilePath}`;
    }

    function fetchArt() {
        if (artDownloader.running) {
            // Art for a song that has since been skipped is not waited for.
            // Once that download has stopped, onExited fetches this one's.
            if (artDownloader.target !== root.artFilePath)
                artDownloader.stop();
            return;
        }
        artDownloader.fetch();
    }

    Process {
        id: artDownloader
        property string target: ""
        property bool stopped: false
        // The address goes to curl as an argument of its own, is never read
        // as an option or a glob, and only goes out over http or https: it
        // comes from whatever the player reports. Other media surfaces fetch
        // the same art into the same folder, so each download writes under a
        // name of its own and moves in whole. Stopping it stops curl too, so
        // nothing keeps downloading for a song that is gone.
        function fetch() {
            artDownloader.target = root.artFilePath;
            artDownloader.stopped = false;
            artDownloader.command = ["bash", "-c",
                '[ -f "$1" ] && exit 0; t="$1.part.$$"; stop() { kill $(jobs -p) 2>/dev/null; wait; rm -f "$t"; exit 143; }; trap stop TERM; curl -4 -fsSL -g --proto "=http,https" --max-time 20 --max-filesize 20000000 --create-dirs -o "$t" -- "$2" & wait $! && mv -f "$t" "$1"; s=$?; rm -f "$t"; exit $s',
                "coverart", artDownloader.target, root.artUrl];
            artDownloader.running = true;
        }
        function stop() {
            artDownloader.stopped = true;
            artDownloader.running = false;
        }
        onExited: (exitCode, exitStatus) => {
            if (artDownloader.stopped || artDownloader.target !== root.artFilePath) {
                // The song changed while this one's art was on its way, or
                // came back to it after the download had been stopped.
                root.updateArt();
                return;
            }
            if (root.shown)
                root.displayedArt = exitCode === 0 ? `file://${artDownloader.target}` : "";
        }
    }

    ColorQuantizer {
        id: colorQuantizer
        depth: 0 // 2^0 = 1 color
        rescaleSize: 1
    }
    // New art reaches the quantizer only while the page is shown; hidden, it
    // keeps what it last had, so reopening does not quantize again.
    Binding {
        target: colorQuantizer
        property: "source"
        value: root.artColors ? root.displayedArt : ""
        when: root.shown
        restoreMode: Binding.RestoreNone
    }

    readonly property color artDominantColor: (root.artColors && root.displayedArt !== "" && colorQuantizer.colors.length > 0)
        ? ColorUtils.mix(colorQuantizer.colors[0], Appearance.colors.colPrimaryContainer, 0.8)
        : Appearance.colors.colPrimaryContainer

    readonly property AdaptedMaterialScheme blendedColors: AdaptedMaterialScheme {
        color: root.artDominantColor
    }

    // ---- playback ----

    // A smoother seek bar than the bar's own slower refresh gives.
    Timer {
        running: root.shown && root.isPlaying
        interval: 1000
        repeat: true
        onTriggered: root.player?.positionChanged()
    }

    // A player that never says how long the track is gets its position
    // reported as the length, so the bar would sit full and both times would
    // read the same. Such a track shows how far in it is and nothing else.
    readonly property bool hasLength: (root.player?.lengthSupported ?? false) && root.player.length > 0
    readonly property real trackLength: root.hasLength ? root.player.length : 0

    readonly property bool canChangeVolume: MprisController.canChangeVolume
    readonly property real volume: root.player?.volume ?? 0
    // Where each player was before it was muted here, so unmuting puts it
    // back rather than at full volume.
    property var volumeBeforeMute: ({})

    function setVolume(value) {
        if (!root.player || !root.canChangeVolume)
            return;
        // Players take 1 as full volume, as the media popup's slider does.
        root.player.volume = Math.max(0, Math.min(1, Math.round(value * 100) / 100));
    }

    function toggleMute() {
        if (!root.player || !root.canChangeVolume)
            return;
        const id = root.player.dbusName;
        if (root.volume > 0) {
            root.volumeBeforeMute[id] = root.volume;
            root.setVolume(0);
        } else {
            root.setVolume(root.volumeBeforeMute[id] ?? 0.5);
        }
    }

    function playerName(player) {
        return player?.identity || player?.desktopEntry || Translation.tr("Unknown");
    }

    // Two windows of one browser are two players with one name, so those
    // say what they are playing as well.
    function playerLabel(player) {
        const name = root.playerName(player);
        const twins = root.players.filter(other => root.playerName(other) === name).length > 1;
        const title = StringUtils.cleanMusicTitle(player?.trackTitle);
        return twins && title ? `${name} · ${title}` : name;
    }

    // ---- sizes ----

    readonly property real playSize: Math.round(Math.max(52, Math.min(70, root.height * 0.085)))
    readonly property real skipSize: Math.round(Math.max(46, Math.min(60, root.height * 0.07)))
    readonly property real smallSize: Math.round(Math.max(34, Math.min(40, root.height * 0.05)))

    // ---- look ----

    Rectangle {
        id: background
        anchors {
            fill: parent
            leftMargin: 4
            rightMargin: 4
            topMargin: -1
            bottomMargin: 4
        }
        color: ColorUtils.transparentize(root.artDominantColor, 0.9)
        radius: Appearance.rounding.normal
        clip: true

        Loader {
            id: blurredArtLoader
            anchors.fill: parent
            active: root.blurredBackground && root.shown && root.displayedArt !== ""
            sourceComponent: Item {
                id: blurredArt
                opacity: 0.5
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: blurredArt.width
                        height: blurredArt.height
                        radius: background.radius
                    }
                }

                ArtImage {
                    id: blurSource
                    anchors.fill: parent
                    // Blurred beyond recognition anyway, so a thumbnail's
                    // worth of pixels is all it needs.
                    sourceSize: Qt.size(64, 64)
                    layer.enabled: true
                    layer.effect: StyledBlurEffect {
                        source: blurSource
                    }
                }
            }
        }

        ColumnLayout {
            id: content
            anchors {
                top: parent.top
                bottom: parent.bottom
                horizontalCenter: parent.horizontalCenter
                margins: 16
            }
            width: Math.min(parent.width - 32, content.widest)
            visible: root.hasPlayer
            spacing: 0

            readonly property real widest: 480

            // The art takes what the rest leaves, up to a square the width
            // of the page, and keeps enough room between the title and the
            // controls for a few lines of lyrics.
            readonly property real gap: 12
            readonly property real middleMinimum: 140
            readonly property real otherHeight: (playerPicker.visible ? playerPicker.implicitHeight + content.gap : 0)
                + titleBlock.implicitHeight + content.gap
                + middle.Layout.topMargin + middle.Layout.bottomMargin
                + controls.implicitHeight + utilityRow.implicitHeight + content.gap
            readonly property real artSide: Math.floor(Math.max(0, Math.min(content.width, content.height * 0.45,
                content.height - content.otherHeight - content.middleMinimum)))

            StyledComboBox {
                id: playerPicker
                visible: root.players.length >= 2
                Layout.fillWidth: true
                Layout.bottomMargin: content.gap
                implicitHeight: 36
                model: root.players.map(player => root.playerLabel(player))
                currentIndex: root.players.indexOf(root.player)
                // A new title in one of two browser windows rebuilds the list,
                // and a rebuilt list puts the choice back at the top. The
                // picker names the player the controls drive regardless, and
                // its choice goes back to that player.
                displayText: root.playerLabel(root.player)
                onModelChanged: Qt.callLater(playerPicker.followPlayer)
                function followPlayer() {
                    playerPicker.currentIndex = Qt.binding(() => root.players.indexOf(root.player));
                }
                onActivated: index => MprisController.setActivePlayer(root.players[index])
            }

            // ── Album art ──
            Item {
                id: artFrame
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: content.artSide
                Layout.preferredHeight: content.artSide
                visible: content.artSide >= 72

                Loader {
                    anchors.fill: parent
                    active: artFrame.visible
                    sourceComponent: roundedArtComponent
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: root.displayedArt === ""
                    fill: 1
                    text: "music_note"
                    color: root.blendedColors.colPrimary
                    iconSize: Math.round(artFrame.width * 0.4)
                }
            }

            // ── Title & artist ──
            ColumnLayout {
                id: titleBlock
                Layout.fillWidth: true
                Layout.topMargin: content.gap
                spacing: 4

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: titleText.implicitHeight
                    clip: true

                    StyledText {
                        id: titleText
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Bold
                        color: root.blendedColors.colOnLayer0
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: StringUtils.cleanMusicTitle(root.player?.trackTitle) || Translation.tr("Unknown Title")
                        textFormat: Text.PlainText

                        Behavior on text {
                            enabled: root.shown
                            SequentialAnimation {
                                NumberAnimation { target: titleText; property: "x"; to: -titleText.width; duration: 150; easing.type: Easing.InQuad }
                                PropertyAction { target: titleText; property: "text" }
                                NumberAnimation { target: titleText; property: "x"; from: titleText.width; to: 0; duration: 150; easing.type: Easing.OutQuad }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: artistText.implicitHeight
                    clip: true

                    StyledText {
                        id: artistText
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: root.blendedColors.colSubtext
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: root.player?.trackArtist || Translation.tr("Unknown Artist")
                        textFormat: Text.PlainText

                        Behavior on text {
                            enabled: root.shown
                            SequentialAnimation {
                                NumberAnimation { target: artistText; property: "x"; to: -artistText.width; duration: 150; easing.type: Easing.InQuad }
                                PropertyAction { target: artistText; property: "text" }
                                NumberAnimation { target: artistText; property: "x"; from: artistText.width; to: 0; duration: 150; easing.type: Easing.OutQuad }
                            }
                        }
                    }
                }
            }

            // ── Lyrics, or the visualizer ──
            Item {
                id: middle
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: content.gap
                Layout.bottomMargin: content.gap

                Lyrics {
                    anchors.fill: parent
                    visible: root.showLyrics && parent.height >= 24
                    active: root.shown
                    textAlignment: Text.AlignHCenter
                    textColor: root.blendedColors.colOnLayer0
                    activeColor: root.blendedColors.colPrimary
                    dimColor: root.blendedColors.colSubtext
                    indicatorColor: root.artDominantColor
                    indicatorShapeColor: root.blendedColors.colPrimary
                }

                Loader {
                    anchors.fill: parent
                    active: root.shown && !root.showLyrics
                    sourceComponent: visualizerComponent
                }
            }

            // ── Transport ──
            ColumnLayout {
                id: controls
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20

                    RippleButton {
                        id: playButton
                        Layout.fillWidth: true
                        implicitHeight: root.playSize
                        enabled: MprisController.canTogglePlaying
                        buttonRadius: root.isPlaying ? Appearance.rounding.verylarge : root.playSize / 2
                        colBackground: root.isPlaying ? root.blendedColors.colPrimary : root.blendedColors.colSecondaryContainer
                        colBackgroundHover: root.isPlaying ? root.blendedColors.colPrimaryHover : root.blendedColors.colSecondaryContainerHover
                        colRipple: root.isPlaying ? root.blendedColors.colPrimaryActive : root.blendedColors.colSecondaryContainerActive
                        downAction: () => MprisController.togglePlaying()
                        contentItem: MaterialSymbol {
                            iconSize: Math.round(root.playSize * 0.62)
                            fill: 1
                            horizontalAlignment: Text.AlignHCenter
                            color: root.isPlaying ? root.blendedColors.colOnPrimary : root.blendedColors.colOnSecondaryContainer
                            text: root.isPlaying ? "pause" : "play_arrow"
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                        StyledToolTip {
                            text: root.isPlaying ? Translation.tr("Pause") : Translation.tr("Play")
                        }
                    }

                    SkipButton {
                        iconName: "skip_next"
                        enabled: MprisController.canGoNext
                        downAction: () => MprisController.next()
                        StyledToolTip {
                            text: Translation.tr("Next track")
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20

                    SkipButton {
                        iconName: "skip_previous"
                        enabled: MprisController.canGoPrevious
                        downAction: () => MprisController.previous()
                        StyledToolTip {
                            text: Translation.tr("Previous track")
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Item {
                            Layout.fillWidth: true
                            visible: root.hasLength
                            implicitHeight: Math.max(seekLoader.implicitHeight, progressLoader.implicitHeight)

                            Loader {
                                id: seekLoader
                                anchors.fill: parent
                                active: root.hasLength && (root.player?.canSeek ?? false)
                                sourceComponent: StyledSlider {
                                    configuration: StyledSlider.Configuration.Wavy
                                    animateWave: root.shown && root.isPlaying
                                    highlightColor: root.blendedColors.colPrimary
                                    trackColor: root.blendedColors.colSecondaryContainer
                                    handleColor: root.blendedColors.colPrimary
                                    usePercentTooltip: false
                                    tooltipContent: StringUtils.friendlyTimeForSeconds(value * root.trackLength)
                                    value: root.trackLength > 0 ? (root.player?.position ?? 0) / root.trackLength : 0
                                    onMoved: {
                                        if (root.player && root.trackLength > 0)
                                            root.player.position = value * root.trackLength;
                                    }
                                }
                            }

                            Loader {
                                id: progressLoader
                                anchors {
                                    verticalCenter: parent.verticalCenter
                                    left: parent.left
                                    right: parent.right
                                }
                                active: root.hasLength && !(root.player?.canSeek ?? false)
                                sourceComponent: StyledProgressBar {
                                    wavy: root.isPlaying
                                    animateWave: root.shown && root.isPlaying
                                    highlightColor: root.blendedColors.colPrimary
                                    trackColor: root.blendedColors.colSecondaryContainer
                                    value: root.trackLength > 0 ? (root.player?.position ?? 0) / root.trackLength : 0
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true

                            StyledText {
                                visible: root.player?.positionSupported ?? false
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: root.blendedColors.colSubtext
                                font.features: { "tnum": 1 }
                                text: StringUtils.friendlyTimeForSeconds(root.player?.position ?? 0)
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                visible: root.hasLength
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: root.blendedColors.colSubtext
                                font.features: { "tnum": 1 }
                                text: StringUtils.friendlyTimeForSeconds(root.trackLength)
                            }
                        }
                    }
                }
            }

            // ── Lyrics toggle, volume, art options ──
            RowLayout {
                id: utilityRow
                Layout.fillWidth: true
                Layout.topMargin: content.gap
                spacing: 8

                UtilityButton {
                    iconName: "lyrics"
                    iconFill: root.showLyrics ? 1 : 0
                    toggled: root.showLyrics
                    downAction: () => {
                        Config.options.sidebar.media.showLyrics = !Config.options.sidebar.media.showLyrics;
                    }
                    StyledToolTip {
                        text: Translation.tr("Lyrics")
                    }
                }

                UtilityButton {
                    iconName: root.volume <= 0 ? "volume_off" : root.volume < 0.5 ? "volume_down" : "volume_up"
                    enabled: root.canChangeVolume
                    downAction: () => root.toggleMute()
                    StyledToolTip {
                        text: root.volume > 0 ? Translation.tr("Click to mute") : Translation.tr("Click to unmute")
                    }
                }

                UtilityButton {
                    Layout.fillWidth: true
                    iconName: "remove"
                    enabled: root.canChangeVolume && root.volume > 0
                    downAction: () => root.setVolume(root.volume - 0.1)
                    StyledToolTip {
                        text: Translation.tr("Lower volume")
                    }
                }

                UtilityButton {
                    Layout.fillWidth: true
                    iconName: "add"
                    enabled: root.canChangeVolume && root.volume < 1
                    downAction: () => root.setVolume(root.volume + 0.1)
                    StyledToolTip {
                        text: Translation.tr("Raise volume")
                    }
                }

                UtilityButton {
                    id: moreButton
                    iconName: "more_vert"
                    toggled: artMenu.visible
                    downAction: () => artMenu.visible ? artMenu.close() : artMenu.open()
                    StyledToolTip {
                        text: Translation.tr("Album art")
                        extraVisibleCondition: !artMenu.visible
                    }

                    Popup {
                        id: artMenu
                        width: Math.min(300, root.width - 24)
                        x: moreButton.width - width
                        y: -height - 8
                        padding: 12
                        modal: true
                        dim: false
                        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape

                        background: Rectangle {
                            color: Appearance.m3colors.m3surfaceContainer
                            radius: Appearance.rounding.large
                            border.width: 1
                            border.color: Appearance.colors.colLayer0Border
                        }

                        contentItem: ColumnLayout {
                            spacing: 4

                            OptionSwitch {
                                buttonIcon: "palette"
                                text: Translation.tr("Album colors")
                                option: "artColors"
                            }

                            OptionSwitch {
                                buttonIcon: "blur_on"
                                text: Translation.tr("Blurred art")
                                option: "blurredBackground"
                            }
                        }
                    }
                }
            }
        }

        // ── Nothing playing ──
        ColumnLayout {
            anchors.centerIn: parent
            visible: !root.hasPlayer
            spacing: 14

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                shape: MaterialShape.Shape.Cookie12Sided
                padding: 22
                iconSize: 44
                text: "music_off"
                color: Appearance.colors.colSecondaryContainer
                colSymbol: Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("No media")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.large
            }
        }
    }

    component SkipButton: RippleButton {
        id: skipButton
        property string iconName
        implicitWidth: root.skipSize
        implicitHeight: root.skipSize
        padding: 0
        colBackground: "transparent"
        colBackgroundHover: "transparent"
        colRipple: "transparent"
        contentItem: MaterialShapeWrappedMaterialSymbol {
            shape: MaterialShape.Shape.Cookie12Sided
            padding: 0
            iconSize: Math.round(root.skipSize * 0.5)
            fill: 1
            text: skipButton.iconName
            color: skipButton.hovered ? root.blendedColors.colSecondaryContainerHover
                : ColorUtils.transparentize(root.blendedColors.colSecondaryContainer, 0.7)
            colSymbol: root.blendedColors.colOnSecondaryContainer
        }
    }

    component UtilityButton: RippleButton {
        id: utilityButton
        property string iconName
        property real iconFill: 1
        implicitWidth: root.smallSize
        implicitHeight: root.smallSize
        buttonRadius: Appearance.rounding.large
        colBackground: ColorUtils.transparentize(root.blendedColors.colSecondaryContainer, 0.7)
        colBackgroundHover: root.blendedColors.colSecondaryContainerHover
        colRipple: root.blendedColors.colSecondaryContainerActive
        colBackgroundToggled: root.blendedColors.colSecondaryContainer
        colBackgroundToggledHover: root.blendedColors.colSecondaryContainerHover
        colRippleToggled: root.blendedColors.colSecondaryContainerActive
        contentItem: MaterialSymbol {
            iconSize: 18
            fill: utilityButton.iconFill
            horizontalAlignment: Text.AlignHCenter
            color: root.blendedColors.colOnSecondaryContainer
            text: utilityButton.iconName
        }
    }

    component ArtImage: StyledImage {
        source: root.displayedArt
        fillMode: Image.PreserveAspectCrop
        cache: false
        onStatusChanged: {
            if (status === Image.Error)
                root.artFailed();
            else if (status === Image.Ready)
                root.artLoaded();
        }
    }

    // Settings has the same options, so after a click here has set one the
    // switch goes back to following it, and a change made there shows here.
    component OptionSwitch: ConfigSwitch {
        id: optionSwitch
        required property string option
        checked: Config.options.sidebar.media[optionSwitch.option]
        onCheckedChanged: {
            Config.options.sidebar.media[optionSwitch.option] = optionSwitch.checked;
            optionSwitch.checked = Qt.binding(() => Config.options.sidebar.media[optionSwitch.option]);
        }
    }

    Component {
        id: roundedArtComponent
        Rectangle {
            id: roundedArt
            radius: Appearance.rounding.normal
            color: root.blendedColors.colSecondaryContainer
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: roundedArt.width
                    height: roundedArt.height
                    radius: roundedArt.radius
                }
            }

            ArtImage {
                anchors.fill: parent
                antialiasing: true
                // Decoded once at the largest the art is ever shown, rather
                // than again at every width the page passes through while
                // the sidebar widens or narrows.
                sourceSize: {
                    const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                    return Qt.size(content.widest * dpr, content.widest * dpr);
                }
            }
        }
    }

    // Bars of dots as end4-pC draws them, fed from the shell's shared cava.
    Component {
        id: visualizerComponent
        Item {
            id: bars
            readonly property real dotSize: 5
            readonly property real dotSpacing: 6
            readonly property int barCount: Math.max(1, Math.min(32, Math.floor((bars.width + bars.dotSpacing) / (bars.dotSize + bars.dotSpacing))))
            readonly property real maxValue: 1000

            Component.onCompleted: Cava.addViewer()
            Component.onDestruction: Cava.removeViewer()

            Row {
                anchors.centerIn: parent
                spacing: bars.dotSpacing

                Repeater {
                    model: bars.barCount
                    Rectangle {
                        required property int index
                        anchors.verticalCenter: parent.verticalCenter
                        width: bars.dotSize
                        height: {
                            const points = Cava.points;
                            if (!root.isPlaying || points.length === 0)
                                return bars.dotSize;
                            const value = points[Math.floor(index * points.length / bars.barCount)] ?? 0;
                            return Math.max(bars.dotSize, value / bars.maxValue * bars.height * 0.8);
                        }
                        radius: width / 2
                        color: root.blendedColors.colPrimary
                        opacity: root.isPlaying ? 0.85 : 0.3
                        Behavior on height { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                    }
                }
            }
        }
    }
}
