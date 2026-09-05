import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background

// Plays one transition on a loop between the desktop's own wallpaper and
// the stock one, recolored so the change always shows even when they are
// the same picture. The knobs mean what they mean on the desktop, so what
// the loop shows is what a change will do.
Rectangle {
    id: root
    property string effect: "fade"
    property bool running: true
    // The effect a loop is playing right now; random draws a new one each time.
    property string playing: "fade"

    implicitHeight: Math.round(width * 9 / 16)
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    readonly property string userWallpaper: Config.options.background.wallpaperPath
    readonly property url stockWallpaper: Quickshell.shellPath("assets/images/default_wallpaper.webp")

    property real fromOpacity: 1
    property real fromShift: 0
    property real fromRevealed: 0
    property real toShift: 0
    property real toZoom: 1
    property real shaderProgress: 0
    property real shaderTime: 0
    property bool shaderRunning: false
    readonly property bool playingIsShader: TransitionEffects.isShader(playing)

    function reset() {
        fromOpacity = 1;
        fromShift = 0;
        fromRevealed = 0;
        toShift = 0;
        toZoom = 1;
        shaderProgress = 0;
        shaderTime = 0;
        shaderRunning = false;
    }

    // Everything that moves is masked to the same rounded corners the
    // wallpaper preview on the Quick page has; a plain clip would cut the
    // pictures square inside the rounded frame.
    Item {
        id: stage
        anchors.fill: parent
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: stage.width
                height: stage.height
                radius: root.radius
            }
        }

    Image {
        id: toPicture
        anchors.fill: parent
        source: root.stockWallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize: Qt.size(root.width * 2, root.height * 2)
        layer.enabled: true
        layer.effect: HueSaturation { hue: 0.5 }
        transform: [
            Translate { x: root.toShift },
            Scale {
                origin.x: toPicture.width / 2
                origin.y: toPicture.height / 2
                xScale: root.toZoom
                yScale: root.toZoom
            }
        ]
    }

    Item {
        id: fromClip
        clip: true
        x: root.fromRevealed
        y: 0
        width: Math.max(0, root.width - root.fromRevealed)
        height: root.height
        Image {
            id: fromPicture
            width: root.width
            height: root.height
            source: root.userWallpaper !== "" ? ("file://" + root.userWallpaper) : root.stockWallpaper
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(root.width * 2, root.height * 2)
            opacity: root.fromOpacity
            transform: Translate { x: root.fromShift - root.fromRevealed }
        }
    }

    Loader {
        active: root.shaderRunning
        anchors.fill: parent
        sourceComponent: TransitionShader {
            fromItem: fromPicture
            toItem: toPicture
            effect: root.playing
            progress: root.shaderProgress
            time: root.shaderTime
        }
    }
    }

    // The name of what is playing, which is the point when the pick is random.
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 10
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer0
        opacity: 0.85
        implicitWidth: playingLabel.implicitWidth + 20
        implicitHeight: playingLabel.implicitHeight + 10
        StyledText {
            id: playingLabel
            anchors.centerIn: parent
            text: TransitionEffects.label(root.playing)
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
        }
    }

    onEffectChanged: {
        loop.stop();
        root.reset();
        loop.start();
    }

    SequentialAnimation {
        id: loop
        running: root.running && root.visible
        loops: Animation.Infinite
        ScriptAction {
            script: {
                root.reset();
                root.playing = TransitionEffects.resolve(root.effect);
                root.toShift = root.playing === "slide" ? root.width : 0;
                root.toZoom = root.playing === "zoom" ? 1.08 : 1;
                root.shaderRunning = root.playingIsShader;
            }
        }
        PauseAnimation { duration: 600 }
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "fromOpacity"
                to: (root.playing === "fade" || root.playing === "zoom" || root.playing === "none") ? 0 : 1
                duration: root.playing === "none" ? 0 : TransitionEffects.durationFor(root.playing)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
            NumberAnimation {
                target: root; property: "fromShift"
                to: root.playing === "slide" ? -root.width : 0
                duration: TransitionEffects.durationFor(root.playing)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
            NumberAnimation {
                target: root; property: "toShift"; to: 0
                duration: TransitionEffects.durationFor(root.playing)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
            NumberAnimation {
                target: root; property: "toZoom"; to: 1
                duration: TransitionEffects.durationFor(root.playing)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
            NumberAnimation {
                target: root; property: "fromRevealed"
                to: root.playing === "wipe" ? root.width : 0
                duration: TransitionEffects.durationFor(root.playing)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
            // A shader's progress is its timeline: the ring, peel or glitch
            // sweeps the whole frame at one speed, so an easing that settles
            // early would park the effect at the corners for the rest of the run.
            NumberAnimation {
                target: root; property: "shaderProgress"
                to: root.playingIsShader ? 1 : 0
                duration: TransitionEffects.durationFor(root.playing)
                easing.type: Easing.Linear
            }
            NumberAnimation {
                target: root; property: "shaderTime"
                to: root.playingIsShader ? TransitionEffects.durationFor(root.playing) / 1000 : 0
                duration: TransitionEffects.durationFor(root.playing)
            }
        }
        PauseAnimation { duration: 1200 }
    }
}
