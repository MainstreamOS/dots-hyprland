import qs.modules.common
import QtQuick

StyledText {
    id: root
    property real iconSize: Appearance?.font.pixelSize.small ?? 16
    property real fill: 0
    property real truncatedFill: fill.toFixed(1) // Reduce memory consumption spikes from constant font remapping
    property real truncatedOpsz: Math.round(iconSize / 4) * 4
    // Not the screen-scale choice StyledText makes, and deliberately so. These
    // glyphs animate their own outline: FILL runs 0 to 1 on a click and opsz
    // changes with the icon size. Distance-field glyphs are cached by glyph
    // index, which a variable axis does not change, so the cache keeps serving
    // the outline it first rasterized and the fill animation tears while an
    // icon at an unusual size can be wrong sitting still. Rasterizing each
    // time costs nothing here and is always right. None of what makes native
    // rendering wrong for text applies: hinting is off just below.
    renderType: Text.NativeRendering
    font {
        hintingPreference: Font.PreferNoHinting
        family: Appearance?.font.family.iconMaterial ?? "Material Symbols Rounded"
        pixelSize: iconSize
        weight: Font.Normal + (Font.DemiBold - Font.Normal) * truncatedFill
        variableAxes: { 
            "FILL": truncatedFill,
            // "wght": font.weight,
            // "GRAD": 0,
            "opsz": truncatedOpsz,
        }
    }

    Behavior on fill { // Leaky leaky, no good
        NumberAnimation {
            duration: Appearance?.animation.elementMoveFast.duration ?? 200
            easing.type: Appearance?.animation.elementMoveFast.type ?? Easing.BezierSpline
            easing.bezierCurve: Appearance?.animation.elementMoveFast.bezierCurve ?? [0.34, 0.80, 0.34, 1.00, 1, 1]
        }
    }
}
