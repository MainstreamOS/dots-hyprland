pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common

/**
 * Solid, Frost and Glass for the bar and dock, which take a preset together.
 * Solid is the shipped look. What a preset sets stays free to change after.
 */
Singleton {
    id: root

    readonly property var shipped: [
        { displayName: Translation.tr("Solid"), enable: false, opacity: -1, blur: 24, haze: 0, magnification: 1, offsetX: 0, offsetY: 0 },
        { displayName: Translation.tr("Frost"), enable: true, opacity: 0.4, blur: 56, haze: 0.16, magnification: 1, offsetX: 0, offsetY: 0 },
        { displayName: Translation.tr("Glass"), enable: true, opacity: 0.55, blur: 4, haze: 0.076, magnification: 1.254, offsetX: 200, offsetY: 7 },
    ]
    readonly property var all: root.shipped.concat(Array.from(Config.options.appearance.backdropPresets))

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
