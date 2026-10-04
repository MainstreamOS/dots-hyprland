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
    // The color the icon sits on, as drawn: its bar group, or the overflow popup.
    property color backdrop: Appearance.barContent.backdrops[0]
    // Read once per image, so a new backdrop is judged without a new read.
    property var iconPixels: []
    // True when almost nothing stands off the backdrop (a white glyph on a light
    // group). An outline or a color of its own keeps the icon as the app drew it.
    readonly property bool iconLost: {
        if (!Appearance.autoIconContrast || iconPixels.length === 0)
            return false;
        const bg = Qt.color(root.backdrop);
        const lbg = ColorUtils.luminanceOfRgb(bg.r, bg.g, bg.b);
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
            if (ColorUtils.contrastOfLuminances(l, lbg) >= 1.5
                    || Math.hypot(r - bg.r, g - bg.g, b - bg.b) >= 0.35)
                standing += a;
        }
        return total > 0 && standing / total < 0.1;
    }
    // The color a lost icon is drawn toward.
    readonly property color ink: {
        const own = Appearance.barContent.colOnLayer0;
        if (ColorUtils.contrastRatio(own, root.backdrop) >= 3)
            return own;
        const lbg = ColorUtils.relativeLuminance(root.backdrop);
        return ColorUtils.contrastOfLuminances(lbg, 0) >= ColorUtils.contrastOfLuminances(lbg, 1) ? "black" : "white";
    }
    // A plain white or gray glyph takes the ink outright. A colored icon moves
    // only until most of it stands off the surface, so it keeps its hue.
    readonly property real inkShare: {
        if (!iconLost)
            return 0;
        const bg = Qt.color(root.backdrop);
        const lbg = ColorUtils.luminanceOfRgb(bg.r, bg.g, bg.b);
        const ink = Qt.color(root.ink);
        const px = [];
        let total = 0;
        let mr = 0;
        let mg = 0;
        let mb = 0;
        for (let i = 0; i < iconPixels.length; i += 4) {
            const a = iconPixels[i + 3] / 255;
            if (a < 0.1)
                continue;
            const r = iconPixels[i] / 255;
            const g = iconPixels[i + 1] / 255;
            const b = iconPixels[i + 2] / 255;
            px.push(r, g, b, a);
            total += a;
            mr += r * a;
            mg += g * a;
            mb += b * a;
        }
        mr /= total;
        mg /= total;
        mb /= total;
        let oneColor = 0;
        for (let i = 0; i < px.length; i += 4) {
            if (Math.hypot(px[i] - mr, px[i + 1] - mg, px[i + 2] - mb) < 0.15)
                oneColor += px[i + 3];
        }
        if (oneColor / total >= 0.85 && Math.max(mr, mg, mb) - Math.min(mr, mg, mb) < 0.15)
            return 1;
        for (let step = 1; step < 20; step++) {
            const k = step / 20;
            let standing = 0;
            for (let i = 0; i < px.length; i += 4) {
                const a = px[i + 3];
                const r = (px[i] + (ink.r - px[i]) * k) * a + bg.r * (1 - a);
                const g = (px[i + 1] + (ink.g - px[i + 1]) * k) * a + bg.g * (1 - a);
                const b = (px[i + 2] + (ink.b - px[i + 2]) * k) * a + bg.b * (1 - a);
                if (ColorUtils.contrastOfLuminances(ColorUtils.luminanceOfRgb(r, g, b), lbg) >= 3)
                    standing += a;
            }
            if (standing / total >= 0.6)
                return k;
        }
        return 1;
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

    // Follows the setting, not Appearance.autoIconContrast, which also drops out
    // while a palette settles; the pixels already read are then re-judged.
    readonly property bool sampling: (Config.options?.appearance.autoIconContrast ?? true)
        && !Config.options.tray.monochromeIcons
    // Grabbed from the drawn icon, never re-requested: a canvas request runs on
    // Qt's image reader thread, where QIcon::fromTheme races the bar's own icon
    // loads and corrupts the shell's memory.
    property var grab: null
    // A grab cannot be cancelled, so its callback drops stale generations.
    property int grabGeneration: 0
    property bool grabPending: false
    function capture(retrying) {
        const g = ++grabGeneration;
        if (!retrying)
            captureRetry.left = 20;
        if (!sampling || trayIcon.status === Image.Null || trayIcon.status === Image.Error) {
            grabPending = false;
            grab = null;
            iconPixels = [];
            return;
        }
        // Old pixels stand until the new image is read, so a state change
        // does not flash back to the app's own colors.
        grabPending = true;
        if (trayIcon.status !== Image.Ready || !(root.QsWindow.window?.visible ?? false))
            return;
        const started = trayIcon.grabToImage(result => {
            if (g !== root.grabGeneration)
                return;
            root.grabPending = false;
            root.grab = result;
            iconReader.requestPaint();
        }, Qt.size(24, 24));
        // Refused while the window is not yet shown to the compositor.
        if (!started && captureRetry.left-- > 0)
            captureRetry.restart();
    }
    onSamplingChanged: capture(false)
    Component.onCompleted: capture(false)
    Connections {
        target: trayIcon
        function onStatusChanged() { root.capture(false); }
        function onSourceChanged() { root.capture(false); }
    }
    Connections {
        target: root.QsWindow.window
        function onVisibleChanged() {
            if (root.grabPending)
                root.capture(false);
        }
    }
    Timer {
        id: captureRetry
        property int left: 0
        interval: 250
        onTriggered: root.capture(true)
    }

    // The grab comes from Qt's pixmap store, so this draws it at once with no provider.
    Canvas {
        id: iconReader
        width: 24
        height: 24
        opacity: 0
        onPaint: {
            const shot = root.grab;
            if (!shot)
                return;
            const src = String(shot.url);
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.drawImage(src, 0, 0, width, height);
            root.iconPixels = Array.from(ctx.getImageData(0, 0, width, height).data);
            unloadImage(src);
            root.grab = null;
        }
    }

    Item {
        anchors.fill: parent
        layer.enabled: root.inkShare > 0
        layer.effect: ColorOverlay {
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, root.inkShare)
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
            active: Config.options.tray.monochromeIcons
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
                    color: ColorUtils.transparentize(Appearance.barContent.colOnLayer0, 0.9)
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
