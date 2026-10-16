import qs.modules.common
import QtQuick
import QtQuick.Shapes

Shape {
    id: root
    property real amplitudeMultiplier: 0.5
    property real frequency: 6
    property color color: Appearance?.colors.colPrimary ?? "#685496"
    property real lineWidth: 4
    property real fullLength: width
    property bool animate: false
    property real _phase: 0

    preferredRendererType: Shape.CurveRenderer
    clip: true

    // Keep the stroke in the scene graph: resizing or reusing a seek bar must
    // not depend on a Canvas's previous backing image or paint state.
    readonly property var points: {
        if (width < lineWidth || height <= 0 || fullLength <= 0) return [];
        const result = [];
        const start = lineWidth / 2;
        const end = width - lineWidth / 2;
        const amplitude = lineWidth * amplitudeMultiplier;
        const k = frequency * 2 * Math.PI / fullLength;
        // Twenty-four samples per cycle keep the curve smooth at every width
        // without rebuilding a point for every pixel on every animation frame.
        const steps = Math.max(2, Math.ceil(frequency * 24 * width / fullLength));
        for (let i = 0; i <= steps; i++) {
            const x = start + (end - start) * i / steps;
            result.push(Qt.point(x, height / 2 + amplitude * Math.sin(k * x + _phase)));
        }
        return result;
    }

    FrameAnimation {
        running: root.animate && root.visible && (root.Window.window?.visible ?? false)
        onTriggered: root._phase += frameTime * 2.5
    }

    ShapePath {
        strokeColor: root.color
        strokeWidth: root.lineWidth
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathPolyline { path: root.points }
    }
}
