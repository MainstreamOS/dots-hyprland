import QtQuick
import qs.services
import qs.modules.common

/**
 * The blurred wallpaper behind a desktop widget's card, in the look chosen for
 * the widgets. Loaded on demand, so on Solid it builds nothing.
 */
Loader {
    id: root
    // The picture to sample. Null when the scene has none, such as a video wallpaper.
    property Item wallpaperItem: null
    // For a card that does without it in some of its layouts.
    property bool wanted: true
    property real cardRadius: 0
    property real trackX: 0
    property real trackY: 0
    readonly property var look: BackdropPresets.widgetLook

    anchors.fill: parent
    active: wanted && BackdropPresets.widgetBlurred && wallpaperItem !== null
    sourceComponent: FastBlurred {
        anchors.fill: parent
        blurSource: root.wallpaperItem
        cardRadius: root.cardRadius
        tint: BackdropPresets.widgetTint
        tintOpacity: 1
        blurRadius: root.look?.blur ?? Config.options.background.widgets.blur.radius
        magnification: root.look?.magnification ?? 1
        offsetX: root.look?.offsetX ?? 0
        offsetY: root.look?.offsetY ?? 0
        trackX: root.trackX
        trackY: root.trackY
    }
}
