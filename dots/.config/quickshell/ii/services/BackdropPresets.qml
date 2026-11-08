pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions

/**
 * Solid, Frost and Glass for the bar and dock, which take a preset together.
 * Solid is the shipped look. What a preset sets stays free to change after.
 */
Singleton {
    id: root

    readonly property var shipped: [
        { displayName: Translation.tr("Solid"), enable: false, opacity: -1, blur: 24, haze: 0, magnification: 1, offsetX: 0, offsetY: 0 },
        { displayName: Translation.tr("Frost"), enable: true, opacity: 0.4, blur: 56, haze: 0.16, magnification: 1, offsetX: 0, offsetY: 0 },
        { displayName: Translation.tr("Glass"), enable: true, opacity: 0.55, blur: 4, haze: 0.076, magnification: 1, offsetX: 0, offsetY: 0 },
    ]
    readonly property var all: root.shipped.concat(Array.from(Config.options.appearance.backdropPresets))
    readonly property bool dockIsFrost: root.indexFor(Config.options.dock) === 1
    // The preset look behind the desktop widgets: Frost, Glass, or whatever the dock has.
    // Null for Solid and the plain blur, and for a dock on Solid, which has none to follow.
    readonly property var widgetLook: {
        const style = Config.options.background.widgets.blur.style;
        if (style === "frost") return root.shipped[1];
        if (style === "glass") return root.shipped[2];
        return style === "follow" && Config.options.dock.backdrop.enable ? Config.options.dock.backdrop : null;
    }
    readonly property bool widgetBlurred: root.widgetLook !== null || Config.options.background.widgets.blur.style === "blur"
    // One tint for every card. The plain blur keeps the card's own color. A preset's haze lifts
    // the card toward its text, so there the theme's background firms up only as far as the text needs.
    readonly property color widgetTint: {
        const look = root.widgetLook;
        if (!look) {
            const layer = Appearance.colors.colLayer1;
            return ColorUtils.applyAlpha(layer, layer.a * 0.55);
        }
        const base = Appearance.m3colors.m3background;
        for (let opacity = 0.55; opacity < 0.85; opacity += 0.05) {
            const tint = Appearance.hazed(base, opacity, look.haze);
            if (ColorUtils.contrastRatio(Appearance.colors.colOnLayer1, ColorUtils.composite(tint, Appearance.wallpaperAverage)) >= 3)
                return tint;
        }
        return Appearance.hazed(base, 0.85, look.haze);
    }
    readonly property bool dockIsGlass: root.indexFor(Config.options.dock) === 2

    // The same three for windows. The opacity comes with them, since blur only shows
    // through a see-through window. The focused window stays opaque in every one,
    // and Solid is the shipped look here too.
    readonly property var windowShipped: [
        { displayName: Translation.tr("Solid"), blur: true, blurVariant: 0, blurSize: 10, blurPasses: 3, blurNoise: 0, blurVibrancy: 0.5,
            blurLensStrength: 24, blurLensWidth: 48, blurClarity: 0.82, activeOpacity: 1, inactiveOpacity: 1 },
        { displayName: Translation.tr("Frost"), blur: true, blurVariant: 1, blurSize: 12, blurPasses: 3, blurNoise: 0.03,
            blurVibrancy: 0.5, activeOpacity: 1, inactiveOpacity: 0.89 },
        { displayName: Translation.tr("Glass"), blur: true, blurVariant: 8, blurSize: 4, blurPasses: 2, blurNoise: 0,
            blurVibrancy: 0.8, blurLensStrength: 32, blurLensWidth: 96, blurClarity: 0.6, activeOpacity: 1, inactiveOpacity: 0.93 },
    ]

    // Which preset a surface's settings amount to, or -1 once they match none.
    function indexFor(surface) {
        const b = surface.backdrop;
        const near = (one, other) => Math.abs(one - other) < 0.01;
        return root.all.findIndex(p => p.enable === b.enable && near(p.opacity, surface.backgroundOpacity)
            && (!p.enable || (near(p.blur, b.blur) && near(p.haze, b.haze) && near(p.magnification, b.magnification)
                && near(p.offsetX, b.offsetX) && near(p.offsetY, b.offsetY))));
    }

    function apply(preset) {
        for (const surface of [Config.options.bar, Config.options.dock]) {
            const b = surface.backdrop;
            b.enable = preset.enable;
            b.blur = preset.blur;
            b.haze = preset.haze;
            b.magnification = preset.magnification;
            b.offsetX = preset.offsetX;
            b.offsetY = preset.offsetY;
            surface.backgroundOpacity = preset.opacity;
            surface.showBackground = true;
        }
    }

    function save(name, surface) {
        const b = surface.backdrop;
        Config.options.appearance.backdropPresets = Array.from(Config.options.appearance.backdropPresets)
            .filter(preset => preset.displayName !== name)
            .concat([{ displayName: name, enable: b.enable, opacity: surface.backgroundOpacity, blur: b.blur,
                haze: b.haze, magnification: b.magnification, offsetX: b.offsetX, offsetY: b.offsetY }]);
    }

    function remove(name) {
        Config.options.appearance.backdropPresets = Array.from(Config.options.appearance.backdropPresets)
            .filter(preset => preset.displayName !== name);
    }
}
