import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    // ── NVIDIA surface-commit race guard ────────────────────────────────────
    // On NVIDIA (and other GPUs with slower Wayland surface commits) the
    // HyprlandFocusGrab fires onCleared immediately after the overview opens
    // from a dock button click, because the overview's Wayland surface hasn't
    // been committed to the compositor yet and focus is still on the dock.
    // This causes the overview to flash and instantly close.
    //
    // Two-phase fix to handle both the initial race and a secondary race:
    //
    //  Phase 1 (0 → 120 ms):  Surface is committing.  Any onCleared that fires
    //    during this window is the false-positive — ignore it.
    //
    //  Phase 2 (120 ms):  rearmTimer fires while the guard is STILL active.
    //    Re-adding the window to the focus grab transitions grab.active from
    //    false → true again, which on NVIDIA can itself trigger a second
    //    immediate onCleared (same race, new grab setup).  Keeping ignoreDismiss
    //    true here absorbs that second false-positive too.
    //
    //  Phase 3 (300 ms):  dismissGuardTimer fires and clears ignoreDismiss.
    //    By this point both races have settled and the surface is fully
    //    committed, so real dismiss events (clicking outside) work normally.
    property bool ignoreDismiss: false

    // Phase 2: re-arm the grab while the guard is still active.
    Timer {
        id: rearmTimer
        interval: 120
        onTriggered: {
            if (GlobalStates.overviewOpen) {
                GlobalFocusGrab.addDismissable(panelWindow);
            }
        }
    }

    // Phase 3: clear the guard after both races have settled.
    Timer {
        id: dismissGuardTimer
        interval: 300
        onTriggered: {
            overviewScope.ignoreDismiss = false;
        }
    }

    PanelWindow {
        id: panelWindow
        property string searchingText: ""
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
        property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
        // False when the user has picked Scrolling Overview as the
        // hot-corner trigger: the drawer is the overview's primary
        // content in that mode (it opens pre-expanded), so collapsing
        // it would leave the workspace-preview pane behind — a layout
        // we don't want users to land in unintentionally. All collapse
        // paths (drag-overshoot, wheel-up at the top, Escape) gate on
        // this, and Escape becomes "close the overview" instead of
        // "collapse the drawer".
        readonly property bool canCollapseAppDrawer: Config.options.bar.hotCorners.trigger !== "scrolloverview"
        // True while the user has Scrolling Overview as their
        // hot-corner trigger AND the drawer is in its pre-expanded
        // launcher state. In this mode:
        //  - the top SearchWidget stays visible above the drawer
        //    (instead of getting hidden by the drawer-expanded
        //    visibility binding) and owns all keyboard input
        //  - the drawer's internal search field is hidden via
        //    useExternalSearch (no two-input clash)
        //  - typing in the SearchWidget hides the drawer the same
        //    way it does in the regular launcher (search results
        //    take over the visual surface); clearing the search
        //    brings the pre-expanded drawer back
        readonly property bool scrolloverviewLauncherMode:
            appDrawer.expanded && Config.options.bar.hotCorners.trigger === "scrolloverview"
        // Stay visible during fade-out; hideTimer cuts visibility after animation
        visible: GlobalStates.overviewOpen || contentFade.opacity > 0

        WlrLayershell.namespace: "quickshell:overview"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        // Full-screen so the dim overlay covers app windows behind the overview.
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Connections {
            target: GlobalStates
            function onOverviewOpenChanged() {
                if (!GlobalStates.overviewOpen) {
                    searchWidget.disableExpandAnimation();
                    overviewScope.dontAutoCancelSearch = false;
                    // Reset drawer state
                    appDrawer.expanded = false;
                    appDrawer.searchText = "";
                    appDrawer.folderPopupVisible = false;
                    appDrawer.openFolder = null;
                    appDrawer.resetScroll();
                    flickable.contentY = 0;
                    rearmTimer.stop();
                    dismissGuardTimer.stop();
                    overviewScope.ignoreDismiss = false;
                    GlobalFocusGrab.dismiss();
                } else {
                    if (!overviewScope.dontAutoCancelSearch) {
                        searchWidget.cancelSearch();
                    }
                    // Reset drawer state on open. When the user has
                    // picked "Scrolling Overview" as the hot-corner
                    // trigger they get workspace switching from the
                    // plugin, so the dots overview's workspace-preview
                    // pane is redundant — open it with the app drawer
                    // already fully expanded so it acts as a pure app
                    // launcher. Workspaces-only mode (the "default"
                    // trigger's hot-corner path) overrides this anyway:
                    // it hides the drawer entirely via existing
                    // visibility bindings.
                    //
                    // Skip the pre-expand when the overview was opened
                    // via toggleClipboard / toggleEmojis (Super+V /
                    // Super+.) — those paths set dontAutoCancelSearch
                    // to keep the search prefix they just primed, and
                    // expanding the drawer hides the search widget
                    // where their results render.
                    //
                    // Suppress the resize Behavior just for this state
                    // change so the drawer pops in pre-expanded instead
                    // of animating from collapsedHeight → expandedHeight
                    // every time. Re-enabled on the next event-loop tick
                    // via Qt.callLater so subsequent in-overview expand /
                    // collapse interactions still animate normally.
                    const openExpanded = (Config.options.bar.hotCorners.trigger === "scrolloverview")
                                         && !overviewScope.dontAutoCancelSearch;
                    if (openExpanded) appDrawer.disableExpandAnimation();
                    appDrawer.expanded = openExpanded;
                    if (openExpanded) Qt.callLater(() => appDrawer.enableExpandAnimation());
                    appDrawer.searchText = "";
                    appDrawer.folderPopupVisible = false;
                    appDrawer.openFolder = null;
                    appDrawer.resetScroll();
                    // Arm the two-phase dismiss guard (see comment above).
                    overviewScope.ignoreDismiss = true;
                    rearmTimer.restart();
                    dismissGuardTimer.restart();
                    GlobalFocusGrab.addDismissable(panelWindow);
                }
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                if (contentFade.appDragging) return  // don't close during app drag
                if (overviewScope.ignoreDismiss) return  // absorb NVIDIA surface-commit race
                GlobalStates.overviewOpen = false;
            }
        }
        function setSearchingText(text) {
            searchWidget.setSearchingText(text);
            searchWidget.focusFirstItem();
        }

        // Wraps all content so a single opacity animation fades everything together
        Item {
            id: contentFade
            anchors.fill: parent
            opacity: GlobalStates.overviewOpen ? 1 : 0
            property bool appDragging: false
            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

        // Floating icon that follows the cursor during app drag
        Rectangle {
            id: dragFloatIcon
            z: 9999
            visible: false
            width: 56
            height: 56
            radius: Appearance.rounding.normal
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
                implicitSize: 40
            }

            // Folder ghost — mini 2x2 grid of contained app icons,
            // mirroring the folder visual in the drawer.
            Grid {
                anchors.centerIn: parent
                columns: 2
                spacing: 2
                visible: dragFloatIcon.isFolder

                Repeater {
                    model: dragFloatIcon.isFolder ? dragFloatIcon.app.appIds.slice(0, 4) : []
                    IconImage {
                        required property var modelData
                        source: Quickshell.iconPath(AppSearch.guessIcon(modelData), "image-missing")
                        implicitSize: 18
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

                // Folder drop → launch every contained app on the target workspace.
                // [workspace N silent] is per-spawn-PID and misses windows from
                // DBus-activated apps (GNOME Nautilus, Text Editor, etc.), which
                // are spawned by the long-running service rather than the binary
                // we exec. Focus the target workspace first so the service's new
                // windows land on it regardless of activation style.
                if (app._isFolder === true) {
                    const ids = app.appIds || []
                    if (ids.length === 0) return
                    Hyprland.dispatch(`workspace ${ws}`)
                    for (let i = 0; i < ids.length; i++) {
                        const entry = AppSearch.guessDesktopEntry(ids[i])
                        const parts = entry ? entry.command : null
                        if (parts && parts.length > 0) {
                            const cmd = parts.map(p => p.includes(" ") ? `"${p}"` : p).join(" ")
                            Hyprland.dispatch(`exec ${cmd}`)
                        }
                    }
                    return
                }

                // Launch single apps the same way as folder drops:
                // focus the target workspace first, then exec. This keeps
                // DBus-activated apps consistent with folder launches.
                const parts = app.command
                if (parts && parts.length > 0) {
                    const cmd = parts.map(p => p.includes(" ") ? `"${p}"` : p).join(" ")
                    Hyprland.dispatch(`workspace ${ws}`)
                    Hyprland.dispatch(`exec ${cmd}`)
                }
            }

            function onAppDragCancelled() {
                contentFade.appDragging = false
                dragFloatIcon.visible = false
                dragFloatIcon.app = null
                if (overviewLoader.item) overviewLoader.item.appDragHoverWorkspace = -1
            }
        }

        StyledFlickable {
            id: flickable
            anchors.fill: parent
            contentWidth: columnLayout.implicitWidth
            contentHeight: columnLayout.implicitHeight
            clip: true
            visible: true
            // Disable scrolling when workspacesOnly mode is active —
            // there's nothing below the workspace previews in that view,
            // so allowing the flickable to scroll just lets the user
            // shove the workspaces off-screen with no way to recover.
            interactive: !contentFade.appDragging && !GlobalStates.overviewWorkspacesOnly
            boundsBehavior: GlobalStates.overviewWorkspacesOnly ? Flickable.StopAtBounds : Flickable.DragAndOvershootBounds

            onContentYChanged: {
                // Drag-overshoot past the top while expanded → collapse.
                // Wheel-based collapse is handled by wheelOverlay below.
                // Skipped in scrolloverview-trigger mode: the drawer
                // can't be collapsed there (see canCollapseAppDrawer).
                if (appDrawer.expanded && contentY < -30 && panelWindow.canCollapseAppDrawer) {
                    appDrawer.expanded = false;
                    appDrawer.searchText = "";
                    Qt.callLater(() => { flickable.contentY = 0; });
                }
            }
            
            ColumnLayout {
                id: columnLayout
                width: flickable.width
                spacing: 20
                property real cachedOverviewWidth: Math.min(1200, flickable.width - 40)

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        if (!panelWindow.canCollapseAppDrawer) {
                            // Scrolloverview-trigger mode: the regular
                            // launcher view (small drawer + workspace
                            // previews) isn't a state the user should
                            // ever land in here. Whether the current
                            // view is the pre-expanded drawer or a
                            // search view (emoji / clipboard primed
                            // by Super+. / Super+V), Escape closes the
                            // overview outright instead of stepping
                            // back into the launcher.
                            GlobalStates.overviewOpen = false;
                        } else if (appDrawer.expanded) {
                            appDrawer.expanded = false;
                            appDrawer.searchText = "";
                            Qt.callLater(() => { flickable.contentY = 0; });
                            columnLayout.forceActiveFocus();
                            Qt.callLater(() => { searchWidget.focusSearchInput(); });
                        } else if (panelWindow.searchingText !== "") {
                            searchWidget.cancelSearch();
                            Qt.callLater(() => { searchWidget.focusSearchInput(); });
                        } else {
                            GlobalStates.overviewOpen = false;
                        }
                    } else if (appDrawer.expanded && (
                            event.key === Qt.Key_Left  || event.key === Qt.Key_Right ||
                            event.key === Qt.Key_Up    || event.key === Qt.Key_Down)) {
                        // Drawer is expanded — workspace previews are
                        // hidden anyway, so route arrows to the app
                        // grid for icon-to-icon navigation instead of
                        // dispatching workspace switches. Without this
                        // guard the arrow events bubble up here from
                        // the drawer's empty search field and trigger
                        // the workspace-switch path below.
                        if (appDrawer.moveSelection(event.key))
                            event.accepted = true;
                    } else if (event.key === Qt.Key_Left) {
                        if (!panelWindow.searchingText)
                            Hyprland.dispatch("workspace r-1");
                    } else if (event.key === Qt.Key_Right) {
                        if (!panelWindow.searchingText)
                            Hyprland.dispatch("workspace r+1");
                    } else if (appDrawer.expanded
                               && event.text && event.text.length > 0
                               && event.text.charCodeAt(0) >= 0x20
                               && (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) === 0) {
                        // Printable keystroke that bubbled up here means
                        // focus is somewhere other than the drawer's
                        // search field (most commonly a grid delegate
                        // the user arrow-keyed into). Route it back to
                        // the search field so typing keeps filtering
                        // apps instead of being dropped.
                        appDrawer.focusSearchAndAppend(event.text);
                        event.accepted = true;
                    }
                }
                    
                // Spacer to prevent drawer from overlapping top bar when
                // expanded. Suppressed in scrolloverview-launcher mode
                // so the SearchWidget below sits at the same y-position
                // it normally occupies (matching the regular launcher
                // overview's spacing).
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: (appDrawer.expanded && !panelWindow.scrolloverviewLauncherMode) ? 10 : 0
                    visible: appDrawer.expanded && !panelWindow.scrolloverviewLauncherMode
                    
                    Behavior on Layout.preferredHeight {
                        NumberAnimation {
                            duration: Appearance.animation.elementResize.duration
                            easing.type: Appearance.animation.elementResize.type
                            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                        }
                    }
                }

                SearchWidget {
                    id: searchWidget
                    anchors.horizontalCenter: parent.horizontalCenter
                    Layout.alignment: Qt.AlignHCenter
                    // Hidden when the app drawer is expanded (it takes
                    // over) — except in scrolloverview-launcher mode,
                    // where the SearchWidget is the single search owner
                    // and stays visible above the drawer. Also hidden
                    // when overview was opened in workspaces-only mode
                    // by the hot corner so the user gets a clean
                    // workspace switcher with no chrome.
                    visible: (!appDrawer.expanded || panelWindow.scrolloverviewLauncherMode) && !GlobalStates.overviewWorkspacesOnly
                    Layout.maximumHeight: ((appDrawer.expanded && !panelWindow.scrolloverviewLauncherMode) || GlobalStates.overviewWorkspacesOnly) ? 0 : implicitHeight
                    opacity: ((appDrawer.expanded && !panelWindow.scrolloverviewLauncherMode) || GlobalStates.overviewWorkspacesOnly) ? 0 : 1
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    Behavior on Layout.maximumHeight {
                        NumberAnimation {
                            duration: Appearance.animation.elementResize.duration
                            easing.type: Appearance.animation.elementResize.type
                            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                        }
                    }
                    Synchronizer on searchingText {
                        property alias source: panelWindow.searchingText
                    }
                }

                Loader {
                    id: overviewLoader
                    Layout.alignment: Qt.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    active: GlobalStates.overviewOpen && (Config?.options.overview.enable ?? true) && !appDrawer.expanded
                    // Drop out of layout entirely (only) in
                    // scrolloverview-launcher mode — otherwise the
                    // empty Loader still gets columnLayout.spacing on
                    // both sides, doubling the gap between the
                    // SearchWidget and the drawer (the SearchWidget
                    // is the one that's visible above an expanded
                    // drawer in this mode; the regular collapsed and
                    // expanded modes keep their existing spacing).
                    visible: !panelWindow.scrolloverviewLauncherMode
                    Layout.maximumHeight: appDrawer.expanded ? 0 : (item ? item.implicitHeight : 0)
                    opacity: appDrawer.expanded ? 0 : 1
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    Behavior on Layout.maximumHeight {
                        NumberAnimation {
                            duration: Appearance.animation.elementResize.duration
                            easing.type: Appearance.animation.elementResize.type
                            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                        }
                    }
                    // Cache width so the drawer can match it after this loader deactivates
                    onWidthChanged: if (width > 0) columnLayout.cachedOverviewWidth = width
                    sourceComponent: OverviewWidget {
                        screen: panelWindow.screen
                        visible: (panelWindow.searchingText == "")
                    }
                }
                    
                ApplicationDrawer {
                    id: appDrawer
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: false
                    Layout.preferredWidth: appDrawer.expanded
                        ? columnLayout.cachedOverviewWidth
                        : Math.min(1200, flickable.width - 40)
                    // Hand off internal-search ownership to the top
                    // SearchWidget while we're in scrolloverview-
                    // launcher mode (drawer pre-expanded). This hides
                    // the drawer's TextField; the searchText Binding{}
                    // below pipes the top widget's stripped query in.
                    useExternalSearch: panelWindow.scrolloverviewLauncherMode
                    // Hidden when:
                    //  - the user is searching (search results take
                    //    priority — including in scrolloverview-
                    //    launcher mode, where the SearchWidget's
                    //    results dropdown is the active surface
                    //    while typing), OR
                    //  - overview was opened in workspaces-only mode by the
                    //    hot corner (no chrome — workspace previews only)
                    visible: panelWindow.searchingText == "" && !GlobalStates.overviewWorkspacesOnly
                    opacity: ((panelWindow.searchingText != "" && !appDrawer.expanded) || GlobalStates.overviewWorkspacesOnly) ? 0 : 1
                    Layout.maximumHeight: ((panelWindow.searchingText != "" && !appDrawer.expanded) || GlobalStates.overviewWorkspacesOnly) ? 0 : implicitHeight
                        
                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                    Behavior on Layout.maximumHeight {
                        NumberAnimation {
                            duration: Appearance.animation.elementResize.duration
                            easing.type: Appearance.animation.elementResize.type
                            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                        }
                    }
                    
                    availableHeight: flickable.height
                    availableWidth: appDrawer.expanded
                        ? columnLayout.cachedOverviewWidth
                        : Math.min(1200, flickable.width - 40)
                    // Match the non-launcher expanded drawer's bottom-y
                    // in scrolloverview-launcher mode so the gap to
                    // the dock is identical across modes.
                    //
                    // Non-launcher expanded drawer top sits at:
                    //   spacer(10) + spacing(20) + loader(0) + spacing(20) = 50
                    // Launcher drawer top sits at:
                    //   searchWidget.height + spacing(20)
                    // Top-delta = (searchWidget.height + 20) - 50
                    //           = searchWidget.height - 30
                    // Subtracting that from the drawer's expanded
                    // height (bypassing the 0.85 factor) lands the
                    // bottom-y at the same place it would in non-
                    // launcher mode.
                    expandedHeightAdjustment: panelWindow.scrolloverviewLauncherMode
                        ? Math.max(0, searchWidget.height - 30)
                        : 0
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
            enabled: GlobalStates.overviewOpen
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

                const scrollingDown = event.angleDelta.y < 0;
                const scrollingUp   = event.angleDelta.y > 0;

                // Searching: route wheel events into the search result list
                // (SearchWidget.appResults) instead of the outer flickable.
                // Without this branch, the fallback at the bottom of this
                // handler scrolls `flickable.contentY`, which moves the whole
                // overview slightly and never scrolls the actual results.
                if (panelWindow.searchingText !== "" && !appDrawer.expanded
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
                    if (scrollingDown && appDrawer.isGridAtBottom()) {
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

                if (appDrawer.expanded && scrollingUp
                        && flickable.scrollTargetY <= 0
                        && appDrawer.isGridAtTop()
                        && panelWindow.canCollapseAppDrawer) {
                    appDrawer.expanded = false;
                    appDrawer.searchText = "";
                    Qt.callLater(() => { flickable.contentY = 0; });
                    columnLayout.forceActiveFocus();
                    Qt.callLater(() => { searchWidget.focusSearchInput(); });
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

    function toggleClipboard() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.clipboard);
        GlobalStates.overviewOpen = true;
    }

    function toggleEmojis() {
        if (GlobalStates.overviewOpen && overviewScope.dontAutoCancelSearch) {
            GlobalStates.overviewOpen = false;
            return;
        }
        overviewScope.dontAutoCancelSearch = true;
        panelWindow.setSearchingText(Config.options.search.prefix.emojis);
        GlobalStates.overviewOpen = true;
    }

    IpcHandler {
        target: "search"

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function workspacesToggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
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
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            GlobalStates.overviewOpen = false;
        }
    }
    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles search on release"

        onPressed: {
            GlobalStates.superReleaseMightTrigger = true;
        }

        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
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
