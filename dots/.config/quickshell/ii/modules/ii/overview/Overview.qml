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
                    // Reset drawer state on open
                    appDrawer.expanded = false;
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

            IconImage {
                anchors.centerIn: parent
                source: dragFloatIcon.app
                    ? Quickshell.iconPath(AppSearch.guessIcon(
                          dragFloatIcon.app.id || dragFloatIcon.app.icon), "image-missing")
                    : ""
                implicitSize: 40
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
                if (ws > 0 && app) {
                    // Use the parsed command array from DesktopEntry so the
                    // command is reliable (app.exec is raw and not runnable).
                    const parts = app.command
                    if (parts && parts.length > 0) {
                        const cmd = parts.map(p => p.includes(" ") ? `"${p}"` : p).join(" ")
                        Hyprland.dispatch(`exec [workspace ${ws} silent] ${cmd}`)
                    }
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
            interactive: !contentFade.appDragging
            boundsBehavior: Flickable.DragAndOvershootBounds

            onContentYChanged: {
                // Drag-overshoot past the top while expanded → collapse.
                // Wheel-based collapse is handled by wheelOverlay below.
                if (appDrawer.expanded && contentY < -30) {
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
                        if (appDrawer.expanded) {
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
                    } else if (event.key === Qt.Key_Left) {
                        if (!panelWindow.searchingText)
                            Hyprland.dispatch("workspace r-1");
                    } else if (event.key === Qt.Key_Right) {
                        if (!panelWindow.searchingText)
                            Hyprland.dispatch("workspace r+1");
                    }
                }
                    
                // Spacer to prevent drawer from overlapping top bar when expanded
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: appDrawer.expanded ? 10 : 0
                    visible: appDrawer.expanded
                    
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
                    visible: !appDrawer.expanded
                    Layout.maximumHeight: appDrawer.expanded ? 0 : implicitHeight
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
                    Synchronizer on searchingText {
                        property alias source: panelWindow.searchingText
                    }
                }

                Loader {
                    id: overviewLoader
                    Layout.alignment: Qt.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    active: GlobalStates.overviewOpen && (Config?.options.overview.enable ?? true) && !appDrawer.expanded
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
                    visible: (panelWindow.searchingText == "")
                    // But hide it when searching and not expanded (search results take priority)
                    opacity: (panelWindow.searchingText != "" && !appDrawer.expanded) ? 0 : 1
                    Layout.maximumHeight: (panelWindow.searchingText != "" && !appDrawer.expanded) ? 0 : implicitHeight
                        
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
                const scrollingDown = event.angleDelta.y < 0;
                const scrollingUp   = event.angleDelta.y > 0;

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
                        && appDrawer.isGridAtTop()) {
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
