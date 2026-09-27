import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import QtMultimedia
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: page
    forceWidth: true
    // As wide as the color styles less the one Auto stands in for, when that
    // is Tonal Spot. They are spread to meet both edges, which also fits the
    // wider eight left when Auto picks Neutral, and the choices on the right
    // sit against the right edge, so every row ends on the same line. A
    // narrower window shrinks it rather than cutting it off.
    baseWidth: Math.max(600, Math.min(page.width - 40, 695))
    // Everything here fits the window at its usual size, so the longer pages'
    // extra room at the bottom would only let it scroll into empty space.
    bottomContentPadding: 20

    Process {
        id: randomWallProc
        property string status: ""
        property string scriptPath: `${Directories.scriptPath}/colors/random/set_default_wall.sh`
        command: ["bash", "-c", FileUtils.trimFileProtocol(randomWallProc.scriptPath)]
        stdout: SplitParser {
            onRead: data => {
                randomWallProc.status = data.trim();
            }
        }
    }

    // Picking a folder turns the slideshow on and shows one straight away, so
    // the button does something visible rather than leaving the desktop
    // unchanged until the first interval is up. The rotation lives in the main
    // shell, so it is asked over IPC rather than run here.
    Process {
        id: slideshowFolderProc
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => slideshowFolderProc.buf += data }
        onExited: exitCode => {
            if (exitCode !== 0) return;
            const picked = (slideshowFolderProc.buf || "").trim();
            if (picked.length === 0) return;
            Config.options.background.slideshow.folder = picked;
            Config.options.background.slideshow.enable = true;
            slideshowNextProc.command = ["qs", "-c", "ii", "ipc", "call", "slideshow", "next"];
            slideshowNextProc.running = false;
            slideshowNextProc.running = true;
        }
    }

    Process { id: slideshowNextProc }

    // Auto settles on one of the other color styles for each wallpaper, and
    // that one is left off the row: picking it would look exactly like Auto.
    // switchwall.sh keeps the answer per picture, keyed on its path, mtime and
    // size; a picture it has not measured yet is measured the same way here.
    property string autoScheme: "scheme-tonal-spot"
    readonly property string autoSchemeWallpaper: FileUtils.trimFileProtocol(Config.options.background.wallpaperPath)
    onAutoSchemeWallpaperChanged: {
        autoSchemeProc.running = false;
        autoSchemeProc.running = true;
    }
    Component.onCompleted: autoSchemeProc.running = true

    Process {
        id: autoSchemeProc
        command: ["bash", "-c", `
            wall="$1"; cache="$2"; detect="$3"
            [ -f "$wall" ] || exit 0
            key="$wall:$(stat -c '%Y:%s' "$wall")"
            scheme="$(awk -F '\\t' -v k="$key" '$1 == k { print $2; exit }' "$cache" 2>/dev/null)"
            venv="\${ILLOGICAL_IMPULSE_VIRTUAL_ENV/#\\~/$HOME}"
            [ -n "$scheme" ] || scheme="$("$venv/bin/python" "$detect" "$wall" 2>/dev/null)"
            printf '%s\\n' "$scheme"
        `, "auto-scheme", page.autoSchemeWallpaper,
            FileUtils.trimFileProtocol(`${Directories.state}/user/generated/scheme-for-image.cache`),
            `${FileUtils.trimFileProtocol(Directories.scriptPath)}/colors/scheme_for_image.py`]
        stdout: StdioCollector {
            onStreamFinished: {
                const scheme = text.trim();
                if (scheme.startsWith("scheme-"))
                    page.autoScheme = scheme;
            }
        }
    }

    // Started detached: this page is rebuilt as soon as the new colors land,
    // and a run it owned would be killed along with it, before the steps that
    // follow the colors (terminal colors, the login background, the portal).
    // The new colors reach this page through MaterialThemeLoader's file watch.
    function applyTheme(args) {
        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} ${args}`]);
    }

    component SmallLightDarkPreferenceButton: RippleButton {
        id: smallLightDarkPreferenceButton
        required property bool dark
        property color colText: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        padding: 5
        Layout.fillWidth: true
        toggled: Appearance.m3colors.darkmode === dark
        colBackground: Appearance.colors.colLayer2
        onClicked: {
            applyTheme(`--mode ${dark ? "dark" : "light"} --noswitch`);
        }
        contentItem: Item {
            anchors.centerIn: parent
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 30
                    text: dark ? "dark_mode" : "light_mode"
                    color: smallLightDarkPreferenceButton.colText
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: dark ? Translation.tr("Dark") : Translation.tr("Light")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: smallLightDarkPreferenceButton.colText
                }
            }
        }
    }

    // Wallpaper selection
    ContentSection {
        icon: "format_paint"
        title: Translation.tr("Wallpaper & Colors")
        Layout.fillWidth: true

        RowLayout {
            Layout.fillWidth: true

            Item {
                implicitWidth: 340
                implicitHeight: 200
                
                property bool isVideo: {
                    const path = Config.options.background.wallpaperPath.toLowerCase();
                    return path.endsWith('.mp4') || path.endsWith('.webm') || 
                           path.endsWith('.mkv') || path.endsWith('.avi') || 
                           path.endsWith('.mov') || path.endsWith('.m4v') ||
                           path.endsWith('.ogv');
                }
                
                ThumbnailImage {
                    id: wallpaperPreviewImage
                    visible: !parent.isVideo
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    // Reads the cached thumbnail rather than the wallpaper.
                    // sourceSize caps how large the pixmap ends up, not how much
                    // work it takes to get there — PNG has no scaled-decode
                    // path, so a 4K wallpaper was decoded at 4K and thrown away
                    // down to this size every time the page was rebuilt.
                    sourcePath: parent.isVideo ? "" : Config.options.background.wallpaperPath
                    sourceSize: Images.wallpaperPreviewSourceSize
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: wallpaperPreviewImage.width
                            height: wallpaperPreviewImage.height
                            radius: Appearance.rounding.normal
                        }
                    }
                }
                
                Rectangle {
                    id: videoContainer
                    visible: parent.isVideo
                    anchors.fill: parent
                    color: "transparent"
                    
                    VideoOutput {
                        id: videoOutput
                        anchors.fill: parent
                        fillMode: VideoOutput.PreserveAspectCrop
                    }
                    
                    MediaPlayer {
                        id: mediaPlayer
                        source: videoContainer.visible ? Config.options.background.wallpaperPath : ""
                        videoOutput: videoOutput
                        audioOutput: AudioOutput {
                            muted: true
                        }
                        loops: MediaPlayer.Infinite
                        playbackRate: 1.0
                        
                        onPlaybackStateChanged: {
                            if (playbackState === MediaPlayer.StoppedState && source !== "") {
                                play();
                            }
                        }
                        
                        onSourceChanged: {
                            if (source !== "" && videoContainer.visible) {
                                // Small delay to ensure video output is ready
                                playTimer.restart();
                            }
                        }
                    }
                    
                    Timer {
                        id: playTimer
                        interval: 100
                        repeat: false
                        onTriggered: {
                            if (mediaPlayer.source !== "" && videoContainer.visible) {
                                mediaPlayer.play();
                            }
                        }
                    }
                    
                    Timer {
                        interval: 100
                        running: videoContainer.visible
                        onTriggered: {
                            if (mediaPlayer.source !== "" && mediaPlayer.playbackState !== MediaPlayer.PlayingState) {
                                mediaPlayer.play();
                            }
                        }
                    }
                    
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: videoContainer.width
                            height: videoContainer.height
                            radius: Appearance.rounding.normal
                        }
                    }
                }
            }

            ColumnLayout {                
                RippleButtonWithIcon {
                    enabled: !randomWallProc.running
                    Layout.fillWidth: true
                    buttonRadius: Appearance.rounding.small
                    centerContent: true
                    materialIcon: "wallpaper"
                    mainText: randomWallProc.running ? Translation.tr("Applying...") : Translation.tr("Default Wallpaper")
                    onClicked: {
                        randomWallProc.scriptPath = `${Directories.scriptPath}/colors/random/set_default_wall.sh`;
                        randomWallProc.running = true;
                    }

                    StyledToolTip {
                        text: Translation.tr("Reset to the default theme wallpaper")
                    }
                }
                RippleButtonWithIcon {
                    enabled: !randomWallProc.running
                    visible: Config.options.policies.weeb === 1
                    Layout.fillWidth: true
                    buttonRadius: Appearance.rounding.small
                    materialIcon: "ifl"
                    mainText: randomWallProc.running ? Translation.tr("Be patient...") : Translation.tr("Random: osu! seasonal")
                    onClicked: {
                        randomWallProc.scriptPath = `${Directories.scriptPath}/colors/random/random_osu_wall.sh`;
                        randomWallProc.running = true;
                    }
                    StyledToolTip {
                        text: Translation.tr("Random osu! seasonal background\nImage is saved to ~/Pictures/Wallpapers")
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    uniformCellSizes: true

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        centerContent: true
                        materialIcon: "wallpaper"
                        mainText: Translation.tr("Wallpaper")
                        StyledToolTip {
                            text: Translation.tr("Pick wallpaper image on your system")
                        }
                        onClicked: {
                            Quickshell.execDetached(`${Directories.wallpaperSwitchScriptPath}`);
                        }
                    }
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        centerContent: true
                        materialIcon: "slideshow"
                        mainText: Translation.tr("Slideshow")
                        StyledToolTip {
                            text: Translation.tr("Rotate the wallpaper through a folder's images")
                        }
                        onClicked: {
                            slideshowFolderProc.command = ["bash", "-c",
                                'zenity --file-selection --directory --filename="$1/" --title="$2"',
                                "--", WallpaperSlideshow.folder, Translation.tr("Choose slideshow folder")];
                            slideshowFolderProc.running = false;
                            slideshowFolderProc.running = true;
                        }
                    }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    uniformCellSizes: true

                    SmallLightDarkPreferenceButton {
                        Layout.fillHeight: true
                        dark: false
                    }
                    SmallLightDarkPreferenceButton {
                        Layout.fillHeight: true
                        dark: true
                    }
                }
            }
        }

        // A style chosen outright that matches what Auto gives this wallpaper
        // shows as Auto, since its button is the one left off.
        ConfigSelectionArray {
            justify: true
            currentValue: Config.options.appearance.palette.type === page.autoScheme
                ? "auto" : Config.options.appearance.palette.type
            onSelected: newValue => {
                Config.options.appearance.palette.type = newValue;
                paletteApplyTimer.restart();
            }

            Timer {
                id: paletteApplyTimer
                interval: 150
                repeat: false
                onTriggered: {
                    applyTheme("--noswitch");
                }
            }
            options: [
                {
                    "value": "auto",
                    "displayName": Translation.tr("Auto")
                },
                {
                    "value": "scheme-content",
                    "displayName": Translation.tr("Content")
                },
                {
                    "value": "scheme-expressive",
                    "displayName": Translation.tr("Expressive")
                },
                {
                    "value": "scheme-fidelity",
                    "displayName": Translation.tr("Fidelity")
                },
                {
                    "value": "scheme-fruit-salad",
                    "displayName": Translation.tr("Fruit Salad")
                },
                {
                    "value": "scheme-monochrome",
                    "displayName": Translation.tr("Monochrome")
                },
                {
                    "value": "scheme-neutral",
                    "displayName": Translation.tr("Neutral")
                },
                {
                    "value": "scheme-rainbow",
                    "displayName": Translation.tr("Rainbow")
                },
                {
                    "value": "scheme-tonal-spot",
                    "displayName": Translation.tr("Tonal Spot")
                }
            ].filter(option => option.value !== page.autoScheme)
        }

        // The choices on the right of each row sit against the right edge at
        // their own width, so every row ends on the same line.
        ConfigRow {
            ConfigSwitch {
                Layout.fillWidth: false
                Layout.preferredWidth: (page.baseWidth - 4) / 2
                Layout.alignment: Qt.AlignBottom
                buttonIcon: "ev_shadow"
                text: Translation.tr("Transparency")
                checked: Config.options.appearance.transparency.enable
                onCheckedChanged: {
                    Config.options.appearance.transparency.enable = checked;
                }
            }

            Item {
                Layout.fillWidth: true
            }

            ContentSubsection {
                title: Translation.tr("Screen round corner")

                Layout.fillWidth: false


                Layout.preferredWidth: screenCornerChoices.naturalWidth

                ConfigSelectionArray {
                    id: screenCornerChoices
                    currentValue: Config.options.appearance.fakeScreenRounding
                    onSelected: newValue => {
                        Config.options.appearance.fakeScreenRounding = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("No"),
                            icon: "close",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Yes"),
                            icon: "check",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("When not fullscreen"),
                            icon: "fullscreen_exit",
                            value: 2
                        }
                    ]
                }
            }
        }
    }

    // Laid out as the Bar and Dock pages lay out the same choices, and saved
    // through the same shared rules, so a Hug dock keeps facing the bar
    // whichever page moves it.
    ContentSection {
        icon: "screenshot_monitor"
        title: Translation.tr("Bar & Dock")

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Bar position")

                ConfigSelectionArray {
                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    onSelected: newValue => Appearance.sizes.placeBar((newValue & 1) !== 0, (newValue & 2) !== 0)
                    options: [
                        {
                            displayName: Translation.tr("Top"),
                            icon: "arrow_upward",
                            value: 0 // bottom: false, vertical: false
                        },
                        {
                            displayName: Translation.tr("Left"),
                            icon: "arrow_back",
                            value: 2 // bottom: false, vertical: true
                        },
                        {
                            displayName: Translation.tr("Bottom"),
                            icon: "arrow_downward",
                            value: 1 // bottom: true, vertical: false
                        },
                        {
                            displayName: Translation.tr("Right"),
                            icon: "arrow_forward",
                            value: 3 // bottom: true, vertical: true
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Bar style")

                Layout.fillWidth: false


                Layout.preferredWidth: barStyleChoices.naturalWidth

                ConfigSelectionArray {
                    id: barStyleChoices
                    currentValue: Config.options.bar.cornerStyle
                    onSelected: newValue => RoundedCorners.pickBarStyle(newValue)
                    options: [
                        {
                            displayName: Translation.tr("Float"),
                            icon: "page_header",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Notch"),
                            icon: "call_to_action",
                            value: 3
                        },
                        {
                            displayName: Translation.tr("Hug"),
                            icon: "line_curve",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Rect"),
                            icon: "toolbar",
                            value: 2
                        }
                    ]
                }
            }
        }

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Dock position")

                // The edge the dock actually occupies, not the saved one: the
                // resolver already flips an edge the bar holds. The bar's own
                // edge is left off, since asking for it only sends the bar to
                // the far side, which Bar position above does directly, and
                // that keeps the row on one line. A Hug dock is only offered the
                // edge facing the bar, the one it can run the length of.
                ConfigSelectionArray {
                    currentValue: Config.options.dock.enable ? Appearance.sizes.dockEdge : "off"
                    onSelected: newValue => {
                        if (newValue === "off") {
                            Config.options.dock.enable = false;
                            return;
                        }
                        Appearance.sizes.placeDock(newValue);
                    }
                    options: [
                        { displayName: Translation.tr("Off"), icon: "close", value: "off" },
                        { displayName: Translation.tr("Top"), icon: "arrow_upward", value: "top" },
                        { displayName: Translation.tr("Left"), icon: "arrow_back", value: "left" },
                        { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: "bottom" },
                        { displayName: Translation.tr("Right"), icon: "arrow_forward", value: "right" }
                    ].filter(option => option.value === "off"
                        || (Appearance.sizes.dockEdgeAllowed(option.value)
                            && !(Appearance.sizes.barShown && option.value === Appearance.sizes.barEdge)))
                }
            }

            ContentSubsection {
                title: Translation.tr("Dock style")

                Layout.fillWidth: false


                Layout.preferredWidth: dockStyleChoices.naturalWidth

                ConfigSelectionArray {
                    id: dockStyleChoices
                    currentValue: Config.options.dock.cornerStyle
                    onSelected: newValue => Appearance.sizes.pickDockStyle(newValue)
                    options: [
                        { displayName: Translation.tr("Float"), icon: "page_header", value: "float" },
                        { displayName: Translation.tr("Notch"), icon: "call_to_action", value: "hug" },
                        { displayName: Translation.tr("Hug"), icon: "line_curve", value: "span" },
                        { displayName: Translation.tr("Rect"), icon: "toolbar", value: "rect" }
                    ]
                }
            }
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        text: Translation.tr("Not all settings are available in this app. You can also check the config file by hitting the \"Copy config path\" button and editing the file in an IDE or text editor.")

        Item {
            Layout.fillWidth: true
        }
        RippleButtonWithIcon {
            id: copyPathButton
            property bool justCopied: false
            Layout.fillWidth: false
            buttonRadius: Appearance.rounding.small
            materialIcon: justCopied ? "check" : "content_copy"
            mainText: justCopied ? Translation.tr("Path copied") : Translation.tr("Copy config path")
            onClicked: {
                copyPathButton.justCopied = true
                Quickshell.clipboardText = FileUtils.trimFileProtocol(Directories.shellConfigPath);
                revertTextTimer.restart();
            }
            colBackground: ColorUtils.transparentize(Appearance.colors.colPrimaryContainer)
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colRipple: Appearance.colors.colPrimaryContainerActive

            Timer {
                id: revertTextTimer
                interval: 1500
                onTriggered: {
                    copyPathButton.justCopied = false
                }
            }
        }
    }
}
