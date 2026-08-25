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
    forceWidth: true

    Process {
        id: randomWallProc
        property string status: ""
        property string scriptPath: `${Directories.scriptPath}/colors/random/random_konachan_wall.sh`
        command: ["bash", "-c", FileUtils.trimFileProtocol(randomWallProc.scriptPath)]
        stdout: SplitParser {
            onRead: data => {
                randomWallProc.status = data.trim();
            }
        }
    }

    Process {
        id: themeApplyProc
        onExited: MaterialThemeLoader.reapplyTheme()
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

    function applyTheme(args) {
        if (themeApplyProc.running)
            return;

        themeApplyProc.command = ["bash", "-c", `${Directories.wallpaperSwitchScriptPath} ${args}`];
        themeApplyProc.running = true;
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
                            width: 360
                            height: 200
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
                            width: 360
                            height: 200
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
                    mainText: randomWallProc.running ? Translation.tr("Be patient...") : Translation.tr("Random: Konachan")
                    onClicked: {
                        randomWallProc.scriptPath = `${Directories.scriptPath}/colors/random/random_konachan_wall.sh`;
                        randomWallProc.running = true;
                    }
                    StyledToolTip {
                        text: Translation.tr("Random SFW Anime wallpaper from Konachan\nImage is saved to ~/Pictures/Wallpapers")
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

        ConfigSelectionArray {
            currentValue: Config.options.appearance.palette.type
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
            ]
        }

        ConfigSwitch {
            buttonIcon: "ev_shadow"
            text: Translation.tr("Transparency")
            checked: Config.options.appearance.transparency.enable
            onCheckedChanged: {
                Config.options.appearance.transparency.enable = checked;
            }
        }
    }

    ContentSection {
        icon: "screenshot_monitor"
        title: Translation.tr("Bar & screen")

        // Dropdowns rather than the rows of buttons the Bar page uses. This
        // page is meant to be read at a glance, and a fourth bar style pushed
        // the buttons onto a second line here where the column is narrower.
        // A menu costs one click to see the choices and never grows again.
        ConfigRow {
            uniform: true
            ContentSubsection {
                title: Translation.tr("Bar position")
                StyledComboBox {
                    textRole: "displayName"
                    Layout.fillWidth: true
                    currentIndex: {
                        const v = (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0);
                        const i = model.findIndex(o => o.value === v);
                        return i !== -1 ? i : 0;
                    }
                    onActivated: index => {
                        const v = model[index].value;
                        Config.options.bar.bottom = (v & 1) !== 0;
                        Config.options.bar.vertical = (v & 2) !== 0;
                    }
                    model: [
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

                StyledComboBox {
                    textRole: "displayName"
                    Layout.fillWidth: true
                    currentIndex: {
                        const i = model.findIndex(o => o.value === Config.options.bar.cornerStyle);
                        return i !== -1 ? i : 1;
                    }
                    onActivated: index => { Config.options.bar.cornerStyle = model[index].value; }
                    model: [
                        {
                            displayName: Translation.tr("Hug"),
                            icon: "line_curve",
                            value: 0
                        },
                        {
                            displayName: Translation.tr("Float"),
                            icon: "page_header",
                            value: 1
                        },
                        {
                            displayName: Translation.tr("Rect"),
                            icon: "toolbar",
                            value: 2
                        },
                        {
                            displayName: Translation.tr("Notch"),
                            icon: "call_to_action",
                            value: 3
                        }
                    ]
                }
            }
        }

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Screen round corner")

                ConfigSelectionArray {
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
