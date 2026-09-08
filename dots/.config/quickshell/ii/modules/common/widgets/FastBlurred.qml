import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common

/**
 * Frosted glass cut to a card's shape, sampled from the wallpaper behind it.
 * The desktop widgets draw on top of the wallpaper inside one surface, so the
 * compositor has nothing to blur there and the picture has to be sampled here.
 */
Item {
    id: root

    required property Item blurSource
    property real cardRadius: 30
    property color tint: "white"
    property real tintOpacity: 0.15
    property real blurRadius: Config.options.background.widgets.blur.radius ?? 24
    property real trackX: 0
    property real trackY: 0

    // The blur reaches past the card on every side so its edge pixels have real
    // picture to average instead of smearing the border inward.
    readonly property real oversample: blurRadius * 1.5

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: root.cardRadius
        }
    }

    // mapToItem is a call rather than a property, so nothing can bind to it and
    // the region has to be recomputed by hand. Both positions matter: parallax
    // slides the wallpaper while the widget holds still, so watching the widget
    // alone would leave the backdrop showing a stale slice of picture.
    function refresh() {
        if (!blurSource) return;
        const pt = root.mapToItem(blurSource, -oversample, -oversample);
        shaderSource.sourceRect = Qt.rect(pt.x, pt.y, blur.width, blur.height);
        shaderSource.scheduleUpdate();
    }

    onTrackXChanged: refresh()
    onTrackYChanged: refresh()
    onWidthChanged: refresh()
    onHeightChanged: refresh()
    onBlurRadiusChanged: refresh()
    onBlurSourceChanged: refresh()
    Component.onCompleted: refresh()

    Connections {
        target: root.blurSource
        ignoreUnknownSignals: true
        function onXChanged() { root.refresh(); }
        function onYChanged() { root.refresh(); }
        function onWidthChanged() { root.refresh(); }
        function onHeightChanged() { root.refresh(); }
        function onSourceChanged() { root.refresh(); }
        function onStatusChanged() { root.refresh(); }
        // Carries the crossfade, so this is what keeps the backdrop in step
        // while one wallpaper transitions to the next.
        function onOpacityChanged() { root.refresh(); }
    }

    FastBlur {
        id: blur
        x: -root.oversample
        y: -root.oversample
        width: root.width + root.oversample * 2
        height: root.height + root.oversample * 2
        radius: root.blurRadius
        visible: root.blurSource !== null
        source: root.blurSource ? shaderSource : null

        ShaderEffectSource {
            id: shaderSource
            sourceItem: root.blurSource
            hideSource: false
            // A wallpaper is a still picture between transitions. Grabbing it on
            // demand keeps a dozen of these off the per-frame path, which is the
            // difference that shows on an older card.
            live: false
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.cardRadius
        color: root.tint
        opacity: root.tintOpacity
    }
}
