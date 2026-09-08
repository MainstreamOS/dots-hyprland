import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas

AbstractWidget {
    id: root

    required property string configEntryName
    required property int screenWidth
    required property int screenHeight
    required property int scaledScreenWidth
    required property int scaledScreenHeight
    required property real wallpaperScale
    // The picture the card samples for its frosted backdrop. Null when there
    // is nothing in the scene to sample, such as a video wallpaper.
    property Item wallpaperItem: null
    property bool visibleWhenLocked: false
    property var configEntry: Config.options.background.widgets[configEntryName]
    property string placementStrategy: configEntry.placementStrategy
    // A stored position is where the widget's center sits across the screen,
    // 0 at the left or top edge and 1 at the right or bottom, so one theme
    // lays its widgets out alike on every monitor. An entry with either value
    // above 1 is a pixel offset pair from before that rule and reads as
    // written until the next drag stores it anew. Either way the widget
    // stays on the screen.
    readonly property bool storedInPixels: configEntry.x > 1 || configEntry.y > 1
    function positionFor(stored, screenSize, extent) {
        const px = storedInPixels ? stored : stored * screenSize - extent / 2;
        return Math.max(0, Math.min(px, screenSize - extent));
    }
    function shareFor(px, screenSize, extent) {
        if (screenSize <= 0)
            return 0;
        const share = Math.max(0, Math.min(1, (px + extent / 2) / screenSize));
        return Math.round(share * 10000) / 10000;
    }
    property real targetX: positionFor(configEntry.x, scaledScreenWidth, width)
    property real targetY: positionFor(configEntry.y, scaledScreenHeight, height)
    // The drag moves a stand-in rather than the widget, so x and y keep their
    // bindings and a theme that moves the widget later still reaches it. The
    // stand-in lives beside the widget, not inside it: the drag measures each
    // step in the target's parent, and a parent that moved with the pointer
    // would hand back half of every step.
    Item {
        id: dragHandle
        parent: root.parent
    }
    drag.target: draggable ? dragHandle : undefined
    readonly property real placeX: drag.active ? dragHandle.x : targetX
    readonly property real placeY: drag.active ? dragHandle.y : targetY
    x: placeX
    y: placeY
    // A widget is placed by its center, so the spot is only known once it has
    // a size; the move animation waits for that or the first frame would
    // slide the widget half its size from the corner.
    property bool placed: false
    onWidthChanged: if (!placed && width > 0 && height > 0) Qt.callLater(() => placed = true)
    onHeightChanged: if (!placed && width > 0 && height > 0) Qt.callLater(() => placed = true)
    animateXPos: placed && !drag.active
    animateYPos: placed && !drag.active
    visible: opacity > 0
    opacity: (GlobalStates.screenLocked && !visibleWhenLocked) ? 0 : 1
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    scale: (draggable && containsPress) ? 1.05 : 1
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    draggable: placementStrategy === "free" && !Config.options.background.widgetsLocked
    onPressed: {
        dragHandle.x = root.x;
        dragHandle.y = root.y;
    }
    drag.onActiveChanged: {
        if (!drag.active)
            commitPosition(dragHandle.x, dragHandle.y);
    }
    function commitPosition(px, py) {
        configEntry.x = shareFor(px, scaledScreenWidth, width);
        configEntry.y = shareFor(py, scaledScreenHeight, height);
        restoreTargetBindings();
    }
    function restoreTargetBindings() {
        root.targetX = Qt.binding(() => positionFor(configEntry.x, scaledScreenWidth, width));
        root.targetY = Qt.binding(() => positionFor(configEntry.y, scaledScreenHeight, height));
    }

    property bool needsColText: false
    property color dominantColor: Appearance.colors.colPrimary
    property string dominantColorSourceWallpaperPath: ""
    property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
    property color colText: {
        const onNormalBackground = (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        const adaptiveColor = ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12))
        return onNormalBackground ? Appearance.colors.colOnLayer0 : adaptiveColor;
    }

    property bool wallpaperIsVideo: Config.options.background.wallpaperPath.endsWith(".mp4") || Config.options.background.wallpaperPath.endsWith(".webm") || Config.options.background.wallpaperPath.endsWith(".mkv") || Config.options.background.wallpaperPath.endsWith(".avi") || Config.options.background.wallpaperPath.endsWith(".mov")
    property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
    
    onWallpaperPathChanged: refreshPlacementIfNeeded()
    // Back on free, the widget stays where the region search parked it until
    // it is dragged or its stored place changes from outside, a theme apply
    // or the settings page, which is what the connection below catches.
    onPlacementStrategyChanged: {
        if (placementStrategy !== "free")
            restoreTargetBindings();
        refreshPlacementIfNeeded();
    }
    Connections {
        target: root.configEntry
        function onXChanged() { if (root.placementStrategy === "free") root.restoreTargetBindings() }
        function onYChanged() { if (root.placementStrategy === "free") root.restoreTargetBindings() }
    }
    onImplicitWidthChanged: refreshPlacementIfNeeded()
    onImplicitHeightChanged: refreshPlacementIfNeeded()
    Connections {
        target: Config
        function onReadyChanged() { refreshPlacementIfNeeded() }
    }

    Timer {
        id: placementDebounce
        interval: 150
        repeat: false
        onTriggered: {
            if (!Config.ready) return;
            if (root.implicitWidth <= 0 || root.implicitHeight <= 0) return;
            if (root.placementStrategy === "free" && !root.needsColText) return;
            leastBusyRegionProc.wallpaperPath = root.wallpaperPath;
            leastBusyRegionProc.contentWidth = Math.ceil(root.implicitWidth);
            leastBusyRegionProc.contentHeight = Math.ceil(root.implicitHeight);
            leastBusyRegionProc.running = false;
            leastBusyRegionProc.running = true;
        }
    }

    function refreshPlacementIfNeeded() {
        if (!Config.ready) return;
        if (root.implicitWidth <= 0 || root.implicitHeight <= 0) return;
        if (root.placementStrategy === "free" && !root.needsColText) return;
        placementDebounce.restart();
    }
    Process {
        id: leastBusyRegionProc
        property string wallpaperPath: root.wallpaperPath
        property int contentWidth: Math.ceil(root.implicitWidth) || 300
        property int contentHeight: Math.ceil(root.implicitHeight) || 300
        property int horizontalPadding: 200
        property int verticalPadding: 200
        command: [Quickshell.shellPath("scripts/images/least-busy-region-venv.sh") // Comments to force the formatter to break lines
            , "--screen-width", Math.round(root.scaledScreenWidth) //
            , "--screen-height", Math.round(root.scaledScreenHeight) //
            , "--width", contentWidth //
            , "--height", contentHeight //
            , "--horizontal-padding", horizontalPadding //
            , "--vertical-padding", verticalPadding //
            , wallpaperPath //
            , ...(root.placementStrategy === "mostBusy" ? ["--busiest"] : [])
            // "--visual-output",
        ]
        stdout: StdioCollector {
            id: leastBusyRegionOutputCollector
            onStreamFinished: {
                const output = leastBusyRegionOutputCollector.text;
                // console.log("[Background] Least busy region output:", output)
                if (output.length === 0) return;
                const parsedContent = JSON.parse(output);
                if (root.dominantColorSourceWallpaperPath !== root.wallpaperPath) {
                    root.dominantColor = parsedContent.dominant_color || Appearance.colors.colLayer0;
                    root.dominantColorSourceWallpaperPath = root.wallpaperPath;
                }
                if (root.placementStrategy === "free") return;
                root.targetX = parsedContent.center_x * root.wallpaperScale - root.width / 2;
                root.targetY  = parsedContent.center_y * root.wallpaperScale - root.height / 2;
            }
        }
    }
}

