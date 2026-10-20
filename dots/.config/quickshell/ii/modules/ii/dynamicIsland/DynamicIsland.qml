pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar

Scope {
    Variants {
        model: Quickshell.screens.filter(s => !Config.options.bar.screenList.length || Config.options.bar.screenList.includes(s.name))
        PanelWindow {
            id: window
            required property var modelData
            screen: modelData
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(window.screen)
            readonly property var workspacesForMonitor: Hyprland.workspaces.values.filter(w => w.monitor?.name === monitor?.name)
            readonly property bool hasFullscreenWindow: workspacesForMonitor.some(w => w.active && w.toplevels.values.some(t => t.wayland?.fullscreen))
            visible: GlobalStates.barOpen && !GlobalStates.screenLocked && !hasFullscreenWindow
            onVisibleChanged: {
                if (!visible) {
                    closeTimer.stop();
                    opened = false;
                    if (window.drawerRequested) IslandLauncher.close();
                }
            }
            anchors { top: !Config.options.bar.bottom; bottom: Config.options.bar.bottom }
            exclusionMode: ExclusionMode.Ignore
            // -1 ignores the zones others reserve, so a pinned sidebar cannot
            // pull the island off the screen's center.
            exclusiveZone: (Config.options.bar.autoHide.enable && (concealed || !Config.options.bar.autoHide.pushWindows)) ? -1 : Appearance.sizes.barHeight
            // Allocate the Wayland buffer once; only the items inside it morph.
            implicitWidth: Math.min(screen.width, Math.ceil(Math.max(compactWidth, expandedWidth) + Math.max(48, 2 * cornerRadius + 2)))
            implicitHeight: expandedChromeHeight + 208 + 24 + edgeGap * 2
            color: "transparent"
            WlrLayershell.namespace: "quickshell:dynamicIsland"
            // Match the standard bar's arrangement priority when a side panel
            // reserves space, keeping the island on the physical screen center.
            WlrLayershell.layer: ((Config.options.dock.enable && GlobalStates.dockPinned
                    && (Appearance.sizes.dockEdge === "left" || Appearance.sizes.dockEdge === "right"))
                    || GlobalStates.sidebarLeftPinned) ? WlrLayer.Top : WlrLayer.Overlay
            // These panels use pointer controls. Taking keyboard focus here
            // makes an open sidebar's focus grab repeatedly exclude and
            // reinclude the island as the pointer moves between surfaces,
            // Inline editors borrow focus only while visible, and yield it
            // while another popup or modal screen is open.
            WlrLayershell.keyboardFocus: window.drawerRequested ? WlrKeyboardFocus.OnDemand
                : window.expanded && !GlobalStates.overviewOpen && !GlobalStates.sessionOpen
                    && GlobalFocusGrab.dismissable.length === 0 && (content.item?.needsKeyboardFocus ?? false)
                    ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            Component.onCompleted: GlobalFocusGrab.addPersistent(window)
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(window);
                GlobalFocusGrab.removePersistent(window);
            }
            mask: Region {
                item: hoverArea
                Region { item: window.notch ? leftFlare : null }
                Region { item: window.notch ? rightFlare : null }
                Region { item: Config.options.bar.autoHide.enable ? edgeReveal : null }
            }
            property bool opened: false
            property bool drawerMode: false
            property bool drawerYielding: false
            readonly property bool drawerRequested: IslandLauncher.opened && IslandLauncher.screenName === screen.name
            onDrawerRequestedChanged: {
                drawerYielding = false;
                if (drawerRequested) {
                    drawerMode = true;
                    closeTimer.stop();
                    Qt.callLater(window.focusDrawer);
                } else {
                    GlobalFocusGrab.removeDismissable(window);
                    window.opened = false;
                }
            }
            function dismissDrawer() {
                if (window.drawerRequested) IslandLauncher.close();
                window.opened = false;
                closeTimer.stop();
            }
            function focusDrawer() {
                if (!window.drawerRequested || window.drawerYielding || !content.item?.focusSearch) return;
                content.item.focusSearch();
                GlobalFocusGrab.focus(window);
            }
            Connections {
                target: window.contentItem.Window.window
                function onActiveChanged() {
                    if (!window.drawerRequested) return;
                    if (window.drawerYielding && !window.contentItem.Window.active) window.dismissDrawer();
                    else if (window.contentItem.Window.active) Qt.callLater(window.focusDrawer);
                }
            }
            Connections {
                target: IslandLauncher
                function onFocusRequested() {
                    if (window.drawerRequested) Qt.callLater(window.focusDrawer);
                }
            }
            Connections {
                target: GlobalFocusGrab
                function onFocusTargetChanged() {
                    if (!window.drawerRequested || GlobalFocusGrab.focusTarget === window) return;
                    window.drawerYielding = true;
                    // Keep this surface admitted until the replacement has
                    // keyboard focus; removing it sooner can clear both popups.
                    if (!window.contentItem.Window.active) window.dismissDrawer();
                }
                function onDismissed() { if (window.drawerRequested) window.dismissDrawer(); }
            }
            property bool superShow: false
            readonly property bool superHeld: visible && Config.options.bar.autoHide.enable
                && Config.options.bar.autoHide.showWhenPressingSuper.enable && GlobalStates.superDown
            onSuperHeldChanged: {
                if (superHeld) showBarTimer.restart();
                else {
                    showBarTimer.stop();
                    superShow = false;
                }
            }
            Timer {
                id: showBarTimer
                interval: Config.options.bar.autoHide.showWhenPressingSuper.delay
                onTriggered: window.superShow = window.superHeld
            }
            readonly property bool panelBusy: drawerMode ? drawerRequested : (content.item?.busy ?? false)
            readonly property bool concealed: Config.options.bar.autoHide.enable && !(opened || automatic || superShow || panelBusy || drawerRequested)
            property real hideOffset: concealed ? (bottom ? height : -height) : 0
            Behavior on hideOffset {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            function revealPanel() {
                closeTimer.stop();
                if (window.drawerRequested) return;
                window.drawerMode = false;
                if (!expanded && IslandState.selected !== "localsend" && !IslandState.alertOpen)
                    IslandState.showDefaultPanel();
                opened = true;
            }
            function toggleSidebar(left) {
                if (left) GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
                else GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
                closeTimer.stop();
            }
            function validPanel(panel) {
                if (panel === "localsend" && IslandPanels.enabled(panel)) return panel;
                return IslandState.panels.includes(panel) ? panel : (IslandState.panels[0] ?? "");
            }
            property string displayedPanel: window.validPanel(IslandState.selected)
            readonly property bool automatic: !drawerMode && Config.options.bar.island.automaticAlerts && IslandState.alertOpen && Hyprland.focusedMonitor?.name === screen.name
            readonly property bool expanded: visible && (drawerRequested || (!drawerMode && (IslandState.panels.length > 0 || (IslandState.selected === "localsend" && IslandPanels.enabled("localsend"))) && (opened || automatic || panelBusy)))
            readonly property bool bottom: Config.options.bar.bottom
            readonly property bool notch: Appearance.sizes.islandShape === "notch"
            readonly property bool floating: Appearance.sizes.islandShape === "float"
            // Fade the outline with the notch, using the bar's own material.
            readonly property color surfaceOutline: window.notch
                ? ColorUtils.applyAlpha(Appearance.colors.colBarBackgroundBorder, 1)
                : Appearance.colors.colBarBackgroundBorder
            readonly property real edgeGap: floating ? Appearance.sizes.hyprlandGapsOut : 0
            readonly property real cornerRadius: Appearance.sizes.islandShape === "rect" ? 0 : Appearance.rounding.barFloat
            readonly property real compactWidth: clock.implicitWidth + 32
            readonly property real expandedWidth: Appearance.sizes.mediaControlsWidth + 32
            readonly property real contentPadding: 16
            readonly property real navigationHeight: 36
            readonly property real contentSpacing: 10
            readonly property real expandedChromeHeight: contentPadding * 2 + navigationHeight + contentSpacing
            Connections {
                target: GlobalStates
                function onMediaControlsOpenChanged() {
                    if (window.drawerRequested) return;
                    window.drawerMode = false;
                    if (GlobalStates.mediaControlsOpen && Hyprland.focusedMonitor?.name === window.screen.name) {
                        if (GlobalStates.mediaReceiveActive && !IslandState.transferSession) return;
                        if (!IslandState.transferSession && !IslandState.panels.includes("media")) return;
                        IslandState.selected = IslandState.transferSession ? "localsend" : "media";
                        window.opened = true;
                    } else if (!GlobalStates.mediaControlsOpen && IslandState.selected === "localsend") {
                        window.opened = false;
                    }
                }
            }
            onExpandedChanged: {
                if (expanded) {
                    unloadContent.stop();
                    displayedPanel = window.validPanel(IslandState.selected);
                    content.active = true;
                } else {
                    // Finish the surface morph before destroying the card's
                    // render layers or switching back to the previous panel.
                    unloadContent.restart();
                    if (!window.drawerMode && GlobalStates.mediaControlsOpen) GlobalStates.mediaControlsOpen = false;
                }
            }
            Connections {
                target: IslandState
                function onSelectedChanged() {
                    if (window.expanded) window.displayedPanel = window.validPanel(IslandState.selected);
                }
            }
            Timer {
                id: unloadContent
                interval: 320
                onTriggered: {
                    if (window.expanded) return;
                    content.active = false;
                    window.drawerMode = false;
                    IslandState.endTransferView();
                }
            }

            Timer {
                id: closeTimer
                interval: 550
                onTriggered: {
                    if (hoverArea.containsMouse || edgeReveal.containsMouse) return;
                    if (fileDrop.containsDrag) { restart(); return; }
                    if (content.item?.busy ?? false) { restart(); return; }
                    window.opened = false;
                }
            }
            // Keep a small input region on the edge while the island slides
            // out of view. The window buffer stays the same size throughout.
            MouseArea {
                id: edgeReveal
                visible: Config.options.bar.autoHide.enable
                width: window.compactWidth + 2 * Appearance.rounding.barFloat
                height: Math.max(1, Config.options.bar.autoHide.hoverRegionWidth)
                anchors.horizontalCenter: parent.horizontalCenter
                y: window.bottom ? window.height - height : 0
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: window.revealPanel()
                onExited: closeTimer.restart()
                DropArea {
                    anchors.fill: parent
                    onEntered: drag => {
                        if (drag.hasUrls && !window.drawerRequested) window.revealPanel();
                        else drag.accepted = false;
                    }
                    onExited: closeTimer.restart()
                }
            }
            MouseArea {
                id: hoverArea
                width: surface.width
                height: surface.height
                anchors.horizontalCenter: parent.horizontalCenter
                y: (window.bottom ? window.height - height - window.edgeGap : window.edgeGap) + window.hideOffset
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: window.revealPanel()
                onExited: closeTimer.restart()
                StyledRectangularShadow {
                    target: surface
                    z: -1
                    visible: window.floating && Config.options.bar.floatStyleShadow
                    color: Appearance.colors.colBarShadow
                }
                Rectangle {
                    id: surface
                    width: Math.min(window.width - 48, window.expanded ? window.expandedWidth : window.compactWidth)
                    height: window.expanded ? (window.drawerMode ? window.contentPadding * 2 : window.expandedChromeHeight)
                        + Math.min(window.drawerMode ? 258 : 208, content.implicitHeight) : Appearance.sizes.baseBarHeight
                    color: "transparent"
                    radius: window.cornerRadius
                    topLeftRadius: window.floating || window.bottom ? radius : 0
                    topRightRadius: topLeftRadius
                    bottomLeftRadius: window.floating || !window.bottom ? radius : 0
                    bottomRightRadius: bottomLeftRadius
                    Item {
                        id: shape
                        // Keep the translucent group's texture stable as well.
                        width: window.width
                        height: window.height
                        x: (surface.width - width) / 2
                        y: window.bottom ? surface.height - height : 0
                        opacity: window.notch ? Appearance.colors.colBarBackground.a : 1
                        layer.enabled: window.notch && opacity < 1
                        Rectangle {
                            // Well past the screen edge it sits on, so fractional scaling cannot smear the outline back onto it.
                            readonly property real edgeLap: window.floating ? 0 : border.width * 2
                            width: surface.width
                            height: surface.height + edgeLap
                            x: (shape.width - width) / 2
                            y: window.bottom ? shape.height - surface.height : -edgeLap
                            color: window.notch ? Appearance.colors.colBarBackgroundOpaque : Appearance.colors.colBarBackground
                            border.width: 1
                            border.color: window.surfaceOutline
                            topLeftRadius: surface.topLeftRadius
                            topRightRadius: surface.topRightRadius
                            bottomLeftRadius: surface.bottomLeftRadius
                            bottomRightRadius: surface.bottomRightRadius
                        }
                        RoundCorner {
                            id: leftFlare
                            visible: window.notch
                            implicitSize: Appearance.rounding.barFloat
                            color: Appearance.colors.colBarBackgroundOpaque
                            outlineWidth: 1
                            outlineColor: window.surfaceOutline
                            x: (shape.width - surface.width) / 2 - width + 2
                            y: window.bottom ? shape.height - height : 0
                            corner: window.bottom ? RoundCorner.CornerEnum.BottomRight : RoundCorner.CornerEnum.TopRight
                        }
                        RoundCorner {
                            id: rightFlare
                            visible: window.notch
                            implicitSize: Appearance.rounding.barFloat
                            color: Appearance.colors.colBarBackgroundOpaque
                            outlineWidth: 1
                            outlineColor: window.surfaceOutline
                            x: (shape.width + surface.width) / 2 - 2
                            y: leftFlare.y
                            corner: window.bottom ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.TopLeft
                        }
                    }
                    Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

                    DropArea {
                        id: fileDrop
                        anchors.fill: parent
                        z: 5
                        onEntered: drag => {
                            if (window.drawerMode || !IslandPanels.enabled("localsend") || !drag.hasUrls) {
                                drag.accepted = false;
                                return;
                            }
                            GlobalStates.mediaTransferActive = true;
                            GlobalStates.mediaReceiveActive = false;
                            window.opened = true;
                            IslandState.beginTransfer();
                            GlobalStates.mediaControlsOpen = true;
                            closeTimer.stop();
                            if (LocalSend.state === LocalSend.stateSending) drag.accepted = false;
                        }
                        onExited: closeTimer.restart()
                        onDropped: drop => {
                            if (window.drawerMode || !IslandPanels.enabled("localsend") || LocalSend.state === LocalSend.stateSending) return;
                            const urls = (drop.urls ?? []).map(url => String(url)).filter(url => url.startsWith("file://"));
                            if (!urls.length) return;
                            GlobalStates.mediaTransferUrls = urls;
                            drop.accept(Qt.CopyAction);
                            closeTimer.restart();
                        }
                    }

                    ClockWidget {
                        id: clock
                        contentColor: Appearance.barStripContent.colOnLayer1
                        anchors.centerIn: parent
                        visible: !window.expanded
                        interactive: false
                    }
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: window.contentPadding
                        visible: window.expanded
                        spacing: window.contentSpacing
                        RowLayout {
                            visible: !window.drawerMode
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.navigationHeight
                            spacing: 8

                            RippleButton {
                                id: leftSidebarButton
                                Layout.preferredWidth: window.navigationHeight
                                Layout.preferredHeight: window.navigationHeight
                                topPadding: 0
                                bottomPadding: 0
                                buttonRadius: 10
                                colBackground: highlighted ? Appearance.colors.colPrimaryContainer : Appearance.surfaces.raised
                                colBackgroundHover: highlighted ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                                colRipple: highlighted ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                                highlighted: GlobalStates.sidebarLeftOpen
                                Accessible.name: Translation.tr("Toggle left sidebar")
                                onClicked: window.toggleSidebar(true)
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "left_panel_open"
                                    iconSize: 18
                                    color: leftSidebarButton.highlighted ? Appearance.colors.colOnPrimaryContainer : Appearance.islandContent.colOnLayer1
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Rectangle {
                                id: navigator
                                Layout.fillWidth: true
                                Layout.preferredHeight: window.navigationHeight
                                radius: 12
                                color: Appearance.surfaces.raised

                                readonly property bool showWorkspaces: navHover.hovered || workspacesWidget.containsMouse

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    spacing: 4

                                    RippleButton {
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        topPadding: 0
                                        bottomPadding: 0
                                        buttonRadius: 8
                                        colBackground: "transparent"
                                        colBackgroundHover: Appearance.surfaces.row
                                        enabled: IslandState.panels.length > 1
                                        Accessible.name: Translation.tr("Previous panel")
                                        onClicked: IslandState.step(-1)
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "chevron_left"
                                            iconSize: 18
                                            color: Appearance.islandContent.colOnLayer1
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 28
                                        radius: 8
                                        color: Appearance.surfaces.row

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            opacity: navigator.showWorkspaces ? 0 : 1
                                            Behavior on opacity { NumberAnimation { duration: 150 } }

                                            MaterialSymbol {
                                                text: IslandPanels.entry(window.displayedPanel)?.icon ?? "tune"
                                                iconSize: 14
                                                color: Appearance.islandContent.colPrimary
                                            }

                                            StyledText {
                                                text: IslandPanels.entry(window.displayedPanel)?.name ?? ""
                                                color: Appearance.islandContent.colOnLayer0
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        Workspaces {
                                            id: workspacesWidget
                                            contentColors: Appearance.islandContent
                                            anchors.centerIn: parent
                                            shownCount: Math.min(Config.options.bar.workspaces.shown, 10)
                                            monitor: window.monitor
                                            alwaysShowNumbers: true
                                            enableWheel: false
                                            enableRightClick: false
                                            opacity: navigator.showWorkspaces ? 1 : 0
                                            visible: opacity > 0
                                            Behavior on opacity {
                                                NumberAnimation { duration: 150 }
                                            }
                                        }

                                        HoverHandler { id: navHover }
                                        TapHandler {
                                            acceptedButtons: Qt.RightButton
                                            onTapped: {
                                                Hyprland.dispatch('hl.dsp.workspace.toggle_special("special")');
                                                closeTimer.stop();
                                                window.opened = false;
                                                IslandState.alertOpen = false;
                                            }
                                        }
                                        WheelHandler {
                                            id: navigationWheel
                                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                            target: null
                                            onWheel: event => {
                                                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : (event.pixelDelta.y !== 0 ? event.pixelDelta.y : (event.angleDelta.x !== 0 ? event.angleDelta.x : event.pixelDelta.x));
                                                if (delta < 0)
                                                    Hyprland.dispatch(`hl.dsp.focus({workspace = "r+1"})`);
                                                else if (delta > 0)
                                                    Hyprland.dispatch(`hl.dsp.focus({workspace = "r-1"})`);
                                                event.accepted = true;
                                            }
                                        }
                                    }

                                    RippleButton {
                                        Layout.preferredWidth: 28
                                        Layout.preferredHeight: 28
                                        topPadding: 0
                                        bottomPadding: 0
                                        buttonRadius: 8
                                        colBackground: "transparent"
                                        colBackgroundHover: Appearance.surfaces.row
                                        enabled: IslandState.panels.length > 1
                                        Accessible.name: Translation.tr("Next panel")
                                        onClicked: IslandState.step(1)
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "chevron_right"
                                            iconSize: 18
                                            color: Appearance.islandContent.colOnLayer1
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }
                            }

                            RippleButton {
                                id: rightSidebarButton
                                Layout.preferredWidth: window.navigationHeight
                                Layout.preferredHeight: window.navigationHeight
                                topPadding: 0
                                bottomPadding: 0
                                buttonRadius: 10
                                colBackground: highlighted ? Appearance.colors.colPrimaryContainer : Appearance.surfaces.raised
                                colBackgroundHover: highlighted ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
                                colRipple: highlighted ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
                                highlighted: GlobalStates.sidebarRightOpen
                                Accessible.name: Translation.tr("Toggle right sidebar")
                                onClicked: window.toggleSidebar(false)
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "right_panel_open"
                                    iconSize: 18
                                    color: rightSidebarButton.highlighted ? Appearance.colors.colOnPrimaryContainer : Appearance.islandContent.colOnLayer1
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                        Loader {
                            id: content
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            active: false
                            sourceComponent: {
                                if (window.drawerMode) return appDrawer;
                                switch (window.displayedPanel) {
                                case "media": return media;
                                case "localsend": return localSend;
                                case "weather": return weather;
                                case "timers": return timers;
                                case "calendar": return calendar;
                                case "resources": return resources;
                                case "call": return call;
                                case "text": return messages;
                                case "notifications": return notifications;
                                default: return system;
                                }
                            }
                            onLoaded: if (window.drawerRequested) Qt.callLater(window.focusDrawer)
                        }
                    }
                }
            }
            Component { id: media; MediaPanel {} }
            Component {
                id: appDrawer
                AppDrawerPanel {
                    active: window.expanded && window.drawerMode
                    searchRequested: window.drawerRequested
                    onDismissed: window.dismissDrawer()
                }
            }
            Component { id: weather; WeatherPanel {} }
            Component { id: calendar; CalendarPanel {} }
            Component { id: timers; TimersPanel {} }
            Component { id: system; SystemPanel { screen: window.screen } }
            Component { id: resources; ResourcesPanel {} }
            Component { id: call; PhonePanel { calls: true } }
            Component { id: messages; PhonePanel { calls: false } }
            Component { id: notifications; NotificationsPanel {} }
            Component { id: localSend; LocalSendPanel {} }
        }
    }
}
