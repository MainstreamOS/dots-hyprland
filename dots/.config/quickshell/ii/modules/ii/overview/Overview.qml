import qs
import qs.services
import qs.modules.common
import qs.modules.common.models.hyprland
import qs.modules.common.widgets
import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import "scrolling.js" as Scrolling
import "launcher-layout.js" as LauncherLayout

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false
    HyprlandConfigOption { id: scrollFit; key: "scrolling:focus_fit_method" }
    HyprlandConfigOption { id: innerGaps; key: "general:gaps_in" }
    HyprlandConfigOption { id: outerGaps; key: "general:gaps_out" }
    HyprlandConfigOption { id: borderSize; key: "general:border_size" }
    // Keep app-use history even before the scrolling launcher is first opened.
    Component.onCompleted: RecentApps.rememberActive()

    // The compositor's edge reservations come from a snapshot that layer
    // open and close events do not refresh, and a mapped layer changing
    // its zone (a pin, an auto-hide) sends no event at all, so the
    // snapshot is retaken at every open. The open can move a zone itself
    // (a bar shown for a held Super hides on the release that opens the
    // launcher), and that reaches the compositor at the bar's next frame,
    // after the first query, so a second query follows once it has landed.
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (!GlobalStates.overviewOpen) return;
            HyprlandData.updateMonitors();
            reservationSettle.restart();
        }
    }
    Timer {
        id: reservationSettle
        interval: 100
        onTriggered: if (GlobalStates.overviewOpen) HyprlandData.updateMonitors()
    }

    // Dismiss in-surface (dismissArea + Escape), not the shared focus grab: the
    // always-alive full-screen surface already captures outside clicks, so the
    // grab was redundant and its races broke the dock launcher button.

    WorkspaceLaunchTracker {
        id: launchTracker
        onWindowResolved: (address, workspace, currentWorkspace) => {
            if (workspace > 0) {
                if (workspace !== currentWorkspace)
                    Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${workspace}, follow = false, window = "address:${address}" })`);
                return;
            }
            overviewScope.dismissExternal(address);
        }
    }

    function dismissExternal(address) {
        for (const panel of overviewVariants.instances) {
            if (!panel.monitorIsFocused) continue;
            if (panel.useScrollingLauncher) {
                const launcher = panel.scrollingLauncherItem;
                if (!launcher || (!GlobalStates.overviewOpen && !launcher.restoringView)) continue;
                if (!address && (launcher.placementPending || launcher.activationPending)) continue;
                launcher.dismissExternal(address);
            } else if (GlobalStates.overviewOpen) {
                GlobalStates.overviewOpen = false;
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "openwindow" && event.name !== "activespecialv2") return;
            const parts = String(event.data).split(",");
            if (!parts[0]) return;
            const address = event.name === "openwindow" ? `0x${parts[0]}` : "";
            // Resolve launch identity first: shared runtimes and portal dialogs
            // use other classes than the desktop entry that was dropped.
            if (address && launchTracker.classify(address)) return;
            if (GlobalStates.overviewOpen || address) overviewScope.dismissExternal(address);
        }
    }

    // One overview per screen: surfaces are torn down and rebuilt with their
    // output, so a DP re-train across suspend/DPMS can't orphan the window.
    Variants {
        id: overviewVariants
        model: Quickshell.screens

    PanelWindow {
        id: panelWindow
        required property ShellScreen modelData
        screen: modelData
        property string searchingText: ""
        property string launcherLayout: ""
        readonly property bool useScrollingLauncher: Config.options.overview.enable
            && Config.options.overview.useScrollingLauncher && Scrolling.usesLayout(launcherLayout)
        property bool scrollingActivationPending: false
        property bool scrollingPlacementPending: false
        readonly property var scrollingLauncherItem: scrollingLauncher.item
        QtObject {
            id: scrollingViewState
            property var selectedByWorkspace: ({})
            property var pannedByWorkspace: ({})
            property var monocleOrder: ({})
        }
        readonly property string currentWorkspaceLayout: HyprlandData.workspaceById[
            panelWindow.monitorData?.activeWorkspace?.id ?? panelWindow.monitor?.activeWorkspace?.id]?.tiledLayout ?? ""
        onCurrentWorkspaceLayoutChanged: {
            if (!GlobalStates.overviewOpen && contentFade.opacity === 0) launcherLayout = currentWorkspaceLayout;
        }
        readonly property bool preloadSurface: Config.options.overview.keepSurfaceAlive
        readonly property bool preloadScrollingLauncher: panelWindow.preloadSurface && panelWindow.useScrollingLauncher
        // What the drawer opens as. Without the workspace previews the
        // short list would sit alone under the search box, so it starts
        // on the full list instead unless that was turned off.
        readonly property bool drawerStartsExpanded: !(Config?.options.overview.enable ?? true)
            && (Config?.options.overview.showAllAppsWhenOff ?? true)
        // Expanding the full list by hand replaces the launcher's search box
        // with the list's own app-only one. A list that started expanded never
        // asked for that, so there the launcher keeps its box and everything
        // it can find.
        readonly property bool drawerOwnsSearch: appDrawer.expanded && !panelWindow.drawerStartsExpanded
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        property bool monitorIsFocused: ((Hyprland.focusedMonitor?.id ?? monitor?.id) === monitor?.id)

        readonly property bool requested: GlobalStates.overviewOpen && monitorIsFocused
        // A preloaded surface stays mapped with an empty input region when closed.
        visible: panelWindow.preloadSurface || requested || contentFade.opacity > 0

        // null mask = capture (open), empty Region = click-through (closed).
        // Gate on overviewOpen only, NOT the fade-out opacity — capturing while
        // contentFade fades out swallowed the next click (dead dock button).
        mask: (GlobalStates.overviewOpen && monitorIsFocused)
            ? null
            : passthroughRegion
        Region { id: passthroughRegion }

        WlrLayershell.namespace: "quickshell:overview"
        // Use Overlay layer (not Top) so the surface stays visible during
        // exclusive/borderless fullscreen apps. Hyprland forces alpha=0 on
        // any layer surface below Overlay when a monitor is in fullscreen
        // mode (see Hyprland src/desktop/view/LayerSurface.cpp:335). With
        // the always-alive surface fix, our overview can't rely on "newly
        // mapped above fullscreen" semantics, so we need Overlay layer.
        WlrLayershell.layer: WlrLayer.Overlay
        // Exclusive brings keyboard focus to search; yield to OnDemand once focused,
        // since Hyprland routes all pointer input to exclusive surfaces (dock unclickable).
        property bool keyboardPrimed: false
        // FrameAnimation can advance before a new layer surface presents its
        // first frame. Leave preview captures and app icons out of that frame.
        property bool framePresented: false
        Connections {
            target: panelWindow.contentItem.Window.window
            enabled: !panelWindow.framePresented && GlobalStates.overviewOpen && panelWindow.monitorIsFocused
            function onFrameSwapped() {
                if (contentFade.opacity > 0 && panelWindow.width > 1 && panelWindow.height > 1)
                    panelWindow.framePresented = true;
            }
        }

        WlrLayershell.keyboardFocus: (GlobalStates.overviewOpen && monitorIsFocused && !((scrollingLauncher.item?.placementPending ?? false) || (scrollingLauncher.item?.activationPending ?? false)
                || (overviewLoader.item?.placementPending ?? false)))
            ? (keyboardPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive) : WlrKeyboardFocus.None
        Connections {
            target: panelWindow.contentItem.Window
            function onActiveChanged() {
                if (panelWindow.contentItem.Window.active) panelWindow.keyboardPrimed = true;
            }
        }
        color: "transparent"
        readonly property bool dimShown: requested && width > 1 && height > 1
        readonly property bool surfaceShown: visible && contentFade.opacity > 0
        property string registeredScreen: ""
        onDimShownChanged: if (registeredScreen) GlobalStates.setLauncherDim(registeredScreen, dimShown)
        Component.onCompleted: {
            launcherLayout = currentWorkspaceLayout;
            registeredScreen = modelData.name;
            GlobalStates.launcherWindows = Object.assign({}, GlobalStates.launcherWindows, {[registeredScreen]: panelWindow});
            if (dimShown) GlobalStates.setLauncherDim(registeredScreen, true);
        }
        Component.onDestruction: {
            if (GlobalStates.launcherWindows[registeredScreen] !== panelWindow) return;
            const windows = Object.assign({}, GlobalStates.launcherWindows);
            delete windows[registeredScreen];
            GlobalStates.launcherWindows = windows;
            GlobalStates.setLauncherDim(registeredScreen, false);
        }

        // Sample the wallpaper directly and blur in-surface so the backdrop fades
        // in exact lockstep with controls. This prevents the compositor blur flash on close.
        Loader {
            id: wallpaperSource
            active: panelWindow.preloadSurface || panelWindow.requested || contentFade.opacity > 0
            sourceComponent: ScreenWallpaperSource {}
        }

        Item {
            id: overviewBackdrop
            anchors.fill: parent
            visible: opacity > 0 && (wallpaperSource.item?.available ?? false)
            opacity: 0

            readonly property bool shouldBeOpen: GlobalStates.overviewOpen && panelWindow.monitorIsFocused
            onShouldBeOpenChanged: {
                if (shouldBeOpen) {
                    backdropFadeOut.stop();
                    backdropFadeIn.from = overviewBackdrop.opacity;
                    backdropFadeIn.start();
                } else {
                    backdropFadeIn.stop();
                    backdropFadeOut.from = overviewBackdrop.opacity;
                    backdropFadeOut.start();
                }
            }

            NumberAnimation {
                id: backdropFadeIn
                target: overviewBackdrop
                property: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.OutQuad
            }

            NumberAnimation {
                id: backdropFadeOut
                target: overviewBackdrop
                property: "opacity"
                to: 0
                duration: 130 // Fades out early (130ms vs 200ms) so zero blur lingers into final frames
                easing.type: Easing.OutQuad
            }

            onVisibleChanged: if (visible) wallpaperSample.scheduleUpdate()

            readonly property var pic: wallpaperSource.item?.picture

            ShaderEffectSource {
                id: wallpaperSample
                anchors.fill: parent
                sourceItem: overviewBackdrop.pic
                readonly property real picX: overviewBackdrop.pic?.x ?? 0
                readonly property real picY: overviewBackdrop.pic?.y ?? 0
                readonly property real picW: overviewBackdrop.pic?.width ?? panelWindow.width
                readonly property real picH: overviewBackdrop.pic?.height ?? panelWindow.height
                sourceRect: overviewBackdrop.pic
                    ? Qt.rect(
                        Math.max(0, -picX),
                        Math.max(0, -picY),
                        Math.min(panelWindow.width, Math.max(0, picW - Math.max(0, -picX))),
                        Math.min(panelWindow.height, Math.max(0, picH - Math.max(0, -picY)))
                    )
                    : Qt.rect(0, 0, 0, 0)
                hideSource: false
                live: false
                textureSize: Qt.size(
                    Math.ceil(parent.width * (panelWindow.screen?.scale ?? 1) * 0.25),
                    Math.ceil(parent.height * (panelWindow.screen?.scale ?? 1) * 0.25)
                )
            }

            Connections {
                target: overviewBackdrop.pic
                enabled: overviewBackdrop.visible
                ignoreUnknownSignals: true
                function onStatusChanged() { wallpaperSample.scheduleUpdate(); }
                function onSourceChanged() { wallpaperSample.scheduleUpdate(); }
                function onXChanged() { wallpaperSample.scheduleUpdate(); }
                function onYChanged() { wallpaperSample.scheduleUpdate(); }
                function onWidthChanged() { wallpaperSample.scheduleUpdate(); }
                function onHeightChanged() { wallpaperSample.scheduleUpdate(); }
            }

            Connections {
                target: GlobalStates
                function onOverviewOpenChanged() {
                    if (GlobalStates.overviewOpen && panelWindow.monitorIsFocused)
                        wallpaperSample.scheduleUpdate();
                }
            }

            FastBlur {
                id: wallpaperBlur
                anchors.fill: parent
                source: wallpaperSample
                radius: 56
            }

            Rectangle {
                anchors.fill: parent
                color: Appearance.launcherDimColor
                opacity: Appearance.launcherDimOpacity
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: opacity > 0 && !(wallpaperSource.item?.available ?? false)
            color: Appearance.launcherDimColor
            opacity: overviewBackdrop.opacity * Appearance.launcherDimOpacity
        }

        // Full-screen so the dim overlay covers app windows behind the overview.
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        // While it is open the compositor sends every click to this surface,
        // wherever the click lands, so the surface lies under every place a
        // click can land, exclusive zones included.
        exclusionMode: ExclusionMode.Ignore
        // Use logical sizes and let the desktop's display scale size the UI.
        // Workspace previews still fit within the available screen area.
        readonly property real launcherUiScale: 1

        // Content keeps clear of whatever holds an edge. The compositor's
        // resolved reservation covers the bar, a pinned dock, a pinned sidebar
        // or keyboard, and anything third party, on this screen alone and only
        // while it is actually there. A dock reserves nothing unpinned and
        // overhangs its zone pinned, so its share is added by hand, and a dock
        // owner keeps the search bar at one height wherever the dock sits:
        // with neither the dock nor the bar on top, the content starts a
        // dock's thickness down, as it does under a top dock.
        readonly property var monitorData: HyprlandData.monitors.find(m => m.id === panelWindow.monitor?.id)
        readonly property var workspaceReserved: {
            const reserved = (monitorData?.reserved ?? [0, 0, 0, 0]).slice();
            if (GlobalStates.sidebarLeftScreen === screen.name) {
                const edge = Appearance.sizes.sidebarLeftEdge === "right" ? 2 : 0;
                reserved[edge] = Math.max(0, reserved[edge] - GlobalStates.sidebarLeftZone);
            }
            return reserved;
        }
        readonly property var launcherReserved: {
            const reserved = workspaceReserved.slice();
            const edge = Appearance.sizes.barEdge === "top" ? 1 : 3;
            reserved[edge] = Math.max(reserved[edge], fullscreenBarClearance);
            return reserved;
        }
        // Keep the panels' size and position in fullscreen while fitting
        // window captures to the desktop's actual available area.
        readonly property var workspaceLayout: LauncherLayout.workspaceGrid({
            monitor: monitorData ?? { width: screen.width, height: screen.height, scale: 1, transform: 0 },
            reserved: workspaceReserved, layoutReserved: launcherReserved,
            rows: Config.options.overview.rows, columns: Config.options.overview.columns,
            size: Config.options.overview.size, unit: launcherUiScale, elevation: Appearance.sizes.elevationMargin
        })
        // A horizontal bar unmaps in fullscreen. Keep its usual space in
        // the launcher on screens where it would have reserved an edge.
        readonly property real fullscreenBarClearance: !Config.options.bar.vertical && GlobalStates.barOpen
            && !Config.options.bar.autoHide.enable
            && (!Config.options.bar.screenList.length || Config.options.bar.screenList.includes(screen.name))
            && HyprlandData.activeWorkspaceHasFullscreen(screen.name) ? Appearance.sizes.horizontalBarExclusiveZone : 0

        function edgeClearance(edge) {
            const index = { left: 0, top: 1, right: 2, bottom: 3 }[edge];
            let c = panelWindow.launcherReserved[index];
            if (Config.options.dock.enable && Appearance.sizes.dockEdge === edge)
                c += GlobalStates.dockPinned ? Appearance.sizes.elevationMargin : Appearance.sizes.dockExtent;
            if (edge === "top" && Config.options.dock.enable
                    && Appearance.sizes.dockEdge !== "top" && Appearance.sizes.barEdge !== "top")
                c += Appearance.sizes.dockExtent;
            return c;
        }

        Connections {
            target: GlobalStates
            function onOverviewOpenChanged() {
                if (!GlobalStates.overviewOpen) {
                    panelWindow.keyboardPrimed = false;
                    searchWidget.disableExpandAnimation();
                    overviewScope.dontAutoCancelSearch = false;
                    // Reset drawer state
                    panelWindow.resetDrawer();
                    flickable.contentY = 0;
                } else {
                    panelWindow.keyboardPrimed = panelWindow.contentItem.Window.active;
                    panelWindow.launcherLayout = panelWindow.currentWorkspaceLayout;
                    if (!overviewScope.dontAutoCancelSearch) {
                        searchWidget.cancelSearch();
                    }
                    // Reset drawer state on open.
                    panelWindow.resetDrawer();
                    // Focus the search box as the surface takes keyboard focus.
                    if (panelWindow.useScrollingLauncher)
                        Qt.callLater(panelWindow.beginScrollingLauncher);
                    else
                        Qt.callLater(searchWidget.focusSearchInput);
                }
            }
        }

        onMonitorIsFocusedChanged: {
            if (monitorIsFocused) Qt.callLater(panelWindow.beginScrollingLauncher);
        }

        function beginScrollingLauncher() {
            if (GlobalStates.overviewOpen && monitorIsFocused && useScrollingLauncher)
                scrollingLauncher.item?.begin(!overviewScope.dontAutoCancelSearch);
        }

        function closeScrollingLauncher() {
            if (scrollingLauncher.item) scrollingLauncher.item.close();
            else GlobalStates.overviewOpen = false;
        }

        function launchAppOnWorkspace(app, ws) {
            if (ws <= 0 || !app) return;
            if (app._isFolder === true) {
                for (const id of app.appIds || []) {
                    const entry = AppSearch.guessDesktopEntry(id);
                    if (entry) launchTracker.launch(entry, ws);
                }
            } else {
                launchTracker.launch(app, ws);
            }
        }

        function setSearchingText(text) {
            if (panelWindow.useScrollingLauncher) {
                if (scrollingLauncher.item) scrollingLauncher.item.setSearchingText(text);
                else LauncherSearch.query = text;
                return;
            }
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
        }

        function collapseDrawer(refocus) {
            appDrawer.closeContextMenu();
            appDrawer.expanded = false;
            appDrawer.searchText = "";
            Qt.callLater(() => { flickable.contentY = 0; });
            if (refocus) {
                columnLayout.forceActiveFocus();
                Qt.callLater(() => { searchWidget.focusSearchInput(); });
            }
        }

        function resetDrawer() {
            appDrawer.closeContextMenu();
            appDrawer.expanded = panelWindow.drawerStartsExpanded;
            appDrawer.searchText = "";
            appDrawer.folderPopupVisible = false;
            appDrawer.openFolder = null;
            appDrawer.resetScroll();
        }

        // Wraps all content so a single opacity animation fades everything together
        Item {
            id: contentFade
            anchors.fill: parent
            opacity: (GlobalStates.overviewOpen && panelWindow.monitorIsFocused) ? 1 : 0
            property bool appDragging: false
            onOpacityChanged: {
                if (opacity !== 0) return;
                panelWindow.framePresented = false;
                if (!GlobalStates.overviewOpen) {
                    panelWindow.launcherLayout = panelWindow.currentWorkspaceLayout;
                    HyprlandData.refreshSoon();
                }
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this, { alwaysRunToEnd: false })
            }

        // Floating icon that follows the cursor during app drag
        Rectangle {
            id: dragFloatIcon
            z: 9999
            visible: false
            width: 56 * panelWindow.launcherUiScale
            height: width
            radius: Appearance.rounding.normal * panelWindow.launcherUiScale
            color: Appearance.colors.colSecondaryContainer
            opacity: 0.92
            property var app: null
            readonly property bool isFolder: app && app._isFolder === true

            IconImage {
                anchors.centerIn: parent
                visible: dragFloatIcon.app && !dragFloatIcon.isFolder
                source: dragFloatIcon.app && !dragFloatIcon.isFolder
                    ? Quickshell.iconPath(AppSearch.guessIcon(
                          dragFloatIcon.app.id || dragFloatIcon.app.icon), "image-missing")
                    : ""
                implicitSize: 40 * panelWindow.launcherUiScale
            }

            // Folder ghost — mini 2x2 grid of contained app icons,
            // mirroring the folder visual in the drawer.
            Grid {
                anchors.centerIn: parent
                columns: 2
                spacing: 2 * panelWindow.launcherUiScale
                visible: dragFloatIcon.isFolder

                Repeater {
                    model: dragFloatIcon.isFolder ? dragFloatIcon.app.appIds.slice(0, 4) : []
                    IconImage {
                        required property var modelData
                        source: Quickshell.iconPath(AppSearch.guessIcon(modelData), "image-missing")
                        implicitSize: 18 * panelWindow.launcherUiScale
                    }
                }
            }
        }

        Connections {
            target: appDrawer

            function onAppDragStarted(app, sceneX, sceneY) {
                contentFade.appDragging = true
                dragFloatIcon.app = app
                dragFloatIcon.x = sceneX - dragFloatIcon.width / 2
                dragFloatIcon.y = sceneY - dragFloatIcon.height / 2
                dragFloatIcon.visible = true
            }

            function onAppDragUpdate(sceneX, sceneY) {
                dragFloatIcon.x = sceneX - dragFloatIcon.width / 2
                dragFloatIcon.y = sceneY - dragFloatIcon.height / 2
                const ws = overviewLoader.item
                    ? overviewLoader.item.workspaceAtScenePoint(sceneX, sceneY)
                    : -1
                if (overviewLoader.item) overviewLoader.item.appDragHoverWorkspace = ws
            }

            function onAppDropped(app, sceneX, sceneY) {
                contentFade.appDragging = false
                dragFloatIcon.visible = false
                dragFloatIcon.app = null
                if (overviewLoader.item) overviewLoader.item.appDragHoverWorkspace = -1

                const ws = overviewLoader.item
                    ? overviewLoader.item.workspaceAtScenePoint(sceneX, sceneY)
                    : -1
                if (ws <= 0 || !app) return

                panelWindow.launchAppOnWorkspace(app, ws);
            }

            function onAppDragCancelled() {
                contentFade.appDragging = false
                dragFloatIcon.visible = false
                dragFloatIcon.app = null
                if (overviewLoader.item) overviewLoader.item.appDragHoverWorkspace = -1
            }
        }

        // An open overview captures clicks across the whole screen, but the
        // dismiss area inside the flickable stops at the clearance kept for
        // the bar and the dock. This backdrop sits under the flickable and
        // takes what lands outside it: a click on either band while this is
        // open, the dock's launcher button above all, means close.
        MouseArea {
            anchors.fill: parent
            enabled: GlobalStates.overviewOpen && !contentFade.appDragging
            onClicked: GlobalStates.overviewOpen = false
        }

        // The corner that opened this cannot close it. While the overview is
        // up the pointer stops reaching the hot corner's surface underneath,
        // so its own close path never runs and the gesture only works one way.
        // This answers in the same rectangle instead, on the same dwell, and
        // fires the same ripple, so the corner behaves the same in both
        // directions. Only while the corner is what opens this overview.
        //
        // Armed by leaving rather than by a timer: the pointer is already in
        // the corner at the moment the overview opens, and closing on that
        // would shut it again the instant it appeared.
        MouseArea {
            id: cornerClose
            z: 100
            x: 0
            y: 0
            width: Appearance.sizes.hotCornerWidth
            height: Appearance.sizes.hotCornerHeight
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            enabled: GlobalStates.overviewOpen
                && (Config.options?.bar.hotCorners.trigger ?? "off") === "default"
            // Ready the moment the overview appears, unless the pointer is
            // still sitting in the corner, which is where it is when the corner
            // itself just opened this. Then it waits for the pointer to leave,
            // so the overview does not shut again the instant it is shown.
            //
            // Deciding this by where the pointer already is, rather than after
            // a wait, is what makes the first return to the corner close it.
            // The overview appears once the ripple has played, by which time
            // the pointer has usually already moved on, and an arming rule that
            // ignored that spent the first visit doing nothing.
            property bool armed: false
            onEnabledChanged: armed = enabled && !containsMouse
            onExited: {
                cornerCloseDwell.stop();
                armed = true;
            }
            onEntered: if (armed) cornerCloseDwell.restart()
            Timer {
                id: cornerCloseDwell
                interval: 50
                onTriggered: {
                    GlobalStates.hotCornerTriggered();
                    overviewScope.dismissOverview();
                }
            }
        }

        Loader {
            id: scrollingLauncher
            anchors.fill: parent
            anchors.topMargin: panelWindow.edgeClearance("top")
            anchors.bottomMargin: panelWindow.edgeClearance("bottom") + 16
            anchors.leftMargin: panelWindow.edgeClearance("left") + 24
            anchors.rightMargin: panelWindow.edgeClearance("right") + 24
            active: (panelWindow.monitorIsFocused && (panelWindow.preloadScrollingLauncher
                || (panelWindow.useScrollingLauncher && GlobalStates.overviewOpen)))
                || (panelWindow.useScrollingLauncher && contentFade.opacity > 0)
                || panelWindow.scrollingActivationPending || panelWindow.scrollingPlacementPending
            visible: panelWindow.monitorIsFocused && panelWindow.useScrollingLauncher
            // Begin after the first frame so the slide is visible on a cold open too.
            transform: Translate {
                y: panelWindow.framePresented ? 0 : -40 * panelWindow.launcherUiScale
                Behavior on y {
                    enabled: panelWindow.requested
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this, { alwaysRunToEnd: false })
                }
            }
            onLoaded: Qt.callLater(panelWindow.beginScrollingLauncher)
            sourceComponent: ScrollingLauncher {
                screen: panelWindow.screen
                layout: GlobalStates.overviewOpen || contentFade.opacity > 0
                    ? panelWindow.launcherLayout : panelWindow.currentWorkspaceLayout
                viewState: scrollingViewState
                preload: panelWindow.preloadScrollingLauncher
                framePresented: panelWindow.framePresented
                fitColumns: (scrollFit.value ?? 0) === 1
                gapsIn: Scrolling.gaps(innerGaps.value)
                gapsOut: Scrolling.gaps(outerGaps.value)
                windowBorder: Number(borderSize.value ?? 0)
                screenCenterX: panelWindow.width / 2 - scrollingLauncher.x
                screenCenterY: panelWindow.height / 2 - scrollingLauncher.y
                screenScale: panelWindow.launcherUiScale
                workspaceLayout: panelWindow.workspaceLayout
                rendering: opened || contentFade.opacity > 0
                onActivationPendingChanged: panelWindow.scrollingActivationPending = activationPending
                onPlacementPendingChanged: panelWindow.scrollingPlacementPending = placementPending
                onAppDropped: (app, workspace) => panelWindow.launchAppOnWorkspace(app, workspace)
            }
        }

        StyledFlickable {
            id: flickable
            anchors.fill: parent
            // Inset by whatever holds each edge, so nothing sits under the
            // bar or the dock.
            anchors.topMargin: panelWindow.edgeClearance("top")
            anchors.bottomMargin: panelWindow.edgeClearance("bottom")
            anchors.leftMargin: panelWindow.edgeClearance("left")
            anchors.rightMargin: panelWindow.edgeClearance("right")
            contentWidth: columnLayout.implicitWidth
            contentHeight: columnLayout.implicitHeight
            clip: true
            visible: !panelWindow.useScrollingLauncher
            enabled: !panelWindow.useScrollingLauncher
            // Disable scrolling when workspacesOnly mode is active —
            // there's nothing below the workspace previews in that view,
            // so allowing the flickable to scroll just lets the user
            // shove the workspaces off-screen with no way to recover.
            interactive: !contentFade.appDragging && !GlobalStates.overviewWorkspacesOnly
            boundsBehavior: GlobalStates.overviewWorkspacesOnly ? Flickable.StopAtBounds : Flickable.DragAndOvershootBounds

            onContentYChanged: {
                // Drag-overshoot past the top while expanded → collapse.
                // Wheel-based collapse is handled by wheelOverlay below.
                if (appDrawer.expanded && appDrawer.collapsible && contentY < -30)
                    panelWindow.collapseDrawer(false);
            }

            // Click empty space to close. Inside the flickable + z:-1 so it sits
            // behind the widgets (which consume their own clicks).
            MouseArea {
                id: dismissArea
                z: -1
                width: flickable.width
                height: Math.max(flickable.height, columnLayout.implicitHeight)
                enabled: GlobalStates.overviewOpen && !contentFade.appDragging
                onClicked: GlobalStates.overviewOpen = false
            }

            ColumnLayout {
                id: columnLayout
                width: flickable.width
                spacing: 20 * panelWindow.launcherUiScale
                readonly property real drawerWidth: Math.min(1200 * panelWindow.launcherUiScale, flickable.width - 40 * panelWindow.launcherUiScale)
                property real cachedOverviewWidth: drawerWidth

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        if (appDrawer.expanded && appDrawer.collapsible) {
                            panelWindow.collapseDrawer(true);
                        } else if (panelWindow.searchingText !== "") {
                            searchWidget.cancelSearch();
                            Qt.callLater(() => { searchWidget.focusSearchInput(); });
                        } else {
                            overviewScope.dismissOverview();
                        }
                    } else if (event.key === Qt.Key_Left) {
                        if (!panelWindow.searchingText)
                            Hyprland.dispatch(`hl.dsp.focus({ workspace = "r-1" })`);
                    } else if (event.key === Qt.Key_Right) {
                        if (!panelWindow.searchingText)
                            Hyprland.dispatch(`hl.dsp.focus({ workspace = "r+1" })`);
                    }
                }
                    
                // Keeps the full list clear of the top bar when it is the
                // first thing in the column. With the search box above it that
                // job is already done, and the gap would only push the box
                // down out of line with where it sits otherwise.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: panelWindow.drawerOwnsSearch ? 10 * panelWindow.launcherUiScale : 0
                    visible: panelWindow.drawerOwnsSearch

                    Behavior on Layout.preferredHeight {
                        animation: Appearance.animation.elementResize.numberAnimation.createObject(this, { alwaysRunToEnd: false })
                    }
                }

                SearchWidget {
                    id: searchWidget
                    quietStyle: false
                    uiScale: panelWindow.launcherUiScale
                    maximumResultsHeight: 600 * uiScale
                    Layout.alignment: Qt.AlignHCenter
                    // Hidden when the app drawer has taken the search over.
                    // Also hidden when overview was opened in workspaces-only
                    // mode by the hot corner so the user gets a clean
                    // workspace switcher with no chrome.
                    visible: !panelWindow.drawerOwnsSearch && !GlobalStates.overviewWorkspacesOnly
                    Layout.maximumHeight: (panelWindow.drawerOwnsSearch || GlobalStates.overviewWorkspacesOnly) ? 0 : implicitHeight
                    opacity: (panelWindow.drawerOwnsSearch || GlobalStates.overviewWorkspacesOnly) ? 0 : 1
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this, { alwaysRunToEnd: false })
                    }
                    Behavior on Layout.maximumHeight {
                        animation: Appearance.animation.elementResize.numberAnimation.createObject(this, { alwaysRunToEnd: false })
                    }
                    Synchronizer on searchingText {
                        property alias source: panelWindow.searchingText
                    }
                }

                Loader {
                    id: overviewLoader
                    Layout.alignment: Qt.AlignHCenter
                    active: panelWindow.monitorIsFocused && !panelWindow.useScrollingLauncher && Config.options.overview.enable
                        && !appDrawer.expanded && (panelWindow.preloadSurface || panelWindow.requested || contentFade.opacity > 0)
                    Layout.maximumHeight: appDrawer.expanded ? 0 : (item ? item.implicitHeight : 0)
                    opacity: appDrawer.expanded ? 0 : 1
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this, { alwaysRunToEnd: false })
                    }
                    Behavior on Layout.maximumHeight {
                        enabled: panelWindow.framePresented
                        animation: Appearance.animation.elementResize.numberAnimation.createObject(this, { alwaysRunToEnd: false })
                    }
                    // Cache width so the drawer can match it after this loader deactivates
                    onWidthChanged: if (width > 0) columnLayout.cachedOverviewWidth = width
                    sourceComponent: OverviewWidget {
                        screen: panelWindow.screen
                        uiScale: panelWindow.launcherUiScale
                        workspaceLayout: panelWindow.workspaceLayout
                        previewsReady: panelWindow.preloadSurface || panelWindow.framePresented
                        visible: (panelWindow.searchingText == "")
                        onFocusSearchRequested: searchWidget.focusSearchInput()
                    }
                }
                    
                ApplicationDrawer {
                    id: appDrawer
                    populateGrid: !panelWindow.useScrollingLauncher
                        && ((panelWindow.preloadSurface && panelWindow.monitorIsFocused) || panelWindow.framePresented)
                    ownSearchField: panelWindow.drawerOwnsSearch
                    collapsible: !panelWindow.drawerStartsExpanded
                    workspaceStyle: false
                    uiScale: panelWindow.launcherUiScale
                    collapsedHeight: 400 * uiScale
                    wallpaper: ""
                    colBackground: Appearance.sizes.dockShowBackground ? Appearance.launcherDrawerBackground : "transparent"
                    contentColors: Appearance.drawerContent
                    surfaceRadius: Appearance.rounding.dockBody * uiScale
                    // The app-only view uses naturally sized rows instead of
                    // spreading three rows over the full expanded panel.
                    visibleRows: 0
                    columns: expanded ? Math.max(6, Math.floor((availableWidth - 60 * uiScale) / (135 * uiScale))) : 14
                    iconSize: (expanded ? 75 : 50) * uiScale
                    spacing: (expanded ? 45 : 30) * uiScale
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: false
                    Layout.preferredWidth: availableWidth
                    // Hidden when:
                    //  - the user is searching (search results take priority), OR
                    //  - overview was opened in workspaces-only mode by the
                    //    hot corner (no chrome — workspace previews only)
                    visible: panelWindow.searchingText == "" && !GlobalStates.overviewWorkspacesOnly
                    opacity: ((panelWindow.searchingText != "" && !panelWindow.drawerOwnsSearch) || GlobalStates.overviewWorkspacesOnly) ? 0 : 1
                    Layout.maximumHeight: ((panelWindow.searchingText != "" && !panelWindow.drawerOwnsSearch) || GlobalStates.overviewWorkspacesOnly) ? 0 : implicitHeight

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this, { alwaysRunToEnd: false })
                    }
                    Behavior on Layout.maximumHeight {
                        animation: Appearance.animation.elementResize.numberAnimation.createObject(this, { alwaysRunToEnd: false })
                    }

                    // The search box above is part of the same column, so the
                    // full list sizes itself against what is left rather than
                    // against the whole window.
                    availableHeight: flickable.height
                        - (searchWidget.visible ? searchWidget.implicitHeight + columnLayout.spacing : 0)
                    availableWidth: appDrawer.expanded
                        ? columnLayout.cachedOverviewWidth
                        : columnLayout.drawerWidth
                }
            }
        }

        // ── Wheel-event interceptor ──────────────────────────────────────────
        // Sits at z:100 — above the StyledFlickable and all its descendants,
        // including StyledFlickable's inner MouseArea (which would otherwise
        // consume every wheel event). Qt hit-tests siblings by z-order, so
        // this MouseArea is evaluated first.
        //
        //  acceptedButtons: Qt.NoButton  — mouse presses pass through to lower-z
        //                                  items (app icon buttons, etc.)
        //  propagateComposedEvents: true — click/release also fall through
        //
        //  Scroll DOWN while collapsed     → expand drawer
        //  Scroll UP  at grid+outer top    → collapse drawer
        //  Otherwise                       → scroll grid (expanded)
        //                                    or outer flickable (collapsed)
        MouseArea {
            id: wheelOverlay
            anchors.fill: flickable
            z: 100
            enabled: GlobalStates.overviewOpen && !panelWindow.useScrollingLauncher
            acceptedButtons: Qt.NoButton
            propagateComposedEvents: true

            onWheel: function(event) {
                // Workspaces-only mode (corner-triggered): swallow wheel
                // events entirely. There's nothing to scroll into (the
                // app drawer chrome is hidden and the flickable below has
                // interactive=false), so passing them through would just
                // let the user shove the workspace previews off-screen
                // via the expand-drawer path below.
                if (GlobalStates.overviewWorkspacesOnly) {
                    event.accepted = true;
                    return;
                }

                // An open folder card scrolls its own list, and this overlay
                // covers it, so the event has to be left alone to reach it.
                if (appDrawer.folderPopupVisible) return;

                const scrollingDown = event.angleDelta.y < 0;
                const scrollingUp   = event.angleDelta.y > 0;

                // Searching: route wheel events into the search result list
                // (SearchWidget.appResults) instead of the outer flickable.
                // Without this branch, the fallback at the bottom of this
                // handler scrolls `flickable.contentY`, which moves the whole
                // overview slightly and never scrolls the actual results.
                if (panelWindow.searchingText !== "" && !panelWindow.drawerOwnsSearch
                        && searchWidget.appResults && searchWidget.appResults.visible) {
                    const list         = searchWidget.appResults;
                    const threshold    = flickable.mouseScrollDeltaThreshold;
                    const delta        = event.angleDelta.y / threshold;
                    const scrollFactor = Math.abs(event.angleDelta.y) >= threshold
                                         ? flickable.mouseScrollFactor
                                         : flickable.touchpadScrollFactor;
                    const maxY    = Math.max(0, list.contentHeight - list.height);
                    const targetY = Math.max(0, Math.min(list.contentY - delta * scrollFactor, maxY));
                    list.contentY = targetY;
                    event.accepted = true;
                    return;
                }

                // Collapsed: route wheel events through the grid first.
                // Scroll down → scroll grid, or expand once at the bottom.
                // Scroll up   → scroll grid back up, or fall through once at the top.
                if (!appDrawer.expanded && panelWindow.searchingText === ""
                        && (scrollingDown || !appDrawer.isGridAtTop())) {
                    if (appDrawer.collapsible && scrollingDown && appDrawer.isGridAtBottom()) {
                        appDrawer.expanded = true;
                        flickable.contentY = 0;
                        event.accepted = true;
                        return;
                    }
                    const threshold    = flickable.mouseScrollDeltaThreshold;
                    const delta        = event.angleDelta.y / threshold;
                    const scrollFactor = Math.abs(event.angleDelta.y) >= threshold
                                         ? flickable.mouseScrollFactor
                                         : flickable.touchpadScrollFactor;
                    appDrawer.scrollGrid(delta, scrollFactor);
                    event.accepted = true;
                    return;
                }

                // Scrolling up off the top of the list goes back to the short
                // one, unless the full list is what the launcher opens on, in
                // which case there is no shorter state to go back to and the
                // scroll falls through to the grid below.
                if (appDrawer.expanded && appDrawer.collapsible
                        && scrollingUp
                        && flickable.scrollTargetY <= 0
                        && appDrawer.isGridAtTop()) {
                    panelWindow.collapseDrawer(true);
                    event.accepted = true;
                    return;
                }

                const threshold    = flickable.mouseScrollDeltaThreshold;
                const delta        = event.angleDelta.y / threshold;
                const scrollFactor = Math.abs(event.angleDelta.y) >= threshold
                                     ? flickable.mouseScrollFactor
                                     : flickable.touchpadScrollFactor;

                if (appDrawer.expanded) {
                    appDrawer.scrollGrid(delta, scrollFactor);
                } else {
                    const maxY    = Math.max(0, flickable.contentHeight - flickable.height);
                    const targetY = Math.max(0, Math.min(
                        flickable.scrollTargetY - delta * scrollFactor, maxY));
                    flickable.scrollTargetY = targetY;
                    flickable.contentY      = targetY;
                }
                event.accepted = true;
            }
        }

        }   // end contentFade

    }   // end PanelWindow

    }   // end Variants

    function dismissOverview() {
        for (const panel of overviewVariants.instances) {
            if (panel.monitorIsFocused && panel.useScrollingLauncher && GlobalStates.overviewOpen) {
                panel.closeScrollingLauncher();
                return;
            }
        }
        GlobalStates.overviewOpen = false;
    }

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            overviewScope.dismissOverview();
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        for (const w of overviewVariants.instances) w.setSearchingText(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            overviewScope.dismissOverview();
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        for (const w of overviewVariants.instances) w.setSearchingText(Config.options.search.prefix.emojis);
        GlobalStates.overviewOpen = true;
    }

    function toggleSearch() {
        if (GlobalStates.wallpaperSelectorOpen || GlobalStates.sessionOpen) return;
        if (GlobalStates.overviewOpen) overviewScope.dismissOverview();
        else if (!IslandLauncher.toggle()) GlobalStates.overviewOpen = true;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            overviewScope.toggleSearch();
        }
        function workspacesToggle() {
            if (GlobalStates.overviewOpen) overviewScope.dismissOverview();
            else GlobalStates.overviewOpen = true;
        }
        function close() {
            IslandLauncher.close();
            overviewScope.dismissOverview();
        }
        function open() {
            if (GlobalStates.wallpaperSelectorOpen || GlobalStates.sessionOpen) return;
            if (!IslandLauncher.open()) GlobalStates.overviewOpen = true;
        }
        function toggleReleaseInterrupt() {
            GlobalStates.superReleaseMightTrigger = false;
        }
        function clipboardToggle() {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles search on press"

        onPressed: {
            overviewScope.toggleSearch();
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            overviewScope.dismissOverview();
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            if (GlobalStates.overviewOpen) overviewScope.dismissOverview();
            else GlobalStates.overviewOpen = true;
        }
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        // Hyprland's native release bind already suppresses Super combinations.
        onReleased: {
            overviewScope.toggleSearch();
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Interrupts possibility of search being toggled on release. " + "This is necessary because GlobalShortcut.onReleased in quickshell triggers whether or not you press something else while holding the key. " + "To make sure this works consistently, use binditn = MODKEYS, catchall in an automatically triggered submap that includes everything."

        onPressed: {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }
    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Toggle clipboard query on overview widget"

        onPressed: {
            overviewScope.toggleClipboard();
        }
    }

    GlobalShortcut {
        name: "overviewEmojiToggle"
        description: "Toggle emoji query on overview widget"

        onPressed: {
            overviewScope.toggleEmojis();
        }
    }
}
