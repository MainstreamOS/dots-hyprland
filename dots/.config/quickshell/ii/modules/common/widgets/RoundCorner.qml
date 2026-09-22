import QtQuick
import QtQuick.Shapes

Item {
    id: root

    enum CornerEnum { TopLeft, TopRight, BottomLeft, BottomRight }
    property var corner: RoundCorner.CornerEnum.TopLeft
    property alias leftVisualMargin: shape.anchors.leftMargin
    property alias topVisualMargin: shape.anchors.topMargin
    property alias rightVisualMargin: shape.anchors.rightMargin
    property alias bottomVisualMargin: shape.anchors.bottomMargin

    property int implicitSize: 25
    property color color: "#000000"
    // An outline along the sweep alone. A curve's other two edges are where it
    // meets the surface beside it and the edge it sits on, and a line drawn
    // there would read as a seam rather than as an outline.
    property int outlineWidth: 0
    property color outlineColor: "transparent"

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    property bool isTopLeft: corner === RoundCorner.CornerEnum.TopLeft
    property bool isBottomLeft: corner === RoundCorner.CornerEnum.BottomLeft
    property bool isTopRight: corner === RoundCorner.CornerEnum.TopRight
    property bool isBottomRight: corner === RoundCorner.CornerEnum.BottomRight
    property bool isTop: isTopLeft || isTopRight
    property bool isBottom: isBottomLeft || isBottomRight
    property bool isLeft: isTopLeft || isBottomLeft
    property bool isRight: isTopRight || isBottomRight
    // Where the sweep starts, shared by the fill and the outline over it so the
    // two can never describe different curves.
    readonly property int arcStartAngle: {
        switch (root.corner) {
        case RoundCorner.CornerEnum.TopLeft: return 180;
        case RoundCorner.CornerEnum.TopRight: return -90;
        case RoundCorner.CornerEnum.BottomLeft: return 90;
        }
        return 0;
    }

    Shape {
        id: shape
        anchors {
            top: root.isTop ? parent.top : undefined
            bottom: root.isBottom ? parent.bottom : undefined
            left: root.isLeft ? parent.left : undefined
            right: root.isRight ? parent.right : undefined
        }
        layer.enabled: true
        layer.smooth: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: shapePath
            strokeWidth: 0
            fillColor: root.color
            pathHints: ShapePath.PathSolid & ShapePath.PathNonIntersecting

            startX: switch (root.corner) {
                case RoundCorner.CornerEnum.TopLeft:
                case RoundCorner.CornerEnum.BottomLeft: return 0;
                case RoundCorner.CornerEnum.TopRight:
                case RoundCorner.CornerEnum.BottomRight: return root.implicitSize;
            }
            startY: switch (root.corner) {
                case RoundCorner.CornerEnum.TopLeft:
                case RoundCorner.CornerEnum.TopRight: return 0;
                case RoundCorner.CornerEnum.BottomLeft:
                case RoundCorner.CornerEnum.BottomRight: return root.implicitSize;
            }
            PathAngleArc {
                moveToStart: false
                centerX: root.implicitSize - shapePath.startX
                centerY: root.implicitSize - shapePath.startY
                radiusX: root.implicitSize
                radiusY: root.implicitSize
                startAngle: root.arcStartAngle
                sweepAngle: 90
            }
            PathLine {
                x: shapePath.startX
                y: shapePath.startY
            }
        }

        ShapePath {
            strokeWidth: root.outlineWidth
            strokeColor: root.outlineColor
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap
            PathAngleArc {
                moveToStart: true
                centerX: root.implicitSize - shapePath.startX
                centerY: root.implicitSize - shapePath.startY
                radiusX: root.implicitSize
                radiusY: root.implicitSize
                startAngle: root.arcStartAngle + 8
                sweepAngle: 74
            }
        }
    }

}
