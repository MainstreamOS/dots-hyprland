pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Item { // Window
    id: root
    property real uiScale: 1
    property bool closing: false
    property bool captureSuppressed: false
    property var toplevel
    property var windowData
    property var monitorData
    property var workspaceReserved: monitorData?.reserved ?? [0, 0, 0, 0]
    property var scale
    property bool restrictToWorkspace: true
    property real widthRatio: {
        const widgetWidth = widgetMonitor.transform & 1 ? widgetMonitor.height : widgetMonitor.width;
        const monitorWidth = monitorData.transform & 1 ? monitorData.height : monitorData.width;
        return (widgetWidth * monitorData.scale) / (monitorWidth * widgetMonitor.scale);
    }
    property real heightRatio: {
        const widgetHeight = widgetMonitor.transform & 1 ? widgetMonitor.width : widgetMonitor.height;
        const monitorHeight = monitorData.transform & 1 ? monitorData.width : monitorData.height;
        return (widgetHeight * monitorData.scale) / (monitorHeight * widgetMonitor.scale);
    }
    property real initX: {
        return Math.max((windowData?.at[0] - (monitorData?.x ?? 0) - workspaceReserved[0]) * widthRatio * root.scale, 0) + xOffset;
    }

    property real initY: {
        return Math.max((windowData?.at[1] - (monitorData?.y ?? 0) - workspaceReserved[1]) * heightRatio * root.scale, 0) + yOffset;
    }
    property real xOffset: 0
    property real yOffset: 0
    property var widgetMonitor
    property int widgetMonitorId: widgetMonitor.id

    property var targetWindowWidth: windowData?.size[0] * scale * widthRatio
    property var targetWindowHeight: windowData?.size[1] * scale * heightRatio
    property bool hovered: false
    property bool pressed: false

    // A window partly off its screen is cut at its workspace's edge instead of
    // spilling onto the workspaces beside it; restrictToWorkspace is lifted
    // while it is dragged, so it shows whole on its way to another one. The
    // workspace sits at xOffset/yOffset on the grid, and x/y are this window's
    // own place there, so the cut follows every move and animation.
    property real workspaceWidth: 0
    property real workspaceHeight: 0
    property vector4d workspaceRadii
    readonly property bool clipped: restrictToWorkspace && workspaceWidth > 0 && workspaceHeight > 0
    readonly property real visibleLeft: clipped ? Math.max(0, xOffset - x) : 0
    readonly property real visibleTop: clipped ? Math.max(0, yOffset - y) : 0
    readonly property real visibleRight: clipped ? Math.min(width, xOffset + workspaceWidth - x) : width
    readonly property real visibleBottom: clipped ? Math.min(height, yOffset + workspaceHeight - y) : height

    property real xwaylandIndicatorToIconRatio: 0.35
    property string iconPath: Quickshell.iconPath(AppSearch.guessIcon(windowData?.class), "image-missing")

    property bool indicateXWayland: windowData?.xwayland ?? false

    x: initX
    y: initY
    width: targetWindowWidth
    height: targetWindowHeight
    opacity: windowData.monitor == widgetMonitorId ? 1 : 0.4

    property real topLeftRadius
    property real topRightRadius
    property real bottomLeftRadius
    property real bottomRightRadius

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: WorkspacePreviewMask {
            width: root.width
            height: root.height
            windowRect: Qt.vector4d(root.visibleLeft, root.visibleTop,
                Math.max(0, root.visibleRight - root.visibleLeft), Math.max(0, root.visibleBottom - root.visibleTop))
            windowRadii: Qt.vector4d(root.topLeftRadius, root.topRightRadius, root.bottomLeftRadius, root.bottomRightRadius)
            workspaceRect: Qt.vector4d(root.xOffset - root.x, root.yOffset - root.y, root.workspaceWidth, root.workspaceHeight)
            workspaceRadii: root.workspaceRadii
            workspaceClipped: root.clipped ? 1 : 0
        }
    }

    Item {
        id: visibleArea
        x: root.visibleLeft
        y: root.visibleTop
        width: Math.max(0, root.visibleRight - root.visibleLeft)
        height: Math.max(0, root.visibleBottom - root.visibleTop)
    }

    Behavior on x {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on y {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on width {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on height {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    // A client can refuse to close (unsaved-changes prompt), which leaves the
    // tile inert, so hand the input back after a grace period. The capture
    // stays down for the rest of this overview session: nothing here tells a
    // refusal apart from a close still in flight, and re-attaching to a
    // toplevel that then dies is the crash this guards against. The next
    // overview open builds the tile again, preview and all.
    onClosingChanged: {
        if (!root.closing) return;
        root.captureSuppressed = true;
        closeGracePeriod.restart();
    }

    Timer {
        id: closeGracePeriod
        interval: 1000
        repeat: false
        running: false
        onTriggered: root.closing = false
    }

    // Live preview of every visible window, including fullscreen and
    // maximised ones (games, IDEs, browsers running solo on a workspace).
    //
    // Capture only happens while the overview is open: captureSource is
    // bound to overviewOpen, so it's null when the overview is closed and
    // no GPU work is happening. When the overview opens with a heavy
    // tile (e.g. a 4K game alone on its workspace), GPU usage climbs for
    // the few seconds the overview is visible — that's the cost of
    // showing what's actually in each window. The overview-open speed
    // fix is independent of this (it's about the wlr-layer-shell surface
    // lifecycle, see Overview.qml).
    HdrScreencopyView {
        id: windowPreview
        anchors.fill: parent
        captureSource: (GlobalStates.overviewOpen && !root.captureSuppressed) ? root.toplevel : null
        live: true
        constraintSize: Qt.size(Math.max(1, root.targetWindowWidth), Math.max(1, root.targetWindowHeight))
    }

    // Color overlay for interactions
    Rectangle {
        anchors.fill: visibleArea
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomRightRadius: root.bottomRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        color: pressed ? ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.5) :
            hovered ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.7) :
            ColorUtils.transparentize(Appearance.colors.colLayer2)
        border.color : ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.88)
        border.width : root.uiScale
    }

    LauncherWindowBadge {
        id: windowIcon
        objectName: "windowBadge"
        uiScale: root.uiScale
        boundsItem: visibleArea
        source: root.iconPath
    }
}
