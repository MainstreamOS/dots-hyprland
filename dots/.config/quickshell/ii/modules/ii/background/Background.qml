pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris

import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.weather

Variants {
    id: root
    readonly property bool fixedClockPosition: Config.options.background.clock.fixedPosition
    readonly property real fixedClockX: Config.options.background.clock.x
    readonly property real fixedClockY: Config.options.background.clock.y
    readonly property real clockSizePadding: 20
    readonly property real screenSizePadding: 50
    readonly property string clockStyle: Config.options.background.clock.style
    readonly property bool showCookieQuote: Config.options.background.showQuote && Config.options.background.quote !== "" && !GlobalStates.screenLocked && Config.options.background.clock.style === "cookie"
    readonly property real clockParallaxFactor: Config.options.background.parallax.clockFactor // 0 = full parallax, 1 = no parallax
    model: Quickshell.screens

    PanelWindow {
        id: bgRoot

        required property var modelData

        // Hide when fullscreen
        property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
        property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
        visible: GlobalStates.screenLocked || (!(activeWorkspaceWithFullscreen != undefined)) || !Config?.options.background.hideWhenFullscreen

        // Workspaces
        property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        property list<var> relevantWindows: HyprlandData.windowList.filter(win => win.monitor == monitor?.id && win.workspace.id >= 0).sort((a, b) => a.workspace.id - b.workspace.id)
        property int firstWorkspaceId: relevantWindows[0]?.workspace.id || 1
        // Take the max of: last workspace containing a window, any visited
        // workspace on this monitor, and the active workspace. Using only
        // window-bearing workspaces caps lastWorkspaceId at 10 when workspaces
        // 11+ are empty, which then pins parallax fraction to 1 past workspace 10.
        property int lastWorkspaceId: Math.max(
            relevantWindows[relevantWindows.length - 1]?.workspace.id || 1,
            workspacesForMonitor.reduce((m, w) => Math.max(m, w.id), 1),
            monitor?.activeWorkspace?.id ?? 1
        )
        property int workspaceChunkSize: Config?.options.bar.workspaces.shown ?? 10
        property int totalWorkspaces: Math.ceil(lastWorkspaceId / workspaceChunkSize) * workspaceChunkSize
        // Wallpaper
        property bool wallpaperIsVideo: Config.options.background.wallpaperPath.endsWith(".mp4") || Config.options.background.wallpaperPath.endsWith(".webm") || Config.options.background.wallpaperPath.endsWith(".mkv") || Config.options.background.wallpaperPath.endsWith(".avi") || Config.options.background.wallpaperPath.endsWith(".mov")
        property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
        property bool wallpaperSafetyTriggered: {
            const enabled = Config.options.workSafety.enable.wallpaper;
            const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
            const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
            return enabled && sensitiveWallpaper && sensitiveNetwork;
        }
        // Preserve a minimum 10% headroom so parallax has range to move through even when
        // workspaceZoom is 1. Matches pre-refactor behavior which had a hardcoded 1.1 baseline.
        readonly property real parallaxRation: Math.max(1.1, Config.options.background.parallax.workspaceZoom)
        property int wallpaperWidth: modelData.width // Some reasonable init value, to be updated
        property int wallpaperHeight: modelData.height // Some reasonable init value, to be updated
        // Derive logical screen size from the HyprlandMonitor directly. monitor.width/height are
        // the monitor's physical pixel resolution; monitor.scale is the Hyprland scale factor.
        // This binding recomputes on live scale changes because monitor.scale is the property
        // that actually fires when the user changes Hyprland scale. bgRoot.width / screen.width
        // don't reliably emit change notifications for the PanelWindow on live reconfigure.
        readonly property real logicalScreenWidth: bgRoot.monitor && bgRoot.monitor.scale > 0
            ? bgRoot.monitor.width / bgRoot.monitor.scale
            : bgRoot.width
        readonly property real logicalScreenHeight: bgRoot.monitor && bgRoot.monitor.scale > 0
            ? bgRoot.monitor.height / bgRoot.monitor.scale
            : bgRoot.height
        readonly property real minSuitableScale: (wallpaperWidth > 0 && wallpaperHeight > 0 && logicalScreenWidth > 0 && logicalScreenHeight > 0)
            ? Math.max(logicalScreenWidth / wallpaperWidth, logicalScreenHeight / wallpaperHeight)
            : 1
        readonly property real effectiveWallpaperScale: minSuitableScale * parallaxRation
        onEffectiveWallpaperScaleChanged: bgRoot.updateClockPosition()
        property real scaledWallpaperWidth: wallpaperWidth * effectiveWallpaperScale
        property real scaledWallpaperHeight: wallpaperHeight * effectiveWallpaperScale
        property real parallaxTotalPixelsX: Math.max(0, scaledWallpaperWidth - logicalScreenWidth)
        property real parallaxTotalPixelsY: Math.max(0, scaledWallpaperHeight - logicalScreenHeight)
        readonly property bool verticalParallax: (Config.options.background.parallax.autoVertical && wallpaperHeight > wallpaperWidth) || Config.options.background.parallax.vertical
        // Position
        property real clockX: (modelData.width / 2)
        property real clockY: (modelData.height / 2)
        property var textHorizontalAlignment: {
            if ((Config.options.lock.centerClock && GlobalStates.screenLocked) || wallpaperSafetyTriggered)
                return Text.AlignHCenter;
            if (clockX < screen.width / 3)
                return Text.AlignLeft;
            if (clockX > screen.width * 2 / 3)
                return Text.AlignRight;
            return Text.AlignHCenter;
        }
        // Colors
        property bool shouldBlur: (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        property color dominantColor: Appearance.colors.colPrimary // Default, to be changed
        property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
        property color colText: {
            if (wallpaperSafetyTriggered)
                return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
            return (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colOnLayer0 : CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12));
        }
        Behavior on colText {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        // Layer props
        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: (GlobalStates.screenLocked && !scaleAnim.running) ? WlrLayer.Overlay : WlrLayer.Bottom
        // WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:background"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: {
            if (!bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo)
                return "transparent";
            return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        onWallpaperPathChanged: {
            bgRoot.updateZoomScale();
            // Clock position gets updated after zoom scale is updated
        }

        // Wallpaper zoom scale
        function updateZoomScale() {
            getWallpaperSizeProc.path = bgRoot.wallpaperPath;
            getWallpaperSizeProc.running = true;
        }
        Process {
            id: getWallpaperSizeProc
            property string path: bgRoot.wallpaperPath
            command: ["magick", "identify", "-format", "%w %h", path]
            stdout: StdioCollector {
                id: wallpaperSizeOutputCollector
                onStreamFinished: {
                    const output = wallpaperSizeOutputCollector.text;
                    const [width, height] = output.split(" ").map(Number);
                    bgRoot.wallpaperWidth = width;
                    bgRoot.wallpaperHeight = height;
                    // minSuitableScale is a reactive binding; no manual assignment needed.
                    bgRoot.updateClockPosition();
                }
            }
        }

        // Clock positioning
        function updateClockPosition() {
            // Somehow all this manual setting is needed to make the proc correctly use the new values
            leastBusyRegionProc.path = bgRoot.wallpaperPath;
            leastBusyRegionProc.contentWidth = clockLoader.implicitWidth + root.clockSizePadding * 2;
            leastBusyRegionProc.contentHeight = clockLoader.implicitHeight + root.clockSizePadding * 2;
            leastBusyRegionProc.horizontalPadding = bgRoot.movableXSpace + root.screenSizePadding * 2;
            leastBusyRegionProc.verticalPadding = bgRoot.movableYSpace + root.screenSizePadding * 2;
            leastBusyRegionProc.running = false;
            leastBusyRegionProc.running = true;
        }
        Process {
            id: leastBusyRegionProc
            property string path: bgRoot.wallpaperPath
            property int contentWidth: 300
            property int contentHeight: 300
            property int horizontalPadding: bgRoot.movableXSpace
            property int verticalPadding: bgRoot.movableYSpace
            command: [Quickshell.shellPath("scripts/images/least-busy-region-venv.sh"), "--screen-width", Math.round(bgRoot.logicalScreenWidth / bgRoot.effectiveWallpaperScale), "--screen-height", Math.round(bgRoot.logicalScreenHeight / bgRoot.effectiveWallpaperScale), "--width", contentWidth, "--height", contentHeight, "--horizontal-padding", horizontalPadding, "--vertical-padding", verticalPadding, path
                // "--visual-output",
                ,]
            stdout: StdioCollector {
                id: leastBusyRegionOutputCollector
                onStreamFinished: {
                    const output = leastBusyRegionOutputCollector.text;
                    // console.log("[Background] Least busy region output:", output)
                    if (output.length === 0)
                        return;
                    const parsedContent = JSON.parse(output);
                    bgRoot.clockX = parsedContent.center_x * bgRoot.effectiveWallpaperScale;
                    bgRoot.clockY = parsedContent.center_y * bgRoot.effectiveWallpaperScale;
                    bgRoot.dominantColor = parsedContent.dominant_color || Appearance.colors.colPrimary;
                }
            }
        }

        // Wallpaper
        Item {
            anchors.fill: parent

            // Wallpaper
            StyledImage {
                id: wallpaper
                visible: opacity > 0 && !blurLoader.active
                opacity: (status === Image.Ready && !bgRoot.wallpaperIsVideo) ? 1 : 0
                cache: false
                smooth: false

                property int workspaceIndex: (bgRoot.monitor.activeWorkspace?.id ?? 1) - 1
                property real middleFraction: 0.5
                property real fraction: {
                    // 0 - start of the picture
                    // 1 - end of the picture
                    if (bgRoot.totalWorkspaces <= 1) {
                        return middleFraction;
                    }
                    return Math.max(0, Math.min(1, workspaceIndex / (bgRoot.totalWorkspaces - 1)));
                }

                property real usedFractionX: {
                    let usedFraction = middleFraction;
                    if (Config.options.background.parallax.enableWorkspace && !bgRoot.verticalParallax) {
                        usedFraction = fraction;
                    }
                    if (Config.options.background.parallax.enableSidebar) {
                        let sidebarFraction = bgRoot.parallaxRation / bgRoot.workspaceChunkSize / 2;
                        usedFraction += (sidebarFraction * GlobalStates.sidebarRightOpen - sidebarFraction * GlobalStates.sidebarLeftOpen);
                    }
                    return Math.max(0, Math.min(1, usedFraction));
                }
                property real usedFractionY: {
                    let usedFraction = middleFraction;
                    if (Config.options.background.parallax.enableWorkspace && bgRoot.verticalParallax) {
                        usedFraction = fraction;
                    }
                    return Math.max(0, Math.min(1, usedFraction));
                }

                x: {
                    if (bgRoot.logicalScreenWidth > width) {
                        // Center the picture
                        return (bgRoot.logicalScreenWidth - width) / 2;
                    }
                    return - bgRoot.parallaxTotalPixelsX * usedFractionX;
                }
                y: {
                    if (bgRoot.logicalScreenHeight > height) {
                        // Center the picture
                        return (bgRoot.logicalScreenHeight - height) / 2;
                    }
                    return - bgRoot.parallaxTotalPixelsY * usedFractionY;
                }

                source: bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.wallpaperPath
                fillMode: Image.PreserveAspectCrop
                Behavior on x {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
                sourceSize {
                    width: bgRoot.scaledWallpaperWidth
                    height: bgRoot.scaledWallpaperHeight
                }
                width: bgRoot.scaledWallpaperWidth
                height: bgRoot.scaledWallpaperHeight
            }

            Loader {
                id: blurLoader
                active: Config.options.lock.blur.enable && (GlobalStates.screenLocked || scaleAnim.running || GlobalStates.overviewOpen)
                anchors.fill: wallpaper
                // extraZoom only applies to the lock screen, not the overview
                scale: GlobalStates.screenLocked ? Config.options.lock.blur.extraZoom : 1
                Behavior on scale {
                    NumberAnimation {
                        id: scaleAnim
                        duration: 400
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                    }
                }
                sourceComponent: GaussianBlur {
                    source: wallpaper
                    // Full lock radius when locked; slightly lighter blur for overview
                    radius: GlobalStates.screenLocked
                        ? Config.options.lock.blur.radius
                        : (GlobalStates.overviewOpen ? Config.options.lock.blur.radius : 0)
                    samples: radius * 2 + 1
                    Behavior on radius {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        // Lock screen: full dim; overview: lighter dim
                        opacity: GlobalStates.screenLocked ? 1 : (GlobalStates.overviewOpen ? 0.85 : 0)
                        color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                    }
                }
            }

            WidgetCanvas {
                id: widgetCanvas
                width: parent.width
                height: parent.height
                readonly property real parallaxFactor: {
                    var f = Config.options.background.parallax.widgetsFactor;
                    return f / bgRoot.parallaxRation;

                }

                // Music
                property bool hasActiveMusic: GlobalStates.screenLocked && MprisController.activePlayer && MprisController.activePlayer.isPlaying
                property real musicOffset: hasActiveMusic ? -80 : 0

                readonly property real baseWallpaperOffsetX: (bgRoot.logicalScreenWidth - wallpaper.width) / 2
                readonly property real baseWallpaperOffsetY: (bgRoot.logicalScreenHeight - wallpaper.height) / 2
                readonly property real wallpaperTotalOffsetX: wallpaper.x - baseWallpaperOffsetX
                readonly property real wallpaperTotalOffsetY: wallpaper.y - baseWallpaperOffsetY
                readonly property bool locked: GlobalStates.screenLocked
                x: wallpaperTotalOffsetX * parallaxFactor * !locked
                y: wallpaperTotalOffsetY * parallaxFactor * !locked

                transitions: Transition {
                    PropertyAnimation {
                        properties: "width,height"
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                    AnchorAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.weather.enable
                    sourceComponent: WeatherWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                    }
                }

                FadeLoader {
                    shown: Config.options.background.widgets.clock.enable
                    sourceComponent: ClockWidget {
                        screenWidth: bgRoot.screen.width
                        screenHeight: bgRoot.screen.height
                        scaledScreenWidth: bgRoot.screen.width
                        scaledScreenHeight: bgRoot.screen.height
                        wallpaperScale: 1
                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                        hasActiveMusic: widgetCanvas.hasActiveMusic
                    }
                }
            }
        }
    }
}
