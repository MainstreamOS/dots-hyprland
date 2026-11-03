import QtQuick
import QtQuick.Window
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
    // A part of the picture to show in place of the one behind this item, such as
    // the part another surface shows. The part this one samples is read back below.
    property rect sampleRect: Qt.rect(0, 0, 0, 0)
    readonly property alias sampledRect: shaderSource.sourceRect

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
    // Held on the picture it has while a new wallpaper's effect gets under way. On
    // release the old blur is kept over the new one and fades, so it changes with the
    // effect instead of snapping to the new picture before the effect has reached it.
    property bool frozen: false
    function releaseSampling(fadeMs) {
        if (!frozen) return;
        frozen = false;
        pictureChanged = true;
        if (fadeMs <= 0) {
            lastSample = 0;
            refresh();
            return;
        }
        oldBlur.visible = true;
        oldBlur.opacity = 1;
        oldBlur.scheduleUpdate();
        oldBlurFade.duration = fadeMs;
        sampleAfterCover.start();
    }

    function refresh() {
        if (frozen) {
            pictureChanged = true;
            return;
        }
        // A blur has no edges to show a skipped frame by, so anything moving the
        // picture under it, like a workspace pan, re-blurs at thirty frames a second.
        const now = Date.now();
        if (now - lastSample < 33) {
            if (!sampleLater.running) sampleLater.start();
            return;
        }
        lastSample = now;
        if (!blurSource) return;
        const shown = Qt.size(blur.width / magnification, blur.height / magnification);
        const center = root.mapToItem(blurSource, root.width / 2, root.height / 2);
        // Kept on the picture, since past its edge there is only emptiness to sample.
        const x = center.x - shown.width / 2 + offsetX;
        const y = center.y - shown.height / 2 + offsetY;
        const rect = sampleRect.width > 0 ? sampleRect
            : Qt.rect(Math.max(0, Math.min(x, blurSource.width - shown.width)),
                Math.max(0, Math.min(y, blurSource.height - shown.height)), shown.width, shown.height);
        // The same picture needs no new blur, however the card around it moved.
        const was = shaderSource.sourceRect;
        const same = Math.abs(was.x - rect.x) < 0.05 && Math.abs(was.y - rect.y) < 0.05
            && Math.abs(was.width - rect.width) < 0.05 && Math.abs(was.height - rect.height) < 0.05;
        if (same && !pictureChanged) return;
        pictureChanged = false;
        shaderSource.sourceRect = rect;
        // The more it is blurred, the fewer of the picture's pixels make a difference.
        const dpr = (root.Window.window?.devicePixelRatio ?? 1) * (blurRadius >= 32 ? 0.25 : blurRadius >= 12 ? 0.5 : 1);
        shaderSource.textureSize = Qt.size(Math.ceil(rect.width * dpr), Math.ceil(rect.height * dpr));
        shaderSource.scheduleUpdate();
    }

    onTrackXChanged: refresh()
    onTrackYChanged: refresh()
    onWidthChanged: refresh()
    onHeightChanged: refresh()
    onBlurRadiusChanged: { pictureChanged = true; refresh(); }
    onMagnificationChanged: refresh()
    onOffsetXChanged: refresh()
    onOffsetYChanged: refresh()
    onSampleRectChanged: refresh()
    onBlurSourceChanged: { pictureChanged = true; refresh(); }
    Component.onCompleted: refresh()

    property double lastSample: 0
    property bool pictureChanged: true
    Timer {
        id: sampleLater
        interval: 33
        onTriggered: root.refresh()
    }

    Connections {
        target: root.blurSource
        ignoreUnknownSignals: true
        function onXChanged() { root.refresh(); }
        function onYChanged() { root.refresh(); }
        function onWidthChanged() { root.refresh(); }
        function onHeightChanged() { root.refresh(); }
        function onSourceChanged() { root.pictureChanged = true; root.refresh(); }
        function onStatusChanged() { root.pictureChanged = true; root.refresh(); }
        // Carries the crossfade, so this is what keeps the backdrop in step
        // while one wallpaper transitions to the next.
        function onOpacityChanged() { root.pictureChanged = true; root.refresh(); }
        function onBackdropMoved() { root.refresh(); }
        function onBackdropFreeze() { root.frozen = true; }
        function onBackdropRelease(fadeMs) { root.releaseSampling(fadeMs); }
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
            // A source assigned before the sampler has a window can keep Qt
            // referencing its old native window after a hide. Connect only
            // while both items belong to the same window, and release on detach.
            sourceItem: shaderSource.Window.window && shaderSource.Window.window === root.blurSource?.Window.window ? root.blurSource : null
            hideSource: false
            // A wallpaper is a still picture between transitions. Grabbing it on
            // demand keeps a dozen of these off the per-frame path, which is the
            // difference that shows on an older card.
            live: false
        }
    }

    ShaderEffectSource {
        id: oldBlur
        x: blur.x
        y: blur.y
        width: blur.width
        height: blur.height
        visible: false
        sourceItem: oldBlur.Window.window && oldBlur.Window.window === blur.Window.window ? blur : null
        hideSource: false
        live: false
    }
    // The old blur needs a frame to be copied before the new picture replaces it.
    Timer {
        id: sampleAfterCover
        interval: 40
        onTriggered: {
            root.lastSample = 0;
            root.refresh();
            oldBlurFade.restart();
        }
    }
    NumberAnimation {
        id: oldBlurFade
        target: oldBlur
        property: "opacity"
        to: 0
        easing.type: Easing.InOutQuad
        onFinished: oldBlur.visible = false
    }

    Rectangle {
        anchors.fill: parent
        visible: root.tintOpacity > 0
        color: root.tint
        opacity: root.tintOpacity
    }
}
