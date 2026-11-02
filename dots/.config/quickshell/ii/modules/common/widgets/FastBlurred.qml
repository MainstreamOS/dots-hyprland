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
    property real topLeftRadius: cardRadius
    property real topRightRadius: cardRadius
    property real bottomLeftRadius: cardRadius
    property real bottomRightRadius: cardRadius
    property color tint: "white"
    property real tintOpacity: 0.15
    property real blurRadius: Config.options.background.widgets.blur.radius ?? 24
    property real trackX: 0
    property real trackY: 0
    // The card's own part of this item, and the curves it grows beyond that.
    property rect cardRect: Qt.rect(0, 0, width, height)
    property var cardCurves: []
    // How much larger the picture shows behind the card, and how far it slides.
    property real magnification: 1
    property real offsetX: 0
    property real offsetY: 0

    // The blur reaches past the card on every side so its edge pixels have real
    // picture to average instead of smearing the border inward.
    readonly property real oversample: blurRadius * 1.5

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Item {
            width: root.width
            height: root.height
            Rectangle {
                x: root.cardRect.x
                y: root.cardRect.y
                width: root.cardRect.width
                height: root.cardRect.height
                topLeftRadius: root.topLeftRadius
                topRightRadius: root.topRightRadius
                bottomLeftRadius: root.bottomLeftRadius
                bottomRightRadius: root.bottomRightRadius
            }
            Repeater {
                model: root.cardCurves
                RoundCorner {
                    required property var modelData
                    x: modelData.x
                    y: modelData.y
                    implicitSize: modelData.size
                    corner: modelData.corner
                }
            }
        }
    }

    // mapToItem is a call rather than a property, so nothing can bind to it and
    // the region has to be recomputed by hand. Both positions matter: parallax
    // slides the wallpaper while the widget holds still, so watching the widget
    // alone would leave the backdrop showing a stale slice of picture.
    function refresh() {
        if (!blurSource) return;
        const shown = Qt.size(blur.width / magnification, blur.height / magnification);
        const center = root.mapToItem(blurSource, root.width / 2, root.height / 2);
        // Kept on the picture, since past its edge there is only emptiness to sample.
        const x = center.x - shown.width / 2 + offsetX;
        const y = center.y - shown.height / 2 + offsetY;
        shaderSource.sourceRect = Qt.rect(Math.max(0, Math.min(x, blurSource.width - shown.width)),
            Math.max(0, Math.min(y, blurSource.height - shown.height)), shown.width, shown.height);
        shaderSource.scheduleUpdate();
    }

    onTrackXChanged: refresh()
    onTrackYChanged: refresh()
    onWidthChanged: refresh()
    onHeightChanged: refresh()
    onBlurRadiusChanged: refresh()
    onMagnificationChanged: refresh()
    onOffsetXChanged: refresh()
    onOffsetYChanged: refresh()
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
        function onBackdropMoved() { root.refresh(); }
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
        visible: root.tintOpacity > 0
        color: root.tint
        opacity: root.tintOpacity
    }
}
