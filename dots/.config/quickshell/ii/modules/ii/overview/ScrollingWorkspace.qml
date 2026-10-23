pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "scrolling.js" as Scrolling

Item {
    id: root
    required property var controller
    required property int workspaceId
    property real cardWidth: width * 0.78
    property real cardHeight: cardWidth * controller.screen.height / Math.max(1, controller.screen.width)
    readonly property real cardRadius: controller.workspaceRadius(cardWidth, cardHeight)
    readonly property real cardX: (width - cardWidth) / 2
    readonly property real innerFadeInset: GlobalStates.overviewWorkspacesOnly ? 0 : root.cardX
    readonly property real fadeLeft: 0
    readonly property real fadeRight: width
    readonly property real uiScale: controller.uiScale
    readonly property real cardY: 0
    readonly property bool selected: controller.selectedWorkspace === workspaceId
    readonly property bool dropHovered: controller.dropWorkspace === workspaceId
    readonly property bool hovered: workspaceHover.hovered && !controller.dragAddress
        && !controller.searching && !controller.activationPending
    readonly property var clients: controller.clients.filter(w => w.workspace.id === workspaceId)
    readonly property bool empty: clients.length === 0
    readonly property string layout: HyprlandData.workspaceById[workspaceId]?.tiledLayout ?? controller.layout
    readonly property var positions: Scrolling.positions(clients, layout, controller.monitorData,
        cardWidth, controller.selectedByWorkspace[workspaceId] ?? "",
        controller.pannedByWorkspace[workspaceId] ?? false, controller.fitColumns, cardHeight, controller.gapsIn, controller.gapsOut, controller.windowBorder, uiScale,
        controller.monocleOrder[workspaceId] ?? [])
    readonly property var order: Object.keys(positions).sort((a, b) => positions[a].x - positions[b].x
        || positions[a].y - positions[b].y || a.localeCompare(b))
    readonly property var navigationItems: layout === "scrolling" ? Scrolling.columns(clients).map(c => c.windows) : order.map(a => [a])
    readonly property int navigationIndex: {
        const chosen = controller.selectedByWorkspace[workspaceId] ?? "";
        const selected = navigationItems.findIndex(group => group.includes(chosen));
        if (selected >= 0) return selected;
        let best = 0, distance = Infinity;
        navigationItems.forEach((group, i) => {
            const rect = positions[group[0]];
            const d = Math.abs((rect?.x ?? 0) + (rect?.width ?? 0) / 2 - cardWidth / 2);
            if (d < distance) { best = i; distance = d; }
        });
        return best;
    }
    readonly property real viewportScale: Math.min(cardWidth / controller.screen.width, cardHeight / controller.screen.height)
    readonly property real viewportLeft: (cardWidth - controller.screen.width * viewportScale) / 2
        + ((controller.monitorData.reserved?.[0] ?? 0) + controller.gapsOut[3]) * viewportScale
    readonly property real viewportRight: (cardWidth - controller.screen.width * viewportScale) / 2
        + (controller.screen.width - (controller.monitorData.reserved?.[2] ?? 0) - controller.gapsOut[1]) * viewportScale
    readonly property bool moreBefore: navigationIndex > 0 && (layout !== "scrolling"
        || navigationItems.slice(0, navigationIndex).some(group => positions[group[0]]?.x < viewportLeft - viewportScale))
    readonly property bool moreAfter: navigationIndex < navigationItems.length - 1 && (layout !== "scrolling"
        || navigationItems.slice(navigationIndex + 1).some(group => {
            const rect = positions[group[0]];
            return rect && rect.x + rect.width > viewportRight + viewportScale;
        }))
    implicitHeight: cardY + cardHeight

    function containsScenePoint(sceneX, sceneY) {
        const point = root.mapFromItem(null, sceneX, sceneY);
        return point.x >= fadeLeft && point.x <= fadeRight && point.y >= cardY && point.y <= cardY + cardHeight;
    }

    function placementAt(sceneX, sceneY) {
        const point = root.mapFromItem(null, sceneX, sceneY);
        const nativeScale = root.viewportScale;
        const desktopX = (cardWidth - controller.screen.width * nativeScale) / 2;
        const desktopY = (cardHeight - controller.screen.height * nativeScale) / 2;
        const dragged = controller.dragClient;
        const reference = clients.find(w => positions[w.address]);
        const referenceRect = positions[reference?.address];
        const nativeX = ((reference?.at?.[0] ?? 0) - controller.monitorData.x) * nativeScale + desktopX;
        const shift = referenceRect ? referenceRect.x - nativeX : 0;
        const reserved = controller.monitorData.reserved ?? [0, 0, 0, 0];
        const grabX = controller.dragGrab.x / Math.max(1, controller.dragSize.width) * (dragged?.size?.[0] ?? 1);
        const grabY = controller.dragGrab.y / Math.max(1, controller.dragSize.height) * (dragged?.size?.[1] ?? 1);
        const x = controller.monitorData.x + Math.max(reserved[0], Math.min(
            (point.x - cardX - desktopX - shift) / nativeScale - grabX,
            controller.screen.width - reserved[2] - (dragged?.size?.[0] ?? 1)));
        const y = controller.monitorData.y + Math.max(reserved[1], Math.min(
            (point.y - cardY - desktopY) / nativeScale - grabY,
            controller.screen.height - reserved[3] - (dragged?.size?.[1] ?? 1)));
        let anchor = "", distance = Infinity;
        if (!dragged?.floating) {
            for (const client of clients) {
                if (client.address === controller.dragAddress || client.floating) continue;
                const rect = positions[client.address];
                if (!rect) continue;
                const dx = Math.max(rect.x + cardX - point.x, 0, point.x - cardX - rect.x - rect.width);
                const dy = Math.max(rect.y + cardY - point.y, 0, point.y - cardY - rect.y - rect.height);
                const d = dx * dx + dy * dy;
                if (d < distance) { distance = d; anchor = client.address; }
            }
        }
        if (!anchor) return { workspace: workspaceId, anchor: "", direction: "", x, y };
        const rect = positions[anchor];
        const rx = (point.x - cardX - rect.x) / rect.width;
        const ry = (point.y - cardY - rect.y) / rect.height;
        // Match ScrollOverview: outer thirds insert a column; the center
        // inserts above/below. Size the highlight against the miniature desktop.
        const side = rx < 1 / 3 ? 0 : rx > 2 / 3 ? 1 : ry < 0.5 ? 2 : 3;
        const size = Math.min(cardWidth, cardHeight) * 0.06;
        const indicator = side < 2
            ? { x: cardX + rect.x + (side === 1 ? rect.width : 0) - size / 2,
                y: cardY + (controller.monitorData.reserved?.[1] ?? 0) * nativeScale,
                width: size, height: cardHeight - ((controller.monitorData.reserved?.[1] ?? 0)
                    + (controller.monitorData.reserved?.[3] ?? 0)) * nativeScale }
            : { x: cardX + rect.x, y: cardY + rect.y + (side === 3 ? rect.height : 0) - size / 2,
                width: rect.width, height: size };
        return { workspace: workspaceId, anchor, direction: ["l", "r", "u", "d"][side], x, y, indicator };
    }

    // Save a tiled window's screen position before focus changes. Restoring
    // this anchor restores the entire scrolling viewport, including its gaps.
    function activationView(preferredAddress, reveal = false) {
        let viewPositions = positions;
        const rect = positions[preferredAddress];
        if (reveal && layout === "scrolling" && rect
                && (rect.x < viewportLeft - viewportScale || rect.x + rect.width > viewportRight + viewportScale)) {
            viewPositions = Scrolling.positions(clients, layout, controller.monitorData, cardWidth,
                preferredAddress, true, controller.fitColumns, cardHeight,
                controller.gapsIn, controller.gapsOut, controller.windowBorder, uiScale);
        }
        const tiled = clients.filter(w => !w.floating && viewPositions[w.address]);
        const anchor = tiled.find(w => w.address === preferredAddress) ?? tiled.slice().sort((a, b) => {
            const ra = viewPositions[a.address], rb = viewPositions[b.address];
            return Math.abs(ra.x + ra.width / 2 - cardWidth / 2)
                - Math.abs(rb.x + rb.width / 2 - cardWidth / 2);
        })[0];
        if (!anchor) return null;
        const nativeScale = root.viewportScale;
        const desktopX = (cardWidth - controller.screen.width * nativeScale) / 2;
        return { address: anchor.address, x: controller.monitorData.x + (viewPositions[anchor.address].x - desktopX) / nativeScale,
            revealed: viewPositions !== positions };
    }

    function step(direction) {
        const next = navigationIndex + direction;
        controller.selectWorkspace(workspaceId);
        if (next >= 0 && next < navigationItems.length)
            controller.panWorkspace(workspaceId, navigationItems[next][0]);
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        enabled: WorkspaceNames.canName(root.workspaceId)
        onTapped: eventPoint => root.controller.renameWorkspace(root.workspaceId,
            eventPoint.scenePosition.x, eventPoint.scenePosition.y)
    }

    LauncherTitlePill {
        x: root.cardX + 6 * root.uiScale
        y: root.cardY + 6 * root.uiScale
        width: Math.max(0, Math.min(root.cardWidth - 12 * root.uiScale, implicitWidth))
        height: Math.max(0, Math.min(26 * root.uiScale, root.cardHeight - 12 * root.uiScale))
        z: 10
        uiScale: root.uiScale
        visible: !root.empty || WorkspaceNames.nameFor(root.workspaceId).length > 0
        text: WorkspaceNames.nameFor(root.workspaceId) || Translation.tr("Workspace %1").arg(root.workspaceId)
    }
    HoverHandler { id: workspaceHover; blocking: false }
    StyledRectangularShadow {
        target: backdrop
        color: Appearance.sizes.dockShowBackground ? Appearance.colors.colDockShadow : "transparent"
    }
    LauncherWorkspaceSurface {
        id: backdrop
        x: root.cardX; y: root.cardY
        width: root.cardWidth; height: root.cardHeight
        radius: root.cardRadius
        uiScale: root.uiScale
        backdropSource: root.controller.dockBackdropSource
        backdropRect: root.controller.dockBackdropRect
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: ColorUtils.applyAlpha(Appearance.launcherContent.colOnLayer0, 0.035)
        }
        StyledText {
            anchors.centerIn: parent
            visible: root.empty
            text: root.workspaceId
            font.pixelSize: root.cardHeight * 0.3
            font.weight: Font.DemiBold
            font.family: Appearance.font.family.expressive
            color: Appearance.launcherContent.colTileNumber
        }
        MouseArea {
            anchors.fill: parent
            onClicked: root.controller.activateWorkspace(root.workspaceId)
        }
    }

    // One alpha ramp per row fades the overhang without drawing over the
    // neighboring column. Mask input too, so invisible windows cannot be hit.
    Item {
        id: windows
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: parent.height
        // Keep the last rendered windows through the closing fade. Captures
        // detach at close, which would otherwise reveal their fallback icons.
        layer.enabled: root.controller.rendering
        layer.live: root.controller.opened
        layer.effect: OpacityMask { maskSource: edgeMask }
        Rectangle {
            id: edgeMask
            anchors.fill: parent
            visible: false
            layer.enabled: root.controller.rendering
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: GlobalStates.overviewWorkspacesOnly ? "white" : "transparent"
                }
                GradientStop {
                    position: root.cardX / Math.max(1, root.width)
                    color: "white"
                }
                GradientStop {
                    position: (root.cardX + root.cardWidth) / Math.max(1, root.width)
                    color: "white"
                }
                GradientStop {
                    position: 1.0
                    color: GlobalStates.overviewWorkspacesOnly ? "white" : "transparent"
                }
            }
        }
        Repeater {
            // Only this workspace's windows; ScriptModel keeps their identity across
            // geometry refreshes, so previews survive updates.
            model: ScriptModel {
                values: ToplevelManager.toplevels.values.filter(toplevel =>
                    HyprlandData.clientForToplevel(toplevel)?.workspace.id === root.workspaceId)
            }
            delegate: Item {
                id: tile
                required property var modelData
                readonly property var client: HyprlandData.clientForToplevel(modelData)
                readonly property string address: client?.address ?? ""
                readonly property string icon: AppSearch.guessIcon(TaskbarApps.resolveAppId(modelData))
                readonly property bool hovered: windowHover.hovered && !root.controller.dragAddress && !root.controller.searching
                readonly property var position: root.positions[address]
                readonly property bool selected: root.selected && root.controller.selectedByWorkspace[root.workspaceId] === address
                readonly property bool intersects: x + width > 0 && x < root.width
                visible: !!position && intersects
                x: root.cardX + (position?.x ?? 0)
                y: root.cardY + (position?.y ?? 0)
                width: position?.width ?? 1
                height: position?.height ?? 1
                z: selected ? 2 : 1
                states: State {
                    when: root.controller.dragItem === tile
                    ParentChange { target: tile; parent: root.controller.windowDragLayer }
                    PropertyChanges {
                        target: tile
                        x: root.controller.dragPoint.x - root.controller.dragGrab.x
                        y: root.controller.dragPoint.y - root.controller.dragGrab.y
                        width: root.controller.dragSize.width
                        height: root.controller.dragSize.height
                        visible: true
                        z: 1
                    }
                }
                Behavior on x { enabled: root.controller.opened && !root.controller.dragAddress; animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -2 * root.uiScale
                    radius: RoundedCorners.on ? (Appearance.rounding.verysmall + 2) * root.uiScale : 0
                    color: "transparent"
                    visible: root.controller.dragItem !== tile
                    border.width: (tile.selected ? 2 : tile.hovered ? 1 : 0) * root.uiScale
                    border.color: tile.selected ? root.controller.contentColors.colSecondaryOnTile
                        : ColorUtils.applyAlpha(root.controller.contentColors.colOnLayer0, 0.35)
                }
                Rectangle {
                    id: body
                    anchors.fill: parent
                    color: Appearance.colors.colLayer2
                    radius: RoundedCorners.on ? Appearance.rounding.verysmall * root.uiScale : 0
                    layer.enabled: tile.visible && root.controller.opened
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: tileMask }
                    WorkspacePreviewMask {
                        id: tileMask
                        // A window running past the card's side carries on into the fade
                        // there, so on that side only the card's top and bottom cut it.
                        readonly property bool pastLeft: tile.x < root.cardX - 0.5
                        readonly property bool pastRight: tile.x + tile.width > root.cardX + root.cardWidth + 0.5
                        readonly property real cardLeft: pastLeft ? -1 : root.cardX - tile.x
                        readonly property real cardRight: pastRight ? tile.width + 1 : root.cardX + root.cardWidth - tile.x
                        readonly property real leftRadius: pastLeft ? 0 : root.cardRadius
                        readonly property real rightRadius: pastRight ? 0 : root.cardRadius
                        anchors.fill: parent
                        windowRadii: Qt.vector4d(body.radius, body.radius, body.radius, body.radius)
                        workspaceRect: Qt.vector4d(cardLeft, root.cardY - tile.y, cardRight - cardLeft, root.cardHeight)
                        workspaceRadii: Qt.vector4d(leftRadius, rightRadius, leftRadius, rightRadius)
                        workspaceClipped: root.controller.dragItem === tile ? 0 : 1
                        layer.enabled: tile.visible && root.controller.opened
                        visible: false
                    }
                    HdrScreencopyView {
                        id: preview
                        anchors.fill: parent
                        captureSource: root.controller.opened && (tile.visible || root.controller.dragItem === tile) ? tile.modelData : null
                        live: !root.controller.searching && !root.controller.activationPending
                        constraintSize: Qt.size(Math.ceil(tile.width * root.controller.monitorData.scale),
                            Math.ceil(tile.height * root.controller.monitorData.scale))
                    }
                }
                LauncherWindowBadge {
                    id: badge
                    objectName: "windowBadge"
                    uiScale: root.uiScale
                    source: Quickshell.iconPath(tile.icon, "application-x-executable")
                    visible: root.controller.dragItem !== tile
                }
                Item {
                    // Only the visible part of an overhanging window receives
                    // presses. Drag coordinates stay in the scene as it lifts.
                    x: root.controller.dragItem === tile ? 0 : Math.max(0, root.fadeLeft - tile.x) + 2 * root.uiScale
                    width: root.controller.dragItem === tile ? tile.width
                        : Math.max(0, Math.min(tile.width, root.fadeRight - tile.x) - x - 2 * root.uiScale)
                    height: tile.height
                    HoverHandler { id: windowHover; blocking: false }
                    TapHandler {
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: (eventPoint, button) => {
                            if (button === Qt.MiddleButton) root.controller.closeWindow(tile.address);
                            else root.controller.activateWindow(tile.address);
                        }
                    }
                    DragHandler {
                        target: null
                        acceptedButtons: Qt.LeftButton
                        dragThreshold: 10 * root.uiScale
                        onActiveChanged: {
                            if (active) {
                                const point = centroid.scenePressPosition;
                                root.controller.beginWindowDrag(tile.address, tile, point.x, point.y);
                            } else if (root.controller.dragItem === tile) {
                                root.controller.finishDrag();
                            }
                        }
                        onCentroidChanged: {
                            if (active && root.controller.dragItem === tile) {
                                const point = centroid.scenePosition;
                                root.controller.updateDrag(point.x, point.y);
                            }
                        }
                    }
                }
            }
        }
    }
    Rectangle {
        x: root.cardX - 2 * root.uiScale; y: root.cardY - 2 * root.uiScale
        width: root.cardWidth + 4 * root.uiScale; height: root.cardHeight + 4 * root.uiScale
        radius: RoundedCorners.on ? root.cardRadius + 2 * root.uiScale : 0
        color: "transparent"
        border.width: (root.dropHovered || root.selected ? 2 : 1) * root.uiScale
        border.color: root.dropHovered ? root.controller.contentColors.colLayer2Hover
            : root.selected ? root.controller.contentColors.colSecondaryOnTile
            : ColorUtils.applyAlpha(root.controller.contentColors.colOutlineVariant, 0.2)
        Behavior on border.color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    }
    Rectangle {
        objectName: "windowDropIndicator"
        readonly property var indicator: root.controller.dropInfo?.workspace === root.workspaceId
            ? root.controller.dropInfo?.indicator : null
        visible: !!indicator && root.controller.dragItem !== null
        x: indicator?.x ?? 0
        y: indicator?.y ?? 0
        width: indicator?.width ?? 0
        height: indicator?.height ?? 0
        radius: RoundedCorners.on ? Math.min(root.cardRadius, width / 2, height / 2) : 0
        color: ColorUtils.applyAlpha(root.controller.contentColors.colPrimary, 0.3)
    }
    Repeater {
        model: Config.options.interactions.showWorkspaceNavigationArrows ? [-1, 1] : []
        delegate: WorkspaceNavigationButton {
            required property int modelData
            objectName: modelData < 0 ? "previousColumn" : "nextColumn"
            x: modelData < 0 ? Math.max(0, root.cardX - width - 8 * root.uiScale)
                : Math.min(root.width - width, root.cardX + root.cardWidth + 8 * root.uiScale)
            y: root.cardY + (root.cardHeight - height) / 2
            visible: modelData < 0 ? root.moreBefore : root.moreAfter
            width: 40 * root.uiScale
            height: width
            uiScale: root.uiScale
            pressedAtRest: false
            iconName: modelData < 0 ? "chevron_left" : "chevron_right"
            Accessible.name: modelData < 0 ? Translation.tr("Back") : Translation.tr("Next")
            onClicked: root.step(modelData)
        }
    }
}
