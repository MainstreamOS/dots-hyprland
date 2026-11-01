import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * The bar's Frost and Glass backdrop, cut to the surface it sits behind. The
 * surface's own color goes on top of it, so that color is the tint.
 */
Loader {
    id: root
    property var source: null
    property real topLeftRadius: 0
    property real topRightRadius: 0
    property real bottomLeftRadius: 0
    property real bottomRightRadius: 0
    property real trackX: 0
    property real trackY: 0

    active: root.source?.available ?? false
    sourceComponent: FastBlurred {
        blurSource: root.source
        tintOpacity: Config.options.bar.backdrop.haze
        blurRadius: Config.options.bar.backdrop.blur
        magnification: Config.options.bar.backdrop.magnification
        offsetX: Config.options.bar.backdrop.offsetX
        offsetY: Config.options.bar.backdrop.offsetY
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        trackX: root.trackX
        trackY: root.trackY
    }
}
