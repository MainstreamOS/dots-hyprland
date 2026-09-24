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
    // An icon with nothing of its own standing off the surface, the way a
    // plain white glyph vanishes into a light group, is drawn inverted. One
    // with something to hold on to, an outline or a color of its own, is left
    // as the app drew it.
    readonly property bool iconLost: {
        if (!Appearance.autoIconContrast || iconPixels.length === 0)
            return false;
        const bg = Qt.color(root.backdrop);
        const linear = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        const luminance = (r, g, b) => 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
        const lbg = luminance(bg.r, bg.g, bg.b);
        let total = 0;
        let standing = 0;
        for (let i = 0; i < iconPixels.length; i += 4) {
            const a = iconPixels[i + 3] / 255;
            if (a < 0.1)
                continue;
            const r = iconPixels[i] / 255 * a + bg.r * (1 - a);
            const g = iconPixels[i + 1] / 255 * a + bg.g * (1 - a);
            const b = iconPixels[i + 2] / 255 * a + bg.b * (1 - a);
            const l = luminance(r, g, b);
            total += a;
            // A pixel counts if it is lighter or darker enough to see, or a
            // color far enough from the surface to see at the same lightness.
            if ((Math.max(l, lbg) + 0.05) / (Math.min(l, lbg) + 0.05) >= 1.5
                    || Math.hypot(r - bg.r, g - bg.g, b - bg.b) >= 0.35)
                standing += a;
        }
        return total > 0 && standing / total < 0.1;
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

    // Reads the icon small and out of sight. A new image from the app, such
    // as a badge appearing, is read again.
    Canvas {
        id: iconReader
        width: 24
        height: 24
        opacity: 0
        readonly property string source: root.item?.icon ?? ""
        property string reading: ""
        function read() {
            if (reading !== "")
                unloadImage(reading);
            reading = source;
            if (reading === "")
                root.iconPixels = [];
            else if (isImageLoaded(reading))
                requestPaint();
            else
                loadImage(reading);
        }
        onSourceChanged: read()
        Component.onCompleted: read()
        onImageLoaded: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (reading === "" || !isImageLoaded(reading))
                return;
            ctx.drawImage(reading, 0, 0, width, height);
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
