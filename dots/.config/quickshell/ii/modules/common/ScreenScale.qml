pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * ScreenScale — the scale the compositor actually draws each monitor at.
 *
 * Qt is not the one to ask. A window on a screen set to 150% is told its
 * device pixel ratio is 2: Hyprland asks the client for a whole-number
 * surface and resamples the result down itself, so nothing inside the
 * process can tell 150% from 200%. Hyprland knows, and answers here.
 *
 * The answer arrives a moment after a process starts rather than with it,
 * so callers get 0 until then and should say what they want in the
 * meantime rather than assume one to one.
 */
Singleton {
    id: root

    // Monitor name to the scale Hyprland draws it at.
    readonly property var byName: {
        const out = ({});
        const monitors = Hyprland.monitors;
        if (monitors)
            for (const monitor of monitors.values)
                out[monitor.name] = monitor.scale;
        return out;
    }

    // 0 while the compositor has not answered yet, which is a different thing
    // from a scale of 1 and worth telling apart.
    function scaleOf(screenName) {
        return root.byName[screenName] ?? 0;
    }

    // Above this, text is display sized rather than interface sized: the clock
    // on the desktop, the one on the lock screen, the temperature. Everything
    // the interface itself is set in sits between 10 and 23.
    readonly property int displaySize: 40

    // How text of that size on that screen should be drawn.
    //
    // Hinting a glyph onto a whole pixel grid is the sharper choice when the
    // screen is drawn at a whole number, and the wrong one when the compositor
    // resamples the result to a fraction: the hinted stems land between pixels
    // and letters built from straight strokes come out chewed. Distance-field
    // glyphs carry no grid, so they are also the safer answer before the scale
    // is known.
    //
    // That holds at interface sizes. Big text reverses it. Qt rasterizes its
    // distance-field atlas once at a fixed size near 54 px and magnifies that
    // one rasterization for anything larger, so a clock set at 90, or at the
    // 700 the slider allows, is a tenfold enlargement of a small picture and
    // its strokes bloom and its corners round off. Drawn at its real size
    // instead it is sharp, and the grid hinting that chews a 14 px label is
    // invisible on a glyph this big.
    function renderTypeFor(screenName, pixelSize) {
        if (pixelSize !== undefined && pixelSize > root.displaySize)
            return Text.NativeRendering;
        const scale = root.scaleOf(screenName);
        return (scale > 0 && scale % 1 === 0) ? Text.NativeRendering : Text.QtRendering;
    }
}
