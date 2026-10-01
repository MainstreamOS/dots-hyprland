pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

MouseArea {
    id: root
    required property SystemTrayItem item
    property bool targetMenuOpen: false
    // What the icon is drawn on, as drawn: the group it sits in on the bar,
    // or the surface of the popup that holds the rest.
    property color backdrop: Appearance.barContent.backdrops[0]
    // The icon's own pixels, read once per image, so the judgement below can
    // be made again against a new surface without reading them again.
    property var iconPixels: []
    // Use an unambiguous foreground while an icon cannot be sampled. This is
    // deliberately based on the drawn bar surface rather than the global
    // theme, so every tray client works on light and dark bar variants.
    readonly property bool fallbackMonochrome: Appearance.autoIconContrast && iconPixels.length === 0
    readonly property color fallbackInk: {
        const bg = Qt.color(root.backdrop);
        const luminance = ColorUtils.luminanceOfRgb(bg.r, bg.g, bg.b);
        return ColorUtils.contrastOfLuminances(luminance, 0)
            >= ColorUtils.contrastOfLuminances(luminance, 1) ? "black" : "white";
    }
    // An icon with nothing of its own standing off the surface, the way a
    // plain white glyph vanishes into a light group, is drawn inverted. One
    // with enough luminance contrast is left as the app drew it. Hue alone
    // is not enough: saturated icons can still vanish against a dark,
    // differently colored bar.
    readonly property bool iconLost: {
        if (!Appearance.autoIconContrast)
            return false;
        const bg = Qt.color(root.backdrop);
        const lbg = ColorUtils.luminanceOfRgb(bg.r, bg.g, bg.b);
        if (iconPixels.length === 0)
            return false;
        const configuredRatio = Number(Config.options.tray.autoContrastMinimumRatio);
        const configuredShare = Number(Config.options.tray.autoContrastMinimumVisibleShare);
        const minimumRatio = configuredRatio >= 1 && configuredRatio <= 21 ? configuredRatio : 3;
        const minimumVisibleShare = configuredShare >= 0 && configuredShare <= 1 ? configuredShare : 0.65;
        let total = 0;
        let standing = 0;
        for (let i = 0; i < iconPixels.length; i += 4) {
            const a = iconPixels[i + 3] / 255;
            if (a < 0.1)
                continue;
            const r = iconPixels[i] / 255 * a + bg.r * (1 - a);
            const g = iconPixels[i + 1] / 255 * a + bg.g * (1 - a);
            const b = iconPixels[i + 2] / 255 * a + bg.b * (1 - a);
            const l = ColorUtils.luminanceOfRgb(r, g, b);
            total += a;
            if (ColorUtils.contrastOfLuminances(l, lbg) >= minimumRatio)
                standing += a;
        }
        return total > 0 && standing / total < minimumVisibleShare;
    }

    signal menuOpened(qsWindow: var)
    signal menuClosed()

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    implicitWidth: 20
    implicitHeight: 20
    onPressed: (event) => {
        switch (event.button) {
        case Qt.LeftButton:
            item.activate();
            break;
        case Qt.RightButton:
            if (item.hasMenu)
                if (menu.active && menu.item && typeof menu.item.close === "function")
                    menu.item.close();
                else 
                    menu.open();
            break;
        }
        event.accepted = true;
    }
    onEntered: {
        tooltip.text = TrayService.getTooltipForItem(root.item);
    }

    Loader {
        id: menu
        function open() {
            menu.active = true;
        }
        active: false
        sourceComponent: SysTrayMenu {
            Component.onCompleted: this.open();
            trayItemMenuHandle: root.item.menu
            trayItemId: root.item.id
            anchor {
                window: root.QsWindow.window
                item: root
                gravity: Config.options.bar.vertical
                    ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                    : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
                edges: Config.options.bar.vertical
                    ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                    : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
            }
            onMenuOpened: (window) => root.menuOpened(window);
            onMenuClosed: {
                root.menuClosed();
                menu.active = false;
            }
        }
    }

    // Capture the already-rendered icon, rather than asking the image provider
    // for it again. Some tray clients send malformed icon updates, and a second
    // request at this reader's size can race the normal tray request.
    Item {
        id: iconSnapshot
        readonly property bool wanted: Appearance.autoIconContrast && !Config.options.tray.monochromeIcons
        property var result: null
        // Each change makes every earlier capture stale. A grab cannot be
        // cancelled, so its callback checks this number before it writes.
        property int generation: 0
        property bool captureInFlight: false

        function refresh() {
            generation += 1;
            retry.stop();
            settle.stop();
            if (!wanted || trayIcon.status !== Image.Ready) {
                result = null;
                return;
            }
            take();
            // Some clients replace icon pixels after emitting the change
            // signal while retaining the same icon URL. Capture again after
            // the next rendered frame instead of preserving the stale grab.
            settle.restart();
        }

        function take() {
            if (!wanted || trayIcon.status !== Image.Ready) {
                result = null;
                return;
            }

            if (trayIcon.width <= 0 || trayIcon.height <= 0 || !trayIcon.window) {
                retry.restart();
                return;
            }

            // Keep one grab outstanding. If the icon changed while it ran,
            // its callback drops the old result and starts the latest capture.
            if (captureInFlight)
                return;

            const captureGeneration = generation;
            captureInFlight = true;
            const started = trayIcon.grabToImage(function(grab) {
                captureInFlight = false;
                if (captureGeneration !== generation) {
                    take();
                    return;
                }
                if (!wanted || trayIcon.status !== Image.Ready) {
                    result = null;
                    return;
                }
                result = grab;
            }, Qt.size(24, 24));
            if (!started) {
                captureInFlight = false;
                if (captureGeneration !== generation)
                    take();
                else
                    retry.restart();
            }
        }

        Timer {
            id: retry
            interval: 150
            onTriggered: iconSnapshot.take()
        }

        Timer {
            id: settle
            interval: 150
            onTriggered: iconSnapshot.take()
        }

        onWantedChanged: refresh()

        Connections {
            target: trayIcon
            function onStatusChanged() { iconSnapshot.refresh(); }
            function onSourceChanged() { iconSnapshot.refresh(); }
            function onWidthChanged() { iconSnapshot.refresh(); }
            function onWindowChanged() { iconSnapshot.refresh(); }
        }

        Connections {
            target: root.item
            function onIconChanged() { iconSnapshot.refresh(); }
        }

        Component.onCompleted: refresh()
    }

    // Canvas cannot load an itemgrabber: URL directly, but Image can. Keeping
    // this invisible image between the grab result and Canvas lets the contrast
    // reader see the same pixels that are already on screen without a second
    // status-notifier image request.
    Image {
        id: snapshotImage
        visible: false
        property var snapshot: iconSnapshot.result
        source: snapshot ? snapshot.url : ""
        onStatusChanged: iconReader.requestPaint()
    }

    Canvas {
        id: iconReader
        width: 24
        height: 24
        opacity: 0
        property var snapshot: iconSnapshot.result
        onSnapshotChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (!snapshot || snapshotImage.snapshot !== snapshot || snapshotImage.status !== Image.Ready) {
                root.iconPixels = [];
                return;
            }
            ctx.drawImage(snapshotImage, 0, 0, width, height);
            root.iconPixels = Array.from(ctx.getImageData(0, 0, width, height).data);
        }
    }

    Item {
        anchors.fill: parent
        layer.enabled: root.iconLost
        // Channels turned end for end, with the alpha left as it is.
        layer.effect: LevelAdjust {
            minimumOutput: "#00ffffff"
            maximumOutput: "#ff000000"
        }

        IconImage {
            id: trayIcon
            visible: !Config.options.tray.monochromeIcons
            source: root.item.icon
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
        }

        Loader {
            // A tray client with no readable pixel data is explicitly drawn
            // in the best-contrasting ink until a usable sample arrives.
            active: Config.options.tray.monochromeIcons || root.fallbackMonochrome
            anchors.fill: trayIcon
            sourceComponent: Item {
                Desaturate {
                    id: desaturatedIcon
                    visible: false // There's already color overlay
                    anchors.fill: parent
                    source: trayIcon
                    desaturation: 0.8 // 1.0 means fully grayscale
                }
                ColorOverlay {
                    anchors.fill: desaturatedIcon
                    source: desaturatedIcon
                    color: root.fallbackMonochrome
                        ? root.fallbackInk
                        : ColorUtils.transparentize(Appearance.barContent.colOnLayer0, 0.9)
                }
            }
        }
    }

    PopupToolTip {
        id: tooltip
        extraVisibleCondition: root.containsMouse
        alternativeVisibleCondition: extraVisibleCondition
        anchorEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top
    }

}
