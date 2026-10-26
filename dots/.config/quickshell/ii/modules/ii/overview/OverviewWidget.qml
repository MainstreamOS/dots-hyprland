pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "placement.js" as Placement

Item {
    id: root
    required property var screen
    property real uiScale: 1
    required property var workspaceLayout
    property Item dockBackdropSource: null
    property rect dockBackdropRect: Qt.rect(0, 0, 1, 1)
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property var toplevels: ToplevelManager.toplevels
    // Clamp to avoid lock-screen temp workspace (2147483647 - N) leaking into UI
    readonly property int effectiveActiveWorkspaceId: Math.max(1, Math.min(100, monitor?.activeWorkspace?.id ?? 1))
    readonly property int workspacesShown: Config.options.overview.rows * Config.options.overview.columns
    readonly property int workspaceGroup: Math.floor((effectiveActiveWorkspaceId - 1) / workspacesShown)
    property var windows: HyprlandData.windowList
    property var windowByAddress: HyprlandData.windowByAddress
    property var monitorData: HyprlandData.monitors.find(m => m.id === root.monitor?.id)
    readonly property var previewReserved: workspaceLayout.reserved
    readonly property real scale: workspaceLayout.previewScale
    property color activeBorderColor: Appearance.launcherContent.colSecondaryOnTile
    readonly property real workspaceImplicitWidth: workspaceLayout.cellWidth
    readonly property real workspaceImplicitHeight: workspaceLayout.cellHeight
    // Use the dock's radius at the reference size, scaling it along with the
    // workspace outlines, window corners and gaps at other output scales.
    property real largeWorkspaceRadius: Appearance.rounding.dockBody * uiScale
    property real smallWorkspaceRadius: Math.min(Appearance.rounding.verysmall * uiScale, largeWorkspaceRadius)

    property real workspaceNumberSize: 250 * (5 / 3) * uiScale
    property int workspaceZ: 0
    property int windowZ: 1
    property int windowDraggingZ: 99999
    readonly property real workspaceSpacing: workspaceLayout.gap

    property int draggingFromWorkspace: -1
    property int draggingTargetWorkspace: -1
    property Item dragWindow: null
    property var dropInfo: null
    property bool placementPending: false
    property string placementAddress: ""
    property int placementAttempts: 0
    signal focusSearchRequested()
    signal placementFinished(string address)

    // Set by Overview.qml during an app-drawer drag to highlight the hovered workspace
    property int appDragHoverWorkspace: -1

    // Returns the 1-indexed workspace number at the given scene coordinates, or -1 if none.
    function workspaceAtScenePoint(sceneX, sceneY) {
        const lp = workspaceColumnLayout.mapFromItem(null, sceneX, sceneY)
        const cellW = root.workspaceImplicitWidth + workspaceSpacing
        const cellH = root.workspaceImplicitHeight + workspaceSpacing
        const col = Math.floor(lp.x / cellW)
        const row = Math.floor(lp.y / cellH)
        if (col < 0 || col >= Config.options.overview.columns) return -1
        if (row < 0 || row >= Config.options.overview.rows) return -1
        if (lp.x - col * cellW >= root.workspaceImplicitWidth
                || lp.y - row * cellH >= root.workspaceImplicitHeight) return -1
        return root.workspaceGroup * root.workspacesShown + getWsInCell(row, col)
    }

    function updateWindowDrag(sceneX, sceneY) {
        const workspace = workspaceAtScenePoint(sceneX, sceneY);
        draggingTargetWorkspace = workspace;
        dropInfo = null;
        if (!dragWindow || workspace < 1) return;
        const point = windowSpace.mapFromItem(null, sceneX, sceneY);
        const left = getWsColumn(workspace) * (workspaceImplicitWidth + workspaceSpacing);
        const top = getWsRow(workspace) * (workspaceImplicitHeight + workspaceSpacing);
        const reserved = monitorData?.reserved ?? [0, 0, 0, 0];
        const size = dragWindow.windowData?.size ?? [1, 1];
        const x = (monitorData?.x ?? 0) + Math.max(reserved[0], Math.min(
            root.previewReserved[0] + (point.x - left - dragWindow.Drag.hotSpot.x) / scale,
            screen.width - reserved[2] - size[0]));
        const y = (monitorData?.y ?? 0) + Math.max(reserved[1], Math.min(
            root.previewReserved[1] + (point.y - top - dragWindow.Drag.hotSpot.y) / scale,
            screen.height - reserved[3] - size[1]));
        let anchor = null, distance = Infinity;
        if (!dragWindow.windowData?.floating) {
            for (let i = 0; i < windowRepeater.count; i++) {
                const tile = windowRepeater.itemAt(i);
                if (!tile || tile === dragWindow || tile.closing || tile.windowData?.floating
                        || tile.windowData?.workspace.id !== workspace) continue;
                const dx = Math.max(tile.initX - point.x, 0, point.x - tile.initX - tile.width);
                const dy = Math.max(tile.initY - point.y, 0, point.y - tile.initY - tile.height);
                const d = dx * dx + dy * dy;
                if (d < distance) { anchor = tile; distance = d; }
            }
        }
        if (!anchor) {
            dropInfo = { workspace, anchor: "", direction: "", x, y };
            return;
        }
        if (HyprlandData.workspaceById[workspace]?.tiledLayout === "master") {
            dropInfo = { workspace, anchor: anchor.address, direction: "", x, y,
                indicator: { x: anchor.initX, y: anchor.initY, width: anchor.width, height: anchor.height } };
            return;
        }
        const rx = (point.x - anchor.initX) / anchor.width;
        const ry = (point.y - anchor.initY) / anchor.height;
        const side = rx < 1 / 3 ? 0 : rx > 2 / 3 ? 1 : ry < 0.5 ? 2 : 3;
        const slot = Math.min(workspaceImplicitWidth, workspaceImplicitHeight) * 0.06;
        const indicator = side < 2
            ? { x: anchor.initX + (side === 1 ? anchor.width : 0) - slot / 2,
                y: top, width: slot, height: workspaceImplicitHeight }
            : { x: anchor.initX, y: anchor.initY + (side === 3 ? anchor.height : 0) - slot / 2,
                width: anchor.width, height: slot };
        // Keep the slot inside its workspace even at the outside edges.
        indicator.x = Math.max(left, Math.min(left + workspaceImplicitWidth - indicator.width, indicator.x));
        indicator.y = Math.max(top, Math.min(top + workspaceImplicitHeight - indicator.height, indicator.y));
        dropInfo = { workspace, anchor: anchor.address, direction: ["l", "r", "u", "d"][side], x, y, indicator };
    }
    function placeWindow(window, target) {
        placementAddress = window.address;
        placement.command = ["hyprctl", "repl", Placement.script(window.address, target.workspace,
            target.anchor, target.direction, target.x, target.y)];
        placementAttempts = 0;
        placementPending = true;
        placementStart.restart();
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
            if (placementOutput.text.includes("overview-placement-focus-pending") && root.placementAttempts < 4) {
                placementStart.restart();
                return;
            }
            if (code !== 0 || placementOutput.text.includes("overview-placement-focus-pending"))
                console.warn("Overview window placement failed:", placementErrors.text || placementOutput.text);
            root.placementPending = false;
            HyprlandData.refreshSoon();
            root.placementFinished(root.placementAddress);
            if (GlobalStates.overviewOpen) Qt.callLater(() => root.focusSearchRequested());
        }
        stdout: StdioCollector { id: placementOutput }
        stderr: StdioCollector { id: placementErrors }
    }

    WorkspaceRenamePopup {
        id: renamePopup
        onClosed: if (GlobalStates.overviewOpen) root.focusSearchRequested()
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: eventPoint => {
            const point = root.mapToItem(null, eventPoint.position.x, eventPoint.position.y);
            const workspace = root.workspaceAtScenePoint(point.x, point.y);
            renamePopup.openFor(workspace, eventPoint.position.x, eventPoint.position.y);
        }
    }

    implicitWidth: overviewBackground.implicitWidth + Appearance.sizes.elevationMargin * root.uiScale * 2
    implicitHeight: overviewBackground.implicitHeight + Appearance.sizes.elevationMargin * root.uiScale * 2

    function getWsRow(ws) {
        // 1-indexed workspace, 0-indexed row
        var normalRow = Math.floor((ws - 1) / Config.options.overview.columns) % Config.options.overview.rows;
        return (Config.options.overview.orderBottomUp ? Config.options.overview.rows - normalRow - 1 : normalRow);
    }
    function getWsColumn(ws) {
        // 1-indexed workspace, 0-indexed column
        var normalCol = (ws - 1) % Config.options.overview.columns;
        return (Config.options.overview.orderRightLeft ? Config.options.overview.columns - normalCol - 1 : normalCol);
    }
    // Top-left, top-right, bottom-left, bottom-right; the grid's outer corners are large.
    function workspaceRadii(column, row) {
        const radius = outer => outer ? root.largeWorkspaceRadius : root.smallWorkspaceRadius;
        const left = column === 0, right = column === Config.options.overview.columns - 1;
        const top = row === 0, bottom = row === Config.options.overview.rows - 1;
        return Qt.vector4d(radius(left && top), radius(right && top), radius(left && bottom), radius(right && bottom));
    }
    function getWsInCell(ri, ci) {
        // 1-indexed workspace, 0-indexed row and column index
        return (Config.options.overview.orderBottomUp ? Config.options.overview.rows - ri - 1 : ri) * Config.options.overview.columns + (Config.options.overview.orderRightLeft ? Config.options.overview.columns - ci - 1 : ci) + 1
    }

    StyledRectangularShadow {
        target: overviewBackground
        color: Appearance.sizes.dockShowBackground ? Appearance.colors.colDockShadow : "transparent"
    }
    LauncherWorkspaceSurface { // Background
        id: overviewBackground
        property real padding: 10 * root.uiScale
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin * root.uiScale

        implicitWidth: workspaceColumnLayout.implicitWidth + padding * 2
        implicitHeight: workspaceColumnLayout.implicitHeight + padding * 2
        radius: root.largeWorkspaceRadius
        uiScale: root.uiScale
        backdropSource: root.dockBackdropSource
        backdropRect: root.dockBackdropRect

        Column { // Workspaces
            id: workspaceColumnLayout

            z: root.workspaceZ
            anchors.centerIn: parent
            spacing: workspaceSpacing
            
            Repeater {
                model: Config.options.overview.rows
                delegate: Row {
                    id: row
                    required property int index
                    spacing: workspaceSpacing

                    Repeater { // Workspace repeater
                        model: Config.options.overview.columns
                        Rectangle { // Workspace
                            id: workspace
                            required property int index
                            property int colIndex: index
                            property int workspaceValue: root.workspaceGroup * root.workspacesShown + getWsInCell(row.index, colIndex)
                            property color hoveredWorkspaceColor: ColorUtils.mix(Appearance.colors.colDockBackground, Appearance.launcherContent.colLayer1Hover, 0.1)
                            property color hoveredBorderColor: Appearance.launcherContent.colLayer2Hover
                            property bool hoveredWhileDragging: false
                            property bool appDragHovered: root.appDragHoverWorkspace === workspaceValue

                            implicitWidth: root.workspaceImplicitWidth
                            implicitHeight: root.workspaceImplicitHeight
                            color: (hoveredWhileDragging || appDragHovered) ? hoveredWorkspaceColor
                                : ColorUtils.applyAlpha(Appearance.launcherContent.colOnLayer0, 0.035)
                            readonly property vector4d radii: root.workspaceRadii(colIndex, row.index)
                            topLeftRadius: radii.x
                            topRightRadius: radii.y
                            bottomLeftRadius: radii.z
                            bottomRightRadius: radii.w
                            border.width: ((hoveredWhileDragging || appDragHovered) ? 2 : 1) * root.uiScale
                            border.color: (hoveredWhileDragging || appDragHovered) ? hoveredBorderColor
                                : ColorUtils.applyAlpha(Appearance.launcherContent.colOutlineVariant, 0.2)

                            StyledText {
                                anchors.centerIn: parent
                                text: workspace.workspaceValue
                                font {
                                    pixelSize: root.workspaceNumberSize * root.scale
                                    weight: Font.DemiBold
                                    family: Appearance.font.family.expressive
                                }
                                color: Appearance.launcherContent.colTileNumber
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            MouseArea {
                                id: workspaceArea
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                onPressed: {
                                    if (root.draggingTargetWorkspace === -1) {
                                        GlobalStates.overviewOpen = false
                                        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${workspace.workspaceValue} })`)
                                    }
                                }
                            }

                            DropArea {
                                anchors.fill: parent
                                onEntered: {
                                    root.draggingTargetWorkspace = workspace.workspaceValue
                                    if (root.draggingFromWorkspace == root.draggingTargetWorkspace) return;
                                    hoveredWhileDragging = true
                                }
                                onExited: {
                                    hoveredWhileDragging = false
                                    if (root.draggingTargetWorkspace == workspace.workspaceValue) root.draggingTargetWorkspace = -1
                                }
                            }

                        }
                    }
                }
            }
        }

        Item { // Windows & focused workspace indicator
            id: windowSpace
            anchors.centerIn: parent
            implicitWidth: workspaceColumnLayout.implicitWidth
            implicitHeight: workspaceColumnLayout.implicitHeight

            Repeater { // Window repeater
                id: windowRepeater
                model: ScriptModel {
                    values: {
                        // console.log(JSON.stringify(ToplevelManager.toplevels.values.map(t => t), null, 2))
                        return ToplevelManager.toplevels.values.filter((toplevel) => {
                            const address = `0x${toplevel.HyprlandToplevel?.address}`
                            var win = windowByAddress[address]
                            const inWorkspaceGroup = (root.workspaceGroup * root.workspacesShown < win?.workspace?.id && win?.workspace?.id <= (root.workspaceGroup + 1) * root.workspacesShown)
                            return inWorkspaceGroup;
                        })
                    }
                }
                delegate: OverviewWindow {
                    id: window
                    required property var modelData
                    property int monitorId: windowData?.monitor
                    property var monitor: HyprlandData.monitors.find(m => m.id == monitorId)
                    property var address: `0x${modelData.HyprlandToplevel.address}`
                    toplevel: modelData
                    uiScale: root.uiScale
                    monitorData: this.monitor
                    scale: root.scale
                    widgetMonitor: HyprlandData.monitors.find(m => m.id == root.monitor.id)
                    windowData: windowByAddress[address]

                    property bool atInitPosition: (initX == x && initY == y)

                    // Cut at its workspace's edge only while it is at rest. A
                    // dropped window stays whole until the timer below has put
                    // it in its new place; clipped to the workspace it left, it
                    // would vanish until Hyprland reported the move.
                    property bool settling: false
                    workspaceWidth: root.workspaceImplicitWidth
                    workspaceHeight: root.workspaceImplicitHeight
                    restrictToWorkspace: !Drag.active && !settling

                    // Offset on the canvas
                    property int workspaceColIndex: getWsColumn(windowData?.workspace.id)
                    property int workspaceRowIndex: getWsRow(windowData?.workspace.id)
                    xOffset: (root.workspaceImplicitWidth + workspaceSpacing) * workspaceColIndex
                    yOffset: (root.workspaceImplicitHeight + workspaceSpacing) * workspaceRowIndex
                    workspaceReserved: monitorId === root.monitor?.id ? root.previewReserved : (monitorData?.reserved ?? [0, 0, 0, 0])
                    property real xWithinWorkspaceWidget: Math.max((windowData?.at[0] - (monitor?.x ?? 0) - workspaceReserved[0]) * root.scale, 0)
                    property real yWithinWorkspaceWidget: Math.max((windowData?.at[1] - (monitor?.y ?? 0) - workspaceReserved[1]) * root.scale, 0)

                    // Radius
                    property real minRadius: Math.min(Appearance.rounding.small * root.uiScale, root.largeWorkspaceRadius)
                    property bool workspaceAtLeft: workspaceColIndex === 0
                    property bool workspaceAtRight: workspaceColIndex === Config.options.overview.columns - 1
                    property bool workspaceAtTop: workspaceRowIndex === 0
                    property bool workspaceAtBottom: workspaceRowIndex === Config.options.overview.rows - 1
                    property bool workspaceAtTopLeft: (workspaceAtLeft && workspaceAtTop) 
                    property bool workspaceAtTopRight: (workspaceAtRight && workspaceAtTop) 
                    property bool workspaceAtBottomLeft: (workspaceAtLeft && workspaceAtBottom) 
                    property bool workspaceAtBottomRight: (workspaceAtRight && workspaceAtBottom) 
                    property real distanceFromLeftEdge: xWithinWorkspaceWidget
                    // Held at 0 for a window cut at the edge, whose cut corner
                    // then takes the workspace's own radius.
                    property real distanceFromRightEdge: Math.max(0, root.workspaceImplicitWidth - (xWithinWorkspaceWidget + targetWindowWidth))
                    property real distanceFromTopEdge: yWithinWorkspaceWidget
                    property real distanceFromBottomEdge: Math.max(0, root.workspaceImplicitHeight - (yWithinWorkspaceWidget + targetWindowHeight))
                    property real distanceFromTopLeftCorner: Math.max(distanceFromLeftEdge, distanceFromTopEdge)
                    property real distanceFromTopRightCorner: Math.max(distanceFromRightEdge, distanceFromTopEdge)
                    property real distanceFromBottomLeftCorner: Math.max(distanceFromLeftEdge, distanceFromBottomEdge)
                    property real distanceFromBottomRightCorner: Math.max(distanceFromRightEdge, distanceFromBottomEdge)
                    topLeftRadius: Math.max((workspaceAtTopLeft ? root.largeWorkspaceRadius : root.smallWorkspaceRadius) - distanceFromTopLeftCorner, minRadius)
                    topRightRadius: Math.max((workspaceAtTopRight ? root.largeWorkspaceRadius : root.smallWorkspaceRadius) - distanceFromTopRightCorner, minRadius)
                    bottomLeftRadius: Math.max((workspaceAtBottomLeft ? root.largeWorkspaceRadius : root.smallWorkspaceRadius) - distanceFromBottomLeftCorner, minRadius)
                    bottomRightRadius: Math.max((workspaceAtBottomRight ? root.largeWorkspaceRadius : root.smallWorkspaceRadius) - distanceFromBottomRightCorner, minRadius)

                    Timer {
                        id: updateWindowPosition
                        interval: Config.options.hacks.arbitraryRaceConditionDelay
                        repeat: false
                        running: false
                        onTriggered: {
                            window.x = Math.round(xWithinWorkspaceWidget + xOffset)
                            window.y = Math.round(yWithinWorkspaceWidget + yOffset)
                            window.settling = false
                        }
                    }
                    Connections {
                        target: root
                        function onPlacementFinished(address) {
                            if (address === window.address) updateWindowPosition.restart();
                        }
                    }

                    z: Drag.active ? root.windowDraggingZ : (root.windowZ + windowData?.floating + windowData?.fullscreen * 2)
                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2
                    MouseArea {
                        id: dragArea
                        // Only the part drawn on its workspace answers the
                        // pointer, so the part cut off leaves the workspace
                        // under it free to hover and click.
                        x: window.visibleLeft
                        y: window.visibleTop
                        width: Math.max(0, window.visibleRight - window.visibleLeft)
                        height: Math.max(0, window.visibleBottom - window.visibleTop)
                        enabled: !window.closing && !root.placementPending
                        hoverEnabled: !window.closing
                        onEntered: hovered = true // For hover color change
                        onExited: hovered = false // For hover color change
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        drag.target: parent
                        onPressed: (mouse) => {
                            if (mouse.button !== Qt.LeftButton) return
                            // In the window's own coordinates, and read before
                            // the drag lifts the cut and this area moves.
                            const hotSpotX = mouse.x + dragArea.x
                            const hotSpotY = mouse.y + dragArea.y
                            root.draggingFromWorkspace = windowData?.workspace.id
                            root.dragWindow = window
                            root.dropInfo = null
                            window.pressed = true
                            window.Drag.active = true
                            window.Drag.source = window
                            window.Drag.hotSpot.x = hotSpotX
                            window.Drag.hotSpot.y = hotSpotY
                            // console.log(`[OverviewWindow] Dragging window ${windowData?.address} from position (${window.x}, ${window.y})`)
                        }
                        onPositionChanged: mouse => {
                            if (!window.pressed || !drag.active) return;
                            const point = window.mapToItem(null, mouse.x + dragArea.x, mouse.y + dragArea.y);
                            root.updateWindowDrag(point.x, point.y);
                        }
                        onCanceled: {
                            window.pressed = false;
                            window.Drag.active = false;
                            root.dragWindow = null;
                            root.dropInfo = null;
                            root.draggingFromWorkspace = -1;
                            root.draggingTargetWorkspace = -1;
                            updateWindowPosition.restart();
                        }
                        onReleased: (mouse) => {
                            if (mouse.button !== Qt.LeftButton) return
                            const target = root.dropInfo;
                            window.pressed = false;
                            window.Drag.active = false;
                            root.draggingFromWorkspace = -1;
                            root.dragWindow = null;
                            root.dropInfo = null;
                            root.draggingTargetWorkspace = -1;
                            window.settling = true;
                            if (target) root.placeWindow(window, target);
                            else updateWindowPosition.restart();
                        }
                        onClicked: (event) => {
                            if (!windowData) return;

                            if (event.button === Qt.LeftButton) {
                                GlobalStates.overviewOpen = false
                                Hyprland.dispatch(`hl.dsp.focus({window = "address:${windowData.address}"})`)
                                event.accepted = true
                            } else if (event.button === Qt.MiddleButton) {
                                window.closing = true
                                Hyprland.dispatch(`hl.dsp.window.close({window = "address:${windowData.address}"})`)
                                event.accepted = true
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: false
                            alternativeVisibleCondition: dragArea.containsMouse && !window.Drag.active && !window.closing
                            text: `${windowData?.title}\n[${windowData?.class}] ${windowData?.xwayland ? "[XWayland] " : ""}`
                        }
                    }
                }
            }

            Rectangle {
                objectName: "windowDropIndicator"
                readonly property var indicator: root.dropInfo?.indicator
                visible: root.dragWindow !== null && !!indicator
                x: indicator?.x ?? 0
                y: indicator?.y ?? 0
                width: indicator?.width ?? 0
                height: indicator?.height ?? 0
                radius: RoundedCorners.on ? Math.min(Appearance.rounding.small, width / 2, height / 2) : 0
                color: ColorUtils.applyAlpha(Appearance.launcherContent.colPrimary, 0.3)
                z: root.windowDraggingZ - 1
            }

            Repeater {
                model: root.workspacesShown
                delegate: WorkspaceSidebarPreview {
                    required property int index
                    readonly property int workspaceId: root.workspaceGroup * root.workspacesShown + index + 1
                    readonly property vector4d radii: root.workspaceRadii(root.getWsColumn(workspaceId), root.getWsRow(workspaceId))
                    visible: hasPreviews && root.windows.some(window => window.mapped && !window.hidden && window.workspace.id === workspaceId)
                    screenName: root.screen.name
                    previewScale: root.scale
                    originX: root.previewReserved[0]
                    originY: root.previewReserved[1]
                    x: (root.workspaceImplicitWidth + root.workspaceSpacing) * root.getWsColumn(workspaceId)
                    y: (root.workspaceImplicitHeight + root.workspaceSpacing) * root.getWsRow(workspaceId)
                    width: root.workspaceImplicitWidth
                    height: root.workspaceImplicitHeight
                    topLeftRadius: radii.x
                    topRightRadius: radii.y
                    bottomLeftRadius: radii.z
                    bottomRightRadius: radii.w
                    z: root.windowZ + 10
                    onActivated: {
                        GlobalStates.overviewOpen = false;
                        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${workspaceId} })`);
                    }
                }
            }

            Repeater {
                model: root.workspacesShown
                delegate: LauncherTitlePill {
                    required property int index
                    readonly property int workspaceId: root.workspaceGroup * root.workspacesShown + index + 1
                    readonly property string workspaceName: WorkspaceNames.nameFor(workspaceId)
                    objectName: "workspaceNamePill"
                    uiScale: root.uiScale
                    visible: workspaceName.length > 0
                    x: (root.workspaceImplicitWidth + root.workspaceSpacing) * root.getWsColumn(workspaceId) + 6 * root.uiScale
                    y: (root.workspaceImplicitHeight + root.workspaceSpacing) * root.getWsRow(workspaceId) + 6 * root.uiScale
                    width: Math.max(0, Math.min(root.workspaceImplicitWidth - 12 * root.uiScale, implicitWidth))
                    height: Math.max(0, Math.min(26 * root.uiScale, root.workspaceImplicitHeight - 12 * root.uiScale))
                    text: workspaceName
                    z: root.windowDraggingZ - 2
                }
            }

            Rectangle { // Focused workspace indicator
                id: focusedWorkspaceIndicator
                property int rowIndex: getWsRow(root.effectiveActiveWorkspaceId)
                property int colIndex: getWsColumn(root.effectiveActiveWorkspaceId)
                x: (root.workspaceImplicitWidth + workspaceSpacing) * colIndex
                y: (root.workspaceImplicitHeight + workspaceSpacing) * rowIndex
                z: root.windowDraggingZ - 1
                width: root.workspaceImplicitWidth
                height: root.workspaceImplicitHeight
                color: "transparent"
                readonly property vector4d radii: root.workspaceRadii(colIndex, rowIndex)
                topLeftRadius: radii.x
                topRightRadius: radii.y
                bottomLeftRadius: radii.z
                bottomRightRadius: radii.w
                border.width: 2 * root.uiScale
                border.color: root.activeBorderColor
                Behavior on x {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on y {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on topLeftRadius {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on topRightRadius {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on bottomLeftRadius {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on bottomRightRadius {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
            }
        }
    }
}
