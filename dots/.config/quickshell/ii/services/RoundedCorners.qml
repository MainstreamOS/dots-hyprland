pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.models.hyprland
import QtQuick
import Quickshell

/**
 * What the Rounded Corners switch does to the bar and the screen corners, for
 * Settings > Decorations and the Welcome windows card alike, so the two cannot
 * drift apart. What it turns back on to is kept in
 * appearance.roundCornersRestore rather than on a page, since Settings and
 * Welcome are separate processes and Settings rebuilds its pages on every
 * page switch and color change. The window rounding itself is written by the
 * caller through decorations.py.
 */
Singleton {
    id: root

    // The bar each dock style is paired with on the Welcome style tiles, for
    // corners turned on with nothing remembered: the Hug dock ("span") only
    // curves beside a bar that is not Rect.
    readonly property var barForDock: ({ span: 0, hug: 3, float: 1 })
    // Config.qml's shipped bar.cornerStyle and appearance.fakeScreenRounding.
    readonly property int stockBarStyle: 1
    readonly property int stockScreenRounding: 2

    // Whether the corners are on, for the shell's own panels to follow, such
    // as the sidebars. Read from the window rounding, as the switch itself
    // is, so corners squared by a theme or by the Decorations page count the
    // same as the switch. On until Hyprland answers.
    readonly property bool on: (windowRounding.value ?? 1) > 0
    HyprlandConfigOption {
        id: windowRounding
        key: "decoration:rounding"
    }

    function inRange(v, lo, hi) {
        return Number.isInteger(v) && v >= lo && v <= hi;
    }

    // The look turnOff leaves behind, still in place with its memory kept:
    // what a page that last read the corners as on may be looking at now.
    function remembersOff() {
        return Config.options.bar.cornerStyle === 2 && Config.options.appearance.fakeScreenRounding === 0
            && root.inRange(Config.options.appearance.roundCornersRestore.windowRounding, 1, 24);
    }

    // `radius` is the window rounding being switched off. What is already
    // square is not remembered over what came before it, so a switch still
    // showing on in the other process cannot record the squared look. A Rect
    // bar is only ever remembered as a pick (see pickBarStyle): one nobody
    // picked was left square by the corners themselves, so turnOn pairs the
    // bar with the dock instead of keeping it square.
    function turnOff(radius) {
        const bar = Config.options.bar;
        const look = Config.options.appearance;
        const memory = look.roundCornersRestore;
        const squared = bar.cornerStyle === 2 && look.fakeScreenRounding === 0;
        if (bar.cornerStyle !== 2)
            memory.barCornerStyle = bar.cornerStyle;
        if (look.fakeScreenRounding !== 0 || !root.inRange(memory.fakeScreenRounding, 0, 2))
            memory.fakeScreenRounding = look.fakeScreenRounding;
        if (root.inRange(radius, 1, 24) && (!squared || !root.inRange(memory.windowRounding, 1, 24)))
            memory.windowRounding = radius;
        bar.cornerStyle = 2;
        look.fakeScreenRounding = 0;
    }

    // Puts back only what still holds what turnOff set, so a style picked
    // while the corners were off stays. Returns the window radius to write,
    // or -1 when the corners were already on with nothing remembered: they
    // were turned on elsewhere, and the radius in place is the one to keep.
    function turnOn(fallbackRadius) {
        const bar = Config.options.bar;
        const look = Config.options.appearance;
        const memory = look.roundCornersRestore;
        const alreadyOn = bar.cornerStyle !== 2 && look.fakeScreenRounding !== 0;
        if (bar.cornerStyle === 2)
            bar.cornerStyle = root.inRange(memory.barCornerStyle, 0, 3) ? memory.barCornerStyle
                : (root.barForDock[Config.options.dock.cornerStyle] ?? root.stockBarStyle);
        // Screen corners that were already off come back as they ship.
        if (look.fakeScreenRounding === 0)
            look.fakeScreenRounding = root.inRange(memory.fakeScreenRounding, 1, 2)
                ? memory.fakeScreenRounding : root.stockScreenRounding;
        const radius = root.inRange(memory.windowRounding, 1, 24) ? memory.windowRounding
            : (alreadyOn ? -1 : fallbackRadius);
        // Written out rather than removed: the adapter keeps a value whose key
        // the file stops naming.
        memory.barCornerStyle = -1;
        memory.fakeScreenRounding = -1;
        memory.windowRounding = -1;
        return radius;
    }

    // Every bar style picker goes through here. Keeping the pick in the memory
    // lets turnOn keep a Rect chosen while the corners were off, which it
    // could not otherwise tell apart from the Rect turnOff set.
    function pickBarStyle(v) {
        Config.options.bar.cornerStyle = v;
        Config.options.appearance.roundCornersRestore.barCornerStyle = v;
    }
}
