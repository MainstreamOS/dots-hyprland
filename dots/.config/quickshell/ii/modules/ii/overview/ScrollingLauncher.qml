pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models.hyprland
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "scrolling.js" as Scrolling
import "placement.js" as Placement
import "launcher-layout.js" as LauncherLayout

Item {
    id: root
    required property var screen
    required property string layout
    property Item dockBackdropSource: null
    property rect dockBackdropRect: Qt.rect(0, 0, 1, 1)
    property real screenCenterX: width / 2
    property real screenCenterY: height / 2
    required property real screenScale
    required property var workspaceLayout
    readonly property bool opened: GlobalStates.overviewOpen && visible
    property bool revealReady: false
    property real revealProgress: 0
    onOpenedChanged: if (revealReady) revealProgress = opened ? 1 : 0
    Component.onCompleted: {
        revealReady = true;
        if (opened) revealProgress = 1;
    }
    Behavior on revealProgress {
        NumberAnimation {
            duration: Appearance.animation.elementResize.duration
            easing.type: Appearance.animation.elementResize.type
            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
        }
    }
    transform: Translate { y: -40 * root.screenScale * (1 - root.revealProgress) }
    property bool rendering: opened
    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property int monitorId: monitor?.id ?? -1
    readonly property var monitorData: HyprlandData.monitors.find(m => m.id === monitorId)
        ?? ({ x: 0, y: 0, width: screen.width, height: screen.height, scale: 1 })
    // Keep geometry ready while closed; captureSource below is still detached
    // while idle. Clearing geometry makes every tile relayout on the first frame.
    readonly property var clients: activationPending ? activationClients
        : HyprlandData.windowList.filter(w => w.mapped && !w.hidden && w.monitor === monitorId)
    readonly property bool searching: search.searchingText.length > 0
    property bool activationPending: false
    property var activationClients: []
    readonly property bool restoringView: activationStart.running || activation.running
    readonly property int visibleCount: Math.max(1, Math.min(8, Config.options.overview.scrollingWorkspaces))
    property var emptyWorkspaceIds: []
    readonly property var availableWorkspaceIds: Scrolling.availableWorkspaceIds(visibleCount,
        HyprlandData.workspaces, monitorId, monitorData.activeWorkspace?.id ?? 1, emptyWorkspaceIds)
    property var workspaceIds: Scrolling.workspaceGroup(monitorData.activeWorkspace?.id ?? 1,
        visibleCount, availableWorkspaceIds)
    readonly property var occupiedIds: HyprlandData.workspaces.filter(w => w.id > 0 && w.monitorID === monitorId && w.windows > 0)
        .map(w => w.id).sort((a, b) => a - b)
    readonly property int shownCount: Math.min(visibleCount, workspaceIds.length)
    readonly property bool moreWorkspacesAbove: shownCount > 0 && availableWorkspaceIds.some(id => id < workspaceIds[0])
    readonly property bool moreWorkspacesBelow: shownCount > 0 && availableWorkspaceIds.some(id => id > workspaceIds[shownCount - 1])
    readonly property bool visibleWorkspacesOccupied: workspaceIds.length >= visibleCount
        && workspaceIds.every(id => occupiedIds.includes(id))
    readonly property int newWorkspaceId: {
        const used = new Set(HyprlandData.workspaces.filter(w => w.windows > 0).map(w => w.id));
        for (const client of clients) used.add(client.workspace.id);
        for (const id of availableWorkspaceIds) used.add(id);
        let id = 1;
        while (used.has(id)) id++;
        return id;
    }
    onAvailableWorkspaceIdsChanged: if (opened && !dragAddress) refreshWorkspaceIds()
    onOccupiedIdsChanged: {
        const remaining = emptyWorkspaceIds.filter(id => !occupiedIds.includes(id));
        if (remaining.length !== emptyWorkspaceIds.length) emptyWorkspaceIds = remaining;
    }
    property int selectedWorkspace: 1
    property int workspaceTransitionDirection: 0
    property var selectedByWorkspace: ({})
    property var pannedByWorkspace: ({})
    property var monocleOrder: ({})
    readonly property bool fitColumns: (scrollFit.value ?? 0) === 1
    HyprlandConfigOption { id: scrollFit; key: "scrolling:focus_fit_method" }
    HyprlandConfigOption { id: innerGaps; key: "general:gaps_in" }
    HyprlandConfigOption { id: outerGaps; key: "general:gaps_out" }
    HyprlandConfigOption { id: borderSize; key: "general:border_size" }
    readonly property var gapsIn: Scrolling.gaps(innerGaps.value)
    readonly property var gapsOut: Scrolling.gaps(outerGaps.value)
    readonly property real windowBorder: Number(borderSize.value ?? 0)
    readonly property bool showRecentApps: Config.options.overview.scrollingShowRecentApps
    property string dragAddress: ""
    property int dropWorkspace: 0
    property point dragPoint
    property Item dragItem: null
    property alias windowDragLayer: windowDragLayer
    property point dragGrab: Qt.point(0, 0)
    property size dragSize: Qt.size(1, 1)
    property var dropInfo: null
    property bool placementPending: false
    property int placementAttempts: 0
    readonly property var dragClient: clients.find(w => w.address === dragAddress) ?? null
    readonly property var contentColors: Appearance.launcherContent
    function workspaceRadius(width, height) {
        return RoundedCorners.on ? Math.min(width / 2, height / 2, Appearance.rounding.dockBody * uiScale) : 0;
    }
    readonly property var geometry: LauncherLayout.scrolling({
        unit: screenScale, width, height, aspect: screen.width / Math.max(1, screen.height),
        centerX: screenCenterX, centerY: screenCenterY,
        searchHeight: search.visible ? search.collapsedHeight + (20 + Appearance.sizes.elevationMargin) * screenScale : 0,
        bodyHeight: workspaceLayout.bodyHeight,
        dockSize: Config.options.dock.enable
            ? Appearance.sizes.dockHeightFor(Appearance.sizes.dockIconSize) + Appearance.sizes.dockEdgeGap : 0,
        horizontalDock: Appearance.sizes.dockEdge === "top" || Appearance.sizes.dockEdge === "bottom",
        workspacesOnly: GlobalStates.overviewWorkspacesOnly, count: visibleCount, shown: shownCount,
        swapped, recentApps: showRecentApps
    })
    // Text and controls follow the desktop's scale, independently of preview fit.
    readonly property real uiScale: screenScale
    readonly property real gap: geometry.gap
    readonly property real slotHeight: geometry.slotHeight
    readonly property real previewWidth: geometry.previewWidth
    readonly property real newWorkspaceHeight: geometry.plusHeight
    readonly property real appColumnInset: geometry.inset
    readonly property real overhang: geometry.overhang
    readonly property bool swapped: Config.options.overview.scrollingSwapSides
    signal appDropped(var app, int workspace)

    function renameWorkspace(workspace, sceneX, sceneY) {
        const point = root.mapFromItem(null, sceneX, sceneY);
        renamePopup.openFor(workspace, point.x, point.y);
    }
    WorkspaceRenamePopup {
        id: renamePopup
        onClosed: if (root.opened) root.focusSearchInput()
    }

    function prepare() {
        drawer.prepareGrid();
        recentApps.prepareGrid();
    }
    function begin(resetQuery = true) {
        activationStart.stop();
        activationPending = false;
        activationClients = [];
        emptyWorkspaceIds = [];
        selectedWorkspace = monitorData.activeWorkspace?.id ?? monitor?.activeWorkspace?.id ?? 1;
        setWorkspaceIds(Scrolling.workspaceGroup(selectedWorkspace, visibleCount, availableWorkspaceIds));
        // Panning is a workspace view, not a one-open selection. Retain live
        // anchors between opens and discard only windows that have gone away.
        const selections = {}, pans = {}, order = {};
        for (const id of Object.keys(selectedByWorkspace)) {
            if (clients.some(w => w.workspace.id === Number(id) && w.address === selectedByWorkspace[id])) {
                selections[id] = selectedByWorkspace[id];
                if (pannedByWorkspace[id]) pans[id] = true;
            }
        }
        for (const id of occupiedIds) {
            const windows = clients.filter(w => w.workspace.id === id);
            const previous = (monocleOrder[id] ?? []).filter(a => windows.some(w => w.address === a));
            order[id] = previous.concat(windows.filter(w => !previous.includes(w.address))
                .sort((a, b) => (a.focusHistoryID ?? 0) - (b.focusHistoryID ?? 0)).map(w => w.address));
        }
        selectedByWorkspace = selections;
        pannedByWorkspace = pans;
        monocleOrder = order;
        cancelDrag();
        const active = HyprlandData.clientForToplevel(ToplevelManager.activeToplevel);
        if (active && !pannedByWorkspace[active.workspace.id]) selectWindow(active.workspace.id, active.address);
        search.setSearchingText(resetQuery ? "" : LauncherSearch.query);
        drawer.closeContextMenu();
        drawer.folderPopupVisible = false;
        drawer.resetScroll();
        recentApps.closeContextMenu();
        recentApps.resetScroll();
        Qt.callLater(() => search.focusSearchInput());
    }
    function setSearchingText(text) { search.setSearchingText(text); }
    function focusSearchInput() { search.focusSearchInput(); }
    function selectWindow(workspace, address) {
        selectedByWorkspace = Object.assign({}, selectedByWorkspace, { [workspace]: address });
        selectedWorkspace = workspace;
    }
    function panWorkspace(workspace, address) {
        pannedByWorkspace = Object.assign({}, pannedByWorkspace, { [workspace]: true });
        selectWindow(workspace, address);
    }
    function setWorkspaceIds(ids, animate = false) {
        workspaceTransitionDirection = animate && workspaceIds.length > 0 && ids.length > 0
            ? Math.sign(ids[0] - workspaceIds[0]) : 0;
        workspaceIds = ids;
    }
    function refreshWorkspaceIds() {
        const valid = workspaceIds.filter(id => availableWorkspaceIds.includes(id));
        if (valid.length === workspaceIds.length && valid.length === Math.min(visibleCount, availableWorkspaceIds.length)
                && valid.includes(selectedWorkspace)) return;
        setWorkspaceIds(Scrolling.workspaceGroup(selectedWorkspace, visibleCount, availableWorkspaceIds));
    }
    function selectWorkspace(id) {
        selectedWorkspace = id;
        if (!workspaceIds.includes(id) && id > 0)
            setWorkspaceIds(Scrolling.workspaceGroup(id, visibleCount, availableWorkspaceIds), true);
        if (!selectedByWorkspace[id]) {
            const nearest = cardForWorkspace(id)?.activationView("")?.address
                ?? Scrolling.ordered(clients.filter(w => w.workspace.id === id))[0]?.address;
            if (nearest) selectWindow(id, nearest);
        }
    }
    function stepWorkspace(direction) {
        const candidates = availableWorkspaceIds.filter(id => direction < 0 ? id < selectedWorkspace : id > selectedWorkspace);
        const id = direction < 0 ? candidates[candidates.length - 1] : candidates[0];
        if (id !== undefined) selectWorkspace(id);
    }
    function shiftWorkspaceGroup(direction) {
        const start = availableWorkspaceIds.indexOf(workspaceIds[0]);
        if (start < 0) return;
        const next = Math.max(0, Math.min(availableWorkspaceIds.length - visibleCount, start + direction));
        if (next === start) return;
        setWorkspaceIds(availableWorkspaceIds.slice(next, next + visibleCount), true);
        if (!workspaceIds.includes(selectedWorkspace))
            selectWorkspace(direction > 0 ? workspaceIds[0] : workspaceIds[workspaceIds.length - 1]);
    }
    function addEmptyWorkspace() {
        const id = newWorkspaceId;
        emptyWorkspaceIds = emptyWorkspaceIds.concat(id);
        selectWorkspace(id);
    }
    function selectedCard() {
        for (let i = 0; i < cards.count; i++)
            if (cards.itemAt(i)?.workspaceId === selectedWorkspace) return cards.itemAt(i);
        return null;
    }
    function activateWindow(address) {
        const client = clients.find(w => w.address === address);
        if (client) activateWorkspace(client.workspace.id, address);
    }
    function closeWindow(address) {
        Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${address}" })`);
    }
    function dismissExternal(address) {
        // Release the launcher's keyboard grab before handing focus to
        // the new app or special workspace.
        if (address) {
            activationStart.stop();
            activationPending = true;
            restoreView({ address });
        }
        GlobalStates.overviewOpen = false;
    }
    function activateWorkspace(id, address = "") {
        if (!address) {
            GlobalStates.overviewOpen = false;
            Hyprland.dispatch(`hl.dsp.focus({ workspace = ${id} })`);
            return;
        }
        const card = cardForWorkspace(id);
        const view = card?.activationView(address, true);
        const floating = clients.some(w => w.address === address && w.floating);
        if (view?.revealed) panWorkspace(id, address);
        if (card?.layout === "scrolling" && view && !floating) {
            commitView(view);
            return;
        }
        // Monocle and floating windows still need keyboard handoff.
        commitView({ address });
    }

    function close() {
        if (activationPending) return;
        GlobalStates.overviewOpen = false;
    }
    function commitView(view) {
        activationClients = clients.slice();
        activationPending = true;
        restoreView(view);
    }
    function restoreView(view) {
        activation.command = ["hyprctl", "eval", Placement.activateScript(view.address, view.x)];
        activationAttempts = 0;
        activationStart.restart();
    }
    property int activationAttempts: 0
    Timer {
        id: activationStart
        interval: 32
        onTriggered: {
            root.activationAttempts++;
            activation.running = true;
        }
    }
    Process {
        id: activation
        onExited: (code, status) => {
            if (activationOutput.text.includes("overview-placement-focus-pending") && root.activationAttempts < 4) {
                activationStart.restart();
                return;
            }
            if (code !== 0 || activationOutput.text.includes("overview-placement-focus-pending"))
                console.warn("Overview workspace activation failed:", activationErrors.text || activationOutput.text);
            if (root.activationPending) {
                GlobalStates.overviewOpen = false;
                root.activationPending = false;
                root.activationClients = [];
            }
            HyprlandData.refreshSoon();
        }
        stdout: StdioCollector { id: activationOutput }
        stderr: StdioCollector { id: activationErrors }
    }
    function workspaceAt(sceneX, sceneY) {
        if (workspaceViewport.contains(workspaceViewport.mapFromItem(null, sceneX, sceneY))) {
            for (let i = 0; i < cards.count; i++)
                if (cards.itemAt(i)?.visible && cards.itemAt(i).workspaceId > 0
                        && cards.itemAt(i).containsScenePoint(sceneX, sceneY)) return cards.itemAt(i).workspaceId;
        }
        const point = newWorkspace.mapFromItem(null, sceneX, sceneY);
        if (newWorkspace.visible && point.x >= 0 && point.x <= newWorkspace.width && point.y >= 0 && point.y <= newWorkspace.height)
            return newWorkspaceId;
        return 0;
    }
    function cardForWorkspace(id) {
        for (let i = 0; i < cards.count; i++)
            if (cards.itemAt(i)?.workspaceId === id) return cards.itemAt(i);
        return null;
    }
    function beginWindowDrag(address, item, sceneX, sceneY) {
        if (placementPending) return false;
        dragSize = Qt.size(item.width, item.height);
        const point = mapFromItem(null, sceneX, sceneY);
        const origin = item.mapToItem(root, 0, 0);
        dragGrab = Qt.point(point.x - origin.x, point.y - origin.y);
        dragPoint = point;
        dragAddress = address;
        dragItem = item;
        updateDrag(sceneX, sceneY);
        return true;
    }
    function updateDrag(sceneX, sceneY) {
        dragPoint = mapFromItem(null, sceneX, sceneY);
        dropWorkspace = workspaceAt(sceneX, sceneY);
        dropInfo = dragAddress && dropWorkspace
            ? cardForWorkspace(dropWorkspace)?.placementAt(sceneX, sceneY) ?? null : null;
    }
    function finishDrag() {
        const client = dragClient;
        const creating = dropWorkspace === newWorkspaceId;
        const destination = dropWorkspace;
        if (client && dropWorkspace) {
            if (dropInfo) {
                placement.command = ["hyprctl", "repl", Placement.script(dragAddress, dropWorkspace,
                    dropInfo.anchor, dropInfo.direction, dropInfo.x, dropInfo.y)];
                // Column operations need desktop focus. Release the exclusive
                // layer for the drop, then restore search focus on completion.
                placementAttempts = 0;
                placementPending = true;
                placementStart.restart();
            } else if (client.workspace.id !== dropWorkspace) {
                Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${dropWorkspace}, follow = false, window = "address:${dragAddress}" })`);
            }
        }
        if (client && creating) selectedWorkspace = destination;
        cancelDrag();
    }
    function cancelDrag() { dragItem = null; dragAddress = ""; dropWorkspace = 0; dropInfo = null; }
    function beginAppDrag(app, sceneX, sceneY) {
        ghost.app = app;
        updateDrag(sceneX, sceneY);
    }
    function endAppDrag() {
        ghost.app = null;
        cancelDrag();
    }
    function dropApp(app, sceneX, sceneY) {
        const workspace = workspaceAt(sceneX, sceneY);
        if (workspace > 0) {
            const creating = workspace === newWorkspaceId;
            appDropped(app, workspace);
            if (creating) selectedWorkspace = workspace;
        }
        endAppDrag();
    }
    Timer {
        id: placementStart
        interval: 32
        onTriggered: {
            root.placementAttempts++;
            placement.running = true;
        }
    }
    Process {
        id: placement
        onExited: (code, status) => {
            // Layer commits and IPC run independently. If the compositor has
            // not released its exclusive focus yet, retry before any mutation.
            if (placementOutput.text.includes("overview-placement-focus-pending") && root.placementAttempts < 4) {
                placementStart.restart();
                return;
            }
            if (code !== 0 || placementOutput.text.includes("overview-placement-focus-pending"))
                console.warn("Overview window placement failed:", placementErrors.text || placementOutput.text);
            root.placementPending = false;
            HyprlandData.refreshSoon();
            if (root.opened) Qt.callLater(() => root.focusSearchInput());
        }
        stdout: StdioCollector { id: placementOutput }
        stderr: StdioCollector { id: placementErrors }
    }
    function handleKey(event) {
        if (event.key === Qt.Key_Escape) {
            if (dragAddress) cancelDrag();
            else if (search.searchingText) search.setSearchingText("");
            else close();
        } else if (!search.searchingText) {
            if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) stepWorkspace(event.key === Qt.Key_Up ? -1 : 1);
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) selectedCard()?.step(event.key === Qt.Key_Left ? -1 : 1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                const address = selectedByWorkspace[selectedWorkspace];
                if (address) activateWindow(address); else activateWorkspace(selectedWorkspace);
            } else return;
        } else return;
        event.accepted = true;
    }
    Keys.onPressed: event => root.handleKey(event)
    onVisibleCountChanged: if (opened) setWorkspaceIds(Scrolling.workspaceGroup(selectedWorkspace, visibleCount, availableWorkspaceIds))
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (!GlobalStates.overviewOpen) {
                cancelDrag();
                drawer.closeContextMenu();
                drawer.folderPopupVisible = false;
                recentApps.closeContextMenu();
            }
        }
    }

    SearchWidget {
        id: search
        quietStyle: true
        uiScale: root.screenScale
        visible: !GlobalStates.overviewWorkspacesOnly
        z: 10
        anchors.horizontalCenter: parent.horizontalCenter
        maximumResultsHeight: Math.min(600 * root.screenScale,
            Math.max(100 * root.screenScale, 1304 * root.uiScale - 110 * root.screenScale))
        onNavigationKeyPressed: event => root.handleKey(event)
    }
    Item {
        x: root.geometry.workspace.x
        y: root.geometry.workspace.y
        width: root.geometry.workspace.width; height: root.geometry.workspace.height
        // Keep capture contexts and masks allocated while search covers them.
        opacity: root.searching ? 0 : 1
        enabled: !root.searching && !root.activationPending
        Item {
            id: workspaceViewport
            readonly property real padding: Appearance.sizes.elevationMargin * root.uiScale
            y: -padding
            width: parent.width
            height: Math.max(0, root.shownCount * (root.slotHeight + root.gap) - root.gap) + padding * 2
            clip: true
            Repeater {
                id: cards
                // Retain workspace captures while whole cards slide between rows.
                model: ScriptModel { values: root.workspaceIds }
                delegate: ScrollingWorkspace {
                    id: workspaceCard
                    required property int index
                    required property int modelData
                    property real enterOffset: 0
                    controller: root
                    workspaceId: modelData
                    y: index * (root.slotHeight + root.gap) + workspaceViewport.padding
                    width: parent.width; height: root.slotHeight
                    cardWidth: root.previewWidth
                    transform: Translate { y: workspaceCard.enterOffset }
                    Behavior on y {
                        enabled: root.opened && root.workspaceTransitionDirection !== 0 && !root.dragAddress
                        NumberAnimation {
                            duration: Appearance.animation.elementResize.duration
                            easing.type: Appearance.animation.elementResize.type
                            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                        }
                    }
                    Component.onCompleted: {
                        if (root.opened && root.workspaceTransitionDirection !== 0) {
                            enterAnimation.from = root.workspaceTransitionDirection * (root.slotHeight + root.gap);
                            enterAnimation.start();
                        }
                    }
                    NumberAnimation {
                        id: enterAnimation
                        target: workspaceCard
                        property: "enterOffset"
                        to: 0
                        duration: Appearance.animation.elementResize.duration
                        easing.type: Appearance.animation.elementResize.type
                        easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                    }
                }
            }
        }
        RippleButton {
            id: newWorkspace
            objectName: "newWorkspace"
            visible: root.visibleWorkspacesOccupied
                && (!root.moreWorkspacesBelow || !Config.options.interactions.showWorkspaceNavigationArrows)
            x: (parent.width - width) / 2
            // Keep the complete target at the bottom of the fitted body,
            // even when fewer workspace slots are occupied.
            y: parent.height - height
            implicitWidth: root.previewWidth
            implicitHeight: root.newWorkspaceHeight
            width: implicitWidth
            height: implicitHeight
            focusPolicy: Qt.NoFocus
            leftInset: root.dropWorkspace === root.newWorkspaceId ? 0 : Math.max(0, (width - 48 * root.uiScale) / 2)
            rightInset: leftInset
            topInset: 6 * root.uiScale
            bottomInset: 6 * root.uiScale
            buttonRadius: RoundedCorners.on ? (root.dropWorkspace === root.newWorkspaceId ? Appearance.rounding.small * root.uiScale : 24 * root.uiScale) : 0
            colBackground: root.dropWorkspace === root.newWorkspaceId
                ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
            colBackgroundHover: Appearance.colors.colLayer2Hover
            Accessible.name: Translation.tr("New workspace")
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "add"
                iconSize: 28 * root.uiScale
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: root.contentColors.colOnLayer0
            }
            StyledToolTip { text: Translation.tr("New workspace") }
            onClicked: root.addEmptyWorkspace()
        }
        Repeater {
            model: Config.options.interactions.showWorkspaceNavigationArrows ? [-1, 1] : []
            delegate: WorkspaceNavigationButton {
                required property int modelData
                objectName: modelData < 0 ? "previousWorkspaces" : "nextWorkspaces"
                x: (parent.width - width) / 2
                y: modelData < 0 ? -height - root.gap
                    : parent.height - (root.newWorkspaceHeight + height) / 2
                visible: modelData < 0 ? root.moreWorkspacesAbove : root.moreWorkspacesBelow
                width: 40 * root.uiScale
                height: width
                uiScale: root.uiScale
                pressedAtRest: false
                iconName: modelData < 0 ? "keyboard_arrow_up" : "keyboard_arrow_down"
                Accessible.name: modelData < 0 ? Translation.tr("Previous workspace") : Translation.tr("Next workspace")
                StyledToolTip { text: parent.Accessible.name }
                onClicked: root.shiftWorkspaceGroup(modelData)
            }
        }
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const x = event.angleDelta.x || event.pixelDelta.x;
                const y = event.angleDelta.y || event.pixelDelta.y;
                if (!x && !y) return;
                if (Math.abs(x) > Math.abs(y)) root.selectedCard()?.step(x > 0 ? -1 : 1);
                else root.shiftWorkspaceGroup(y > 0 ? -1 : 1);
                event.accepted = true;
            }
        }
    }
    Item {
        id: appSide
        x: root.geometry.apps.x
        y: root.geometry.apps.y
        width: root.geometry.apps.width; height: root.geometry.apps.height
        visible: !GlobalStates.overviewWorkspacesOnly
        opacity: root.searching ? 0 : 1
        enabled: !root.searching && !root.activationPending
        ScrollingLauncherApps {
            launcher: root
            id: recentApps
            width: parent.width
            collapsedHeight: root.geometry.recentHeight
            visibleRows: 2
            visible: root.showRecentApps
            appSource: RecentApps.apps.slice(0, columns * visibleRows)
            panelTitle: Translation.tr("Recently used apps")
            emptyText: Translation.tr("No recently used apps yet")
        }
        ScrollingLauncherApps {
            launcher: root
            id: drawer
            y: root.geometry.drawerOffset
            width: parent.width
            collapsedHeight: root.geometry.drawerHeight
            visibleRows: root.showRecentApps ? 4 : 8
        }
    }
    Item {
        id: windowDragLayer
        anchors.fill: parent
        z: 30
    }
    Rectangle {
        id: ghost
        property var app: null
        z: 20
        visible: app !== null
        x: root.dragPoint.x - width / 2; y: root.dragPoint.y - height / 2
        width: 56 * root.uiScale; height: width
        radius: Appearance.rounding.normal * root.uiScale
        color: Appearance.colors.colSecondaryContainer
        opacity: 0.9
        IconImage {
            anchors.centerIn: parent
            implicitSize: 40 * root.uiScale
            source: Quickshell.iconPath(AppSearch.guessIcon(ghost.app?.id
                ?? root.clients.find(w => w.address === root.dragAddress)?.class ?? ""), "application-x-executable")
        }
    }
}
