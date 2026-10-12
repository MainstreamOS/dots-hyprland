pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "layout.js" as Layout

Scope {
    id: root
    readonly property real uiScale: Math.max(0.01, Math.min((targetScreen?.width ?? 2304) / 2304, (targetScreen?.height ?? 1296) / 1296))
    property bool opened: false
    property bool held: false
    property var targetScreen: null
    property int monitorId: -1
    property int workspaceId: 1
    property var workspaceIds: []
    property string selectedAddress: ""
    property string query: ""
    property bool starting: false
    property string pendingAddress: ""
    property int pendingWorkspace: -1
    readonly property var monitor: HyprlandData.monitors.find(m => m.id === monitorId)
    readonly property bool live: opened || progress > 0
    readonly property var clients: live ? Layout.eligible(HyprlandData.windowList, monitorId) : []
    readonly property var visualOrder: Layout.readingOrder(clients, workspaceIds)
    readonly property var filteredOrder: visualOrder.filter(a => clients.some(w => w.address === a && matches(w)))
    // The zoom out waits until the current card can draw its wallpaper and
    // window captures; a first opening would otherwise flash their placeholder
    // colors across the whole screen.
    property bool revealed: false
    property real progress: opened && revealed ? 1 : 0
    Behavior on progress { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
    // The dock is drawn over the overview once it has faded in, so the overview's surface never
    // lands on top of it, and stays until the overview has faded out.
    property bool dockRaised: false
    onProgressChanged: if (progress >= 1) dockRaised = true; else if (progress <= 0) dockRaised = false
    readonly property string dockScreen: dockRaised ? (targetScreen?.name ?? "") : ""
    onDockScreenChanged: GlobalStates.windowOverviewScreen = dockScreen
    // The room the dock takes on its edge, so the overview keeps its spacing around a dock of any size.
    readonly property real dockSpace: Appearance.sizes.dockHeightFor(Appearance.sizes.dockIconSize) + Appearance.sizes.dockEdgeGap
    function dockInset(edge: string): real {
        return (Config.options.dock.enable ?? true) && Appearance.sizes.dockEdge === edge ? root.dockSpace : 0;
    }
    readonly property real dockSideInset: Math.max(dockInset("left"), dockInset("right"))

    // A dock app picks among its windows here: one is focused, several are stepped through.
    function pickApp(app) {
        const addresses = app.toplevels.map(t => HyprlandData.clientForToplevel(t)?.address).filter(a => a);
        const order = root.visualOrder.filter(a => addresses.includes(a));
        if (order.length) {
            if (order.length === 1) { root.activate(order[0]); return; }
            root.query = "";
            root.select(Layout.step(order, root.selectedAddress, 1));
        } else if (addresses.length) {
            root.activate(addresses[0]);
        } else {
            root.close();
            AppSearch.guessDesktopEntry(app.appId)?.execute();
        }
    }

    function matches(window) {
        const terms = query.toLowerCase().trim().split(/\s+/);
        const label = `${window.title || ""} ${window.class || ""}`.toLowerCase();
        return terms.every(term => label.includes(term));
    }

    function firstOn(id) {
        return filteredOrder.find(a => clients.some(w => w.address === a && w.workspace.id === id)) || "";
    }

    function select(address) {
        selectedAddress = address;
        const selected = clients.find(w => w.address === address);
        if (selected) showWorkspace(selected.workspace.id, false);
    }

    function begin(holdAlt) {
        if (GlobalStates.screenLocked || GlobalStates.scrollOverviewOpen) return false;
        const focused = Hyprland.focusedMonitor;
        targetScreen = Quickshell.screens.find(s => s.name === focused?.name) || Quickshell.screens[0];
        if (!targetScreen) return false;
        const pending = focusAfterClose.running;
        focusAfterClose.stop();
        revealed = false;
        starting = true;
        monitorId = Hyprland.monitorFor(targetScreen)?.id ?? -1;
        // A choice from a session closed moments ago is focused now and leads this one.
        const chosen = pending ? HyprlandData.windowByAddress[pendingAddress] : null;
        const chosenHere = chosen?.mapped && chosen.monitor === monitorId ? chosen : null;
        const chosenWorkspace = chosenHere?.workspace.id ?? (pending ? pendingWorkspace : -1);
        if (pending) focusPending();
        workspaceId = chosenWorkspace > 0 ? chosenWorkspace : (focused?.activeWorkspace?.id || 1);
        query = "";
        GlobalStates.overviewOpen = false;
        GlobalStates.desktopMenuOpen = false;
        held = holdAlt;
        opened = true;
        const ids = HyprlandData.workspaces.filter(w => w.monitorID === monitorId).map(w => w.id);
        clients.forEach(w => ids.push(w.workspace.id));
        ids.push(workspaceId);
        const used = [...new Set(ids)].filter(id => id > 0 && id < 2147483600).sort((a, b) => a - b);
        // The spare workspace must be free on every monitor, or opening it jumps there.
        const taken = new Set(HyprlandData.workspaces.map(w => w.id));
        let spare = Math.max(...used) + 1;
        while (taken.has(spare)) spare++;
        workspaceIds = used.concat([spare]);
        const active = chosenHere?.address ?? HyprlandData.clientForToplevel(ToplevelManager.activeToplevel)?.address ?? "";
        selectedAddress = clients.some(w => w.address === active && w.workspace.id === workspaceId)
            ? active : firstOn(workspaceId);
        starting = false;
        HyprlandData.updateWindowList();
        revealCheck.startedAt = Date.now();
        revealCheck.restart();
        Qt.callLater(() => search.forceActiveFocus());
        return true;
    }

    function focusPending() {
        if (pendingAddress && HyprlandData.windowByAddress[pendingAddress]?.mapped)
            Hyprland.dispatch(`hl.dsp.focus({ window = "address:${pendingAddress}" })`);
        else if (pendingWorkspace > 0)
            Hyprland.dispatch(`hl.dsp.focus({ workspace = ${pendingWorkspace} })`);
        pendingAddress = "";
        pendingWorkspace = -1;
    }

    function close() {
        focusAfterClose.stop();
        pendingAddress = "";
        pendingWorkspace = -1;
        held = false;
        opened = false;
        query = "";
    }

    function cycle(direction) {
        if (!opened && !begin(true)) return;
        select(Layout.step(filteredOrder, selectedAddress, direction));
    }

    function showWorkspace(id, selectFirst = true) {
        if (!workspaceIds.includes(id)) return;
        workspaceId = id;
        if (selectFirst) selectedAddress = firstOn(id);
    }

    function stepWorkspace(direction) {
        const index = workspaceIds.indexOf(workspaceId);
        showWorkspace(workspaceIds[Math.max(0, Math.min(workspaceIds.length - 1, index + direction))]);
    }

    function scrollWorkspace(event) {
        event.accepted = true;
        if (scrollCooldown.running) return;
        const delta = event.angleDelta.y || event.angleDelta.x || event.pixelDelta.y || event.pixelDelta.x;
        if (Math.abs(delta) < 5) return;
        stepWorkspace(delta > 0 ? -1 : 1);
        scrollCooldown.restart();
    }

    function activate(address) {
        if (!opened || GlobalStates.screenLocked) return;
        const window = HyprlandData.windowByAddress[address];
        if (!window?.mapped || window.hidden || !/^0x[0-9a-f]+$/i.test(address)) return;
        close();
        pendingAddress = address;
        focusAfterClose.restart();
    }

    function activateWorkspace(id) {
        if (!opened || GlobalStates.screenLocked || !workspaceIds.includes(id)) return;
        close();
        pendingWorkspace = id;
        focusAfterClose.restart();
    }

    function accept() {
        if (selectedAddress) activate(selectedAddress);
        else activateWorkspace(workspaceId);
    }

    function releaseAlt() {
        if (opened && held) accept();
    }

    function toggle() {
        if (opened) close();
        else begin(false);
    }

    onClientsChanged: {
        if (!opened || starting) return;
        const present = clients.map(w => w.address);
        const added = clients.map(w => w.workspace.id).filter(id => !workspaceIds.includes(id));
        if (added.length) workspaceIds = [...new Set(workspaceIds.concat(added))].sort((a, b) => a - b);
        if (!present.includes(selectedAddress)) selectedAddress = firstOn(workspaceId);
    }
    onQueryChanged: {
        if (!opened || starting) return;
        if (!filteredOrder.includes(selectedAddress)) select(filteredOrder[0] || "");
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { if (GlobalStates.screenLocked) root.close(); }
        function onOverviewOpenChanged() { if (GlobalStates.overviewOpen) root.close(); }
        function onScrollOverviewOpenChanged() { if (GlobalStates.scrollOverviewOpen) root.close(); }
        function onWindowOverviewAppClicked(app) { root.pickApp(app); }
    }
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (root.opened && !Quickshell.screens.includes(root.targetScreen)) root.close();
        }
    }
    Timer { id: scrollCooldown; interval: 180 }
    // Gives up after a moment rather than hold the overview back.
    Timer {
        id: revealCheck
        property double startedAt: 0
        interval: 16
        repeat: true
        onTriggered: {
            const card = cards.itemAt(root.workspaceIds.indexOf(root.workspaceId));
            if (!root.opened || (card?.ready() && carousel.cardWidth > 1) || Date.now() - startedAt > 400) {
                root.revealed = true;
                stop();
            }
        }
    }
    // Wait for the layer surface to unmap before focusing an application.
    // Focusing during the fade lets the compositor restore the old window
    // when it drops the overlay's exclusive keyboard focus afterwards.
    Timer {
        id: focusAfterClose
        interval: 260
        onTriggered: {
            if (root.opened || GlobalStates.screenLocked || GlobalStates.overviewOpen || GlobalStates.scrollOverviewOpen) return;
            root.focusPending();
        }
    }

    GlobalShortcut { name: "windowOverviewNext"; description: "Next window in Activities overview"; onPressed: root.cycle(1) }
    GlobalShortcut { name: "windowOverviewPrevious"; description: "Previous window in Activities overview"; onPressed: root.cycle(-1) }
    GlobalShortcut { name: "windowOverviewAccept"; description: "Select overview window on Alt release"; onPressed: root.releaseAlt() }
    GlobalShortcut { name: "windowOverviewToggle"; description: "Toggle Activities overview"; onPressed: root.toggle() }
    IpcHandler {
        target: "windowOverview"
        function toggle(): void { root.toggle(); }
        function open(): void { root.begin(false); }
        function close(): void { root.close(); }
        function next(): void { root.cycle(1); }
        function previous(): void { root.cycle(-1); }
        function accept(): void { root.accept(); }
        function releaseAlt(): void { root.releaseAlt(); }
        function workspace(direction: int): void { root.stepWorkspace(direction); }
    }

    PanelWindow {
        id: panel
        screen: root.targetScreen
        visible: root.live
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:windowOverview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        mask: root.opened ? null : passthrough
        Region { id: passthrough }

        Item {
            anchors.fill: parent
            opacity: root.progress
            Rectangle { anchors.fill: parent; color: Appearance.m3colors.m3background }
            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
                onWheel: event => root.scrollWorkspace(event)
            }
            StyledRectangularShadow {
                target: searchSurface
                blur: 0.9 * Appearance.sizes.elevationMargin * root.uiScale
                offset: Qt.vector2d(0, root.uiScale)
                spread: root.uiScale
                color: Appearance.colors.colLauncherShadow
            }
            LauncherSearchSurface {
                id: searchSurface
                anchors.horizontalCenter: parent.horizontalCenter
                y: 18 + root.dockInset("top")
                width: Math.min(collapsedWidth, panel.width * 0.8)
                uiScale: root.uiScale
                MaterialSymbol {
                    x: 14 * root.uiScale
                    anchors.verticalCenter: parent.verticalCenter
                    text: "search"
                    iconSize: 22 * root.uiScale
                    color: Appearance.launcherPanelContent.colOnLayer0
                }
                ToolbarTextField {
                    id: search
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                        leftMargin: 50 * root.uiScale; rightMargin: 14 * root.uiScale }
                    height: 40 * root.uiScale
                    padding: 10 * root.uiScale
                    font.pixelSize: Appearance.font.pixelSize.small * root.uiScale
                    colBackground: "transparent"
                    color: Appearance.launcherPanelContent.colOnLayer0
                    placeholderTextColor: Appearance.launcherPanelContent.colSubtext
                    selectedTextColor: Appearance.launcherPanelContent.colOnSecondaryContainer
                    selectionColor: Appearance.launcherPanelContent.colSecondaryContainer
                    placeholderText: Translation.tr("Type to search windows")
                    selectByMouse: true
                    text: root.query
                    onTextEdited: root.query = text
                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true; }
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.accept(); event.accepted = true; }
                        else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                            root.cycle(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown
                                || ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Left || event.key === Qt.Key_Right))) {
                            root.stepWorkspace(event.key === Qt.Key_Left || event.key === Qt.Key_PageUp ? -1 : 1);
                            event.accepted = true;
                        } else if (!root.query && [Qt.Key_Left, Qt.Key_Right, Qt.Key_Up, Qt.Key_Down].includes(event.key)) {
                            root.cycle(event.key === Qt.Key_Left || event.key === Qt.Key_Up ? -1 : 1);
                            event.accepted = true;
                        }
                    }
                    Keys.onReleased: event => {
                        if (event.key === Qt.Key_Alt && !event.isAutoRepeat) root.releaseAlt();
                    }
                }
            }

            Item {
                id: carousel
                // Side docks take the same room off both sides, so the cards stay centered on the screen.
                anchors {
                    top: parent.top; bottom: parent.bottom; left: parent.left; right: parent.right
                    topMargin: searchSurface.y + searchSurface.height + 20 * root.uiScale; bottomMargin: 38 + root.dockInset("bottom")
                    leftMargin: root.dockSideInset; rightMargin: root.dockSideInset
                }
                readonly property real cardWidth: Math.max(1, Math.min(width * 0.89, height * panel.width / Math.max(1, panel.height)))
                readonly property real cardHeight: cardWidth * panel.height / Math.max(1, panel.width)
                readonly property real stride: cardWidth + 32
                property real position: root.workspaceIds.indexOf(root.workspaceId)
                Behavior on position {
                    NumberAnimation {
                        duration: Appearance.animation.scroll.duration
                        easing.type: Appearance.animation.scroll.type
                        easing.bezierCurve: Appearance.animation.scroll.bezierCurve
                    }
                }
                Repeater {
                    id: cards
                    model: root.workspaceIds
                    WorkspaceCard {
                        required property int modelData
                        required property int index
                        controller: root
                        workspaceId: modelData
                        monitor: root.monitor
                        screenName: root.targetScreen?.name ?? ""
                        current: modelData === root.workspaceId
                        nearby: Math.abs(index - carousel.position) < 1.1 && panel.visible
                        width: carousel.cardWidth
                        height: carousel.cardHeight
                        x: (carousel.width - width) / 2 + (index - carousel.position) * carousel.stride
                        y: (carousel.height - height) / 2
                        scale: current ? 1 + (1 - root.progress) * (panel.width / carousel.cardWidth - 1) : 0.94
                        progress: root.progress
                        // Only switching workspaces eases the scale: the opening zoom already follows
                        // the eased progress, and a first opening starts from the unsized panel.
                        Behavior on scale { enabled: root.progress === 1; animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: panel.height - 26 - root.dockInset("bottom")
                spacing: 8
                Repeater {
                    model: root.workspaceIds
                    Rectangle {
                        id: dot
                        required property int modelData
                        property bool hovered: dotHover.hovered
                        width: modelData === root.workspaceId ? 26 : 9
                        height: 9
                        radius: Appearance.rounding.full
                        color: modelData === root.workspaceId ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
                        Behavior on width { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                        TapHandler { onTapped: root.showWorkspace(dot.modelData) }
                        HoverHandler { id: dotHover }
                        StyledToolTip { text: Translation.tr("Workspace %1").arg(dot.modelData) }
                    }
                }
            }
        }
    }
}
