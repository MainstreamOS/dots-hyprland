//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_SCALE_FACTOR=1

// Feature-walkthrough tutorial. Launches as its own window via
//   qs -p $HOME/.config/quickshell/ii/welcome-tutorial.qml
// and walks the user through a few of the more discoverable features
// in card-by-card "next next next" form.
//
// To add a card later: drop a new component in the `cards` model below
// and bump `cardCount`. The card itself just needs a title, body, and a
// visual on the right; share the Card scaffold component for layout.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions

ApplicationWindow {
    id: root
    visible: true
    // Fixed 1100×680: minimum and maximum match, so the window is
    // non-resizable. Hyprland reads the size hints and floats it.
    // The extra horizontal room (was 980) lets the first-run setup
    // page render the two Window Layout cards (layout picker + Title
    // Bars) side-by-side at the same width they have in Settings →
    // Layouts, rather than the squished half-width version they had
    // when the window matched the tutorial's other cards.
    width: 1100
    height: 680
    minimumWidth: 1100
    minimumHeight: 680
    maximumWidth: 1100
    maximumHeight: 680
    color: Appearance.m3colors.m3background
    title: Translation.tr("Welcome to Mainstream")

    property int currentCard: 0
    readonly property int cardCount: 8   // bump as you add more cards

    // First-run state — mirrors welcome.qml so the "Show next time"
    // switch toggles the same first_run.txt file the FirstRunExperience
    // service watches. Default ON: leaving the switch alone keeps the
    // tutorial scheduled for next login; toggling OFF writes the file
    // so it stays skipped on subsequent boots.
    property string firstRunFilePath: FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property bool showNextTime: true

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        // Align the file state with the switch's default-ON: remove
        // the marker so the tutorial fires again next session unless
        // the user toggles the switch off.
        if (root.showNextTime) {
            Quickshell.execDetached(["rm", "-f", root.firstRunFilePath])
        }
    }

    // ── Frame ────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        // Titlebar — mirrors welcome.qml's titlebar so the tutorial
        // takes over the welcome window's role on first boot. Title
        // text and placement match welcome.qml; the Skip button is
        // replaced by a "Show next time" StyledSwitch (default ON)
        // that toggles the same first_run.txt marker the
        // FirstRunExperience service watches.
        Item {
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            implicitHeight: Math.max(welcomeText.implicitHeight, windowControlsRow.implicitHeight)

            StyledText {
                id: welcomeText
                anchors {
                    left: Config.options.windows.centerTitle ? undefined : parent.left
                    horizontalCenter: Config.options.windows.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                color: Appearance.colors.colOnLayer0
                text: Translation.tr("Hi there! First things first...")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }

            RowLayout { // Window controls row
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: Translation.tr("Show next time")
                }
                StyledSwitch {
                    id: showNextTimeSwitch
                    checked: root.showNextTime
                    scale: 0.6
                    Layout.alignment: Qt.AlignVCenter
                    onCheckedChanged: {
                        if (checked) {
                            Quickshell.execDetached(["rm", root.firstRunFilePath]);
                        } else {
                            Quickshell.execDetached(["bash", "-c", `echo '${StringUtils.shellSingleQuoteEscape(root.firstRunFileContent)}' > '${StringUtils.shellSingleQuoteEscape(root.firstRunFilePath)}'`]);
                        }
                    }
                }
                // Close button suppressed — use Super+Q (or the window
                // manager's own close gesture) to dismiss the window.
                RippleButton {
                    visible: false
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 35
                    implicitHeight: 35
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                    }

                    StyledToolTip {
                        text: Translation.tr("Tip: Close a window with Super+Q")
                    }
                }
            }
        }

        // Card stage
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Appearance.m3colors.m3surfaceContainerLow
            radius: Appearance.rounding.normal

            StackLayout {
                anchors.fill: parent
                currentIndex: root.currentCard

                Card0Setup {}
                Card1BarTour {}
                Card2Workspaces {}
                Card3DockAndDrawer {}
                Card4MoveBetweenWorkspaces {}
                Card5FileDragViaBar {}
                Card6DockPreview {}
                Card7AppShowcaseTabs {}
                // Card10 {}, … add more here
            }
        }

        // Footer
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            RippleButton {
                // Keep the slot in the layout so the page indicator
                // stays centred — `visible: false` would have RowLayout
                // exclude it entirely and pull the indicator left. Use
                // opacity + enabled instead.
                opacity: root.currentCard > 0 ? 1 : 0
                enabled: root.currentCard > 0
                buttonRadius: Appearance.rounding.normal
                implicitWidth: 110
                implicitHeight: 38
                onClicked: root.currentCard--
                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Translation.tr("Back")
                    color: Appearance.colors.colOnLayer0
                }
            }
            Item { Layout.fillWidth: true }

            // Page indicator dots
            RowLayout {
                spacing: 8
                Repeater {
                    model: root.cardCount
                    delegate: Rectangle {
                        required property int index
                        readonly property bool active: index === root.currentCard
                        implicitWidth: active ? 28 : 10
                        implicitHeight: 10
                        radius: 5
                        color: active
                            ? Appearance.m3colors.m3primary
                            : Appearance.colors.colOutlineVariant
                        Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on color        { ColorAnimation  { duration: 220 } }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            RippleButton {
                buttonRadius: Appearance.rounding.normal
                implicitWidth: 110
                implicitHeight: 38
                colBackground: Appearance.m3colors.m3primary
                colBackgroundHover: Appearance.m3colors.m3primary
                onClicked: {
                    if (root.currentCard < root.cardCount - 1) root.currentCard++
                    else root.close()
                }
                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.currentCard < root.cardCount - 1
                        ? Translation.tr("Next")
                        : Translation.tr("Done")
                    color: Appearance.m3colors.m3onPrimary
                }
            }
        }
    }


    // Faint pill background shared by every bar section in card 2 —
    // matches the real shell's BarGroup.qml (colLayer1 with a touch
    // of transparency, soft rounding, no border).
    component PillBg : Rectangle {
        color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.3)
        radius: 8
        border.width: 0
    }

    // Generic app-window mockup — matches Card10's launched-window
    // style (white body, light grey title bar with a rounded tab pill,
    // app icon centred). Title bar height + tab pill + icon all scale
    // proportionally so a single component works for full-mockup
    // windows AND small workspace tiles.
    component AppWindow : Rectangle {
        id: appWin
        property string appIcon: ""
        radius: 8
        color: "#FFFFFF"
        clip: true

        readonly property real titleBarH: Math.max(12, Math.min(32, height * 0.13))
        readonly property real iconSize:
            Math.max(16, Math.min(64, Math.min(width, height - titleBarH) * 0.5))

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: appWin.titleBarH
            color: "#F0F0F4"
            topLeftRadius: 8
            topRightRadius: 8
            bottomLeftRadius: 0
            bottomRightRadius: 0

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Math.max(4, appWin.titleBarH * 0.35)
                width: Math.min(110, Math.max(28, parent.width * 0.22))
                height: parent.height - Math.max(3, parent.height * 0.27)
                radius: Math.max(2, height / 4)
                color: "#FFFFFF"
                border.color: "#D0D0D5"
                border.width: 1
            }
        }

        IconImage {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: appWin.titleBarH / 2
            source: appWin.appIcon !== "" ? Quickshell.iconPath(appWin.appIcon, "image-missing") : ""
            implicitSize: appWin.iconSize
            visible: appWin.appIcon !== ""
        }
    }

    // Nautilus "Home" window mockup. Used by both card 6's dock-
    // preview popup AND the Nautilus tile on workspace 3 so the
    // preview and its destination window show the exact same
    // contents — just at different sizes. Everything (title bar,
    // folder grid, icons) is sized proportionally to the host so
    // the mockup scales cleanly from preview size up to full tile.
    component NautilusWindow : Rectangle {
        id: nw
        radius: 8
        color: Appearance.m3colors.m3surfaceContainer
        border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.45)
        border.width: 1
        clip: true

        readonly property real titleBarH: Math.max(18, height * 0.18)
        // Folder cell width scales with overall width; cap so big
        // tiles don't end up with one massive folder.
        readonly property real cellW: Math.min(80, width * 0.18)
        readonly property real cellH: cellW * 1.08

        // Title bar — "Home" on the left, close X on the right.
        Item {
            id: nwTitleBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: nw.titleBarH

            StyledText {
                anchors.left: parent.left
                anchors.leftMargin: nw.titleBarH * 0.5
                anchors.verticalCenter: parent.verticalCenter
                text: "Home"
                font {
                    family: Appearance.font.family.title
                    pixelSize: Math.max(9, nw.titleBarH * 0.55)
                }
                color: Appearance.colors.colOnLayer0
            }
            MaterialSymbol {
                anchors.right: parent.right
                anchors.rightMargin: nw.titleBarH * 0.4
                anchors.verticalCenter: parent.verticalCenter
                text: "close"
                iconSize: Math.max(11, nw.titleBarH * 0.6)
                color: Appearance.colors.colOnLayer0
                opacity: 0.75
            }
        }

        // Content area — bordered card with a centred 4×2 folder grid.
        Rectangle {
            anchors.top: nwTitleBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.bottomMargin: 8
            anchors.topMargin: 2
            radius: 6
            color: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.35)
            clip: true

            Grid {
                anchors.centerIn: parent
                columns: 4
                rows: 2
                columnSpacing: Math.max(6, nw.cellW * 0.18)
                rowSpacing: Math.max(4, nw.cellH * 0.16)
                Repeater {
                    model: 8
                    Item {
                        width: nw.cellW
                        height: nw.cellH
                        MaterialSymbol {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            text: "folder"
                            iconSize: nw.cellW * 0.68
                            color: Appearance.m3colors.m3primary
                            opacity: 0.78
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: nw.cellW * 0.7
                            height: Math.max(2, nw.cellH * 0.08)
                            radius: 1
                            color: Appearance.colors.colOnLayer0
                            opacity: 0.32
                        }
                    }
                }
            }
        }
    }

    // ── Card 2: Workspaces ───────────────────────────────────────────────
    component Card2Workspaces : Item {
        id: card2

        // Animation state. `currentWs` is the active workspace; the
        // tiled-background viewport slides to it via a Behavior on x.
        // `cycleDir` flips at the ends so the demo ping-pongs
        // (0→1→2→3→4→3→2→1→0…) instead of wrap-snapping.
        property int currentWs: 0
        property int cycleDir: 1

        // Demo content — each entry is the apps "open" on that
        // workspace. Window counts vary so each page reads differently
        // when the tiled background swaps.
        readonly property var workspaceApps: [
            ["google-chrome", "code-oss", "kitty"],
            ["spotify", "telegram"],
            ["firefox"],
            ["gimp", "vlc", "thunderbird", "blender"],
            ["discord", "obs"],
        ]
        readonly property int totalWs: 10
        readonly property int cycleLength: workspaceApps.length

        // The workspace widget (bar + magnified strip) only ever shows
        // a single icon — the workspace's first app — to mirror the
        // real shell. The full list of apps shows up tiled in the
        // background area below instead.
        function primaryAppFor(ws) {
            const list = workspaceApps[ws] || []
            return list.length > 0 ? list[0] : ""
        }

        // Mockup geometry — same 600×380 internal grid as card 1 so the
        // scale-to-fit container behaves identically.
        readonly property int mockW: 600
        readonly property int mockH: 380

        // ── Top bar ───────────────────────────────────────────────────
        // Closely mirrors the real bar: faint pill backgrounds on each
        // section (no defined border), workspace strip dead-centre,
        // active-window text + media pill on the left, clock+utils +
        // weather + sys-tray pill on the right.
        readonly property int barW: 560
        readonly property int barH: 30               // matches Card1BarTour (panel 1)
        readonly property int barX: (mockW - barW) / 2
        readonly property int barY: 12
        readonly property int barPillH: 22           // inset inside the bar
        readonly property int barPillRadius: 8
        // Workspace strip inside the bar: fixed-grid slots, a stretchy
        // indicator overlays them via AnimatedTabIndexPair so the
        // leading edge moves fast (100ms) and the trailing edge lags
        // (300ms) — same "trail catches up" feel as the real bar.
        readonly property int barSlotW: 16
        readonly property int barSlotH: 16
        readonly property int barSlotR: 2            // smaller inactive dot, highlight + icon unchanged
        readonly property int barIconSize: 10
        readonly property int barIndicatorInset: 1   // → 14×14 circle at rest

        // ── Tiled-windows background ─────────────────────────────────
        // Same dimensions and position as Card6DockPreview's tile area
        // so panel 2 and panel 7 share the same window real estate.
        readonly property int tileX: 20
        readonly property int tileW: mockW - 2 * tileX
        readonly property int tileY: barY + barH + 12
        readonly property int tileH: Math.round(barW * 1034 / 1912)
        readonly property int tileGap: 6
        readonly property int tileBarH: 11

        // Dwindle-ish layout templates: each entry is a list of unit
        // rectangles {x, y, w, h} in 0..1 normalized coords inside the
        // tile container. Picked to read as natural tile shapes for
        // each window count.
        function tileLayout(count) {
            switch (count) {
            case 0: return []
            case 1: return [{x:0,    y:0,   w:1,    h:1   }]
            case 2: return [{x:0,    y:0,   w:0.5,  h:1   },
                            {x:0.5,  y:0,   w:0.5,  h:1   }]
            case 3: return [{x:0,    y:0,   w:0.55, h:1   },
                            {x:0.55, y:0,   w:0.45, h:0.5 },
                            {x:0.55, y:0.5, w:0.45, h:0.5 }]
            case 4: return [{x:0,    y:0,   w:0.55, h:1   },
                            {x:0.55, y:0,   w:0.45, h:0.34},
                            {x:0.55, y:0.34,w:0.45, h:0.33},
                            {x:0.55, y:0.67,w:0.45, h:0.33}]
            default: return []
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 28

            // Left: title + body
            ColumnLayout {
                Layout.minimumWidth: 280
                Layout.maximumWidth: 280
                Layout.preferredWidth: 280
                Layout.fillWidth: false
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 12

                Item { Layout.fillHeight: true }

                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 280
                    text: Translation.tr("Workspaces keep your apps tidy")
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.huge
                        variableAxes: Appearance.font.variableAxes.title
                    }
                    color: Appearance.colors.colOnLayer0
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 280
                    text: Translation.tr("Think of each workspace as its own desk — put email on one, code on another, a game on a third. The dots in your bar show which desk you're on and which have apps open. Click one, press <b>Super <font face='JetBrains Mono NF'>(󰖳)</font> + 1‑9</b>, or press <b>Super <font face='JetBrains Mono NF'>(󰖳)</font> + scroll the mouse wheel</b> to switch between them.")
                    textFormat: Text.RichText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.85
                    wrapMode: Text.WordWrap
                    lineHeight: 1.35
                }

                Item { Layout.fillHeight: true }
            }

            // Right: animated mockup — same scale-to-fit shape as card 1
            Item {
                id: card2MockupHost
                Layout.fillWidth: true
                Layout.fillHeight: true

                Item {
                    id: card2MockupContainer
                    width: card2.mockW
                    height: card2.mockH
                    anchors.centerIn: parent
                    scale: Math.min(
                        1.0,
                        (card2MockupHost.width  - 8) / width,
                        (card2MockupHost.height - 8) / height
                    )

                    Rectangle {
                        id: card2Mockup
                        anchors.fill: parent
                        radius: 14
                        color: "#0e0e12"
                        border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.6)
                        border.width: 1
                        clip: true

                        // ─── Top bar ───
                        Rectangle {
                            id: barFrame
                            x: card2.barX
                            y: card2.barY
                            width: card2.barW
                            height: card2.barH
                            // Fully-rounded pill ends to match the
                            // earlier mockup shape.
                            radius: card2.barH / 2
                            color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.45)
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.35)
                            border.width: 1

                            // Active-window text column on the far left
                            // (mirrors the real shell's ActiveWindow.qml:
                            // top line dim, bottom line bright).
                            ColumnLayout {
                                id: activeWindowText
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 10
                                spacing: -3
                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Desktop"
                                    font.pixelSize: 7
                                    color: Appearance.colors.colSubtext
                                    opacity: 0.85
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Workspace " + (card2.currentWs + 1)
                                    font.pixelSize: 9
                                    color: Appearance.colors.colOnLayer0
                                }
                            }

                            // Media pill — music-note glyph in a soft
                            // circle (stands in for album art when none)
                            // plus a clipped track title, all on a
                            // colLayer1 pill.
                            PillBg {
                                id: mediaPill
                                anchors.left: activeWindowText.right
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                height: card2.barPillH
                                width: mediaRow.implicitWidth + 12
                                Row {
                                    id: mediaRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Rectangle {
                                        width: 12; height: 12; radius: 6
                                        color: Appearance.m3colors.m3primary
                                        opacity: 0.9
                                        anchors.verticalCenter: parent.verticalCenter
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "music_note"
                                            iconSize: 9
                                            color: Appearance.m3colors.m3onPrimary
                                        }
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Subnautica 2 LAU…"
                                        font.pixelSize: 8
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                        width: 70
                                    }
                                }
                            }

                            // ── Centre: workspace strip pill ──
                            // Perfectly centered in the bar (matches the
                            // real shell where middleSection is anchored
                            // to parent.horizontalCenter).
                            PillBg {
                                id: workspacePill
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                height: card2.barPillH
                                width: barWsStrip.implicitWidth + 10
                                Item {
                                    id: barWsStrip
                                    anchors.centerIn: parent
                                    implicitWidth: card2.barSlotW * card2.totalWs
                                    implicitHeight: card2.barSlotH

                                    AnimatedTabIndexPair {
                                        id: barIdxPair
                                        index: card2.currentWs
                                    }

                                    Rectangle {
                                        z: 1
                                        readonly property real lo: Math.min(barIdxPair.idx1, barIdxPair.idx2)
                                        readonly property real hi: Math.max(barIdxPair.idx1, barIdxPair.idx2)
                                        x: lo * card2.barSlotW + card2.barIndicatorInset
                                        width: (hi - lo) * card2.barSlotW + card2.barSlotW - 2 * card2.barIndicatorInset
                                        height: card2.barSlotH - 2 * card2.barIndicatorInset
                                        y: card2.barIndicatorInset
                                        radius: height / 2
                                        color: Appearance.m3colors.m3primary
                                        opacity: 0.9
                                    }

                                    Row {
                                        z: 2
                                        anchors.fill: parent
                                        Repeater {
                                            model: card2.totalWs
                                            delegate: Item {
                                                required property int index
                                                width: card2.barSlotW
                                                height: card2.barSlotH
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: card2.barSlotR * 2
                                                    height: card2.barSlotR * 2
                                                    radius: width / 2
                                                    color: Appearance.colors.colOnLayer0
                                                    opacity: 0.35
                                                }
                                            }
                                        }
                                    }

                                    IconImage {
                                        z: 3
                                        readonly property string primary: card2.primaryAppFor(card2.currentWs)
                                        visible: primary !== ""
                                        implicitSize: card2.barIconSize
                                        x: card2.currentWs * card2.barSlotW + (card2.barSlotW - implicitSize) / 2
                                        y: (card2.barSlotH - implicitSize) / 2
                                        source: primary !== ""
                                            ? Quickshell.iconPath(primary, "image-missing")
                                            : ""
                                        Behavior on x {
                                            NumberAnimation { duration: 180; easing.type: Easing.OutSine }
                                        }
                                    }
                                }
                            }

                            // ── Right side ──
                            // System-tray pill stays anchored to the
                            // far right; clock + weather are anchored
                            // to its left with extra margin so they
                            // sit closer to the centred workspace pill.

                            // System-tray pill (volume, wifi, settings)
                            PillBg {
                                id: sysTrayPill
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 10
                                height: card2.barPillH
                                width: trayRow.implicitWidth + 12
                                Row {
                                    id: trayRow
                                    anchors.centerIn: parent
                                    spacing: 6
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "volume_up"
                                        iconSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "wifi"
                                        iconSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "settings"
                                        iconSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }
                            }

                            // Clock + weather row — anchored to the
                            // sys-tray pill's left edge with a gap that
                            // pulls them toward the workspace pill.
                            Row {
                                anchors.right: sysTrayPill.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 12
                                spacing: 4

                                // Clock pill — time only.
                                PillBg {
                                    height: card2.barPillH
                                    width: clockText.implicitWidth + 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    StyledText {
                                        id: clockText
                                        anchors.centerIn: parent
                                        text: "12:53"
                                        font.pixelSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }

                                // Weather pill (icon + temp)
                                PillBg {
                                    height: card2.barPillH
                                    width: weatherRow.implicitWidth + 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    Row {
                                        id: weatherRow
                                        anchors.centerIn: parent
                                        spacing: 2
                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "cloud"
                                            iconSize: 11
                                            color: Appearance.colors.colOnLayer1
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "74°"
                                            font.pixelSize: 9
                                            color: Appearance.colors.colOnLayer1
                                        }
                                    }
                                }
                            }
                        }

                        // ─── Tiled windows background ───
                        // Sliding viewport of workspace pages. Each
                        // page renders one workspace's tiled apps; the
                        // Row's x is bound to -currentWs * tileW so the
                        // current page sits at x=0 in the viewport. The
                        // Behavior on x reproduces Hyprland's actual
                        // workspace-switch animation:
                        //   hl.animation({ leaf="workspaces", speed=7,
                        //                  bezier="menu_decel",
                        //                  style="slide" })
                        // where menu_decel ≈ {{0.1, 1}, {0, 1}} — a
                        // sharp decel curve. Easing.OutQuint at 280ms
                        // matches the feel of speed 7 with that curve.
                        Item {
                            id: tileBackground
                            x: card2.tileX
                            y: card2.tileY
                            width: card2.tileW
                            height: card2.tileH
                            clip: true

                            // Live workspace label, fixed in the
                            // viewport (does not slide with pages).
                            StyledText {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.rightMargin: 10
                                anchors.bottomMargin: 10
                                text: Translation.tr("Workspace %1").arg(card2.currentWs + 1)
                                font.pixelSize: 10
                                color: Appearance.colors.colOnLayer0
                                opacity: 0.55
                                z: 5
                            }

                            Row {
                                id: pageRow
                                x: -card2.currentWs * card2.tileW
                                Behavior on x {
                                    NumberAnimation { duration: 280; easing.type: Easing.OutQuint }
                                }
                                Repeater {
                                    model: card2.cycleLength
                                    delegate: Item {
                                        id: page
                                        required property int index
                                        width: card2.tileW
                                        height: card2.tileH

                                        Repeater {
                                            model: card2.workspaceApps[page.index] || []
                                            delegate: Rectangle {
                                                id: tile
                                                required property int index
                                                required property string modelData
                                                readonly property var apps: card2.workspaceApps[page.index] || []
                                                readonly property var rect: {
                                                    const rects = card2.tileLayout(apps.length)
                                                    return rects[index] || {x:0, y:0, w:0, h:0}
                                                }
                                                x: Math.round(rect.x * card2.tileW) + (rect.x > 0 ? card2.tileGap / 2 : 0)
                                                y: Math.round(rect.y * card2.tileH) + (rect.y > 0 ? card2.tileGap / 2 : 0)
                                                width: (rect.x + rect.w >= 1)
                                                    ? card2.tileW - x
                                                    : Math.round(rect.w * card2.tileW) - (rect.x > 0 ? card2.tileGap / 2 : 0) - card2.tileGap / 2
                                                height: (rect.y + rect.h >= 1)
                                                    ? card2.tileH - y
                                                    : Math.round(rect.h * card2.tileH) - (rect.y > 0 ? card2.tileGap / 2 : 0) - card2.tileGap / 2
                                                radius: 8
                                                color: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.18)
                                                border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.45)
                                                border.width: 1

                                                Rectangle {
                                                    width: parent.width
                                                    height: card2.tileBarH
                                                    radius: 4
                                                    color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.5)
                                                    Rectangle {
                                                        x: 4
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 26
                                                        height: 3
                                                        radius: 1.5
                                                        color: Appearance.colors.colOnLayer0
                                                        opacity: 0.35
                                                    }
                                                }

                                                IconImage {
                                                    anchors.centerIn: parent
                                                    anchors.verticalCenterOffset: card2.tileBarH / 2
                                                    implicitSize: Math.min(36, Math.min(tile.width, tile.height) - 18)
                                                    source: Quickshell.iconPath(tile.modelData, "image-missing")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } // end Rectangle (mockup)
                }     // end Item (mockupContainer)
            }         // end Item (mockupHost)
        }             // end RowLayout

        // Ping-pong through the demo workspaces. The Behavior on x on
        // pageRow handles the slide; the bar indicator's trail
        // animation is driven by AnimatedTabIndexPair off `currentWs`.
        Timer {
            interval: 1900
            running: true
            repeat: true
            onTriggered: {
                let next = card2.currentWs + card2.cycleDir
                if (next >= card2.cycleLength) {
                    card2.cycleDir = -1
                    next = card2.currentWs - 1
                } else if (next < 0) {
                    card2.cycleDir = 1
                    next = card2.currentWs + 1
                }
                card2.currentWs = next
            }
        }
    }

    // ── Card 6: Dock previews + click-to-jump ────────────────────────────
    component Card6DockPreview : Item {
        id: card6

        // ── State ──
        property int currentWs: 0          // active workspace, drives tile slide + bar indicator
        property int displayedWs: 0
        property real cursorX: 1000
        property real cursorY: 1000
        property bool dockHovered: false   // gates the magnify falloff
        property bool previewVisible: false

        // Phase 2 state — right-click chrome → context menu
        property bool spotifyFaded: false  // fade the ws-3 spotify window before phase 2
        property bool menuVisible: false
        property real cursorPulse: 1.0     // briefly scales the cursor on right-click
        readonly property int rightClickIdx: 0     // chrome's dock index
        readonly property real volume1: 0.91
        readonly property real volume2: 0.57

        // Demo workspaces. Workspace 3 has Spotify alone so the tile
        // fills the whole viewport — clicking the dock preview jumps
        // there and the destination window shows the same Spotify
        // screenshot the preview shows, just at full tile size.
        readonly property var workspaceApps: [
            ["google-chrome", "code-oss", "kitty"],
            ["telegram"],
            ["spotify"],
            ["gimp", "vlc", "blender"],
            ["discord", "obs"],
        ]

        // Path to the welcome-tutorial-images directory (same lookup
        // pattern Card6FileManager / Card11 use for their screenshots).
        readonly property string imageDir:
            Quickshell.env("HOME") + "/.config/quickshell/ii/welcome-tutorial-images"
        readonly property int totalWs: 10
        readonly property int cycleLength: workspaceApps.length

        function primaryAppFor(ws) {
            const list = workspaceApps[ws] || []
            return list.length > 0 ? list[0] : ""
        }

        // ── Mockup geometry ──
        readonly property int mockW: 600
        readonly property int mockH: 380

        // Bar (same shape as card 2; numbers tightened a touch so the
        // dock fits below)
        readonly property int barW: 560
        readonly property int barH: 30
        readonly property int barX: (mockW - barW) / 2
        readonly property int barY: 12
        readonly property int barPillH: 22
        readonly property int barSlotW: 16
        readonly property int barSlotH: 16
        readonly property int barSlotR: 2
        readonly property int barIconSize: 10
        readonly property int barIndicatorInset: 1

        // Tile viewport — extended down to the same height as Card6
        // FileManager's window so the windows feel substantial. The
        // dock renders on top (higher z), so it intentionally covers
        // the bottom of the tiles. visibleTileH keeps the workspace
        // counter pinned just above the dock instead of being hidden.
        readonly property int tileX: 20
        readonly property int tileW: mockW - 2 * tileX
        readonly property int tileY: barY + barH + 12
        readonly property int tileH: Math.round(barW * 1034 / 1912)
        readonly property int visibleTileH: dockY - tileY - 12
        readonly property int tileGap: 5
        readonly property int tileBarH: 10

        // Dock — 80% bigger than card 1's (icon 16 → 29, gap 8 → 14,
        // padding 8 → 14). Pin button on the left, pinned apps in
        // the middle, drawer button on the right (matches card 1).
        readonly property var dockApps: [
            "google-chrome", "spotify", "org.gnome.Nautilus", "gimp", "discord"
        ]
        readonly property int dockIconSize: 29
        readonly property int dockGap: 14
        readonly property int dockPadding: 14
        readonly property int dockCellCount: dockApps.length + 2   // pin + apps + drawer
        readonly property real dockW: dockCellCount * dockIconSize + (dockCellCount - 1) * dockGap + 2 * dockPadding
        readonly property real dockH: dockIconSize + 2 * dockPadding
        readonly property real dockX: (mockW - dockW) / 2
        readonly property real dockY: mockH - dockH - 14
        readonly property real dockCenterY: dockY + dockH / 2

        // The pin button occupies cell 0; dockApps[i] sits in cell i+1.
        function dockIconCenterX(appIdx) {
            const cellIdx = appIdx + 1
            return dockX + dockPadding + cellIdx * (dockIconSize + dockGap) + dockIconSize / 2
        }

        // Gaussian magnify, mirroring DockApps.qml#scaleForX. Numbers
        // dialled down slightly because the mockup runs at a smaller
        // scale than the real dock.
        readonly property real maxScale: 2.0
        readonly property real sigma: 50

        function scaleForIdx(appIdx) {
            if (!dockHovered || previewVisible || menuVisible) return 1.0
            const iconCenterX = dockIconCenterX(appIdx)
            const dist = iconCenterX - cursorX
            return 1.0 + (maxScale - 1.0) * Math.exp(-(dist * dist) / (2 * sigma * sigma))
        }

        // Demo: hover settles on Spotify (dock idx 1), preview opens,
        // click slides to ws 3 (where Spotify lives, alone).
        readonly property int demoAppIdx: 1
        readonly property int demoTargetWs: 2

        // Phase 2 menu geometry — same as Card4ContextMenu
        readonly property int menuW: 268
        readonly property int menuH: 282
        readonly property int menuX:
            Math.max(20, Math.min(mockW - menuW - 20, dockIconCenterX(rightClickIdx) - menuW / 2))
        readonly property int menuY: dockY - menuH - 14

        // Same Dwindle-ish tile templates as card 2.
        function tileLayout(count) {
            switch (count) {
            case 0: return []
            case 1: return [{x:0,    y:0,   w:1,    h:1   }]
            case 2: return [{x:0,    y:0,   w:0.5,  h:1   },
                            {x:0.5,  y:0,   w:0.5,  h:1   }]
            case 3: return [{x:0,    y:0,   w:0.55, h:1   },
                            {x:0.55, y:0,   w:0.45, h:0.5 },
                            {x:0.55, y:0.5, w:0.45, h:0.5 }]
            case 4: return [{x:0,    y:0,   w:0.55, h:1   },
                            {x:0.55, y:0,   w:0.45, h:0.34},
                            {x:0.55, y:0.34,w:0.45, h:0.33},
                            {x:0.55, y:0.67,w:0.45, h:0.33}]
            default: return []
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 28

            // Left: title + body
            ColumnLayout {
                Layout.minimumWidth: 280
                Layout.maximumWidth: 280
                Layout.preferredWidth: 280
                Layout.fillWidth: false
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 12

                Item { Layout.fillHeight: true }

                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 280
                    text: Translation.tr("Click and right-click your dock apps")
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.huge
                        variableAxes: Appearance.font.variableAxes.title
                    }
                    color: Appearance.colors.colOnLayer0
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 280
                    text: Translation.tr("Hover the dock and the icons magnify. Click an open app to peek at its window — click the preview to jump straight to its workspace. Right-click to open a context menu with the app's most useful commands: a new window, control it's audio, move to another workspace, pin or unpin, and close every window at once.")
                    textFormat: Text.RichText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.85
                    wrapMode: Text.WordWrap
                    lineHeight: 1.35
                }

                Item { Layout.fillHeight: true }
            }

            // Right: animated mockup
            Item {
                id: card6MockupHost
                Layout.fillWidth: true
                Layout.fillHeight: true

                Item {
                    id: card6MockupContainer
                    width: card6.mockW
                    height: card6.mockH
                    anchors.centerIn: parent
                    scale: Math.min(
                        1.0,
                        (card6MockupHost.width  - 8) / width,
                        (card6MockupHost.height - 8) / height
                    )

                    Rectangle {
                        id: card6Mockup
                        anchors.fill: parent
                        radius: 14
                        color: "#0e0e12"
                        border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.6)
                        border.width: 1
                        clip: true

                        // ─── Bar at top (same shape as card 2's) ───
                        Rectangle {
                            id: barFrame3
                            x: card6.barX
                            y: card6.barY
                            width: card6.barW
                            height: card6.barH
                            radius: card6.barH / 2
                            color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.45)
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.35)
                            border.width: 1

                            // Active-window text
                            ColumnLayout {
                                id: activeWindowText3
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 10
                                spacing: -3
                                StyledText {
                                    text: "Desktop"
                                    font.pixelSize: 7
                                    color: Appearance.colors.colSubtext
                                    opacity: 0.85
                                }
                                StyledText {
                                    text: "Workspace " + (card6.currentWs + 1)
                                    font.pixelSize: 9
                                    color: Appearance.colors.colOnLayer0
                                }
                            }

                            // Media pill
                            PillBg {
                                id: mediaPill3
                                anchors.left: activeWindowText3.right
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                height: card6.barPillH
                                width: mediaRow3.implicitWidth + 12
                                Row {
                                    id: mediaRow3
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Rectangle {
                                        width: 12; height: 12; radius: 6
                                        color: Appearance.m3colors.m3primary
                                        opacity: 0.9
                                        anchors.verticalCenter: parent.verticalCenter
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "music_note"
                                            iconSize: 9
                                            color: Appearance.m3colors.m3onPrimary
                                        }
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Subnautica 2 LAU…"
                                        font.pixelSize: 8
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                        width: 70
                                    }
                                }
                            }

                            // Centre: workspace pill
                            PillBg {
                                id: workspacePill3
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                height: card6.barPillH
                                width: barWsStrip3.implicitWidth + 10
                                Item {
                                    id: barWsStrip3
                                    anchors.centerIn: parent
                                    implicitWidth: card6.barSlotW * card6.totalWs
                                    implicitHeight: card6.barSlotH

                                    AnimatedTabIndexPair {
                                        id: barIdxPair3
                                        index: card6.currentWs
                                    }

                                    Rectangle {
                                        z: 1
                                        readonly property real lo: Math.min(barIdxPair3.idx1, barIdxPair3.idx2)
                                        readonly property real hi: Math.max(barIdxPair3.idx1, barIdxPair3.idx2)
                                        x: lo * card6.barSlotW + card6.barIndicatorInset
                                        width: (hi - lo) * card6.barSlotW + card6.barSlotW - 2 * card6.barIndicatorInset
                                        height: card6.barSlotH - 2 * card6.barIndicatorInset
                                        y: card6.barIndicatorInset
                                        radius: height / 2
                                        color: Appearance.m3colors.m3primary
                                        opacity: 0.9
                                    }

                                    Row {
                                        z: 2
                                        anchors.fill: parent
                                        Repeater {
                                            model: card6.totalWs
                                            delegate: Item {
                                                required property int index
                                                width: card6.barSlotW
                                                height: card6.barSlotH
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: card6.barSlotR * 2
                                                    height: card6.barSlotR * 2
                                                    radius: width / 2
                                                    color: Appearance.colors.colOnLayer0
                                                    opacity: 0.35
                                                }
                                            }
                                        }
                                    }

                                    IconImage {
                                        z: 3
                                        readonly property string primary: card6.primaryAppFor(card6.currentWs)
                                        visible: primary !== ""
                                        implicitSize: card6.barIconSize
                                        x: card6.currentWs * card6.barSlotW + (card6.barSlotW - implicitSize) / 2
                                        y: (card6.barSlotH - implicitSize) / 2
                                        source: primary !== ""
                                            ? Quickshell.iconPath(primary, "image-missing")
                                            : ""
                                        Behavior on x {
                                            NumberAnimation { duration: 180; easing.type: Easing.OutSine }
                                        }
                                    }
                                }
                            }

                            // Right: sys tray + clock/weather (same
                            // layout as card 2, just smaller numbers)
                            PillBg {
                                id: sysTrayPill3
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 10
                                height: card6.barPillH
                                width: trayRow3.implicitWidth + 12
                                Row {
                                    id: trayRow3
                                    anchors.centerIn: parent
                                    spacing: 6
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "volume_up"; iconSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "wifi"; iconSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "settings"; iconSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }
                            }

                            Row {
                                anchors.right: sysTrayPill3.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 12
                                spacing: 4
                                PillBg {
                                    height: card6.barPillH
                                    width: clockText3.implicitWidth + 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    StyledText {
                                        id: clockText3
                                        anchors.centerIn: parent
                                        text: "12:53"
                                        font.pixelSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }
                                PillBg {
                                    height: card6.barPillH
                                    width: weatherRow3.implicitWidth + 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    Row {
                                        id: weatherRow3
                                        anchors.centerIn: parent
                                        spacing: 2
                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "cloud"
                                            iconSize: 11
                                            color: Appearance.colors.colOnLayer1
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "74°"
                                            font.pixelSize: 9
                                            color: Appearance.colors.colOnLayer1
                                        }
                                    }
                                }
                            }
                        }

                        // ─── Tile viewport with sliding pages ───
                        Item {
                            id: tileBackground3
                            x: card6.tileX
                            y: card6.tileY
                            width: card6.tileW
                            height: card6.tileH
                            clip: true

                            Row {
                                id: pageRow3
                                x: -card6.currentWs * card6.tileW
                                Behavior on x {
                                    NumberAnimation { duration: 280; easing.type: Easing.OutQuint }
                                }
                                Repeater {
                                    model: card6.cycleLength
                                    delegate: Item {
                                        id: page3
                                        required property int index
                                        width: card6.tileW
                                        height: card6.tileH

                                        Repeater {
                                            model: card6.workspaceApps[page3.index] || []
                                            delegate: Item {
                                                id: tile3
                                                required property int index
                                                required property string modelData
                                                readonly property bool isSpotify: modelData === "spotify"
                                                readonly property var apps: card6.workspaceApps[page3.index] || []
                                                readonly property var rect: {
                                                    const rects = card6.tileLayout(apps.length)
                                                    return rects[index] || {x:0, y:0, w:0, h:0}
                                                }
                                                x: Math.round(rect.x * card6.tileW) + (rect.x > 0 ? card6.tileGap / 2 : 0)
                                                y: Math.round(rect.y * card6.tileH) + (rect.y > 0 ? card6.tileGap / 2 : 0)
                                                // Tiles at the right/bottom edge stretch to fill the
                                                // remaining viewport so the cumulative rounding error
                                                // doesn't push the last tile past the clip bounds (was
                                                // shaving ~1px off the kitty tile in ws1).
                                                width: (rect.x + rect.w >= 1)
                                                    ? card6.tileW - x
                                                    : Math.round(rect.w * card6.tileW) - (rect.x > 0 ? card6.tileGap / 2 : 0) - card6.tileGap / 2
                                                height: (rect.y + rect.h >= 1)
                                                    ? card6.tileH - y
                                                    : Math.round(rect.h * card6.tileH) - (rect.y > 0 ? card6.tileGap / 2 : 0) - card6.tileGap / 2

                                                // Spotify tile shows the same screenshot
                                                // the preview popup uses, so the
                                                // destination window literally matches
                                                // the preview content. Fades out before
                                                // phase 2 (the right-click demo) so the
                                                // workspace reads as empty under the menu.
                                                Item {
                                                    visible: tile3.isSpotify && opacity > 0.01
                                                    anchors.fill: parent
                                                    opacity: card6.spotifyFaded ? 0 : 1
                                                    Behavior on opacity {
                                                        NumberAnimation { duration: 360; easing.type: Easing.OutCubic }
                                                    }
                                                    Image {
                                                        anchors.fill: parent
                                                        source: card6.imageDir + "/spotify.png"
                                                        fillMode: Image.PreserveAspectFit
                                                        smooth: true
                                                        asynchronous: true
                                                        layer.enabled: true
                                                        layer.effect: OpacityMask {
                                                            maskSource: Rectangle {
                                                                width: tile3.width
                                                                height: tile3.height
                                                                radius: 8
                                                            }
                                                        }
                                                    }
                                                }

                                                // Generic tile (every other app):
                                                // small title bar + centred icon.
                                                Rectangle {
                                                    visible: !tile3.isSpotify
                                                    anchors.fill: parent
                                                    radius: 8
                                                    color: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.18)
                                                    border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.45)
                                                    border.width: 1
                                                    Rectangle {
                                                        width: parent.width
                                                        height: card6.tileBarH
                                                        radius: 4
                                                        color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.5)
                                                        Rectangle {
                                                            x: 4
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: 24; height: 3; radius: 1.5
                                                            color: Appearance.colors.colOnLayer0
                                                            opacity: 0.35
                                                        }
                                                    }
                                                    IconImage {
                                                        anchors.centerIn: parent
                                                        anchors.verticalCenterOffset: card6.tileBarH / 2
                                                        implicitSize: Math.min(32, Math.min(tile3.width, tile3.height) - 16)
                                                        source: Quickshell.iconPath(tile3.modelData, "image-missing")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ─── Dock (80% bigger than card 1's) ───
                        Rectangle {
                            id: dockStrip3
                            x: card6.dockX
                            y: card6.dockY
                            width: card6.dockW
                            height: card6.dockH
                            radius: Appearance.rounding.large
                            // Solid black so the tiles extending behind the
                            // dock don't show through (tileH now reaches
                            // past the dock's y-range).
                            color: "#000000"
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.5)
                            border.width: 1
                            z: 2

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: card6.dockPadding
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: card6.dockGap

                                // Pin button
                                Item {
                                    width: card6.dockIconSize
                                    height: card6.dockIconSize
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "push_pin"
                                        iconSize: card6.dockIconSize - 6
                                        color: Appearance.colors.colOnLayer0
                                        opacity: 0.85
                                    }
                                }

                                // Pinned app icons — each magnifies
                                // based on Gaussian distance from
                                // cursor, exactly like the real dock.
                                Repeater {
                                    model: card6.dockApps
                                    delegate: Item {
                                        id: dockSlot
                                        required property int index
                                        required property string modelData
                                        width: card6.dockIconSize
                                        height: card6.dockIconSize
                                        IconImage {
                                            anchors.centerIn: parent
                                            implicitSize: card6.dockIconSize
                                            source: Quickshell.iconPath(dockSlot.modelData, "image-missing")
                                            scale: card6.scaleForIdx(dockSlot.index)
                                            transformOrigin: Item.Bottom
                                            Behavior on scale {
                                                NumberAnimation { duration: 60; easing.type: Easing.OutCubic }
                                            }
                                        }
                                        // Open-window indicator below
                                        // each icon — small bar that
                                        // shows when the workspace
                                        // demo includes this app.
                                        Rectangle {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: -6
                                            width: 10
                                            height: 2
                                            radius: 1
                                            color: Appearance.colors.colOnLayer0
                                            opacity: 0.55
                                            visible: dockSlot.modelData !== ""
                                        }
                                    }
                                }

                                // App-drawer toggle on the far right
                                // (matches the dock in card 1).
                                Item {
                                    width: card6.dockIconSize
                                    height: card6.dockIconSize
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "apps"
                                        iconSize: card6.dockIconSize - 6
                                        color: Appearance.colors.colOnLayer0
                                        opacity: 0.85
                                    }
                                }
                            }
                        }

                        // ─── Preview popup ───
                        // Matches the real DockApps.qml preview: a dark
                        // m3surfaceContainer rectangle with the window
                        // title at the top-left and the screenshot
                        // thumbnail beneath, rounded to elementMoveFast
                        // norm radii. Same Spotify image the destination
                        // tile on ws 3 renders.
                        Rectangle {
                            id: previewPopup
                            readonly property int popupW: 220
                            readonly property int popupH: 142
                            x: card6.dockIconCenterX(card6.demoAppIdx) - popupW / 2
                            y: card6.dockY - popupH - 14
                            width: popupW
                            height: popupH
                            color: Appearance.m3colors.m3surfaceContainer
                            radius: 12
                            clip: true
                            opacity: card6.previewVisible ? 1 : 0
                            visible: opacity > 0
                            z: 4
                            Behavior on opacity {
                                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 5
                                spacing: 3

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 4
                                    Layout.rightMargin: 4
                                    text: "Spotify"
                                    font.pixelSize: 10
                                    color: Appearance.m3colors.m3onSurface
                                    elide: Text.ElideRight
                                }

                                Item {
                                    id: thumbContainer
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    Image {
                                        anchors.fill: parent
                                        source: card6.imageDir + "/spotify.png"
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        asynchronous: true
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: thumbContainer.width
                                                height: thumbContainer.height
                                                radius: 6
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ─── Context menu popup (phase 2) ───
                        // Mirrors DockContextMenu.qml: m3surfaceContainer
                        // background, soft rounding, no border, items
                        // stacked with thin separators. Position pinned
                        // above the right-clicked Chrome icon.
                        Rectangle {
                            id: contextMenu3
                            x: card6.menuX
                            y: card6.menuY
                            width: card6.menuW
                            height: menuColumn3.implicitHeight + 12
                            radius: 12
                            color: Appearance.m3colors.m3surfaceContainer
                            opacity: card6.menuVisible ? 1 : 0
                            visible: opacity > 0
                            scale: card6.menuVisible ? 1.0 : 0.94
                            transformOrigin: Item.Bottom
                            z: 7
                            Behavior on opacity {
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }
                            Behavior on scale {
                                NumberAnimation { duration: 240; easing.type: Easing.OutBack }
                            }

                            ColumnLayout {
                                id: menuColumn3
                                anchors {
                                    fill: parent
                                    margins: 6
                                }
                                spacing: 0

                                // 1. New Window
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 26
                                    StyledText {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 14
                                        text: "New Window"
                                        font.pixelSize: 11
                                        color: Appearance.m3colors.m3onSurface
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 7
                                    Rectangle {
                                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
                                        implicitHeight: 1
                                        color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
                                    }
                                }

                                // 2. Open new instance
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 26
                                    spacing: 8
                                    MaterialSymbol {
                                        Layout.leftMargin: 10
                                        text: "open_in_new"
                                        iconSize: 13
                                        color: Appearance.m3colors.m3onSurface
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.rightMargin: 14
                                        text: "Open new instance"
                                        font.pixelSize: 11
                                        color: Appearance.m3colors.m3onSurface
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 7
                                    Rectangle {
                                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
                                        implicitHeight: 1
                                        color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
                                    }
                                }

                                // 3. Volume row 1: Hulu, 91%
                                Item {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 10
                                    Layout.rightMargin: 10
                                    Layout.topMargin: 3
                                    implicitHeight: 36
                                    StyledText {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.leftMargin: 2
                                        text: "Hulu | Watch"
                                        font.pixelSize: 9
                                        color: Appearance.m3colors.m3onSurface
                                    }
                                    RowLayout {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        spacing: 6
                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: card6.volume1 < 0.5 ? "volume_down" : "volume_up"
                                            iconSize: 13
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            implicitHeight: 5
                                            radius: 2.5
                                            color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                width: parent.width * card6.volume1
                                                radius: 2.5
                                                color: Appearance.m3colors.m3primary
                                            }
                                            Rectangle {
                                                x: parent.width * card6.volume1 - width / 2
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 12; height: 12; radius: 6
                                                color: Appearance.m3colors.m3primary
                                            }
                                        }
                                        StyledText {
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.preferredWidth: 26
                                            horizontalAlignment: Text.AlignRight
                                            text: Math.round(card6.volume1 * 100) + "%"
                                            font.pixelSize: 9
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                    }
                                }

                                // 4. Volume row 2: PoE2, 57%
                                Item {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 10
                                    Layout.rightMargin: 10
                                    Layout.topMargin: 3
                                    implicitHeight: 36
                                    StyledText {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.leftMargin: 2
                                        text: "(179) PoE2 Made Me Rethink How I Play Path of Exile ..."
                                        elide: Text.ElideRight
                                        font.pixelSize: 9
                                        color: Appearance.m3colors.m3onSurface
                                    }
                                    RowLayout {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        spacing: 6
                                        MaterialSymbol {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: card6.volume2 < 0.5 ? "volume_down" : "volume_up"
                                            iconSize: 13
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            implicitHeight: 5
                                            radius: 2.5
                                            color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                width: parent.width * card6.volume2
                                                radius: 2.5
                                                color: Appearance.m3colors.m3primary
                                            }
                                            Rectangle {
                                                x: parent.width * card6.volume2 - width / 2
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 12; height: 12; radius: 6
                                                color: Appearance.m3colors.m3primary
                                            }
                                        }
                                        StyledText {
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.preferredWidth: 26
                                            horizontalAlignment: Text.AlignRight
                                            text: Math.round(card6.volume2 * 100) + "%"
                                            font.pixelSize: 9
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 7
                                    Rectangle {
                                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
                                        implicitHeight: 1
                                        color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
                                    }
                                }

                                // 5. Move to workspace + numbered row
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 26
                                    spacing: 8
                                    MaterialSymbol {
                                        Layout.leftMargin: 10
                                        text: "logout"
                                        iconSize: 13
                                        color: Appearance.m3colors.m3outline
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.rightMargin: 14
                                        text: "Move to workspace"
                                        font.pixelSize: 11
                                        color: Appearance.m3colors.m3outline
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 10
                                    Layout.rightMargin: 10
                                    Layout.bottomMargin: 2
                                    spacing: 0
                                    Repeater {
                                        model: 10
                                        delegate: Item {
                                            required property int index
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 22
                                            StyledText {
                                                anchors.centerIn: parent
                                                text: String(parent.index + 1)
                                                font.pixelSize: 10
                                                color: Appearance.m3colors.m3onSurface
                                            }
                                        }
                                    }
                                }

                                // 6. Pin to dock
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 26
                                    spacing: 8
                                    MaterialSymbol {
                                        Layout.leftMargin: 10
                                        text: "push_pin"
                                        iconSize: 13
                                        color: Appearance.m3colors.m3onSurface
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.rightMargin: 14
                                        text: "Pin to dock"
                                        font.pixelSize: 11
                                        color: Appearance.m3colors.m3onSurface
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 7
                                    Rectangle {
                                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10; rightMargin: 10 }
                                        implicitHeight: 1
                                        color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
                                    }
                                }

                                // 7. Close all windows
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 26
                                    spacing: 8
                                    MaterialSymbol {
                                        Layout.leftMargin: 10
                                        text: "close"
                                        iconSize: 13
                                        color: Appearance.m3colors.m3onSurface
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.rightMargin: 14
                                        text: "Close all windows"
                                        font.pixelSize: 11
                                        color: Appearance.m3colors.m3onSurface
                                    }
                                }
                            }
                        }

                        // ─── Cursor cue ───
                        MaterialSymbol {
                            id: cursor3
                            z: 8
                            text: "arrow_selector_tool"
                            iconSize: 20
                            color: Appearance.colors.colOnLayer0
                            x: card6.cursorX - 4
                            y: card6.cursorY - 4
                            scale: card6.cursorPulse
                            transformOrigin: Item.TopLeft
                            Behavior on scale {
                                NumberAnimation { duration: 120; easing.type: Easing.OutBack }
                            }
                        }
                    }
                }
            }
        }

        // ── Animation timeline ──
        // Two phases per loop:
        //   1. Hover dock → click Spotify → preview pops up → click
        //      preview → workspace slides to ws 3 with full Spotify.
        //   2. Spotify fades, cursor drops down to Chrome → right-click
        //      → context menu opens with its full row of options.
        SequentialAnimation {
            id: demoCycle3
            running: card6.visible
            loops: Animation.Infinite

            // Reset
            ScriptAction {
                script: {
                    card6.cursorX = card6.mockW + 60
                    card6.cursorY = card6.dockCenterY
                    card6.dockHovered = false
                    card6.previewVisible = false
                    card6.spotifyFaded = false
                    card6.menuVisible = false
                    card6.cursorPulse = 1.0
                    card6.currentWs = 0
                }
            }
            PauseAnimation { duration: 700 }

            // ── Phase 1: click-preview → jump-to-workspace ──

            // Cursor swoops in toward the right edge of the dock
            ParallelAnimation {
                NumberAnimation { target: card6; property: "cursorX"; to: card6.dockX + card6.dockW - card6.dockPadding; duration: 500; easing.type: Easing.OutCubic }
                NumberAnimation { target: card6; property: "cursorY"; to: card6.dockCenterY; duration: 500; easing.type: Easing.OutCubic }
                ScriptAction { script: card6.dockHovered = true }
            }
            PauseAnimation { duration: 220 }

            // Sweep across the dock — Gaussian falloff bumps each icon
            NumberAnimation {
                target: card6; property: "cursorX"
                to: card6.dockIconCenterX(card6.demoAppIdx)
                duration: 1300
                easing.type: Easing.InOutQuad
            }
            PauseAnimation { duration: 320 }

            // Click → preview opens
            ScriptAction { script: card6.previewVisible = true }
            PauseAnimation { duration: 900 }

            // Cursor moves into the preview's centre
            ParallelAnimation {
                NumberAnimation { target: card6; property: "cursorX"; to: card6.dockIconCenterX(card6.demoAppIdx); duration: 380; easing.type: Easing.InOutQuad }
                NumberAnimation { target: card6; property: "cursorY"; to: card6.dockY - 75; duration: 380; easing.type: Easing.InOutQuad }
            }
            PauseAnimation { duration: 320 }

            // Click preview → workspace slides + preview fades.
            // dockHovered turns off here so the magnify falloff stops
            // re-bumping icons as the cursor descends in phase 2.
            ParallelAnimation {
                ScriptAction { script: card6.currentWs = card6.demoTargetWs }
                ScriptAction { script: card6.previewVisible = false }
                ScriptAction { script: card6.dockHovered = false }
            }
            PauseAnimation { duration: 2500 }

            // ── Phase 2: right-click chrome → context menu ──

            // Spotify window fades out so the workspace reads empty
            // under the menu. Fade takes ~0.36s; the rest of the hold
            // (≈1.1s) lets the empty workspace land before phase 2.
            ScriptAction { script: card6.spotifyFaded = true }
            PauseAnimation { duration: 1500 }

            // Cursor moves down to Chrome (dock idx 0)
            ParallelAnimation {
                NumberAnimation { target: card6; property: "cursorX"; to: card6.dockIconCenterX(card6.rightClickIdx); duration: 800; easing.type: Easing.InOutQuad }
                NumberAnimation { target: card6; property: "cursorY"; to: card6.dockCenterY; duration: 800; easing.type: Easing.InOutQuad }
            }
            PauseAnimation { duration: 280 }

            // Right-click → quick cursor pulse, menu opens
            ScriptAction { script: card6.cursorPulse = 0.78 }
            PauseAnimation { duration: 110 }
            ParallelAnimation {
                ScriptAction { script: card6.cursorPulse = 1.0 }
                ScriptAction { script: card6.menuVisible = true }
            }
            // Hold the menu open so the user can read every row
            PauseAnimation { duration: 4500 }

            // Close menu, cursor parks off-screen right for the loop
            ScriptAction { script: card6.menuVisible = false }
            PauseAnimation { duration: 280 }
            NumberAnimation { target: card6; property: "cursorX"; to: card6.mockW + 60; duration: 500; easing.type: Easing.InCubic }
            ScriptAction { script: card6.dockHovered = false }
            PauseAnimation { duration: 600 }
        }
    }


    // ── Card 4: Move open windows between workspaces ─────────────────────
    // Same scaffold as card 1 (bar, overview widget, drawer, dock) but
    // the demo starts with two windows already open on workspace 1 and
    // the cursor grabs the right one out of ws 1 and drops it on ws 2.
    component Card4MoveBetweenWorkspaces : Item {
        id: card4

        // Phase 1 state — moving telegram from ws 1 to ws 2
        property bool appPickedUp: false
        property bool appDropped: false
        property real cursorX: 0
        property real cursorY: 0
        property real dragX: 0
        property real dragY: 0
        property bool ws2Hovered: false

        // Phase 2 state — dragging chrome from the drawer onto ws 3
        property bool chromePickedUp: false
        property bool chromeDropped: false
        property real chromeDragX: 0
        property real chromeDragY: 0
        property bool ws3Hovered: false

        // ── Mockup geometry (identical to card 1) ──
        readonly property int mockW: 600
        readonly property int mockH: 380
        readonly property int barH: 22

        readonly property int wsTileW: 100
        readonly property int wsTileH: 60
        readonly property int wsGap: 8
        readonly property int wsCols: 5
        readonly property int wsRows: 2
        readonly property int wsPadding: 12
        readonly property int wsContainerW: wsCols * wsTileW + (wsCols - 1) * wsGap + 2 * wsPadding
        readonly property int wsContainerH: wsRows * wsTileH + (wsRows - 1) * wsGap + 2 * wsPadding
        readonly property int wsContainerX: (mockW - wsContainerW) / 2
        readonly property int wsContainerY: barH + 14
        readonly property int wsAreaX: wsContainerX + wsPadding
        readonly property int wsAreaY: wsContainerY + wsPadding

        // Drawer (visible but no drag-from-drawer happens here)
        readonly property var drawerApps: [
            "firefox", "google-chrome", "visual-studio-code", "spotify", "telegram",
            "vlc", "gimp", "blender", "krita", "obs",
            "thunderbird", "libreoffice-startcenter", "audacity", "godot",
            "inkscape", "chromium", "brave-browser", "slack", "signal-desktop",
            "element-desktop", "zoom", "kdenlive", "transmission", "qbittorrent",
            "steam", "lutris", "heroic", "mpv",
            "handbrake", "openshot", "scribus", "ksnip", "virt-manager",
            "postman", "dbeaver", "joplin"
        ]
        readonly property int drawerCols: 14
        readonly property int drawerRows: 3
        readonly property int drawerIconSize: 16
        readonly property int drawerGap: 8
        readonly property int drawerPadding: 10

        readonly property var dockApps: [
            "keepassxc", "evince", "kitty", "anki", "joplin"
        ]
        readonly property int dockIconSize: 16
        readonly property int dockGap: 8
        readonly property int dockPadding: 8
        readonly property int dockBottomMargin: 10
        readonly property int dockCellCount: dockApps.length + 2
        readonly property real dockW: dockCellCount * dockIconSize + (dockCellCount - 1) * dockGap + 2 * dockPadding
        readonly property real dockH: dockIconSize + 2 * dockPadding
        readonly property real dockLeftX:    (mockW - dockW) / 2
        readonly property real dockRightX:   dockLeftX + dockW
        readonly property real dockCenterY:  mockH - dockBottomMargin - dockH / 2
        readonly property real dockDrawerBtnRightX: dockRightX - dockPadding
        readonly property real cursorParkX: dockDrawerBtnRightX + 4
        readonly property real cursorParkY: dockCenterY
        readonly property int drawerInnerW: drawerCols * drawerIconSize + (drawerCols - 1) * drawerGap
        readonly property int drawerInnerH: drawerRows * drawerIconSize + (drawerRows - 1) * drawerGap
        readonly property int drawerW: drawerInnerW + 2 * drawerPadding
        readonly property int drawerH: drawerInnerH + 2 * drawerPadding
        readonly property int drawerX: (mockW - drawerW) / 2
        readonly property int drawerY: wsContainerY + wsContainerH + 16

        // Two demo apps already open on ws 1.
        //   appA stays on ws 1 — kept on the left half all the way through.
        //   appB is the one the cursor grabs and drops on ws 2.
        readonly property string appA: "spotify"
        readonly property string appB: "telegram"
        // Phase 2: app pulled fresh from the drawer onto ws 3.
        readonly property string chromeApp: "google-chrome"
        readonly property int chromeAppIdx: 1  // index of google-chrome in drawerApps
        readonly property color demoWindowColor: "#FFFFFF"
        readonly property color demoWindowBarColor: "#E8EAED"

        function wsCenter(idx) {
            const col = idx % wsCols
            const row = Math.floor(idx / wsCols)
            return Qt.point(
                wsAreaX + col * (wsTileW + wsGap) + wsTileW / 2,
                wsAreaY + row * (wsTileH + wsGap) + wsTileH / 2
            )
        }
        readonly property point ws1Center: wsCenter(0)
        readonly property point ws2Center: wsCenter(1)
        readonly property point ws3Center: wsCenter(2)
        // Pickup point — middle of ws 1's right half, where appB sits.
        readonly property real demoAppX: ws1Center.x + wsTileW / 4
        readonly property real demoAppY: ws1Center.y

        // Chrome's centre point inside the drawer, used as the
        // phase-2 cursor target / pickup origin.
        function chromeInDrawerX() {
            const col = chromeAppIdx % drawerCols
            return drawerX + drawerPadding + col * (drawerIconSize + drawerGap) + drawerIconSize / 2
        }
        function chromeInDrawerY() {
            const row = Math.floor(chromeAppIdx / drawerCols)
            return drawerY + drawerPadding + row * (drawerIconSize + drawerGap) + drawerIconSize / 2
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 28

            // Left: title + body
            ColumnLayout {
                Layout.minimumWidth: 280
                Layout.maximumWidth: 280
                Layout.preferredWidth: 280
                Layout.fillWidth: false
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 12

                Item { Layout.fillHeight: true }

                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 280
                    text: Translation.tr("Drag apps to any workspace")
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.huge
                        variableAxes: Appearance.font.variableAxes.title
                    }
                    color: Appearance.colors.colOnLayer0
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 280
                    text: Translation.tr("Open Overview with <b>Super <font face='JetBrains Mono NF'>(󰖳)</font></b>, then drag — move an already-open window from one workspace tile to another, or grab a fresh app from the drawer and drop it on any workspace. Either way, the app lands right where you want it.")
                    textFormat: Text.RichText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.85
                    wrapMode: Text.WordWrap
                    lineHeight: 1.35
                }

                Item { Layout.fillHeight: true }
            }

            // Right: animated mockup
            Item {
                id: mockupHost7
                Layout.fillWidth: true
                Layout.fillHeight: true

                Item {
                    id: mockupContainer7
                    width: card4.mockW
                    height: card4.mockH
                    anchors.centerIn: parent
                    scale: Math.min(
                        1.0,
                        (mockupHost7.width  - 8) / width,
                        (mockupHost7.height - 8) / height
                    )

                    Rectangle {
                        id: mockup7
                        anchors.fill: parent
                        radius: 14
                        color: "#0e0e12"
                        border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.6)
                        border.width: 1
                        clip: true

                        // Top bar
                        Rectangle {
                            x: 10; y: 8
                            width: parent.width - 20
                            height: card4.barH - 6
                            radius: (height) / 2
                            color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.35)
                        }

                        // Overview widget container
                        Rectangle {
                            x: card4.wsContainerX
                            y: card4.wsContainerY
                            width: card4.wsContainerW
                            height: card4.wsContainerH
                            radius: 12
                            color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.22)
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.55)
                            border.width: 1
                        }

                        // Workspace tiles
                        Repeater {
                            model: card4.wsCols * card4.wsRows
                            delegate: Rectangle {
                                required property int index
                                readonly property int col: index % card4.wsCols
                                readonly property int row: Math.floor(index / card4.wsCols)
                                readonly property bool isActive: index === 0
                                readonly property bool isSource: index === 0   // ws 1 holds the two apps
                                readonly property bool isTarget: index === 1   // ws 2 receives appB
                                readonly property bool isChromeTarget: index === 2 // ws 3 receives chrome
                                x: card4.wsAreaX + col * (card4.wsTileW + card4.wsGap)
                                y: card4.wsAreaY + row * (card4.wsTileH + card4.wsGap)
                                width: card4.wsTileW
                                height: card4.wsTileH
                                radius: 8
                                color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.14)
                                border.width: isActive ? 2 : 1
                                border.color: isActive
                                    ? Appearance.colors.colOnLayer0
                                    : ((isTarget && card4.ws2Hovered) || (isChromeTarget && card4.ws3Hovered)
                                        ? Appearance.m3colors.m3primary
                                        : ColorUtils.transparentize(Appearance.colors.colOutline, 0.45))
                                Behavior on border.color { ColorAnimation { duration: 180 } }

                                // Workspace number watermark — hidden on
                                // ws 1 (already has apps) and on any
                                // workspace once its window lands.
                                StyledText {
                                    anchors.centerIn: parent
                                    text: (index + 1).toString()
                                    font.pixelSize: 22
                                    font.family: Appearance.font.family.title
                                    color: Appearance.colors.colOnLayer0
                                    opacity: (parent.isSource
                                              || (parent.isTarget && card4.appDropped)
                                              || (parent.isChromeTarget && card4.chromeDropped)) ? 0 : 0.35
                                    Behavior on opacity { NumberAnimation { duration: 220 } }
                                }

                                // ── WS 1 contents — two half-tile windows ──
                                // App A on the left. Spans half the tile
                                // initially; once appB has been dropped on
                                // ws 2, A expands to fill the whole tile,
                                // matching how a Dwindle layout reflows
                                // when its sibling window leaves.
                                Rectangle {
                                    visible: parent.isSource
                                    x: 3
                                    y: 3
                                    width: card4.appDropped ? parent.width - 6 : parent.width / 2 - 4
                                    height: parent.height - 6
                                    radius: 4
                                    color: card4.demoWindowColor
                                    Behavior on width {
                                        NumberAnimation { duration: 320; easing.type: Easing.InOutQuad }
                                    }

                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: parent.height * 0.28
                                        color: card4.demoWindowBarColor
                                        topLeftRadius: 4
                                        topRightRadius: 4
                                        bottomLeftRadius: 0
                                        bottomRightRadius: 0
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.leftMargin: 4
                                            anchors.topMargin: 2
                                            width: 12
                                            height: parent.height - 3
                                            radius: 2
                                            color: card4.demoWindowColor
                                        }
                                    }

                                    IconImage {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.verticalCenterOffset: 3
                                        source: Quickshell.iconPath(card4.appA, "image-missing")
                                        implicitSize: 18
                                    }
                                }

                                // App B on the right — dims when the
                                // cursor lifts it, disappears entirely
                                // once the drop completes.
                                Rectangle {
                                    visible: parent.isSource
                                    x: parent.width / 2 + 1
                                    y: 3
                                    width: parent.width / 2 - 4
                                    height: parent.height - 6
                                    radius: 4
                                    color: card4.demoWindowColor
                                    opacity: card4.appDropped
                                        ? 0
                                        : (card4.appPickedUp ? 0.2 : 1)
                                    Behavior on opacity {
                                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                                    }

                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: parent.height * 0.28
                                        color: card4.demoWindowBarColor
                                        topLeftRadius: 4
                                        topRightRadius: 4
                                        bottomLeftRadius: 0
                                        bottomRightRadius: 0
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.leftMargin: 4
                                            anchors.topMargin: 2
                                            width: 12
                                            height: parent.height - 3
                                            radius: 2
                                            color: card4.demoWindowColor
                                        }
                                    }

                                    IconImage {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.verticalCenterOffset: 3
                                        source: Quickshell.iconPath(card4.appB, "image-missing")
                                        implicitSize: 18
                                    }
                                }

                                // ── WS 2 destination — appB appears
                                // here once the drop completes, full
                                // tile, scaling in like card 1's drop.
                                Rectangle {
                                    visible: parent.isTarget
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    radius: 5
                                    color: card4.demoWindowColor
                                    transformOrigin: Item.Center
                                    opacity: (parent.isTarget && card4.appDropped) ? 1.0 : 0.0
                                    scale:   (parent.isTarget && card4.appDropped) ? 1.0 : 0.55
                                    Behavior on opacity { NumberAnimation { duration: 230 } }
                                    Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: parent.height * 0.28
                                        color: card4.demoWindowBarColor
                                        topLeftRadius: 5
                                        topRightRadius: 5
                                        bottomLeftRadius: 0
                                        bottomRightRadius: 0
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.leftMargin: 6
                                            anchors.topMargin: 3
                                            width: 18
                                            height: parent.height - 4
                                            radius: 3
                                            color: card4.demoWindowColor
                                        }
                                    }

                                    IconImage {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.verticalCenterOffset: 5
                                        source: Quickshell.iconPath(card4.appB, "image-missing")
                                        implicitSize: 24
                                    }
                                }

                                // ── WS 3 destination — chrome window
                                // appears here after the drawer-drag drop.
                                Rectangle {
                                    visible: parent.isChromeTarget
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    radius: 5
                                    color: card4.demoWindowColor
                                    transformOrigin: Item.Center
                                    opacity: (parent.isChromeTarget && card4.chromeDropped) ? 1.0 : 0.0
                                    scale:   (parent.isChromeTarget && card4.chromeDropped) ? 1.0 : 0.55
                                    Behavior on opacity { NumberAnimation { duration: 230 } }
                                    Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: parent.height * 0.28
                                        color: card4.demoWindowBarColor
                                        topLeftRadius: 5
                                        topRightRadius: 5
                                        bottomLeftRadius: 0
                                        bottomRightRadius: 0
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.leftMargin: 6
                                            anchors.topMargin: 3
                                            width: 18
                                            height: parent.height - 4
                                            radius: 3
                                            color: card4.demoWindowColor
                                        }
                                    }

                                    IconImage {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.verticalCenterOffset: 5
                                        source: Quickshell.iconPath(card4.chromeApp, "image-missing")
                                        implicitSize: 24
                                    }
                                }
                            }
                        }

                        // Application drawer container (visual context)
                        Rectangle {
                            x: card4.drawerX
                            y: card4.drawerY
                            width: card4.drawerW
                            height: card4.drawerH
                            radius: 12
                            color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.28)
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.55)
                            border.width: 1
                        }

                        Repeater {
                            model: card4.drawerApps
                            delegate: IconImage {
                                required property int index
                                required property string modelData
                                function colOf(i) { return i % card4.drawerCols }
                                function rowOf(i) { return Math.floor(i / card4.drawerCols) }
                                x: card4.drawerX + card4.drawerPadding + colOf(index) * (card4.drawerIconSize + card4.drawerGap)
                                y: card4.drawerY + card4.drawerPadding + rowOf(index) * (card4.drawerIconSize + card4.drawerGap)
                                implicitSize: card4.drawerIconSize
                                source: Quickshell.iconPath(modelData, "image-missing")
                                opacity: (modelData === card4.chromeApp && card4.chromePickedUp) ? 0.15 : 1
                                Behavior on opacity { NumberAnimation { duration: 180 } }
                            }
                        }

                        // Dock
                        Rectangle {
                            id: dockStrip7
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: card4.dockBottomMargin
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: card4.dockW
                            height: card4.dockH
                            radius: Math.round(card4.dockH * Appearance.rounding.large / 70)
                            color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.55)
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.55)
                            border.width: 1

                            Row {
                                anchors.centerIn: parent
                                spacing: card4.dockGap

                                Item {
                                    width: card4.dockIconSize
                                    height: card4.dockIconSize
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "push_pin"
                                        iconSize: card4.dockIconSize
                                        color: Appearance.colors.colOnLayer0
                                        opacity: 0.85
                                    }
                                }
                                Repeater {
                                    model: card4.dockApps
                                    delegate: IconImage {
                                        required property string modelData
                                        implicitSize: card4.dockIconSize
                                        source: Quickshell.iconPath(modelData, "image-missing")
                                    }
                                }
                                Item {
                                    width: card4.dockIconSize
                                    height: card4.dockIconSize
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "apps"
                                        iconSize: card4.dockIconSize
                                        color: Appearance.colors.colOnLayer0
                                        opacity: 0.85
                                    }
                                }
                            }
                        }

                        // Drag ghost — appB while in flight
                        IconImage {
                            id: dragGhost7
                            visible: card4.appPickedUp
                            source: Quickshell.iconPath(card4.appB, "image-missing")
                            implicitSize: card4.drawerIconSize + 6
                            x: card4.dragX - implicitSize / 2
                            y: card4.dragY - implicitSize / 2
                            scale: card4.appPickedUp ? 1.08 : 1.0
                            opacity: 0.95
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                        }

                        // Drag ghost — chrome while in flight (phase 2)
                        IconImage {
                            id: chromeDragGhost7
                            visible: card4.chromePickedUp
                            source: Quickshell.iconPath(card4.chromeApp, "image-missing")
                            implicitSize: card4.drawerIconSize + 6
                            x: card4.chromeDragX - implicitSize / 2
                            y: card4.chromeDragY - implicitSize / 2
                            scale: card4.chromePickedUp ? 1.08 : 1.0
                            opacity: 0.95
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                        }

                        // Cursor cue
                        MaterialSymbol {
                            id: cursor7
                            text: "arrow_selector_tool"
                            iconSize: 22
                            color: Appearance.colors.colOnLayer0
                            x: card4.cursorX - 4
                            y: card4.cursorY - 4
                        }
                    }
                }
            }
        }

        // ── Animation timeline ──
        // Two phases per loop:
        //   1. Cursor moves appB (telegram) from ws 1's right half to ws 2.
        //   2. Cursor drops down to the drawer, grabs chrome, drags it
        //      up to ws 3.
        // ws 1 keeps appA after phase 1; ws 2 ends with appB; ws 3 ends
        // with chrome.
        SequentialAnimation {
            id: demoCycle7
            running: card4.visible
            loops: Animation.Infinite

            ScriptAction {
                script: {
                    card4.appPickedUp = false
                    card4.appDropped = false
                    card4.ws2Hovered = false
                    card4.chromePickedUp = false
                    card4.chromeDropped = false
                    card4.ws3Hovered = false
                    card4.cursorX = card4.cursorParkX
                    card4.cursorY = card4.cursorParkY
                    card4.dragX = card4.demoAppX
                    card4.dragY = card4.demoAppY
                    card4.chromeDragX = card4.chromeInDrawerX()
                    card4.chromeDragY = card4.chromeInDrawerY()
                }
            }
            PauseAnimation { duration: 700 }

            // ── Phase 1: move appB from ws 1 → ws 2 ──

            // Cursor approaches appB inside ws 1
            ParallelAnimation {
                NumberAnimation { target: card4; property: "cursorX"; to: card4.demoAppX; duration: 700; easing.type: Easing.OutCubic }
                NumberAnimation { target: card4; property: "cursorY"; to: card4.demoAppY; duration: 700; easing.type: Easing.OutCubic }
            }
            PauseAnimation { duration: 240 }

            // Pick up — ghost spawns at appB's position
            ScriptAction {
                script: {
                    card4.dragX = card4.demoAppX
                    card4.dragY = card4.demoAppY
                    card4.appPickedUp = true
                }
            }
            PauseAnimation { duration: 180 }

            // Drag right to ws 2 (cursor + ghost together)
            ParallelAnimation {
                NumberAnimation { target: card4; property: "cursorX"; to: card4.ws2Center.x; duration: 850; easing.type: Easing.InOutQuad }
                NumberAnimation { target: card4; property: "cursorY"; to: card4.ws2Center.y; duration: 850; easing.type: Easing.InOutQuad }
                NumberAnimation { target: card4; property: "dragX";   to: card4.ws2Center.x; duration: 850; easing.type: Easing.InOutQuad }
                NumberAnimation { target: card4; property: "dragY";   to: card4.ws2Center.y; duration: 850; easing.type: Easing.InOutQuad }
                // Light up ws 2 halfway through the drag
                SequentialAnimation {
                    PauseAnimation { duration: 420 }
                    ScriptAction { script: card4.ws2Hovered = true }
                }
            }
            PauseAnimation { duration: 320 }

            // Drop — ghost disappears, appB lands on ws 2, appB tile
            // on ws 1 fades out.
            ScriptAction {
                script: {
                    card4.appPickedUp = false
                    card4.appDropped = true
                }
            }
            PauseAnimation { duration: 1500 }

            // Fade the ws-2 hover highlight before phase 2
            ScriptAction { script: card4.ws2Hovered = false }
            PauseAnimation { duration: 400 }

            // ── Phase 2: drag chrome from drawer → ws 3 ──

            // Cursor descends to chrome in the drawer
            ParallelAnimation {
                NumberAnimation { target: card4; property: "cursorX"; to: card4.chromeInDrawerX(); duration: 800; easing.type: Easing.OutCubic }
                NumberAnimation { target: card4; property: "cursorY"; to: card4.chromeInDrawerY(); duration: 800; easing.type: Easing.OutCubic }
            }
            PauseAnimation { duration: 240 }

            // Pick up chrome
            ScriptAction {
                script: {
                    card4.chromeDragX = card4.chromeInDrawerX()
                    card4.chromeDragY = card4.chromeInDrawerY()
                    card4.chromePickedUp = true
                }
            }
            PauseAnimation { duration: 180 }

            // Drag chrome up to ws 3 (cursor + ghost together)
            ParallelAnimation {
                NumberAnimation { target: card4; property: "cursorX"; to: card4.ws3Center.x; duration: 950; easing.type: Easing.InOutQuad }
                NumberAnimation { target: card4; property: "cursorY"; to: card4.ws3Center.y; duration: 950; easing.type: Easing.InOutQuad }
                NumberAnimation { target: card4; property: "chromeDragX"; to: card4.ws3Center.x; duration: 950; easing.type: Easing.InOutQuad }
                NumberAnimation { target: card4; property: "chromeDragY"; to: card4.ws3Center.y; duration: 950; easing.type: Easing.InOutQuad }
                SequentialAnimation {
                    PauseAnimation { duration: 450 }
                    ScriptAction { script: card4.ws3Hovered = true }
                }
            }
            PauseAnimation { duration: 350 }

            // Drop — chrome lands on ws 3
            ScriptAction {
                script: {
                    card4.chromePickedUp = false
                    card4.chromeDropped = true
                }
            }
            PauseAnimation { duration: 1700 }

            // Fade the ws-3 hover highlight before reset
            ScriptAction { script: card4.ws3Hovered = false }
            PauseAnimation { duration: 400 }
        }
    }

    // ── Card 1: Tour of the bar ──────────────────────────────────────────
    // Mirrors the bar from card 4 (same anchored 3-zone layout, same
    // pills) but the only animation is a chevron pointer that walks
    // section to section while a callout below the bar fades in a name +
    // description for whichever section is "selected".
    component Card1BarTour : Item {
        id: card1

        // Index into sectionNames/Descs/Xs — drives both the pointer's
        // x position and the callout text.
        property int currentSection: 0
        readonly property int totalSections: 8

        readonly property var sectionNames: [
            "Active window",
            "Now playing",
            "Workspaces",
            "Clock",
            "Weather",
            "System tray",
            "Dock",
            "App drawer"
        ]
        readonly property var sectionDescs: [
            "Shows the workspace you're on and the focused window's title.",
            "Whatever's playing right now. Click to open the full media controls.",
            "Every workspace at a glance. The highlight shows where you are; the icon shows the workspace's primary window. Click a dot to switch to it.",
            "Current time. Click to open the calendar and notification feed.",
            "Local weather. Click for the full forecast.",
            "Quick toggles for volume, network, and system settings.",
            "Pinned apps along the bottom edge, available from every workspace. We'll cover pinning shortly.",
            "Opens the launcher — every installed app, one click away."
        ]
        // Centre-x of each pointer target. Bar pills (0–5) tuned by eye
        // against the bar layout. Dock (6) sits at the dock's centre.
        // App drawer (7) lands on the rightmost dock cell.
        readonly property var sectionXs: [60, 150, 300, 440, 485, 545, 300, 360]
        // Per-section pointer y + arrow direction. Bar sections point up
        // from just below the bar; dock sections point down from just
        // above the dock.
        readonly property var sectionYs: [
            barY + barH + 4,        // Active window
            barY + barH + 4,        // Now playing
            barY + barH + 4,        // Workspaces
            barY + barH + 4,        // Clock
            barY + barH + 4,        // Weather
            barY + barH + 4,        // System tray
            mockH - dockBottomMargin - dockH - 4 - 22, // Dock (above dock)
            mockH - dockBottomMargin - dockH - 4 - 22  // App drawer
        ]
        readonly property var sectionPointsDown: [
            false, false, false, false, false, false, true, true
        ]

        // Workspace state for the bar mockup — Chrome on ws 1 so the
        // strip has a recognisable app icon to point at.
        readonly property int currentWs: 0
        readonly property var workspaceApps: [
            ["google-chrome"],
            ["spotify", "telegram"],
            ["org.gnome.Nautilus"],
            ["gimp", "vlc", "blender"],
            ["discord", "obs"],
        ]
        readonly property int totalWs: 10
        function primaryAppFor(ws) {
            const list = workspaceApps[ws] || []
            return list.length > 0 ? list[0] : ""
        }

        // ── Mockup geometry ──
        readonly property int mockW: 600
        readonly property int mockH: 380

        // Bar (identical to card 4's)
        readonly property int barW: 560
        readonly property int barH: 30
        readonly property int barX: (mockW - barW) / 2
        readonly property int barY: 12
        readonly property int barPillH: 22
        readonly property int barSlotW: 16
        readonly property int barSlotH: 16
        readonly property int barSlotR: 2
        readonly property int barIconSize: 10
        readonly property int barIndicatorInset: 1

        // Dock at the bottom — sized like card 4's; joplin is intentionally
        // omitted here so a later card can demo adding it.
        readonly property var dockApps: [
            "keepassxc", "evince", "kitty", "anki"
        ]
        readonly property int dockIconSize: 16
        readonly property int dockGap: 8
        readonly property int dockPadding: 8
        readonly property int dockBottomMargin: 10
        readonly property int dockCellCount: dockApps.length + 2
        readonly property real dockW: dockCellCount * dockIconSize + (dockCellCount - 1) * dockGap + 2 * dockPadding
        readonly property real dockH: dockIconSize + 2 * dockPadding

        // Callout below the pointer
        readonly property int calloutW: 400
        readonly property int calloutH: 130
        readonly property int calloutX: (mockW - calloutW) / 2
        readonly property int calloutY: 120

        RowLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 28

            // Left: title + body
            ColumnLayout {
                Layout.minimumWidth: 280
                Layout.maximumWidth: 280
                Layout.preferredWidth: 280
                Layout.fillWidth: false
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 12

                Item { Layout.fillHeight: true }

                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 280
                    text: Translation.tr("Get to know your bar and dock")
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.huge
                        variableAxes: Appearance.font.variableAxes.title
                    }
                    color: Appearance.colors.colOnLayer0
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 280
                    text: Translation.tr("Two surfaces always within reach. The bar across the top handles status — your active window, media, workspaces, time, weather, and system toggles. The dock at the bottom holds your pinned apps and the app drawer.")
                    textFormat: Text.RichText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.85
                    wrapMode: Text.WordWrap
                    lineHeight: 1.35
                }

                Item { Layout.fillHeight: true }
            }

            // Right: animated mockup
            Item {
                id: mockupHost8
                Layout.fillWidth: true
                Layout.fillHeight: true

                Item {
                    id: mockupContainer8
                    width: card1.mockW
                    height: card1.mockH
                    anchors.centerIn: parent
                    scale: Math.min(
                        1.0,
                        (mockupHost8.width  - 8) / width,
                        (mockupHost8.height - 8) / height
                    )

                    Rectangle {
                        id: mockup8
                        anchors.fill: parent
                        radius: 14
                        color: "#0e0e12"
                        border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.6)
                        border.width: 1
                        clip: true

                        // ─── Bar (clone of card 4's) ───
                        Rectangle {
                            id: barFrame8
                            x: card1.barX
                            y: card1.barY
                            width: card1.barW
                            height: card1.barH
                            radius: card1.barH / 2
                            color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.45)
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.35)
                            border.width: 1
                            z: 2

                            ColumnLayout {
                                id: activeWindowText8
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 10
                                spacing: -3
                                StyledText {
                                    text: "Desktop"
                                    font.pixelSize: 7
                                    color: Appearance.colors.colSubtext
                                    opacity: 0.85
                                }
                                StyledText {
                                    text: "Workspace " + (card1.currentWs + 1)
                                    font.pixelSize: 9
                                    color: Appearance.colors.colOnLayer0
                                }
                            }

                            PillBg {
                                id: mediaPill8
                                anchors.left: activeWindowText8.right
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                height: card1.barPillH
                                width: mediaRow8.implicitWidth + 12
                                Row {
                                    id: mediaRow8
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Rectangle {
                                        width: 12; height: 12; radius: 6
                                        color: Appearance.m3colors.m3primary
                                        opacity: 0.9
                                        anchors.verticalCenter: parent.verticalCenter
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "music_note"
                                            iconSize: 9
                                            color: Appearance.m3colors.m3onPrimary
                                        }
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Subnautica 2 LAU…"
                                        font.pixelSize: 8
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                        width: 70
                                    }
                                }
                            }

                            PillBg {
                                id: workspacePill8
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                height: card1.barPillH
                                width: barWsStrip8.implicitWidth + 10
                                Item {
                                    id: barWsStrip8
                                    anchors.centerIn: parent
                                    implicitWidth: card1.barSlotW * card1.totalWs
                                    implicitHeight: card1.barSlotH

                                    AnimatedTabIndexPair {
                                        id: barIdxPair8
                                        index: card1.currentWs
                                    }

                                    Rectangle {
                                        z: 1
                                        readonly property real lo: Math.min(barIdxPair8.idx1, barIdxPair8.idx2)
                                        readonly property real hi: Math.max(barIdxPair8.idx1, barIdxPair8.idx2)
                                        x: lo * card1.barSlotW + card1.barIndicatorInset
                                        width: (hi - lo) * card1.barSlotW + card1.barSlotW - 2 * card1.barIndicatorInset
                                        height: card1.barSlotH - 2 * card1.barIndicatorInset
                                        y: card1.barIndicatorInset
                                        radius: height / 2
                                        color: Appearance.m3colors.m3primary
                                        opacity: 0.9
                                    }

                                    Row {
                                        z: 2
                                        anchors.fill: parent
                                        Repeater {
                                            model: card1.totalWs
                                            delegate: Item {
                                                required property int index
                                                width: card1.barSlotW
                                                height: card1.barSlotH
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: card1.barSlotR * 2
                                                    height: card1.barSlotR * 2
                                                    radius: width / 2
                                                    color: Appearance.colors.colOnLayer0
                                                    opacity: 0.35
                                                }
                                            }
                                        }
                                    }

                                    IconImage {
                                        z: 3
                                        readonly property string primary: card1.primaryAppFor(card1.currentWs)
                                        visible: primary !== ""
                                        implicitSize: card1.barIconSize
                                        x: card1.currentWs * card1.barSlotW + (card1.barSlotW - implicitSize) / 2
                                        y: (card1.barSlotH - implicitSize) / 2
                                        source: primary !== ""
                                            ? Quickshell.iconPath(primary, "image-missing")
                                            : ""
                                    }
                                }
                            }

                            PillBg {
                                id: sysTrayPill8
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 10
                                height: card1.barPillH
                                width: trayRow8.implicitWidth + 12
                                Row {
                                    id: trayRow8
                                    anchors.centerIn: parent
                                    spacing: 6
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "volume_up"; iconSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "wifi"; iconSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "settings"; iconSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }
                            }

                            Row {
                                anchors.right: sysTrayPill8.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 12
                                spacing: 4
                                PillBg {
                                    height: card1.barPillH
                                    width: clockText8.implicitWidth + 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    StyledText {
                                        id: clockText8
                                        anchors.centerIn: parent
                                        text: "12:53"
                                        font.pixelSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }
                                PillBg {
                                    height: card1.barPillH
                                    width: weatherRow8.implicitWidth + 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    Row {
                                        id: weatherRow8
                                        anchors.centerIn: parent
                                        spacing: 2
                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "cloud"
                                            iconSize: 11
                                            color: Appearance.colors.colOnLayer1
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "74°"
                                            font.pixelSize: 9
                                            color: Appearance.colors.colOnLayer1
                                        }
                                    }
                                }
                            }
                        }

                        // ─── Pointer ───
                        // A small primary-coloured chevron that slides
                        // along underneath the bar to whichever section
                        // currentSection is pointing at.
                        MaterialSymbol {
                            id: barPointer
                            text: card1.sectionPointsDown[card1.currentSection]
                                ? "keyboard_arrow_down"
                                : "keyboard_arrow_up"
                            iconSize: 22
                            color: Appearance.m3colors.m3primary
                            x: card1.sectionXs[card1.currentSection] - 11
                            y: card1.sectionYs[card1.currentSection]
                            z: 3
                            Behavior on x {
                                NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                            }
                            Behavior on y {
                                NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                            }
                        }

                        // ─── Callout ───
                        // Card centred below the bar; title + body
                        // bound to currentSection. Title font scales
                        // bigger so the section name reads as a heading.
                        Rectangle {
                            id: barCallout
                            x: card1.calloutX
                            y: card1.calloutY
                            width: card1.calloutW
                            height: card1.calloutH
                            radius: 12
                            color: Appearance.m3colors.m3surfaceContainer
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.45)
                            border.width: 1
                            z: 2

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 6

                                StyledText {
                                    Layout.fillWidth: true
                                    text: card1.sectionNames[card1.currentSection]
                                    font {
                                        family: Appearance.font.family.title
                                        pixelSize: Appearance.font.pixelSize.large
                                        variableAxes: Appearance.font.variableAxes.title
                                    }
                                    color: Appearance.m3colors.m3onSurface
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: card1.sectionDescs[card1.currentSection]
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: Appearance.m3colors.m3onSurface
                                    opacity: 0.82
                                    wrapMode: Text.WordWrap
                                    lineHeight: 1.3
                                }
                            }
                        }

                        // ─── Dock (clone of card 4's) ───
                        Rectangle {
                            id: dockStrip8
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: card1.dockBottomMargin
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: card1.dockW
                            height: card1.dockH
                            radius: Math.round(card1.dockH * Appearance.rounding.large / 70)
                            color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.55)
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.55)
                            border.width: 1

                            Row {
                                anchors.centerIn: parent
                                spacing: card1.dockGap

                                Item {
                                    width: card1.dockIconSize
                                    height: card1.dockIconSize
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "push_pin"
                                        iconSize: card1.dockIconSize
                                        color: Appearance.colors.colOnLayer0
                                        opacity: 0.85
                                    }
                                }
                                Repeater {
                                    model: card1.dockApps
                                    delegate: IconImage {
                                        required property string modelData
                                        implicitSize: card1.dockIconSize
                                        source: Quickshell.iconPath(modelData, "image-missing")
                                    }
                                }
                                Item {
                                    width: card1.dockIconSize
                                    height: card1.dockIconSize
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "apps"
                                        iconSize: card1.dockIconSize
                                        color: Appearance.colors.colOnLayer0
                                        opacity: 0.85
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Walk through every section in order. Resets to 0 each time
        // the card becomes visible so the tour always starts at the
        // far-left section.
        Timer {
            interval: 4500
            running: card1.visible
            repeat: true
            onTriggered: card1.currentSection = (card1.currentSection + 1) % card1.totalSections
        }
        onVisibleChanged: if (visible) currentSection = 0
    }

    // ── Card 3: Dock + app drawer walkthrough ───────────────────────────
    // Teaches four mechanics in one loop:
    //   1. Hover the bottom edge to reveal the dock
    //   2. Click the apps button to open the drawer
    //   3. Right-click an app → "Pin to dock"
    //   4. Click an app to launch it on the active workspace
    //
    // Visual primitives + 200ms BezierSpline timings mirror the real
    // shell (Dock.qml elementMoveFast, Overview.qml contentFade,
    // DockContextMenu.qml). The animation cycle loops infinitely.
    component Card3DockAndDrawer : Item {
        id: card3

        // ── Animation state ───────────────────────────────────────────
        property int currentStep: 0
        property real cursorX: 0
        property real cursorY: 0
        property real dockReveal: 0           // 0 = offscreen-below, 1 = visible
        property real drawerOpen: 0           // 0 = hidden, 1 = visible
        property bool ctxMenuOpen: false
        property bool joplinPinned: false     // dock width grows once true
        property real joplinPopScale: 0       // pop-in scale for joplin's new dock slot
        property real clickPulse: 0           // brief cursor scale-up on click
        property bool appLaunched: false

        // ── Mockup geometry (mirrors Card1's layout) ──────────────────
        readonly property int mockW: 600
        readonly property int mockH: 380
        readonly property int barH: 22

        // Workspaces
        readonly property int wsTileW: 100
        readonly property int wsTileH: 60
        readonly property int wsGap: 8
        readonly property int wsCols: 5
        readonly property int wsRows: 2
        readonly property int wsPadding: 12
        readonly property int wsContainerW: wsCols * wsTileW + (wsCols - 1) * wsGap + 2 * wsPadding
        readonly property int wsContainerH: wsRows * wsTileH + (wsRows - 1) * wsGap + 2 * wsPadding
        readonly property int wsContainerX: (mockW - wsContainerW) / 2
        readonly property int wsContainerY: barH + 14
        readonly property int wsAreaX: wsContainerX + wsPadding
        readonly property int wsAreaY: wsContainerY + wsPadding
        readonly property int activeWsIdx: 0

        // Drawer (same 36-app grid as Card1/Card7; joplin at the end)
        readonly property var drawerApps: [
            "firefox", "google-chrome", "visual-studio-code", "spotify", "telegram",
            "vlc", "gimp", "blender", "krita", "obs",
            "thunderbird", "libreoffice-startcenter", "audacity", "godot",
            "inkscape", "chromium", "brave-browser", "slack", "signal-desktop",
            "element-desktop", "zoom", "kdenlive", "transmission", "qbittorrent",
            "steam", "lutris", "heroic", "mpv",
            "handbrake", "openshot", "scribus", "ksnip", "virt-manager",
            "postman", "dbeaver", "joplin"
        ]
        readonly property int joplinIdx: 35
        readonly property int firefoxIdx: 0
        readonly property int drawerCols: 14
        readonly property int drawerRows: 3
        readonly property int drawerIconSize: 16
        readonly property int drawerGap: 8
        readonly property int drawerPadding: 10
        readonly property int drawerInnerW: drawerCols * drawerIconSize + (drawerCols - 1) * drawerGap
        readonly property int drawerInnerH: drawerRows * drawerIconSize + (drawerRows - 1) * drawerGap
        readonly property int drawerW: drawerInnerW + 2 * drawerPadding
        readonly property int drawerH: drawerInnerH + 2 * drawerPadding
        readonly property int drawerX: (mockW - drawerW) / 2
        readonly property int drawerY: wsContainerY + wsContainerH + 16

        // Dock — 4 apps initially; joplinPinned adds a 5th and resizes
        readonly property var baseDockApps: ["keepassxc", "evince", "kitty", "anki"]
        readonly property var dockApps: joplinPinned
            ? baseDockApps.concat(["joplin"])
            : baseDockApps
        readonly property int dockIconSize: 16
        readonly property int dockGap: 8
        readonly property int dockPadding: 8
        readonly property int dockBottomMargin: 10
        readonly property int dockCellCount: dockApps.length + 2
        readonly property real dockW:
            dockCellCount * dockIconSize + (dockCellCount - 1) * dockGap + 2 * dockPadding
        readonly property real dockH: dockIconSize + 2 * dockPadding
        readonly property real dockLeftX: (mockW - dockW) / 2
        readonly property real dockTopY: mockH - dockBottomMargin - dockH
        readonly property real dockCenterY: dockTopY + dockH / 2
        readonly property real dockHiddenOffset: dockH + dockBottomMargin + 8
        readonly property real dockVisualY: dockTopY + (1 - dockReveal) * dockHiddenOffset
        // Drawer button = rightmost dock cell
        readonly property real dockDrawerBtnCenterX:
            dockLeftX + dockPadding + (dockCellCount - 1) * (dockIconSize + dockGap) + dockIconSize / 2

        // Joplin's drawer coords — used to park the cursor on the right
        // icon for the right-click + menu navigation animation.
        readonly property real joplinDrawerX: drawerIconCenterX(joplinIdx)
        readonly property real joplinDrawerY: drawerIconCenterY(joplinIdx)

        // Cursor park (idle, outside the action area)
        readonly property real cursorParkX: mockW - 40
        readonly property real cursorParkY: mockH - 40

        function drawerIconCenterX(idx) {
            const col = idx % drawerCols
            return drawerX + drawerPadding + col * (drawerIconSize + drawerGap) + drawerIconSize / 2
        }
        function drawerIconCenterY(idx) {
            const row = Math.floor(idx / drawerCols)
            return drawerY + drawerPadding + row * (drawerIconSize + drawerGap) + drawerIconSize / 2
        }

        // ── Layout ────────────────────────────────────────────────────
        RowLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 28

            // Left: title + body
            ColumnLayout {
                Layout.minimumWidth: 280
                Layout.maximumWidth: 280
                Layout.preferredWidth: 280
                Layout.fillWidth: false
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 12

                Item { Layout.fillHeight: true }

                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 280
                    text: Translation.tr("The dock and app drawer")
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.huge
                        variableAxes: Appearance.font.variableAxes.title
                    }
                    color: Appearance.colors.colOnLayer0
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 280
                    text: Translation.tr("To see the dock, hover the bottom edge of the screen to get it to slide up. From there, click the app drawer button to open the drawer.<br><br>The dock can hold pinned apps for quick access — right-click any app in the drawer and choose <b>\"Pin to dock\"</b> to add it. The drawer is your launcher — click any app to open it on the active workspace.")
                    textFormat: Text.RichText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.85
                    wrapMode: Text.WordWrap
                    lineHeight: 1.35
                }

                Item { Layout.fillHeight: true }
            }

            // Right: animated mockup
            Item {
                id: mockupHost
                Layout.fillWidth: true
                Layout.fillHeight: true

                Item {
                    id: mockupContainer
                    width: card3.mockW
                    height: card3.mockH
                    anchors.centerIn: parent
                    scale: Math.min(
                        1.0,
                        (mockupHost.width  - 8) / width,
                        (mockupHost.height - 8) / height
                    )

                    Rectangle {
                        id: mockup
                        anchors.fill: parent
                        radius: 14
                        color: "#0e0e12"
                        border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.6)
                        border.width: 1
                        clip: true

                        // Top bar
                        Rectangle {
                            x: 10; y: 8
                            width: parent.width - 20
                            height: card3.barH - 6
                            radius: height / 2
                            color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.35)
                        }

                        // Overview group — fades together with the drawer
                        // (matches Overview.qml's contentFade, which gates
                        // workspaces + drawer with a single opacity).
                        Item {
                            anchors.fill: parent
                            opacity: card3.drawerOpen

                            // Workspaces container
                            Rectangle {
                                x: card3.wsContainerX
                                y: card3.wsContainerY
                                width: card3.wsContainerW
                                height: card3.wsContainerH
                                radius: 12
                                color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.22)
                                border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.55)
                                border.width: 1
                            }

                            // Workspace tiles
                            Repeater {
                                model: card3.wsCols * card3.wsRows
                                delegate: Rectangle {
                                    required property int index
                                    readonly property int col: index % card3.wsCols
                                    readonly property int row: Math.floor(index / card3.wsCols)
                                    readonly property bool isActive: index === card3.activeWsIdx
                                    x: card3.wsAreaX + col * (card3.wsTileW + card3.wsGap)
                                    y: card3.wsAreaY + row * (card3.wsTileH + card3.wsGap)
                                    width: card3.wsTileW
                                    height: card3.wsTileH
                                    radius: 8
                                    color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.14)
                                    border.width: isActive ? 2 : 1
                                    border.color: isActive
                                        ? Appearance.colors.colOnLayer0
                                        : ColorUtils.transparentize(Appearance.colors.colOutline, 0.45)

                                    StyledText {
                                        anchors.centerIn: parent
                                        text: (index + 1).toString()
                                        font.pixelSize: 22
                                        font.family: Appearance.font.family.title
                                        color: Appearance.colors.colOnLayer0
                                        opacity: 0.35
                                    }
                                }
                            }
                        }

                        // Drawer container — opacity tracks drawerOpen
                        Rectangle {
                            x: card3.drawerX
                            y: card3.drawerY
                            width: card3.drawerW
                            height: card3.drawerH
                            radius: 12
                            color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.28)
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.55)
                            border.width: 1
                            opacity: card3.drawerOpen
                        }

                        // Drawer icons
                        Repeater {
                            model: card3.drawerApps
                            delegate: IconImage {
                                required property int index
                                required property string modelData
                                x: card3.drawerIconCenterX(index) - implicitSize / 2
                                y: card3.drawerIconCenterY(index) - implicitSize / 2
                                implicitSize: card3.drawerIconSize
                                source: Quickshell.iconPath(modelData, "image-missing")
                                opacity: card3.drawerOpen
                            }
                        }

                        // Desktop window — Firefox surfaces here after the
                        // overview + drawer fade out. Same OutBack scale
                        // feel as the real shell's window-open animation.
                        Rectangle {
                            id: desktopWindow
                            readonly property real topPad: card3.barH + 16
                            readonly property real bottomPad: card3.dockTopY - 14
                            x: 36
                            y: topPad
                            width: card3.mockW - 72
                            height: bottomPad - topPad
                            radius: 8
                            color: "#FFFFFF"
                            transformOrigin: Item.Center
                            visible: opacity > 0.01
                            opacity: card3.appLaunched ? 1 : 0
                            scale:   card3.appLaunched ? 1 : 0.55
                            Behavior on opacity { NumberAnimation { duration: 230 } }
                            Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

                            // Firefox-ish title bar with a tab pill
                            Rectangle {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 30
                                color: "#F0F0F4"
                                topLeftRadius: 8
                                topRightRadius: 8
                                bottomLeftRadius: 0
                                bottomRightRadius: 0

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 10
                                    width: 110
                                    height: parent.height - 8
                                    radius: 5
                                    color: "#FFFFFF"
                                    border.color: "#D0D0D5"
                                    border.width: 1
                                }
                            }

                            IconImage {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: 15
                                source: Quickshell.iconPath("firefox", "image-missing")
                                implicitSize: 64
                            }
                        }

                        // Dock strip — slides up via dockVisualY
                        Rectangle {
                            id: dockStrip
                            x: card3.dockLeftX
                            y: card3.dockVisualY
                            width: card3.dockW
                            height: card3.dockH
                            radius: Math.round(card3.dockH * Appearance.rounding.large / 70)
                            color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.55)
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.55)
                            border.width: 1

                            Row {
                                anchors.centerIn: parent
                                spacing: card3.dockGap

                                // Pin button
                                Item {
                                    width: card3.dockIconSize
                                    height: card3.dockIconSize
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "push_pin"
                                        iconSize: card3.dockIconSize
                                        color: Appearance.colors.colOnLayer0
                                        opacity: 0.85
                                    }
                                }

                                // Pinned apps. Joplin's icon uses joplinPopScale
                                // so it can pop into existence in its new slot
                                // when the user pins it (timeline drives the
                                // overshoot-then-settle scale curve).
                                Repeater {
                                    model: card3.dockApps
                                    delegate: IconImage {
                                        required property string modelData
                                        implicitSize: card3.dockIconSize
                                        source: Quickshell.iconPath(modelData, "image-missing")
                                        scale: modelData === "joplin" ? card3.joplinPopScale : 1
                                        transformOrigin: Item.Center
                                    }
                                }

                                // Drawer toggle button
                                Item {
                                    width: card3.dockIconSize
                                    height: card3.dockIconSize
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "apps"
                                        iconSize: card3.dockIconSize
                                        color: Appearance.colors.colOnLayer0
                                        opacity: 0.85
                                    }
                                }
                            }
                        }

                        // Right-click context menu — anchored above joplin.
                        // Only "Pin to dock" is shown so the user's eye
                        // tracks straight to the action being taught.
                        Rectangle {
                            id: ctxMenu
                            readonly property real menuW: 116
                            readonly property real menuH: 30
                            x: Math.min(card3.drawerIconCenterX(card3.joplinIdx) + 6,
                                        card3.mockW - menuW - 8)
                            y: card3.drawerIconCenterY(card3.joplinIdx) - menuH - 6
                            width: menuW
                            height: menuH
                            radius: 8
                            color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainer, 0.05)
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.55)
                            border.width: 1
                            visible: opacity > 0.01
                            opacity: card3.ctxMenuOpen ? 1 : 0
                            scale:   card3.ctxMenuOpen ? 1 : 0.85
                            transformOrigin: Item.BottomLeft
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.34, 0.80, 0.34, 1.00, 1, 1]
                                }
                            }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: [0.34, 0.80, 0.34, 1.00, 1, 1]
                                }
                            }

                            Column {
                                anchors.fill: parent
                                anchors.margins: 4
                                spacing: 0

                                Rectangle {
                                    width: parent.width
                                    height: 22
                                    radius: 4
                                    color: "transparent"
                                    Row {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 6
                                        spacing: 5
                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "keep"
                                            iconSize: 12
                                            color: Appearance.colors.colOnLayer0
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Translation.tr("Pin to dock")
                                            font.pixelSize: 10
                                            color: Appearance.colors.colOnLayer0
                                        }
                                    }
                                }
                            }
                        }

                        // Cursor cue (with brief click pulse)
                        MaterialSymbol {
                            text: "arrow_selector_tool"
                            iconSize: 22 + 6 * card3.clickPulse
                            color: Appearance.colors.colOnLayer0
                            x: card3.cursorX - 4
                            y: card3.cursorY - 4
                        }
                    }
                }
            }
        }

        // ── Animation timeline ────────────────────────────────────────
        // One full loop ≈ 12s. Reset → reveal dock → open drawer →
        // right-click joplin → pin → launch firefox → pause → repeat.
        SequentialAnimation {
            id: demoCycle10
            running: card3.visible
            loops: Animation.Infinite

            ScriptAction {
                script: {
                    card3.currentStep = 0
                    card3.cursorX = card3.cursorParkX
                    card3.cursorY = card3.cursorParkY
                    card3.dockReveal = 0
                    card3.drawerOpen = 0
                    card3.ctxMenuOpen = false
                    card3.joplinPinned = false
                    card3.joplinPopScale = 0
                    card3.appLaunched = false
                    card3.clickPulse = 0
                }
            }
            PauseAnimation { duration: 800 }

            // Step 1: hover the bottom edge → dock slides up
            ScriptAction { script: card3.currentStep = 1 }
            ParallelAnimation {
                NumberAnimation { target: card3; property: "cursorX"; to: card3.mockW / 2; duration: 800; easing.type: Easing.OutCubic }
                NumberAnimation { target: card3; property: "cursorY"; to: card3.mockH - 8; duration: 800; easing.type: Easing.OutCubic }
            }
            NumberAnimation {
                target: card3
                property: "dockReveal"
                to: 1
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.34, 0.80, 0.34, 1.00, 1, 1]
            }
            PauseAnimation { duration: 1100 }

            // Step 2: click drawer button → drawer fades in
            ScriptAction { script: card3.currentStep = 2 }
            ParallelAnimation {
                NumberAnimation { target: card3; property: "cursorX"; to: card3.dockDrawerBtnCenterX; duration: 600; easing.type: Easing.OutCubic }
                NumberAnimation { target: card3; property: "cursorY"; to: card3.dockCenterY; duration: 600; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
                NumberAnimation { target: card3; property: "clickPulse"; to: 1; duration: 80 }
                NumberAnimation { target: card3; property: "clickPulse"; to: 0; duration: 140 }
            }
            NumberAnimation {
                target: card3
                property: "drawerOpen"
                to: 1
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.34, 0.80, 0.34, 1.00, 1, 1]
            }
            PauseAnimation { duration: 1000 }

            // Step 3: right-click joplin → context menu → Pin to dock
            ScriptAction { script: card3.currentStep = 3 }
            ParallelAnimation {
                NumberAnimation { target: card3; property: "cursorX"; to: card3.joplinDrawerX; duration: 800; easing.type: Easing.OutCubic }
                NumberAnimation { target: card3; property: "cursorY"; to: card3.joplinDrawerY; duration: 800; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
                NumberAnimation { target: card3; property: "clickPulse"; to: 1; duration: 80 }
                NumberAnimation { target: card3; property: "clickPulse"; to: 0; duration: 140 }
            }
            ScriptAction { script: card3.ctxMenuOpen = true }
            PauseAnimation { duration: 750 }

            // Move cursor to the highlighted "Pin to dock" entry
            ParallelAnimation {
                NumberAnimation { target: card3; property: "cursorX"; to: card3.joplinDrawerX + 50; duration: 500; easing.type: Easing.OutCubic }
                NumberAnimation { target: card3; property: "cursorY"; to: card3.joplinDrawerY - 21; duration: 500; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
                NumberAnimation { target: card3; property: "clickPulse"; to: 1; duration: 80 }
                NumberAnimation { target: card3; property: "clickPulse"; to: 0; duration: 140 }
            }
            ScriptAction { script: card3.ctxMenuOpen = false }
            PauseAnimation { duration: 240 }

            // Pop joplin into its new dock slot: overshoot to 1.25 then
            // settle to 1.0. Mirrors the feel of pinning an app in the
            // real shell — the new icon appears right where it lands.
            ScriptAction {
                script: {
                    card3.joplinPinned = true
                    card3.joplinPopScale = 0
                }
            }
            NumberAnimation { target: card3; property: "joplinPopScale"; to: 1.25; duration: 180; easing.type: Easing.OutQuad }
            NumberAnimation { target: card3; property: "joplinPopScale"; to: 1.0;  duration: 220; easing.type: Easing.InOutQuad }
            PauseAnimation { duration: 1000 }

            // Step 4: click firefox → drawer closes, window opens on ws1
            ScriptAction { script: card3.currentStep = 4 }
            ParallelAnimation {
                NumberAnimation { target: card3; property: "cursorX"; to: card3.drawerIconCenterX(card3.firefoxIdx); duration: 800; easing.type: Easing.OutCubic }
                NumberAnimation { target: card3; property: "cursorY"; to: card3.drawerIconCenterY(card3.firefoxIdx); duration: 800; easing.type: Easing.OutCubic }
            }
            SequentialAnimation {
                NumberAnimation { target: card3; property: "clickPulse"; to: 1; duration: 80 }
                NumberAnimation { target: card3; property: "clickPulse"; to: 0; duration: 140 }
            }
            // Overview + drawer fade out first; only then does the
            // desktop window scale in — reads as "shell gets out of
            // the way, then the app appears."
            NumberAnimation {
                target: card3
                property: "drawerOpen"
                to: 0
                duration: 200
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.34, 0.80, 0.34, 1.00, 1, 1]
            }
            PauseAnimation { duration: 80 }
            ScriptAction { script: card3.appLaunched = true }
            PauseAnimation { duration: 1800 }
        }
    }

    // ── Card 5: Drag a file across workspaces via the bar ───────────────
    // The bar's workspace pill strip has a DropArea that scrolls workspaces
    // when a drag hovers near its edges (Workspaces.qml:108). Mock that:
    //   1. Lift a file out of a Nautilus window on ws1
    //   2. Hover the cursor over the right side of the bar's pill strip
    //   3. Active workspace scrolls ws1 → ws2 → ws3; canvas slides like
    //      real Hyprland's workspace transition
    //   4. Drop the file on a Downloads window now visible on ws3
    component Card5FileDragViaBar : Item {
        id: card5

        // ── State ─────────────────────────────────────────────────────
        property int currentStep: 0
        property real cursorX: 0
        property real cursorY: 0
        property real dragX: 0
        property real dragY: 0
        property real clickPulse: 0
        property bool filePickedUp: false
        property int activeWs: 0          // 0 = ws1 (src), 1 = ws2, 2 = ws3 (dest)
        property bool fileDropped: false
        // Drag-over-pill state — drives the BarGroup-style glow and the
        // dot-to-chevron swap on the workspace pill.
        property bool barDragActive: false

        // ── Mockup geometry ──────────────────────────────────────────
        readonly property int mockW: 600
        readonly property int mockH: 380

        // Bar — same compact sizing as Card8's bar tour, so the user
        // sees the workspace pill in the context of the full top bar
        // (active window, media, workspaces, clock, weather, tray).
        readonly property int barW: 560
        readonly property int barH: 30
        readonly property int barX: (mockW - barW) / 2
        readonly property int barY: 12

        // Workspace pill — Card8 PillBg dimensions. Slots are small but
        // the new feedback (glow, chevrons, next-pill preview, progress
        // fill) still reads at this scale.
        readonly property int pillCount: 10
        readonly property int barSlotW: 16
        readonly property int barSlotH: 16
        readonly property int barSlotR: 2
        readonly property int barIconSize: 10
        readonly property int barIndicatorInset: 1
        readonly property int barPillPadH: 5
        readonly property int barPillPadV: 3
        readonly property int barStripW: pillCount * barSlotW
        readonly property int barPillW: barStripW + 2 * barPillPadH
        readonly property int barPillH: barSlotH + 2 * barPillPadV
        readonly property int barPillX: (mockW - barPillW) / 2
        readonly property int barPillY: barY + (barH - barPillH) / 2
        readonly property int barStripX: barPillX + barPillPadH
        readonly property int barStripY: barPillY + barPillPadV
        function barSlotCenterX(idx) { return barStripX + idx * barSlotW + barSlotW / 2 }
        readonly property real barSlotCenterY: barStripY + barSlotH / 2

        // Workspace canvas (the filmstrip viewport below the bar)
        readonly property int canvasX: 16
        readonly property int canvasY: barY + barH + 12
        readonly property int canvasW: mockW - 32
        readonly property int canvasH: mockH - canvasY - 12

        // Nautilus window dimensions — same width as the bar so the
        // window fills the canvas like Card6FileManager's screenshot.
        // Height tracks the 1912×1034 aspect with no letterboxing.
        readonly property int winW: barW
        readonly property int winH: Math.round(winW * 1034 / 1912)
        readonly property int winLocalX: (canvasW - winW) / 2
        // Anchor the Nautilus window to the top of the canvas (= barY +
        // barH + 12) so it sits exactly where Card6FileManager's storeY
        // does, instead of being centred vertically.
        readonly property int winLocalY: 0

        // File icon position inside its workspace's window
        readonly property int sidebarW: 60
        readonly property int fileLocalX: winLocalX + sidebarW + (winW - sidebarW) / 2
        readonly property int fileLocalY: winLocalY + 22 + (winH - 22) * 0.45

        // Path to the welcome-tutorial-images directory (same lookup
        // pattern Card6FileManager uses for its screenshots).
        readonly property string imageDir:
            Quickshell.env("HOME") + "/.config/quickshell/ii/welcome-tutorial-images"

        // Mockup-coordinate helpers for the cursor / ghost
        function fileMockX() { return canvasX + fileLocalX }
        function fileMockY() { return canvasY + fileLocalY }
        function destMockX() { return canvasX + winLocalX + sidebarW + (winW - sidebarW) / 2 }
        function destMockY() { return canvasY + winLocalY + 22 + (winH - 22) * 0.45 }

        // Cursor park
        readonly property real cursorParkX: mockW - 40
        readonly property real cursorParkY: canvasY + canvasH - 16

        // ── Layout ────────────────────────────────────────────────────
        RowLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 28

            // Left: title + body
            ColumnLayout {
                Layout.minimumWidth: 280
                Layout.maximumWidth: 280
                Layout.preferredWidth: 280
                Layout.fillWidth: false
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 12

                Item { Layout.fillHeight: true }

                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 280
                    text: Translation.tr("Drag files between workspaces with the bar")
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.huge
                        variableAxes: Appearance.font.variableAxes.title
                    }
                    color: Appearance.colors.colOnLayer0
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 280
                    text: Translation.tr("Grab a file and hover the workspace pill in the bar — it lights up and the dots fan out into arrows showing the scroll direction. Slide right to advance workspaces, left to go back, and drop the file into any app on the new workspace without ever opening the overview.")
                    textFormat: Text.RichText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                    opacity: 0.85
                    wrapMode: Text.WordWrap
                    lineHeight: 1.35
                }

                Item { Layout.fillHeight: true }
            }

            // Right: animated mockup
            Item {
                id: mockupHost11
                Layout.fillWidth: true
                Layout.fillHeight: true

                Item {
                    id: mockupContainer11
                    width: card5.mockW
                    height: card5.mockH
                    anchors.centerIn: parent
                    scale: Math.min(
                        1.0,
                        (mockupHost11.width  - 8) / width,
                        (mockupHost11.height - 8) / height
                    )

                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: "#0e0e12"
                        border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.6)
                        border.width: 1
                        clip: true

                        // ─── Bar (clone of Card8's bar layout) ───
                        // Full bar context: active window + media pill +
                        // workspace pill + clock + weather + system tray.
                        // The workspace pill weaves in the new feedback
                        // features (glow, chevrons, next-pill preview,
                        // progress fill) so the user sees those changes
                        // applied inside a real-feeling bar.
                        Rectangle {
                            id: barFrame11
                            x: card5.barX
                            y: card5.barY
                            width: card5.barW
                            height: card5.barH
                            radius: card5.barH / 2
                            color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.45)
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.35)
                            border.width: 1
                            z: 2

                            // Active window text (left)
                            ColumnLayout {
                                id: activeWindowText11
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 10
                                spacing: -3
                                StyledText {
                                    text: card5.activeWs === 0 ? "Downloads — Files"
                                        : card5.activeWs === 2 ? "Documents — Files"
                                        : "Desktop"
                                    font.pixelSize: 7
                                    color: Appearance.colors.colSubtext
                                    opacity: 0.85
                                }
                                StyledText {
                                    text: "Workspace " + (card5.activeWs + 1)
                                    font.pixelSize: 9
                                    color: Appearance.colors.colOnLayer0
                                }
                            }

                            // Now playing pill
                            Rectangle {
                                id: mediaPill11
                                anchors.left: activeWindowText11.right
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                height: card5.barPillH
                                width: mediaRow11.implicitWidth + 12
                                radius: 8
                                color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.3)
                                Row {
                                    id: mediaRow11
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Rectangle {
                                        width: 12; height: 12; radius: 6
                                        color: "#FFFFFF"
                                        anchors.verticalCenter: parent.verticalCenter
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "music_note"
                                            iconSize: 9
                                            color: "#202024"
                                        }
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Subnautica 2 LAU…"
                                        font.pixelSize: 8
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                        width: 70
                                    }
                                }
                            }

                            // Workspace pill — with new feedback features
                            Rectangle {
                                id: workspacePill11
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                height: card5.barPillH
                                width: card5.barPillW
                                radius: 8
                                color: card5.barDragActive
                                    ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.82)
                                    : ColorUtils.transparentize(Appearance.colors.colLayer1, 0.3)
                                border.color: card5.barDragActive
                                    ? Appearance.colors.colPrimary
                                    : "transparent"
                                border.width: card5.barDragActive ? 1.5 : 0
                                Behavior on color        { ColorAnimation  { duration: 220 } }
                                Behavior on border.color { ColorAnimation  { duration: 220 } }
                                Behavior on border.width { NumberAnimation { duration: 220 } }

                                Item {
                                    id: workspaceStrip11
                                    anchors.centerIn: parent
                                    implicitWidth: card5.barStripW
                                    implicitHeight: card5.barSlotH

                                    // Active indicator
                                    Rectangle {
                                        id: activeIndicator11
                                        x: card5.activeWs * card5.barSlotW + card5.barIndicatorInset
                                        y: card5.barIndicatorInset
                                        width: card5.barSlotW - 2 * card5.barIndicatorInset
                                        height: card5.barSlotH - 2 * card5.barIndicatorInset
                                        radius: height / 2
                                        color: Appearance.m3colors.m3primary
                                        opacity: 0.9
                                        z: 2
                                        Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                    }

                                    // Dots / chevrons row
                                    Row {
                                        z: 3
                                        anchors.fill: parent
                                        Repeater {
                                            model: card5.pillCount
                                            delegate: Item {
                                                required property int index
                                                width: card5.barSlotW
                                                height: card5.barSlotH

                                                readonly property real centerIdx: (card5.pillCount - 1) / 2
                                                readonly property bool isLeft: index < centerIdx - 0.5
                                                readonly property bool isRight: index > centerIdx + 0.5
                                                readonly property bool isMiddle: !isLeft && !isRight
                                                readonly property bool isActive: index === card5.activeWs

                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: card5.barSlotR * 2
                                                    height: card5.barSlotR * 2
                                                    radius: width / 2
                                                    color: parent.isActive
                                                        ? Appearance.m3colors.m3onPrimary
                                                        : Appearance.colors.colOnLayer0
                                                    opacity: card5.barDragActive && !parent.isMiddle
                                                        ? 0
                                                        : (parent.isActive ? 1 : 0.35)
                                                    Behavior on opacity { NumberAnimation { duration: 220 } }
                                                }

                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: parent.isLeft ? "chevron_left" : "chevron_right"
                                                    iconSize: card5.barSlotW * 0.85
                                                    color: parent.isActive
                                                        ? Appearance.m3colors.m3onPrimary
                                                        : Appearance.colors.colOnLayer0
                                                    visible: opacity > 0.01
                                                    opacity: card5.barDragActive
                                                             && !parent.isMiddle
                                                             && !parent.isActive ? 0.95 : 0
                                                    Behavior on opacity { NumberAnimation { duration: 220 } }
                                                }
                                            }
                                        }
                                    }

                                    // App icon overlay on active workspace
                                    IconImage {
                                        z: 4
                                        readonly property string app:
                                              card5.activeWs === 0 ? "org.gnome.Nautilus"
                                            : card5.activeWs === 2 ? "org.gnome.Nautilus"
                                            : ""
                                        visible: app !== ""
                                        implicitSize: card5.barIconSize
                                        x: card5.activeWs * card5.barSlotW + (card5.barSlotW - implicitSize) / 2
                                        y: (card5.barSlotH - implicitSize) / 2
                                        source: app !== "" ? Quickshell.iconPath(app, "image-missing") : ""
                                        Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }

                            // System tray pill (right)
                            Rectangle {
                                id: sysTrayPill11
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 10
                                height: card5.barPillH
                                width: trayRow11.implicitWidth + 12
                                radius: 8
                                color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.3)
                                Row {
                                    id: trayRow11
                                    anchors.centerIn: parent
                                    spacing: 6
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "volume_up"; iconSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "wifi"; iconSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "settings"; iconSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }
                            }

                            // Clock + weather row (right, before tray)
                            Row {
                                anchors.right: sysTrayPill11.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 12
                                spacing: 4
                                Rectangle {
                                    height: card5.barPillH
                                    width: clockText11.implicitWidth + 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: 8
                                    color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.3)
                                    StyledText {
                                        id: clockText11
                                        anchors.centerIn: parent
                                        text: "12:34 AM"
                                        font.pixelSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }
                                Rectangle {
                                    height: card5.barPillH
                                    width: weatherRow11.implicitWidth + 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: 8
                                    color: ColorUtils.transparentize(Appearance.colors.colLayer1, 0.3)
                                    Row {
                                        id: weatherRow11
                                        anchors.centerIn: parent
                                        spacing: 2
                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "cloud"
                                            iconSize: 11
                                            color: Appearance.colors.colOnLayer1
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "74°"
                                            font.pixelSize: 9
                                            color: Appearance.colors.colOnLayer1
                                        }
                                    }
                                }
                            }
                        }

                        // ─── Workspace canvas (filmstrip) ───
                        // 3 ws slots placed side-by-side; the strip's x
                        // translates left as activeWs advances, matching
                        // Hyprland's horizontal workspace transition.
                        Item {
                            id: canvas
                            x: card5.canvasX
                            y: card5.canvasY
                            width: card5.canvasW
                            height: card5.canvasH
                            clip: true

                            Item {
                                id: filmstrip
                                width: card5.canvasW * 3
                                height: card5.canvasH
                                x: -card5.activeWs * card5.canvasW
                                Behavior on x {
                                    NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                                }

                                // Source Nautilus on ws1 (slot 0)
                                Item {
                                    id: sourceNautilus
                                    x: card5.winLocalX
                                    y: card5.winLocalY
                                    width: card5.winW
                                    height: card5.winH

                                    Image {
                                        anchors.fill: parent
                                        source: card5.imageDir + "/files-downloads.png"
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        asynchronous: true
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: sourceNautilus.width
                                                height: sourceNautilus.height
                                                radius: 8
                                            }
                                        }
                                    }

                                    // File icon (source) — dims while picked up
                                    Item {
                                        x: card5.sidebarW + (card5.winW - card5.sidebarW) / 2 - width / 2
                                        y: 22 + (card5.winH - 22) * 0.45 - height / 2
                                        width: 52
                                        height: 68
                                        opacity: card5.filePickedUp ? 0.2 : 1
                                        Behavior on opacity { NumberAnimation { duration: 180 } }

                                        Image {
                                            anchors.top: parent.top
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 46
                                            height: 46
                                            source: card5.imageDir + "/generic-file.svg"
                                            sourceSize.width: 64
                                            sourceSize.height: 64
                                            smooth: true
                                            asynchronous: true
                                        }
                                        StyledText {
                                            anchors.bottom: parent.bottom
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: "notes.txt"
                                            font.pixelSize: 12
                                            color: "#FFFFFF"
                                        }
                                    }
                                }

                                // ws2 placeholder (slot 1) — just a faint
                                // empty workspace so the slide reads as
                                // moving across real workspaces.
                                Item {
                                    x: card5.canvasW + card5.winLocalX
                                    y: card5.winLocalY
                                    width: card5.winW
                                    height: card5.winH
                                    StyledText {
                                        anchors.centerIn: parent
                                        text: "2"
                                        font.pixelSize: 96
                                        font.family: Appearance.font.family.title
                                        color: Appearance.colors.colOnLayer0
                                        opacity: 0.08
                                    }
                                }

                                // Destination Nautilus on ws3 (slot 2)
                                Item {
                                    id: destNautilus
                                    x: card5.canvasW * 2 + card5.winLocalX
                                    y: card5.winLocalY
                                    width: card5.winW
                                    height: card5.winH

                                    Image {
                                        anchors.fill: parent
                                        source: card5.imageDir + "/files-documents.png"
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        asynchronous: true
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: destNautilus.width
                                                height: destNautilus.height
                                                radius: 8
                                            }
                                        }
                                    }

                                    // Dropped file — scale-in OutBack
                                    Item {
                                        x: card5.sidebarW + (card5.winW - card5.sidebarW) / 2 - width / 2
                                        y: 22 + (card5.winH - 22) * 0.45 - height / 2
                                        width: 52
                                        height: 68
                                        transformOrigin: Item.Center
                                        visible: opacity > 0.01
                                        opacity: card5.fileDropped ? 1 : 0
                                        scale:   card5.fileDropped ? 1 : 0.55
                                        Behavior on opacity { NumberAnimation { duration: 230 } }
                                        Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }

                                        Image {
                                            anchors.top: parent.top
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: 46
                                            height: 46
                                            source: card5.imageDir + "/generic-file.svg"
                                            sourceSize.width: 64
                                            sourceSize.height: 64
                                            smooth: true
                                            asynchronous: true
                                        }
                                        StyledText {
                                            anchors.bottom: parent.bottom
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: "notes.txt"
                                            font.pixelSize: 12
                                            color: "#FFFFFF"
                                        }
                                    }
                                }
                            }
                        }

                        // Drag ghost (file follows the cursor while picked up)
                        Item {
                            visible: card5.filePickedUp
                            x: card5.dragX - width / 2
                            y: card5.dragY - height / 2
                            width: 52
                            height: 68
                            opacity: 0.92
                            scale: card5.filePickedUp ? 1.08 : 1
                            transformOrigin: Item.Center
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            z: 4

                            Image {
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 46
                                height: 46
                                source: card5.imageDir + "/generic-file.svg"
                                sourceSize.width: 64
                                sourceSize.height: 64
                                smooth: true
                                asynchronous: true
                            }
                            StyledText {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "notes.txt"
                                font.pixelSize: 12
                                color: "#FFFFFF"
                            }
                        }

                        // Cursor cue
                        MaterialSymbol {
                            text: "arrow_selector_tool"
                            iconSize: 22 + 6 * card5.clickPulse
                            color: Appearance.colors.colOnLayer0
                            x: card5.cursorX - 4
                            y: card5.cursorY - 4
                            z: 5
                        }
                    }
                }
            }
        }

        // ── Animation timeline ────────────────────────────────────────
        // One loop ≈ 11s. Reset → grab file → drag up to right side of
        // pills → workspaces scroll ws1→ws2→ws3 → descend onto dest →
        // drop → pause → repeat.
        SequentialAnimation {
            id: demoCycle11
            running: card5.visible
            loops: Animation.Infinite

            ScriptAction {
                script: {
                    card5.currentStep = 0
                    card5.cursorX = card5.cursorParkX
                    card5.cursorY = card5.cursorParkY
                    card5.dragX = card5.fileMockX()
                    card5.dragY = card5.fileMockY()
                    card5.filePickedUp = false
                    card5.activeWs = 0
                    card5.barDragActive = false
                    card5.fileDropped = false
                    card5.clickPulse = 0
                }
            }
            PauseAnimation { duration: 700 }

            // Cursor approaches the file in the source Nautilus
            ParallelAnimation {
                NumberAnimation { target: card5; property: "cursorX"; to: card5.fileMockX(); duration: 700; easing.type: Easing.OutCubic }
                NumberAnimation { target: card5; property: "cursorY"; to: card5.fileMockY(); duration: 700; easing.type: Easing.OutCubic }
            }
            PauseAnimation { duration: 220 }

            // Pick up
            ScriptAction {
                script: {
                    card5.dragX = card5.fileMockX()
                    card5.dragY = card5.fileMockY()
                    card5.filePickedUp = true
                }
            }
            PauseAnimation { duration: 180 }

            // Drag up onto the bar pill — cursor lands on slot 8 (index 7,
            // right side). barDragActive flips on once the cursor reaches
            // the pill (the pill glows + dots fan into chevrons).
            ParallelAnimation {
                NumberAnimation { target: card5; property: "cursorX"; to: card5.barSlotCenterX(7); duration: 800; easing.type: Easing.InOutQuad }
                NumberAnimation { target: card5; property: "cursorY"; to: card5.barSlotCenterY; duration: 800; easing.type: Easing.InOutQuad }
                NumberAnimation { target: card5; property: "dragX"; to: card5.barSlotCenterX(7); duration: 800; easing.type: Easing.InOutQuad }
                NumberAnimation { target: card5; property: "dragY"; to: card5.barSlotCenterY; duration: 800; easing.type: Easing.InOutQuad }
                SequentialAnimation {
                    PauseAnimation { duration: 450 }
                    ScriptAction { script: card5.barDragActive = true }
                }
            }
            PauseAnimation { duration: 300 }

            // Scroll ws1 → ws2 → ws3
            PauseAnimation { duration: 480 }
            ScriptAction { script: card5.activeWs = 1 }
            PauseAnimation { duration: 480 }
            ScriptAction { script: card5.activeWs = 2 }
            PauseAnimation { duration: 500 }

            // Cursor + ghost descend onto the destination window. Glow
            // clears partway down as the cursor leaves the pill strip.
            ParallelAnimation {
                NumberAnimation { target: card5; property: "cursorX"; to: card5.destMockX(); duration: 850; easing.type: Easing.OutCubic }
                NumberAnimation { target: card5; property: "cursorY"; to: card5.destMockY(); duration: 850; easing.type: Easing.OutCubic }
                NumberAnimation { target: card5; property: "dragX"; to: card5.destMockX(); duration: 850; easing.type: Easing.OutCubic }
                NumberAnimation { target: card5; property: "dragY"; to: card5.destMockY(); duration: 850; easing.type: Easing.OutCubic }
                SequentialAnimation {
                    PauseAnimation { duration: 200 }
                    ScriptAction { script: card5.barDragActive = false }
                }
            }
            PauseAnimation { duration: 280 }

            // Drop on ws3 — ghost vanishes, file scales into the dest window
            ScriptAction {
                script: {
                    card5.filePickedUp = false
                    card5.fileDropped = true
                }
            }
            PauseAnimation { duration: 1800 }
        }
    }

    // ── Card 7: App Showcase (tabs version) ────────────────────────────
    // Combines Files / Settings / App Store into a single panel with
    // tab-style headers on the left column. Each tab's underline
    // doubles as a progress bar — it fills from 0 to full width over
    // sectionDuration, then snaps to the next tab.
    component Card7AppShowcaseTabs : Item {
        id: card7

        // State
        property int currentSection: 0
        property int currentImage: 0
        property real progressFraction: 0

        // Section content. Titles and bodies are the exact same strings
        // the standalone Files/Settings/App Store cards (Card6, Card9,
        // Card5) use, so this tabbed view reads identically to the
        // single-app pages.
        readonly property var sectionTabs: [
            Translation.tr("Files"),
            Translation.tr("Settings"),
            Translation.tr("App Store")
        ]
        readonly property var sectionTitles: [
            Translation.tr("Manage your files and downloads"),
            Translation.tr("Make it yours in Settings"),
            Translation.tr("Find new apps in the App Store")
        ]
        readonly property var sectionBodies: [
            Translation.tr("Open Files to browse your Home folder, Documents, Downloads, Pictures, and more. Drop any folder into the sidebar to bookmark it for quick access later."),
            Translation.tr("Settings is one place for everything you can tune — wallpaper, themes, what shows on the bar, workspace layout, keybinds, account info, OS updates, and system recovery. Tweak the small stuff or rebuild your workflow from scratch."),
            Translation.tr("Open the App Store to browse curated categories, search by name, and install — or uninstall — anything you find. It also keeps every installed app up to date for you.")
        ]
        readonly property var sectionImages: [
            ["files-home.png", "files-home-custom.png"],
            ["settings-1.png", "settings-2.png", "settings-3.png", "settings-4.png", "settings-5.png", "settings-6.png", "settings-7.png"],
            ["store-1.png", "store-2.png", "store-3.png"]
        ]
        readonly property var sectionIcons: [
            "system-file-manager.svg",
            "settings-icon.svg",
            "org.gnome.Software.svg"
        ]

        // Per-section timing. Each tab runs for as long as its
        // standalone card would: imageCount × imageCycleInterval. The
        // image-cycle interval also matches the standalone card, so
        // each screenshot rotation feels identical on a single tab
        // and on the merged view.
        //   Files     (Card6): 2 images × 4500ms =  9000ms
        //   Settings  (Card9): 7 images × 2500ms = 17500ms
        //   App Store (Card5): 3 images × 2400ms =  7200ms
        // Per-image intervals tuned so each section gets enough dwell
        // time on screen before auto-advancing. App Store has only 3
        // images, so its per-image interval is bumped to keep its
        // total section duration in line with the others.
        // Files     (2 images × 6750ms) = 13500ms
        // Settings  (7 images × 2750ms) = 19250ms
        // App Store (3 images × 4500ms) = 13500ms
        readonly property var sectionImageIntervals: [6750, 2750, 4500]
        readonly property var sectionDurations: [
            sectionImageIntervals[0] * sectionImages[0].length,
            sectionImageIntervals[1] * sectionImages[1].length,
            sectionImageIntervals[2] * sectionImages[2].length
        ]

        // Jump to a specific section in response to a tab click.
        // Stops the auto-cycle, swaps state, and restarts so the new
        // section runs for its full duration before auto-advancing.
        function selectSection(index) {
            if (index === card7.currentSection) return
            card7.currentSection = index
            card7.currentImage = 0
            card7.progressFraction = 0
            card7Cycle.restart()
            card7ImageTimer.restart()
        }

        // Mockup geometry — same as Card6/Card9/Card5
        readonly property int mockW: 600
        readonly property int mockH: 380
        readonly property int barW: 560
        readonly property int barH: 30
        readonly property int barX: (mockW - barW) / 2
        readonly property int barY: 12
        readonly property int storeY: 54
        readonly property int storeW: barW
        readonly property int storeX: barX
        readonly property int storeH: Math.round(storeW * 1034 / 1912)
        readonly property int iconSize: 78
        readonly property int iconLeftInset: 24
        readonly property int iconBottomInset: 28
        readonly property string imageDir:
            Quickshell.env("HOME") + "/.config/quickshell/ii/welcome-tutorial-images"

        // Bar internals — same geometry as Card5/6/9 so the bar
        // contents render identically when reproduced here.
        readonly property int barPillH: 22
        readonly property int barSlotW: 16
        readonly property int barSlotH: 16
        readonly property int barSlotR: 2
        readonly property int barIconSize: 10
        readonly property int barIndicatorInset: 1

        // Workspace state for the bar mock — each section pretends the
        // current workspace's primary app is the one being showcased,
        // matching what its standalone card (Card5/6/9) does.
        readonly property int currentWs: 0
        readonly property int totalWs: 10
        readonly property var sectionPrimaryApps: [
            "org.gnome.Nautilus",   // Files     (Card6)
            "mainstream-settings",  // Settings  (Card9) — matches hicolor icon
            "org.gnome.Software"    // App Store (Card5)
        ]
        function primaryAppFor(ws) {
            if (ws === currentWs) return sectionPrimaryApps[currentSection]
            const others = [
                [],                              // ws 0 — handled above
                ["spotify", "telegram"],
                ["org.gnome.Nautilus"],
                ["gimp", "vlc", "blender"],
                ["discord", "obs"]
            ]
            const list = others[ws] || []
            return list.length > 0 ? list[0] : ""
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 28

            ColumnLayout {
                Layout.minimumWidth: 280
                Layout.maximumWidth: 280
                Layout.preferredWidth: 280
                Layout.fillWidth: false
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignVCenter
                // Match Card5/6/9 so the title/body sit at the same Y
                // as the standalone cards instead of being pushed down
                // by the tab row.
                spacing: 12

                // Top section hosts the tab row at its bottom edge.
                // Fixed (non-fillHeight) so the whole stack — tabs,
                // title, body — sits higher in the column than a
                // standalone card with two fill-height spacers would.
                // The bottom fill-height spacer below the body
                // absorbs the freed space, pulling everything up to
                // align the tabs with the title position on the
                // preceding panel.
                Item {
                    Layout.fillHeight: false
                    Layout.preferredHeight: 130
                    Layout.fillWidth: true

                    // ── Tab row ──
                    // ConfigSelectionArray gives us the same look as
                    // BarConfig.qml's Corner style / Bar position
                    // selectors — joined pill buttons that highlight
                    // the active option. Selecting one calls
                    // selectSection() to jump to that tab and let it
                    // run for its full animation duration.
                    Item {
                        id: tabRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        implicitHeight: tabSelector.implicitHeight

                        ConfigSelectionArray {
                            id: tabSelector
                            anchors.horizontalCenter: parent.horizontalCenter
                            currentValue: card7.currentSection
                            onSelected: newValue => card7.selectSection(newValue)
                            options: [
                                { displayName: Translation.tr("Files"),     icon: "folder",       value: 0 },
                                { displayName: Translation.tr("Settings"),  icon: "settings",     value: 1 },
                                { displayName: Translation.tr("App Store"), icon: "shopping_bag", value: 2 }
                            ]
                        }
                    }
                }

                // ── Title (crossfades between sections) ──
                // Slot height matches Card6's natural 2-line title
                // (Files / App Store both wrap to 2 lines at huge
                // pixel size with the 280-wide column). The slot top
                // is the rendered title's top, so this keeps the
                // title at the same Y as the standalone cards.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    Repeater {
                        id: titleRepeater12
                        model: 3
                        delegate: StyledText {
                            required property int index
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: card7.sectionTitles[index]
                            font {
                                family: Appearance.font.family.title
                                pixelSize: Appearance.font.pixelSize.huge
                                variableAxes: Appearance.font.variableAxes.title
                            }
                            color: Appearance.colors.colOnLayer0
                            wrapMode: Text.WordWrap
                            opacity: index === card7.currentSection ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 250 } }
                        }
                    }
                }

                // ── Body (crossfades between sections) ──
                // Slot height matches Card6's natural body (Files wraps
                // to 5 lines at the normal pixel size with line-height
                // 1.35 ≈ 95px). The longer Settings/App Store bodies
                // overflow into the empty bottom-spacer area below,
                // which is visually empty anyway — and the title stays
                // aligned with the standalone cards regardless.
                //
                // The body's y is pulled up by however much the active
                // section's title is shorter than the 60-px title slot
                // — so Settings' 1-line title doesn't leave an awkward
                // empty line of space between its title and body.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 95
                    Repeater {
                        model: 3
                        delegate: StyledText {
                            required property int index
                            anchors.left: parent.left
                            anchors.right: parent.right
                            text: card7.sectionBodies[index]
                            textFormat: Text.RichText
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer0
                            opacity: index === card7.currentSection ? 0.85 : 0
                            wrapMode: Text.WordWrap
                            lineHeight: 1.35
                            // Slide up to absorb the gap left by a
                            // shorter title (e.g. Settings' 1-liner).
                            y: -Math.max(0, 60 - (titleRepeater12.itemAt(card7.currentSection)?.implicitHeight ?? 60))
                            Behavior on opacity { NumberAnimation { duration: 250 } }
                            Behavior on y { NumberAnimation { duration: 250 } }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }

            // Right: mockup
            Item {
                id: mockupHost12
                Layout.fillWidth: true
                Layout.fillHeight: true

                Item {
                    width: card7.mockW
                    height: card7.mockH
                    anchors.centerIn: parent
                    scale: Math.min(
                        1.0,
                        (mockupHost12.width  - 8) / width,
                        (mockupHost12.height - 8) / height
                    )

                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: "#0e0e12"
                        border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.6)
                        border.width: 1
                        clip: true

                        // ─── Bar at top — same layout as Card5/6/9, but
                        // the workspace icon swaps with the active tab.
                        Rectangle {
                            id: barFrame12
                            x: card7.barX
                            y: card7.barY
                            width: card7.barW
                            height: card7.barH
                            radius: card7.barH / 2
                            color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.45)
                            border.color: ColorUtils.transparentize(Appearance.colors.colOutline, 0.35)
                            border.width: 1
                            z: 2

                            ColumnLayout {
                                id: activeWindowText12
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 10
                                spacing: -3
                                StyledText {
                                    text: "Desktop"
                                    font.pixelSize: 7
                                    color: Appearance.colors.colSubtext
                                    opacity: 0.85
                                }
                                StyledText {
                                    text: "Workspace " + (card7.currentWs + 1)
                                    font.pixelSize: 9
                                    color: Appearance.colors.colOnLayer0
                                }
                            }

                            PillBg {
                                id: mediaPill12
                                anchors.left: activeWindowText12.right
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                height: card7.barPillH
                                width: mediaRow12.implicitWidth + 12
                                Row {
                                    id: mediaRow12
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Rectangle {
                                        width: 12; height: 12; radius: 6
                                        color: Appearance.m3colors.m3primary
                                        opacity: 0.9
                                        anchors.verticalCenter: parent.verticalCenter
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "music_note"
                                            iconSize: 9
                                            color: Appearance.m3colors.m3onPrimary
                                        }
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Subnautica 2 LAU…"
                                        font.pixelSize: 8
                                        color: Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                        width: 70
                                    }
                                }
                            }

                            PillBg {
                                id: workspacePill12
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                height: card7.barPillH
                                width: barWsStrip12.implicitWidth + 10
                                Item {
                                    id: barWsStrip12
                                    anchors.centerIn: parent
                                    implicitWidth: card7.barSlotW * card7.totalWs
                                    implicitHeight: card7.barSlotH

                                    AnimatedTabIndexPair {
                                        id: barIdxPair12
                                        index: card7.currentWs
                                    }

                                    Rectangle {
                                        z: 1
                                        readonly property real lo: Math.min(barIdxPair12.idx1, barIdxPair12.idx2)
                                        readonly property real hi: Math.max(barIdxPair12.idx1, barIdxPair12.idx2)
                                        x: lo * card7.barSlotW + card7.barIndicatorInset
                                        width: (hi - lo) * card7.barSlotW + card7.barSlotW - 2 * card7.barIndicatorInset
                                        height: card7.barSlotH - 2 * card7.barIndicatorInset
                                        y: card7.barIndicatorInset
                                        radius: height / 2
                                        color: Appearance.m3colors.m3primary
                                        opacity: 0.9
                                    }

                                    Row {
                                        z: 2
                                        anchors.fill: parent
                                        Repeater {
                                            model: card7.totalWs
                                            delegate: Item {
                                                required property int index
                                                width: card7.barSlotW
                                                height: card7.barSlotH
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: card7.barSlotR * 2
                                                    height: card7.barSlotR * 2
                                                    radius: width / 2
                                                    color: Appearance.colors.colOnLayer0
                                                    opacity: 0.35
                                                }
                                            }
                                        }
                                    }

                                    IconImage {
                                        z: 3
                                        readonly property string primary: card7.primaryAppFor(card7.currentWs)
                                        visible: primary !== ""
                                        implicitSize: card7.barIconSize
                                        x: card7.currentWs * card7.barSlotW + (card7.barSlotW - implicitSize) / 2
                                        y: (card7.barSlotH - implicitSize) / 2
                                        source: primary !== ""
                                            ? Quickshell.iconPath(primary, "image-missing")
                                            : ""
                                    }
                                }
                            }

                            PillBg {
                                id: sysTrayPill12
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 10
                                height: card7.barPillH
                                width: trayRow12.implicitWidth + 12
                                Row {
                                    id: trayRow12
                                    anchors.centerIn: parent
                                    spacing: 6
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "volume_up"; iconSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "wifi"; iconSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "settings"; iconSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }
                            }

                            Row {
                                anchors.right: sysTrayPill12.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 12
                                spacing: 4
                                PillBg {
                                    height: card7.barPillH
                                    width: clockText12.implicitWidth + 16
                                    anchors.verticalCenter: parent.verticalCenter
                                    StyledText {
                                        id: clockText12
                                        anchors.centerIn: parent
                                        text: "12:53"
                                        font.pixelSize: 10
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }
                                PillBg {
                                    height: card7.barPillH
                                    width: weatherRow12.implicitWidth + 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    Row {
                                        id: weatherRow12
                                        anchors.centerIn: parent
                                        spacing: 2
                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "cloud"
                                            iconSize: 11
                                            color: Appearance.colors.colOnLayer1
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "74°"
                                            font.pixelSize: 9
                                            color: Appearance.colors.colOnLayer1
                                        }
                                    }
                                }
                            }
                        }

                        // Screenshot window — nested Repeater: section → images
                        Item {
                            id: appWindow12
                            x: card7.storeX
                            y: card7.storeY
                            width: card7.storeW
                            height: card7.storeH
                            z: 3

                            Repeater {
                                model: 3
                                delegate: Item {
                                    required property int index
                                    readonly property int sectionIdx: index
                                    anchors.fill: parent
                                    visible: opacity > 0.01
                                    opacity: card7.currentSection === sectionIdx ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 280 } }

                                    Repeater {
                                        model: card7.sectionImages[sectionIdx]
                                        delegate: Image {
                                            required property int index
                                            required property string modelData
                                            anchors.fill: parent
                                            source: card7.imageDir + "/" + modelData
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            asynchronous: true
                                            opacity: card7.currentImage === index ? 1 : 0
                                            Behavior on opacity {
                                                NumberAnimation { duration: 380; easing.type: Easing.InOutQuad }
                                            }
                                            layer.enabled: true
                                            layer.effect: OpacityMask {
                                                maskSource: Rectangle {
                                                    width: appWindow12.width
                                                    height: appWindow12.height
                                                    radius: 10
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // App icon — crossfades between sections
                        Repeater {
                            model: 3
                            delegate: Image {
                                required property int index
                                x: card7.storeX + card7.iconLeftInset
                                y: card7.storeY + card7.storeH - card7.iconSize - card7.iconBottomInset
                                width: card7.iconSize
                                height: card7.iconSize
                                sourceSize.width: card7.iconSize * 2
                                sourceSize.height: card7.iconSize * 2
                                source: card7.imageDir + "/" + card7.sectionIcons[index]
                                smooth: true
                                asynchronous: true
                                z: 5
                                visible: opacity > 0.01
                                opacity: index === card7.currentSection ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 280 } }
                                layer.enabled: true
                                layer.effect: DropShadow {
                                    horizontalOffset: 0
                                    verticalOffset: 8
                                    radius: 26
                                    samples: 53
                                    color: "#cc000000"
                                }
                            }
                        }
                    }
                }
            }
        }

        // Section progress + advance — single animation drives the
        // tab underline AND triggers the section switch when full.
        // Duration follows the currently-selected section so each tab
        // runs as long as its standalone Card6/Card9/Card5 version
        // would, instead of a fixed 8s for all three.
        SequentialAnimation {
            id: card7Cycle
            running: card7.visible
            loops: Animation.Infinite

            ScriptAction { script: card7.progressFraction = 0 }
            NumberAnimation {
                target: card7; property: "progressFraction"
                to: 1
                duration: card7.sectionDurations[card7.currentSection]
                easing.type: Easing.Linear
            }
            ScriptAction {
                script: {
                    card7.currentSection = (card7.currentSection + 1) % 3
                    card7.currentImage = 0
                }
            }
        }

        // Cycle images within each section. Interval matches the
        // standalone card's image-cycle interval so each screenshot
        // rotation feels the same on a single tab and on the merged
        // view.
        Timer {
            id: card7ImageTimer
            interval: card7.sectionImageIntervals[card7.currentSection]
            running: card7.visible
            repeat: true
            onTriggered: {
                const count = card7.sectionImages[card7.currentSection].length
                card7.currentImage = (card7.currentImage + 1) % count
            }
        }

        onVisibleChanged: if (visible) {
            currentSection = 0
            currentImage = 0
            progressFraction = 0
        }
    }

    // ── Card 0: First-run setup ──────────────────────────────────────────
    // Settings-style page that runs before the feature tour. Mirrors the
    // most-used knobs from Settings → welcome / Layouts / Interface so the
    // user can tune the basics once, before the tutorial starts walking
    // them through the bar, dock, workspaces, etc.
    component Card0Setup : Item {
        id: card0

        // ── Window-Layout state ─────────────────────────────────────────
        // Mirrors what `hyprctl getoption general:layout` reports. We only
        // expose the four "real" tiling layouts here — float and
        // per-workspace are handled elsewhere in Settings → Layouts.
        property string currentLayout: "dwindle"
        readonly property string hyprlandConf: Quickshell.env("HOME") + "/.config/hypr/hyprland.lua"
        readonly property string hyprGeneralConf: Quickshell.env("HOME") + "/.config/hypr/hyprland/general.lua"

        Component.onCompleted: {
            layoutProc.running = true
            TitleBars.load()
        }

        Process {
            id: layoutProc
            command: ["hyprctl", "getoption", "general:layout"]
            stdout: SplitParser {
                onRead: data => {
                    const m = data.match(/str:\s*(\S+)/)
                    if (m) {
                        const l = m[1].toLowerCase()
                        if (l === "dwindle" || l === "master" || l === "scrolling" || l === "monocle")
                            card0.currentLayout = l
                    }
                }
            }
        }

        // Step 2 — fire the live `hyprctl keyword` after the conf rewrite
        // finished, so the in-memory layout matches the file on disk.
        Process { id: applyLayoutLiveProc }

        // Step 1 — rewrite hyprland/general.lua's `general = { layout = "..." }`
        // (and comment out the per-workspace tryRequire so we definitely
        // leave per-workspace mode), then chain into step 2.
        Process {
            id: editLayoutProc
            property string pendingLayout: ""
            onExited: {
                if (pendingLayout !== "") {
                    applyLayoutLiveProc.command = ["hyprctl", "keyword", "general:layout", pendingLayout]
                    applyLayoutLiveProc.running = false
                    applyLayoutLiveProc.running = true
                    pendingLayout = ""
                }
            }
        }

        function applyLayout(name) {
            card0.currentLayout = name
            const py =
                "import sys, re\n" +
                "hy_lua, gen_lua, layout = sys.argv[1], sys.argv[2], sys.argv[3]\n" +
                "text = open(hy_lua).read()\n" +
                "text = re.sub(r'(?m)^(\\s*)(?!--)(tryRequire\\(\"workspaces\"\\))', r'\\1-- \\2', text)\n" +
                "open(hy_lua, 'w').write(text)\n" +
                "text = open(gen_lua).read()\n" +
                "new_text, count = re.subn(r'(^[ \\t]*general\\s*=\\s*\\{[^}]*?layout\\s*=\\s*\")[^\"]+(\")', r'\\g<1>' + layout + r'\\g<2>', text, count=1, flags=re.S|re.M)\n" +
                "if count == 0:\n" +
                "    new_text = re.sub(r'(?m)^([ \\t]*)general(\\s*=\\s*\\{)', r'\\1general\\2\\n        layout = \"' + layout + r'\",', text, count=1)\n" +
                "open(gen_lua, 'w').write(new_text)\n"
            editLayoutProc.pendingLayout = name
            editLayoutProc.command = ["python3", "-c", py, card0.hyprlandConf, card0.hyprGeneralConf, name]
            editLayoutProc.running = false
            editLayoutProc.running = true
        }

        // Random-wallpaper helper (matches welcome.qml)
        Process {
            id: konachanWallProc
            command: ["bash", "-c", Quickshell.shellPath("scripts/colors/random/random_konachan_wall.sh")]
        }

        // Re-runs the wallpaper-switch script in --noswitch mode to
        // re-derive theme colors from the current wallpaper when the
        // palette type changes. Mirrors QuickConfig.qml's themeApplyProc
        // + applyTheme() helper.
        Process {
            id: themeApplyProc
            onExited: MaterialThemeLoader.reapplyTheme()
        }
        function applyTheme(args) {
            if (themeApplyProc.running) return
            themeApplyProc.command = ["bash", "-c", `${Directories.wallpaperSwitchScriptPath} ${args}`]
            themeApplyProc.running = true
        }

        // ── Layout ──────────────────────────────────────────────────────
        RowLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 14

            // ── LEFT COLUMN: Language / Bar / Style & Wallpaper ─────────
            // 5:6 split with the right column (~45% / ~55%). The right
            // column needs slightly more room for the Window Layout
            // section's two side-by-side cards; the left column's
            // content (a combo, position/style pills, and Light/Dark +
            // wallpaper buttons) fits comfortably in the narrower half.
            // The inner Window Layout cards still use a 1:1 preferred
            // width so they stay uniform with each other.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 5
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignTop
                spacing: 8

                // ── Language ────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    implicitHeight: langCol.implicitHeight + 24

                    ColumnLayout {
                        id: langCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        RowLayout {
                            spacing: 8
                            MaterialSymbol { text: "language"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                            StyledText {
                                text: Translation.tr("Language")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                        }

                        StyledComboBox {
                            id: langCombo
                            Layout.fillWidth: true
                            textRole: "displayName"
                            buttonIcon: "language"
                            model: {
                                const opts = [{ displayName: Translation.tr("Auto (System)"), value: "auto", icon: "language" }]
                                for (const l of Translation.allAvailableLanguages) {
                                    opts.push({ displayName: l, value: l, icon: "language" })
                                }
                                return opts
                            }
                            currentIndex: {
                                const idx = model.findIndex(item => item.value === Config.options.language.ui)
                                return idx !== -1 ? idx : 0
                            }
                            onActivated: index => {
                                Config.options.language.ui = model[index].value
                            }
                        }
                    }
                }

                // ── Style & Wallpaper ───────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    implicitHeight: styleCol.implicitHeight + 24

                    ColumnLayout {
                        id: styleCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        RowLayout {
                            spacing: 8
                            MaterialSymbol { text: "format_paint"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                            StyledText {
                                text: Translation.tr("Style, wallpaper, & colors")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                        }

                        // Light/Dark — compact two-button row. The
                        // full-fat LightDarkPreferenceButton from welcome.qml
                        // is ~260px wide and won't fit two-across in this
                        // column.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: [
                                    { mode: false, icon: "light_mode", label: Translation.tr("Light") },
                                    { mode: true,  icon: "dark_mode",  label: Translation.tr("Dark")  }
                                ]
                                delegate: RippleButton {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 38
                                    buttonRadius: Appearance.rounding.small
                                    toggled: Appearance.m3colors.darkmode === modelData.mode
                                    onClicked: {
                                        Quickshell.execDetached(["bash", "-c",
                                            `${Directories.wallpaperSwitchScriptPath} --mode ${modelData.mode ? "dark" : "light"} --noswitch`])
                                    }
                                    contentItem: RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        MaterialSymbol {
                                            text: modelData.icon
                                            iconSize: 18
                                            color: toggled
                                                ? Appearance.m3colors.m3onPrimary
                                                : Appearance.colors.colOnSecondaryContainer
                                        }
                                        StyledText {
                                            text: modelData.label
                                            color: toggled
                                                ? Appearance.m3colors.m3onPrimary
                                                : Appearance.colors.colOnSecondaryContainer
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            // Random Konachan wallpaper — visible iff weeb=Yes,
                            // matching welcome.qml's policy gating.
                            RippleButtonWithIcon {
                                Layout.fillWidth: true
                                visible: Config.options.policies.weeb === 1
                                buttonRadius: Appearance.rounding.small
                                materialIcon: "ifl"
                                mainText: konachanWallProc.running
                                    ? Translation.tr("Be patient...")
                                    : Translation.tr("Random: Konachan")
                                onClicked: {
                                    konachanWallProc.running = true
                                }
                                StyledToolTip {
                                    text: Translation.tr("Random SFW Anime wallpaper from Konachan\nImage is saved to ~/Pictures/Wallpapers")
                                }
                            }
                            RippleButtonWithIcon {
                                Layout.fillWidth: true
                                buttonRadius: Appearance.rounding.small
                                materialIcon: "wallpaper"
                                onClicked: {
                                    Quickshell.execDetached([`${Directories.wallpaperSwitchScriptPath}`])
                                }
                                // Mirrors welcome.qml's "Choose file"
                                // button — surfaces the Super+W keybind
                                // alongside the label so users know they
                                // can also open the picker via keyboard.
                                // Trailing fillWidth spacer pushes both
                                // the label and the chips to the left so
                                // they sit flush against the icon.
                                mainContentComponent: Component {
                                    RowLayout {
                                        spacing: 10
                                        StyledText {
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            text: Translation.tr("Choose wallpaper")
                                            color: Appearance.colors.colOnSecondaryContainer
                                        }
                                        RowLayout {
                                            spacing: 3
                                            KeyboardKey { key: "󰖳" }
                                            StyledText {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: "+"
                                            }
                                            KeyboardKey { key: "W" }
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                                }
                                StyledToolTip {
                                    text: Translation.tr("Pick wallpaper image on your system")
                                }
                            }
                        }

                        // Material colour palette — same options as
                        // Settings → Quick. Selecting one writes
                        // Config.options.appearance.palette.type and
                        // (debounced 150ms) re-derives the theme from
                        // the current wallpaper with the new palette.
                        ConfigSelectionArray {
                            Layout.fillWidth: true
                            currentValue: Config.options.appearance.palette.type
                            onSelected: newValue => {
                                Config.options.appearance.palette.type = newValue
                                paletteApplyTimer.restart()
                            }

                            Timer {
                                id: paletteApplyTimer
                                interval: 150
                                repeat: false
                                onTriggered: card0.applyTheme("--noswitch")
                            }
                            options: [
                                { value: "auto",              displayName: Translation.tr("Auto") },
                                { value: "scheme-content",    displayName: Translation.tr("Content") },
                                { value: "scheme-expressive", displayName: Translation.tr("Expressive") },
                                { value: "scheme-fidelity",   displayName: Translation.tr("Fidelity") },
                                { value: "scheme-fruit-salad",displayName: Translation.tr("Fruit Salad") },
                                { value: "scheme-monochrome", displayName: Translation.tr("Monochrome") },
                                { value: "scheme-neutral",    displayName: Translation.tr("Neutral") },
                                { value: "scheme-rainbow",    displayName: Translation.tr("Rainbow") },
                                { value: "scheme-tonal-spot", displayName: Translation.tr("Tonal Spot") }
                            ]
                        }
                    }
                }

                // ── Bar ─────────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    implicitHeight: barCol.implicitHeight + 24

                    ColumnLayout {
                        id: barCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        RowLayout {
                            spacing: 8
                            MaterialSymbol { text: "screenshot_monitor"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                            StyledText {
                                text: Translation.tr("Bar")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            StyledText {
                                text: Translation.tr("Bar position")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                            ConfigSelectionArray {
                                Layout.fillWidth: true
                                currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                                onSelected: newValue => {
                                    Config.options.bar.bottom = (newValue & 1) !== 0
                                    Config.options.bar.vertical = (newValue & 2) !== 0
                                }
                                options: [
                                    { displayName: Translation.tr("Top"),    icon: "arrow_upward",    value: 0 },
                                    { displayName: Translation.tr("Left"),   icon: "arrow_back",      value: 2 },
                                    { displayName: Translation.tr("Bottom"), icon: "arrow_downward",  value: 1 },
                                    { displayName: Translation.tr("Right"),  icon: "arrow_forward",   value: 3 }
                                ]
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            StyledText {
                                text: Translation.tr("Bar style")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                            ConfigSelectionArray {
                                Layout.fillWidth: true
                                currentValue: Config.options.bar.cornerStyle
                                onSelected: newValue => {
                                    Config.options.bar.cornerStyle = newValue
                                }
                                options: [
                                    { displayName: Translation.tr("Hug"),   icon: "line_curve",  value: 0 },
                                    { displayName: Translation.tr("Float"), icon: "page_header", value: 1 },
                                    { displayName: Translation.tr("Rect"),  icon: "toolbar",     value: 2 }
                                ]
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }

            // ── RIGHT COLUMN: Window Layout / Left Hot Corner ───────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 6
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignTop
                spacing: 8

                // ── Window Layout ───────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    implicitHeight: winLayoutCol.implicitHeight + 24

                    ColumnLayout {
                        id: winLayoutCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        RowLayout {
                            spacing: 8
                            MaterialSymbol { text: "view_quilt"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                            StyledText {
                                text: Translation.tr("Window Layout")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                        }

                        // 50/50 split — left half is the layout picker with
                        // a live picture preview, right half is the title-bars
                        // mockup with its toggle below. Both columns put the
                        // picture on top and the control underneath, matching
                        // the Settings → Layouts cards. Both halves get the
                        // same Layout.preferredWidth: without it the combo
                        // box's "Dwindle (default)" + chevron has a wider
                        // implicit width than the switch and the fillWidth
                        // split goes uneven.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            // Layout picker: picture + dropdown below
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.alignment: Qt.AlignTop
                                spacing: 6

                                // Picture preview — one mockup per layout,
                                // toggled visible by currentLayout. These
                                // mockups are lifted 1:1 from Settings →
                                // Layouts (LayoutsConfig.qml) so the previews
                                // look identical to the picker cards there.
                                // The `sel` flag on each LayoutsConfig
                                // MouseArea becomes
                                // `card0.currentLayout === "..."` here.
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 130
                                    radius: Appearance.rounding.normal
                                    color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.1)
                                    border.width: 2
                                    border.color: Appearance.colors.colPrimary

                                    // Dwindle
                                    Item {
                                        visible: card0.currentLayout === "dwindle"
                                        anchors { fill: parent; margins: 10 }
                                        Rectangle {
                                            x: 0; y: 0; width: parent.width * 0.54; height: parent.height
                                            radius: 3; color: Appearance.colors.colLayer3
                                            border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                            Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2
                                                Rectangle { x: 3; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 4; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.35 }
                                            }
                                            Column { x: 7; y: 15; spacing: 4
                                                Repeater { model: [38, 28, 40, 24]
                                                    Rectangle { width: modelData; height: 5; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.22 }
                                                }
                                            }
                                            StyledText { anchors { right: parent.right; bottom: parent.bottom; margins: 5 }
                                                text: "1"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                        }
                                        Rectangle {
                                            x: parent.width * 0.54 + 3; y: 0
                                            width: parent.width * 0.46 - 3; height: parent.height * 0.5 - 2
                                            radius: 3; color: Appearance.colors.colLayer3
                                            border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                            Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2 }
                                            StyledText { anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                                                text: "2"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                        }
                                        Rectangle {
                                            x: parent.width * 0.54 + 3; y: parent.height * 0.5 + 2
                                            width: (parent.width * 0.46 - 3) * 0.54; height: parent.height * 0.5 - 2
                                            radius: 3; color: Appearance.colors.colLayer3
                                            border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                            Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2 }
                                            StyledText { anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                                                text: "3"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                        }
                                        Rectangle {
                                            x: parent.width * 0.54 + 3 + (parent.width * 0.46 - 3) * 0.54 + 2
                                            y: parent.height * 0.5 + 2
                                            width: (parent.width * 0.46 - 3) * 0.46 - 2; height: parent.height * 0.5 - 2
                                            radius: 3; color: Appearance.colors.colLayer3
                                            border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                            Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2 }
                                            StyledText { anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                                                text: "4"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                        }
                                    }

                                    // Master
                                    Item {
                                        visible: card0.currentLayout === "master"
                                        anchors { fill: parent; margins: 10 }
                                        Rectangle {
                                            x: 0; y: 0; width: parent.width * 0.57; height: parent.height
                                            radius: 3
                                            color: card0.currentLayout === "master" ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.08) : Appearance.colors.colLayer3
                                            border.width: 1
                                            border.color: card0.currentLayout === "master" ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.5) : Appearance.colors.colOutlineVariant
                                            Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2
                                                Rectangle { x: 3; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 4; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.35 }
                                            }
                                            Column { x: 7; y: 15; spacing: 4
                                                Repeater { model: [38, 26, 42, 20, 36]
                                                    Rectangle { width: modelData; height: 5; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.22 }
                                                }
                                            }
                                            StyledText { anchors { right: parent.right; bottom: parent.bottom; margins: 5 }
                                                text: "M"; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext; opacity: 0.45 }
                                        }
                                        Rectangle {
                                            x: parent.width * 0.57 + 3; y: 0
                                            width: parent.width * 0.43 - 3; height: parent.height / 3 - 2
                                            radius: 3; color: Appearance.colors.colLayer3
                                            border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                            Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2 }
                                        }
                                        Rectangle {
                                            x: parent.width * 0.57 + 3; y: parent.height / 3 + 1
                                            width: parent.width * 0.43 - 3; height: parent.height / 3 - 2
                                            radius: 3; color: Appearance.colors.colLayer3
                                            border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                            Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2 }
                                        }
                                        Rectangle {
                                            x: parent.width * 0.57 + 3; y: parent.height * 2 / 3 + 2
                                            width: parent.width * 0.43 - 3; height: parent.height / 3 - 2
                                            radius: 3; color: Appearance.colors.colLayer3
                                            border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                            Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2 }
                                        }
                                    }

                                    // Scrolling
                                    Item {
                                        visible: card0.currentLayout === "scrolling"
                                        anchors { fill: parent; margins: 10 }
                                        clip: true
                                        Rectangle {
                                            x: -18; y: 4; width: 24; height: parent.height - 8
                                            radius: 3; opacity: 0.45; color: Appearance.colors.colLayer3
                                            border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                        }
                                        Row {
                                            x: 10; y: 0; width: parent.width - 14; height: parent.height; spacing: 4
                                            Repeater {
                                                model: 3
                                                Rectangle {
                                                    width: (parent.width - 8) / 3; height: parent.height
                                                    radius: 3; color: Appearance.colors.colLayer3
                                                    border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                                    Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2
                                                        Rectangle { x: 3; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 4; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.3 }
                                                    }
                                                    Column { x: 5; y: 14; spacing: 3
                                                        Repeater { model: [20, 14, 22, 12]
                                                            Rectangle { width: modelData; height: 4; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.22 }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        Rectangle {
                                            x: parent.width - 6; y: 4; width: 20; height: parent.height - 8
                                            radius: 3; opacity: 0.5; color: Appearance.colors.colLayer3
                                            border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                        }
                                        MaterialSymbol {
                                            x: -2; anchors.verticalCenter: parent.verticalCenter
                                            text: "chevron_left"; iconSize: 16; z: 3
                                            color: card0.currentLayout === "scrolling" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext; opacity: 0.75
                                        }
                                        MaterialSymbol {
                                            anchors.right: parent.right; anchors.rightMargin: -2
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "chevron_right"; iconSize: 16; z: 3
                                            color: card0.currentLayout === "scrolling" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext; opacity: 0.75
                                        }
                                    }

                                    // Monocle
                                    Item {
                                        visible: card0.currentLayout === "monocle"
                                        anchors { fill: parent; margins: 10 }
                                        Rectangle {
                                            x: 10; y: 8; width: parent.width - 20; height: parent.height - 18
                                            radius: 3; opacity: 0.38; color: Appearance.colors.colLayer3
                                            border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                        }
                                        Rectangle {
                                            x: 5; y: 4; width: parent.width - 10; height: parent.height - 10
                                            radius: 3; opacity: 0.65; color: Appearance.colors.colLayer3
                                            border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                        }
                                        Rectangle {
                                            x: 0; y: 0; width: parent.width; height: parent.height
                                            radius: 3; color: Appearance.colors.colLayer3
                                            border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                            Rectangle { width: parent.width; height: 9; radius: 2; color: Appearance.colors.colLayer2
                                                Rectangle { x: 3; anchors.verticalCenter: parent.verticalCenter; width: 4; height: 4; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.35 }
                                            }
                                            Column { x: 8; y: 15; spacing: 4
                                                Repeater { model: [55, 38, 60, 28, 50]
                                                    Rectangle { width: modelData; height: 5; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.22 }
                                                }
                                            }
                                            Row {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                                                spacing: 5
                                                Repeater {
                                                    model: 4
                                                    Rectangle {
                                                        width: index === 0 ? 16 : 6; height: 4; radius: 2
                                                        color: index === 0 ? (card0.currentLayout === "monocle" ? Appearance.colors.colPrimary : Appearance.colors.colSubtext) : Appearance.colors.colSubtext
                                                        opacity: index === 0 ? 0.85 : 0.3
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                StyledComboBox {
                                    Layout.fillWidth: true
                                    textRole: "displayName"
                                    model: [
                                        { displayName: Translation.tr("Dwindle (default)"), value: "dwindle",   icon: "view_quilt"     },
                                        { displayName: Translation.tr("Master"),            value: "master",    icon: "splitscreen_right" },
                                        { displayName: Translation.tr("Scrolling"),         value: "scrolling", icon: "view_day"       },
                                        { displayName: Translation.tr("Monocle"),           value: "monocle",   icon: "crop_square"    }
                                    ]
                                    currentIndex: {
                                        const idx = model.findIndex(item => item.value === card0.currentLayout)
                                        return idx !== -1 ? idx : 0
                                    }
                                    onActivated: index => {
                                        card0.applyLayout(model[index].value)
                                    }
                                }

                                // Per-layout description — the same one-liner
                                // each LayoutsConfig picker card shows under
                                // its title/radio row. Swaps with the combo
                                // selection so the user knows what the
                                // picture is showing.
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 4
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                    wrapMode: Text.WordWrap
                                    text: {
                                        switch (card0.currentLayout) {
                                        case "dwindle":   return Translation.tr("Each new window splits the last in half")
                                        case "master":    return Translation.tr("One main window with a side stack")
                                        case "scrolling": return Translation.tr("Horizontally scrollable window columns")
                                        case "monocle":   return Translation.tr("One focused fullscreen window at a time")
                                        default: return ""
                                        }
                                    }
                                }
                            }

                            // Title Bars: mockup + toggle below. Lifted
                            // 1:1 from Settings → Layouts (the titleBarCard
                            // block in LayoutsConfig.qml). The mockup
                            // includes the same window-control circles,
                            // menu-indicator dot+bar, and content-line
                            // Repeaters as the Settings card so the two
                            // surfaces look identical.
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.alignment: Qt.AlignTop
                                spacing: 6

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: 130
                                    radius: Appearance.rounding.normal
                                    color: TitleBars.enabled ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.1) : Appearance.colors.colLayer2
                                    border.width: TitleBars.enabled ? 2 : 1
                                    border.color: TitleBars.enabled ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

                                    Item {
                                        anchors { fill: parent; margins: 10 }

                                        // Dwindle-style layout but with prominent title bars
                                        Rectangle {
                                            x: 0; y: 0; width: parent.width * 0.54; height: parent.height
                                            radius: 3; color: Appearance.colors.colLayer3
                                            border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                            Rectangle {
                                                width: parent.width; height: 14; radius: 2
                                                color: TitleBars.enabled ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.18) : Appearance.colors.colLayer2
                                                border.width: TitleBars.enabled ? 1 : 0
                                                border.color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.3)
                                                Row {
                                                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 4 }
                                                    spacing: 2
                                                    Rectangle { width: 3; height: 3; radius: 1.5; color: Appearance.colors.colSubtext; opacity: 0.5 }
                                                    Rectangle { width: 20; height: 3; radius: 1.5; color: Appearance.colors.colSubtext; opacity: 0.35 }
                                                }
                                                Row {
                                                    anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 4 }
                                                    spacing: 3
                                                    Repeater { model: 3
                                                        Rectangle { width: 5; height: 5; radius: 2.5; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                                    }
                                                }
                                            }
                                            Column { x: 7; y: 20; spacing: 4
                                                Repeater { model: [38, 28, 40, 24]
                                                    Rectangle { width: modelData; height: 5; radius: 2; color: Appearance.colors.colSubtext; opacity: 0.22 }
                                                }
                                            }
                                        }
                                        Rectangle {
                                            x: parent.width * 0.54 + 3; y: 0
                                            width: parent.width * 0.46 - 3; height: parent.height * 0.5 - 2
                                            radius: 3; color: Appearance.colors.colLayer3
                                            border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                            Rectangle {
                                                width: parent.width; height: 14; radius: 2
                                                color: TitleBars.enabled ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.18) : Appearance.colors.colLayer2
                                                border.width: TitleBars.enabled ? 1 : 0
                                                border.color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.3)
                                                Row {
                                                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 4 }
                                                    spacing: 2
                                                    Rectangle { width: 3; height: 3; radius: 1.5; color: Appearance.colors.colSubtext; opacity: 0.5 }
                                                    Rectangle { width: 14; height: 3; radius: 1.5; color: Appearance.colors.colSubtext; opacity: 0.35 }
                                                }
                                                Row {
                                                    anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 4 }
                                                    spacing: 3
                                                    Repeater { model: 3
                                                        Rectangle { width: 5; height: 5; radius: 2.5; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                                    }
                                                }
                                            }
                                        }
                                        Rectangle {
                                            x: parent.width * 0.54 + 3; y: parent.height * 0.5 + 2
                                            width: parent.width * 0.46 - 3; height: parent.height * 0.5 - 2
                                            radius: 3; color: Appearance.colors.colLayer3
                                            border.width: 1; border.color: Appearance.colors.colOutlineVariant
                                            Rectangle {
                                                width: parent.width; height: 14; radius: 2
                                                color: TitleBars.enabled ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.18) : Appearance.colors.colLayer2
                                                border.width: TitleBars.enabled ? 1 : 0
                                                border.color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.3)
                                                Row {
                                                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 4 }
                                                    spacing: 2
                                                    Rectangle { width: 3; height: 3; radius: 1.5; color: Appearance.colors.colSubtext; opacity: 0.5 }
                                                    Rectangle { width: 14; height: 3; radius: 1.5; color: Appearance.colors.colSubtext; opacity: 0.35 }
                                                }
                                                Row {
                                                    anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 4 }
                                                    spacing: 3
                                                    Repeater { model: 3
                                                        Rectangle { width: 5; height: 5; radius: 2.5; color: Appearance.colors.colSubtext; opacity: 0.4 }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Toggle centered below the card. Driven
                                // by the TitleBars singleton so this and
                                // Settings → Interface stay in sync.
                                ConfigSwitch {
                                    Layout.alignment: Qt.AlignHCenter
                                    buttonIcon: "title"
                                    text: Translation.tr("Title Bars")
                                    checked: TitleBars.enabled
                                    animateChanges: TitleBars.enabledLoaded
                                    onCheckedChanged: TitleBars.setEnabled(checked)
                                    StyledToolTip {
                                        text: Translation.tr("Show title bars on windows")
                                    }
                                }

                                // Description below the switch — pulls the
                                // same one-liner the LayoutsConfig switch's
                                // tooltip uses. Matches the layout-picker
                                // description on the left so both cards
                                // hold the same total height.
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 4
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                    wrapMode: Text.WordWrap
                                    text: Translation.tr("Show title bars on windows")
                                }
                            }
                        }
                    }
                }

                // ── Left Hot Corner ─────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    implicitHeight: hotCornerCol.implicitHeight + 24

                    ColumnLayout {
                        id: hotCornerCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4

                        RowLayout {
                            spacing: 8
                            MaterialSymbol { text: "ads_click"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                            StyledText {
                                text: Translation.tr("Left Hot Corner")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                        }

                        // Ripple animation switch — hidden when corner is
                        // off, matching Settings → Interface.
                        ConfigSwitch {
                            Layout.fillWidth: true
                            visible: Config.options.bar.hotCorners.trigger !== "off"
                            buttonIcon: "blur_circular"
                            text: Translation.tr("Ripple Animation")
                            checked: Config.options.bar.hotCorners.animationEnabled
                            onCheckedChanged: {
                                if (checked === Config.options.bar.hotCorners.animationEnabled) return
                                Config.options.bar.hotCorners.animationEnabled = checked
                            }
                        }

                        // Trigger overview combo — same layout/padding
                        // as Settings → Interface so the icon lines up
                        // with the Ripple Animation switch's icon above
                        // (ConfigSwitch wraps in a RippleButton that has
                        // ~6-8px of internal padding before the icon — a
                        // bare RowLayout doesn't, so it needs explicit
                        // left/right margins to match).
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8
                            spacing: 4
                            OptionalMaterialSymbol {
                                icon: "drag_click"
                                Layout.alignment: Qt.AlignVCenter
                            }
                            StyledText {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: 6
                                text: Translation.tr("Trigger overview")
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledComboBox {
                                textRole: "displayName"
                                Layout.fillWidth: false
                                Layout.preferredWidth: 220
                                model: [
                                    { displayName: Translation.tr("Off"),                icon: "block",     value: "off" },
                                    { displayName: Translation.tr("Default Overview"),   icon: "grid_view", value: "default" },
                                    { displayName: Translation.tr("Scrolling Overview"), icon: "view_day",  value: "scrolloverview" }
                                ]
                                currentIndex: {
                                    const idx = model.findIndex(item => item.value === Config.options.bar.hotCorners.trigger)
                                    return idx !== -1 ? idx : 0
                                }
                                onActivated: index => {
                                    Config.options.bar.hotCorners.trigger = model[index].value
                                }
                            }
                        }
                    }
                }

                // ── Usage docs ──────────────────────────────────────────
                // Mirrors welcome.qml's Info + Useless-buttons sections
                // — quick links to the keybind cheatsheet, the project
                // wiki, the repo, and the sponsor link. Donate is the
                // same target as welcome.qml's "Funny number" button.
                Rectangle {
                    Layout.fillWidth: true
                    color: Appearance.colors.colLayer1
                    radius: Appearance.rounding.normal
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    implicitHeight: usageCol.implicitHeight + 24

                    ColumnLayout {
                        id: usageCol
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        RowLayout {
                            spacing: 8
                            MaterialSymbol { text: "info"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                            StyledText {
                                text: Translation.tr("Info")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 5

                            RippleButtonWithIcon {
                                materialIcon: "keyboard_alt"
                                onClicked: {
                                    Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "cheatsheet", "toggle"])
                                }
                                mainContentComponent: Component {
                                    RowLayout {
                                        spacing: 10
                                        StyledText {
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            text: Translation.tr("Keybinds")
                                            color: Appearance.colors.colOnSecondaryContainer
                                        }
                                        RowLayout {
                                            spacing: 3
                                            KeyboardKey { key: "󰖳" }
                                            StyledText {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: "+"
                                            }
                                            KeyboardKey { key: "Tab" }
                                        }
                                    }
                                }
                            }
                            RippleButtonWithIcon {
                                materialIcon: "help"
                                mainText: Translation.tr("Docs")
                                onClicked: {
                                    Qt.openUrlExternally("https://mainstreamos.org/docs")
                                }
                            }
                            RippleButtonWithIcon {
                                nerdIcon: "󰊤"
                                mainText: Translation.tr("GitHub")
                                onClicked: {
                                    Qt.openUrlExternally("https://github.com/MainstreamOS")
                                }
                            }
                            RippleButtonWithIcon {
                                materialIcon: "favorite"
                                mainText: Translation.tr("Donate")
                                onClicked: {
                                    Qt.openUrlExternally("https://github.com/sponsors/MainstreamOS")
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }

}
