pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool visible: false
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property var realPlayers: MprisController.players
    // Recency-ordered and capped: with per-tab browser players the full list
    // grows unbounded, so only the most recently played few are shown. Any
    // older player re-enters the moment it plays or is selected. The local
    // read of recentPlayerNames makes the recency dependency explicit so the
    // binding re-evaluates on every bump.
    readonly property var meaningfulPlayers: {
        const order = MprisController.recentPlayerNames;
        return filterDuplicatePlayers(MprisController.orderByRecency(realPlayers)).slice(0, Config.options.media.maxShownPlayers);
    }
    // One track mirrored on several buses is one card: the active player when
    // it is among them, so the selection keeps its card, else the one with art.
    function filterDuplicatePlayers(players) {
        const groups = [];
        for (const player of players) {
            const title = player.trackTitle;
            const group = title ? groups.find(g => g[0].trackTitle
                && (g[0].trackTitle.includes(title) || title.includes(g[0].trackTitle))) : null;
            if (group) group.push(player);
            else groups.push([player]);
        }
        return groups.map(g => g.find(p => p === root.activePlayer)
            ?? g.find(p => p.trackArtUrl?.length > 0) ?? g[0]);
    }
    readonly property real osdWidth: Appearance.sizes.osdWidth
    readonly property real widgetWidth: Appearance.sizes.mediaControlsWidth
    readonly property real widgetHeight: Appearance.sizes.mediaControlsHeight
    property real popupRounding: RoundedCorners.on ? Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1 : 0

    // Centralized post-send revert: once a transfer reaches Sent state
    // (whether the popup is open or not), wait 3 seconds, then close the
    // popup and clear the transfer state so the bar reverts to the player.
    Timer {
        id: postSendRevertTimer
        interval: 3000
        repeat: false
        onTriggered: {
            GlobalStates.mediaControlsOpen = false;
            GlobalStates.mediaTransferActive = false;
            GlobalStates.mediaTransferUrls = [];
            LocalSend.reset();
        }
    }

    Connections {
        target: LocalSend
        function onStateChanged() {
            if (LocalSend.state === LocalSend.stateSent) {
                postSendRevertTimer.restart();
            }
        }
        // Receive choreography: the service only tracks protocol state; the
        // popup raises the ReceivePanel when a session starts, finishes, or
        // fails, and puts the view away when the receiver is turned off.
        function onReceiveSessionActiveChanged() {
            if (LocalSend.receiveSessionActive) root.showReceiveView();
        }
        function onReceiveCompleted(fileCount) {
            root.showReceiveView();
        }
        function onReceiveErrorChanged() {
            if (LocalSend.receiveError.length > 0) root.showReceiveView();
        }
        function onReceiveActiveChanged() {
            if (!LocalSend.receiveActive && GlobalStates.mediaReceiveActive
                && LocalSend.receiveError.length === 0) {
                GlobalStates.mediaReceiveActive = false;
                GlobalStates.mediaControlsOpen = false;
            }
        }
    }

    function showReceiveView() {
        GlobalStates.mediaReceiveActive = true;
        GlobalStates.mediaControlsOpen = true;
    }

    Loader {
        id: mediaControlsLoader
        active: GlobalStates.mediaControlsOpen
        onActiveChanged: {
            if (!mediaControlsLoader.active && root.realPlayers.length === 0) {
                GlobalStates.mediaControlsOpen = false;
            }
        }

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: true

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            // Single home for the transfer > receive > player precedence;
            // height, mask, and every view's visible read from here.
            readonly property Item shownItem: GlobalStates.mediaTransferActive ? transferPanel
                : GlobalStates.mediaReceiveActive ? receivePanel
                : playerColumnLayout

            implicitWidth: root.widgetWidth
            implicitHeight: shownItem === playerColumnLayout
                ? playerColumnLayout.implicitHeight
                : shownItem.height
            color: "transparent"
            WlrLayershell.namespace: "quickshell:mediaControls"

            anchors {
                top: !Config.options.bar.bottom || Config.options.bar.vertical
                bottom: Config.options.bar.bottom && !Config.options.bar.vertical
                left: !(Config.options.bar.vertical && Config.options.bar.bottom)
                right: Config.options.bar.vertical && Config.options.bar.bottom
            }
            // The stock spots, used until the widget that opened the popup has
            // been measured — and kept whenever it cannot be. Which one is read
            // depends on the edge the bar is on: a vertical bar puts the popup
            // beside itself and slides it up and down, a horizontal one puts it
            // below and slides it across.
            property real anchorLeft: (panelWindow.screen.width / 2) - (osdWidth / 2) - widgetWidth
            property real anchorTop: (panelWindow.screen.height / 2) - widgetHeight * 1.5

            // Measured on open rather than bound: the loader rebuilds this
            // window every time the popup opens, and the widget publishes
            // itself immediately before, so one measurement per open is both
            // current and free of binding loops against the layout.
            function placeUnderWidget() {
                try {
                    const it = GlobalStates.mediaWidgetItem;
                    const win = it ? it.QsWindow.window : null;
                    const pos = win?.contentItem ? win.contentItem.mapFromItem(it, 0, 0) : null;
                    if (!pos) return;
                    const gap = Appearance.sizes.hyprlandGapsOut;
                    if (Config.options.bar.vertical) {
                        const wantY = pos.y + it.height / 2 - root.widgetHeight / 2;
                        const maxY = panelWindow.screen.height - root.widgetHeight - gap;
                        panelWindow.anchorTop = Math.max(gap, Math.min(wantY, maxY));
                    } else {
                        const want = pos.x + it.width / 2 - root.widgetWidth / 2;
                        const maxX = panelWindow.screen.width - root.widgetWidth - gap;
                        panelWindow.anchorLeft = Math.max(gap, Math.min(want, maxX));
                    }
                } catch (e) {}
            }

            margins {
                top: Config.options.bar.vertical ? panelWindow.anchorTop : Appearance.sizes.barHeight
                bottom: Appearance.sizes.barHeight
                left: Config.options.bar.vertical ? Appearance.sizes.barHeight : panelWindow.anchorLeft
                right: Appearance.sizes.barHeight
            }

            mask: Region {
                item: panelWindow.shownItem
            }

            Component.onCompleted: {
                GlobalFocusGrab.addDismissable(panelWindow);
                panelWindow.placeUnderWidget();
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.mediaControlsOpen = false;
                }
            }

            FocusedScrollMouseArea {
                anchors.fill: parent
                onScrollDown: Audio.decrementVolume();
                onScrollUp: Audio.incrementVolume();

                ColumnLayout {
                    id: playerColumnLayouta
                    anchors.fill: parent
                    spacing: -Appearance.sizes.elevationMargin // Shadow overlap okay

                    Repeater {
                        model: ScriptModel { values: root.meaningfulPlayers }
                        delegate: PlayerControl {}
                    }
                }
            }

            // Drop zone covering the popup window so files dragged onto the
            // popup (after the bar's DropArea opened it) are captured here.
            DropArea {
                id: popupDropArea
                anchors.fill: parent
                visible: GlobalStates.mediaTransferActive
                z: 5
                onDropped: (drop) => {
                    if (LocalSend.state === LocalSend.stateSending) return;
                    const urls = (drop.urls ?? []).map(u => String(u));
                    if (urls.length > 0) GlobalStates.mediaTransferUrls = urls;
                    drop.accept(Qt.CopyAction);
                }
            }

            FileTransferPanel {
                id: transferPanel
                visible: panelWindow.shownItem === transferPanel
                anchors.top: parent.top
                anchors.left: parent.left
                fileUrls: GlobalStates.mediaTransferUrls
                radius: root.popupRounding
                targetWidth: root.widgetWidth
                targetHeight: root.widgetHeight
            }

            ReceivePanel {
                id: receivePanel
                visible: panelWindow.shownItem === receivePanel
                anchors.top: parent.top
                anchors.left: parent.left
                radius: root.popupRounding
                targetWidth: root.widgetWidth
                targetHeight: root.widgetHeight
            }

            ColumnLayout {
                id: playerColumnLayout
                anchors.fill: parent
                visible: panelWindow.shownItem === playerColumnLayout
                spacing: -Appearance.sizes.elevationMargin // Shadow overlap okay

                Repeater {
                    model: ScriptModel {
                        values: root.meaningfulPlayers
                    }
                    delegate: PlayerControl {
                        required property MprisPlayer modelData
                        player: modelData
                        implicitWidth: root.widgetWidth
                        implicitHeight: root.widgetHeight
                        radius: root.popupRounding
                    }
                }

                Item {
                    // No player placeholder
                    Layout.alignment: {
                        if (panelWindow.anchors.left)
                            return Qt.AlignLeft;
                        if (panelWindow.anchors.right)
                            return Qt.AlignRight;
                        return Qt.AlignHCenter;
                    }
                    Layout.leftMargin: Appearance.sizes.hyprlandGapsOut
                    Layout.rightMargin: Appearance.sizes.hyprlandGapsOut
                    visible: root.meaningfulPlayers.length === 0
                    implicitWidth: placeholderBackground.implicitWidth + Appearance.sizes.elevationMargin
                    implicitHeight: placeholderBackground.implicitHeight + Appearance.sizes.elevationMargin

                    StyledRectangularShadow {
                        target: placeholderBackground
                    }

                    Rectangle {
                        id: placeholderBackground
                        anchors.centerIn: parent
                        color: Appearance.colors.colLayer0
                        radius: root.popupRounding
                        property real padding: 20
                        implicitWidth: placeholderLayout.implicitWidth + padding * 2
                        implicitHeight: placeholderLayout.implicitHeight + padding * 2

                        ColumnLayout {
                            id: placeholderLayout
                            anchors.centerIn: parent

                            StyledText {
                                text: Translation.tr("No active player")
                                font.pixelSize: Appearance.font.pixelSize.large
                            }
                            StyledText {
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("Make sure your player has MPRIS support\nor try turning off duplicate player filtering")
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "localsend"

        function receiveToggle(): void {
            GlobalStates.toggleReceiveView();
        }
        function receiveOn(): void {
            if (!LocalSend.receiveActive) GlobalStates.toggleReceiveView();
        }
        function receiveOff(): void {
            LocalSend.stopReceive();
        }
    }

    IpcHandler {
        target: "mediaControls"

        function toggle(): void {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
            if (GlobalStates.mediaControlsOpen)
                Notifications.timeoutAll();
        }

        function close(): void {
            GlobalStates.mediaControlsOpen = false;
        }

        function open(): void {
            GlobalStates.mediaControlsOpen = true;
            Notifications.timeoutAll();
        }
    }

    GlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
        }
    }
    GlobalShortcut {
        name: "mediaControlsOpen"
        description: "Opens media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = true;
        }
    }
    GlobalShortcut {
        name: "mediaControlsClose"
        description: "Closes media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = false;
        }
    }
}
