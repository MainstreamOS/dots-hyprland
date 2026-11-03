import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * A surface's wallpaper blur, cut to the surface it sits behind and
 * the curves it grows. The surface's own color goes on top of it, so that color
 * is the tint.
 */
Loader {
    id: root
    property var source: null
    // Whichever surface's config holds these values.
    property var settings: Config.options.bar.backdrop
    // Solid has plain blur when its color is see-through. Keep it neutral
    // even if a previously selected Glass preset left lens settings behind.
    readonly property var look: root.settings.enable ? root.settings : BackdropPresets.shipped[0]
    property real topLeftRadius: 0
    property real topRightRadius: 0
    property real bottomLeftRadius: 0
    property real bottomRightRadius: 0
    property real trackX: 0
    property real trackY: 0
    // The part of the wallpaper to show instead of the one behind, and the part shown.
    property rect sampleRect: Qt.rect(0, 0, 0, 0)
    readonly property rect sampledRect: root.item?.sampled ?? Qt.rect(0, 0, 0, 0)
    // The screen edge a notch's curves stand on, beside its two ends, and how far they lap it.
    property string notchEdge: ""
    property int notchSize: 0
    property real notchLap: 2
    // The screen edge a hugging strip lies along, with its curves at the screen's corners.
    property string hugEdge: ""
    property int hugSize: 0

    readonly property var curves: {
        const w = root.width;
        const h = root.height;
        const s = root.notchSize;
        const lap = root.notchLap;
        const r = root.hugSize;
        const piece = (x, y, size, corner) => ({ "x": x, "y": y, "size": size, "corner": corner });
        switch (root.notchEdge) {
        case "top": return [piece(lap - s, 0, s, RoundCorner.CornerEnum.TopRight), piece(w - lap, 0, s, RoundCorner.CornerEnum.TopLeft)];
        case "bottom": return [piece(lap - s, h - s, s, RoundCorner.CornerEnum.BottomRight), piece(w - lap, h - s, s, RoundCorner.CornerEnum.BottomLeft)];
        case "left": return [piece(0, lap - s, s, RoundCorner.CornerEnum.BottomLeft), piece(0, h - lap, s, RoundCorner.CornerEnum.TopLeft)];
        case "right": return [piece(w - s, lap - s, s, RoundCorner.CornerEnum.BottomRight), piece(w - s, h - lap, s, RoundCorner.CornerEnum.TopRight)];
        }
        switch (root.hugEdge) {
        case "top": return [piece(0, h, r, RoundCorner.CornerEnum.TopLeft), piece(w - r, h, r, RoundCorner.CornerEnum.TopRight)];
        case "bottom": return [piece(0, -r, r, RoundCorner.CornerEnum.BottomLeft), piece(w - r, -r, r, RoundCorner.CornerEnum.BottomRight)];
        case "left": return [piece(w, 0, r, RoundCorner.CornerEnum.TopLeft), piece(w, h - r, r, RoundCorner.CornerEnum.BottomLeft)];
        case "right": return [piece(-r, 0, r, RoundCorner.CornerEnum.TopRight), piece(-r, h - r, r, RoundCorner.CornerEnum.BottomRight)];
        }
        return [];
    }
    // How far past the surface the curves reach on each side.
    readonly property real reachLeft: Math.max(0, ...curves.map(c => -c.x))
    readonly property real reachTop: Math.max(0, ...curves.map(c => -c.y))
    readonly property real reachRight: Math.max(0, ...curves.map(c => c.x + c.size - width))
    readonly property real reachBottom: Math.max(0, ...curves.map(c => c.y + c.size - height))

    // The blur covers the largest size the surface has needed, or this much from
    // the start, so a surface animating inside it only reshapes the cut. Re-blurring
    // for every frame of a resize is what would cost a low end card the most.
    property real regionWidth: 0
    property real regionHeight: 0
    // Which edge the surface grows away from, when it doesn't grow evenly around its middle.
    property string growsFrom: ""
    readonly property real wantedWidth: root.width + root.reachLeft + root.reachRight
    readonly property real wantedHeight: root.height + root.reachTop + root.reachBottom
    property real largestWidth: 0
    property real largestHeight: 0
    onWantedWidthChanged: largestWidth = Math.max(largestWidth, wantedWidth)
    onWantedHeightChanged: largestHeight = Math.max(largestHeight, wantedHeight)
    readonly property real blurWidth: Math.max(root.regionWidth, root.largestWidth, root.wantedWidth)
    readonly property real blurHeight: Math.max(root.regionHeight, root.largestHeight, root.wantedHeight)
    readonly property real blurX: (root.width + root.reachRight - root.reachLeft - root.blurWidth) / 2
    readonly property real blurY: root.growsFrom === "top" ? -root.reachTop
        : root.growsFrom === "bottom" ? root.height + root.reachBottom - root.blurHeight
        : (root.height + root.reachBottom - root.reachTop - root.blurHeight) / 2

    active: root.source?.available ?? false
    sourceComponent: Item {
        readonly property rect sampled: blurred.sampledRect
        FastBlurred {
            id: blurred
            x: root.blurX
            y: root.blurY
            width: root.blurWidth
            height: root.blurHeight
            blurSource: root.source.picture
            tintOpacity: root.look.haze
            blurRadius: root.look.blur
            magnification: root.look.magnification
            offsetX: root.look.offsetX
            offsetY: root.look.offsetY
            cardRect: Qt.rect(-root.blurX, -root.blurY, root.width, root.height)
            cardCurves: root.curves.map(c => Object.assign({}, c, { "x": c.x - root.blurX, "y": c.y - root.blurY }))
            topLeftRadius: root.topLeftRadius
            topRightRadius: root.topRightRadius
            bottomLeftRadius: root.bottomLeftRadius
            bottomRightRadius: root.bottomRightRadius
            trackX: root.trackX
            trackY: root.trackY
            sampleRect: root.sampleRect
        }
    }
}
