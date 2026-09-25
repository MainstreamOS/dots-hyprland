pragma Singleton
import Quickshell

Singleton {
    id: root

    /**
     * Returns a color with the hue of color2 and the saturation, value, and alpha of color1.
     *
     * @param {string} color1 - The base color (any Qt.color-compatible string).
     * @param {string} color2 - The color to take hue from.
     * @returns {Qt.rgba} The resulting color.
     */
    function colorWithHueOf(color1, color2) {
        var c1 = Qt.color(color1);
        var c2 = Qt.color(color2);

        // Qt.color hsvHue/hsvSaturation/hsvValue/alpha return 0-1
        var hue = c2.hsvHue;
        var sat = c1.hsvSaturation;
        var val = c1.hsvValue;
        var alpha = c1.a;

        return Qt.hsva(hue, sat, val, alpha);
    }

    /**
     * Returns a color with the saturation of color2 and the hue/value/alpha of color1.
     *
     * @param {string} color1 - The base color (any Qt.color-compatible string).
     * @param {string} color2 - The color to take saturation from.
     * @returns {Qt.rgba} The resulting color.
     */
    function colorWithSaturationOf(color1, color2) {
        var c1 = Qt.color(color1);
        var c2 = Qt.color(color2);

        var hue = c1.hsvHue;
        var sat = c2.hsvSaturation;
        var val = c1.hsvValue;
        var alpha = c1.a;

        return Qt.hsva(hue, sat, val, alpha);
    }

    /**
     * Returns a color with the given lightness and the hue, saturation, and alpha of the input color (using HSL).
     *
     * @param {string} color - The base color (any Qt.color-compatible string).
     * @param {number} lightness - The lightness value to use (0-1).
     * @returns {Qt.rgba} The resulting color.
     */
    function colorWithLightness(color, lightness) {
        var c = Qt.color(color);
        return Qt.hsla(c.hslHue, c.hslSaturation, lightness, c.a);
    }

    /**
     * Returns a color with the lightness of color2 and the hue, saturation, and alpha of color1 (using HSL).
     *
     * @param {string} color1 - The base color (any Qt.color-compatible string).
     * @param {string} color2 - The color to take lightness from.
     * @returns {Qt.rgba} The resulting color.
     */
    function colorWithLightnessOf(color1, color2) {
        var c2 = Qt.color(color2);
        return colorWithLightness(color1, c2.hslLightness);
    }

    /**
     * Adapts color1 to the accent (hue and saturation) of color2 using HSL, keeping lightness and alpha from color1.
     *
     * @param {string} color1 - The base color (any Qt.color-compatible string).
     * @param {string} color2 - The accent color.
     * @returns {Qt.rgba} The resulting color.
     */
    function adaptToAccent(color1, color2) {
        var c1 = Qt.color(color1);
        var c2 = Qt.color(color2);

        var hue = c2.hslHue;
        var sat = c2.hslSaturation;
        var light = c1.hslLightness;
        var alpha = c1.a;

        return Qt.hsla(hue, sat, light, alpha);
    }

    /**
     * Mixes two colors by a given percentage.
     *
     * @param {string} color1 - The first color (any Qt.color-compatible string).
     * @param {string} color2 - The second color.
     * @param {number} percentage - The mix ratio (0-1). 1 = all color1, 0 = all color2.
     * @returns {Qt.rgba} The resulting mixed color.
     */
    function mix(color1, color2, percentage = 0.5) {
        var c1 = Qt.color(color1);
        var c2 = Qt.color(color2);
        return Qt.rgba(percentage * c1.r + (1 - percentage) * c2.r, percentage * c1.g + (1 - percentage) * c2.g, percentage * c1.b + (1 - percentage) * c2.b, percentage * c1.a + (1 - percentage) * c2.a);
    }

    /**
     * Transparentizes a color by a given percentage.
     *
     * @param {string} color - The color (any Qt.color-compatible string).
     * @param {number} percentage - The amount to transparentize (0-1).
     * @returns {Qt.rgba} The resulting color.
     */
    function transparentize(color, percentage = 1) {
        var c = Qt.color(color);
        return Qt.rgba(c.r, c.g, c.b, c.a * (1 - percentage));
    }

    /**
     * Sets the alpha channel of a color.
     *
     * @param {string} color - The base color (any Qt.color-compatible string).
     * @param {number} alpha - The desired alpha (0-1).
     * @returns {Qt.rgba} The resulting color with applied alpha.
     */
    function applyAlpha(color, alpha) {
        var c = Qt.color(color);
        var a = Math.max(0, Math.min(1, alpha));
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    /**
     * Returns true if the color is considered "dark" (hslLightness < 0.5).
     *
     * @param {string} color - The color to check (any Qt.color-compatible string).
     * @returns {boolean} True if dark, false otherwise.
     */
    function isDark(color) {
        var c = Qt.color(color);
        return c.hslLightness < 0.5;
    }

    /**
     * Relative luminance as WCAG defines it, from 0 for black to 1 for white.
     *
     * @param {string} color - The color (any Qt.color-compatible string). Alpha is ignored.
     * @returns {number} The luminance (0-1).
     */
    function relativeLuminance(color) {
        const c = Qt.color(color);
        const linear = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b);
    }

    /**
     * WCAG contrast ratio between two opaque colors, from 1 (none) to 21.
     *
     * @param {string} color1 - The first color.
     * @param {string} color2 - The second color.
     * @returns {number} The contrast ratio.
     */
    function contrastRatio(color1, color2) {
        const l1 = relativeLuminance(color1);
        const l2 = relativeLuminance(color2);
        return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
    }

    /**
     * Paints a color over an opaque one, the way the compositor blends them.
     *
     * @param {string} top - The color laid on top; its alpha is how much of it shows.
     * @param {string} bottom - The opaque color underneath.
     * @returns {Qt.rgba} The opaque result.
     */
    function composite(top, bottom) {
        const t = Qt.color(top);
        const b = Qt.color(bottom);
        return Qt.rgba(t.r * t.a + b.r * (1 - t.a), t.g * t.a + b.g * (1 - t.a), t.b * t.a + b.b * (1 - t.a), 1);
    }

    /**
     * The least mix of one color toward another that stands a given contrast
     * off an opaque backdrop. Alpha is mixed along with the rest, so a
     * see-through color firms up only as far as it has to.
     *
     * @param {string} color - The color to start from; its alpha is how much of it shows.
     * @param {string} toward - The color to move toward.
     * @param {string} backdrop - The opaque color both are drawn over.
     * @param {number} ratio - The contrast ratio to reach.
     * @returns {Qt.rgba} The color exactly as given when it already stands that far off, `toward` as given when even that falls short, otherwise the mix.
     */
    function mixForContrast(color, toward, backdrop, ratio) {
        // A hair under the mark, so a color that sits on it and misses only
        // by rounding is left where it is.
        return mixUntil(color, toward, c => contrastRatio(composite(c, backdrop), backdrop) >= ratio - 0.01);
    }

    /**
     * The same for how far apart the two look rather than their contrast, so
     * a color set off its backdrop by hue alone counts for as much as it
     * shows. Contrast ratio sees only luminance, and a pale blue on a pale
     * gray of the same luminance stands no distance off it at all.
     *
     * @param {string} color - The color to start from; its alpha is how much of it shows.
     * @param {string} toward - The color to move toward.
     * @param {string} backdrop - The opaque color both are drawn over.
     * @param {number} distance - The delta E to reach.
     * @returns {Qt.rgba} The color exactly as given when it already stands that far off, `toward` as given when even that falls short, otherwise the mix.
     */
    function mixForDistance(color, toward, backdrop, distance) {
        // A hair under the mark as well, far less than an eye can tell.
        return mixUntil(color, toward, c => deltaE(composite(c, backdrop), backdrop) >= distance - 0.05);
    }

    /**
     * The least mix of one color toward another that passes a test, found by
     * halving: to a 256th of the way, which is under one step of an 8-bit
     * channel.
     *
     * @param {string} color - The color to start from.
     * @param {string} toward - The color to move toward.
     * @param {function} reaches - Whether a color is far enough.
     * @returns {Qt.rgba} The color exactly as given when it passes, `toward` as given when even that fails, otherwise the mix.
     */
    function mixUntil(color, toward, reaches) {
        if (reaches(color))
            return color;
        if (!reaches(toward))
            return toward;
        let low = 0;
        let high = 1;
        for (let i = 0; i < 8; i++) {
            const p = (low + high) / 2;
            if (reaches(mix(toward, color, p)))
                high = p;
            else
                low = p;
        }
        return mix(toward, color, high);
    }

    /**
     * A color in CIE L*a*b*, where equal steps look about equally far apart,
     * whether the step is in lightness or in hue.
     *
     * @param {string} color - The color (any Qt.color-compatible string). Alpha is ignored.
     * @returns {Array<number>} L*, a* and b* under the sRGB (D65) white.
     */
    function lab(color) {
        const c = Qt.color(color);
        const linear = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        const r = linear(c.r), g = linear(c.g), b = linear(c.b);
        const f = t => t > 216 / 24389 ? Math.cbrt(t) : (24389 / 27 * t + 16) / 116;
        const x = f((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047);
        const y = f(0.2126 * r + 0.7152 * g + 0.0722 * b);
        const z = f((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883);
        return [116 * y - 16, 500 * (x - y), 200 * (y - z)];
    }

    /**
     * How far apart two opaque colors look (CIE76 delta E). About 2.3 is the
     * least most people can tell apart side by side.
     *
     * @param {string} color1 - The first color.
     * @param {string} color2 - The second color.
     * @returns {number} The distance, from 0 for the same color.
     */
    function deltaE(color1, color2) {
        const a = lab(color1);
        const b = lab(color2);
        return Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
    }

    /**
     * The same hue, saturation and alpha at the opposite lightness (using HSL),
     * so light content turns into dark content that keeps its accent.
     *
     * @param {string} color - The color (any Qt.color-compatible string).
     * @returns {Qt.rgba} The mirrored color.
     */
    function mirrorLightness(color) {
        const c = Qt.color(color);
        return Qt.hsla(c.hslHue, c.hslSaturation, 1 - c.hslLightness, c.a);
    }

    /**
     * Clamps a value to the inclusive range [0, 1].
     *
     * @param {number} x - The value to clamp.
     * @returns {number} The clamped value in the range [0, 1].
     */
    function clamp01(x) {
        return Math.min(1, Math.max(0, x));
    }

    /**
     * Solves for the solid overlay color that, when composited over a base color
     * with a given opacity, yields the target color.
     *
     * The compositing equation is:
     *   result = overlay * overlayOpacity + base * (1 - overlayOpacity)
     *
     * This function algebraically inverts that equation per channel.
     *
     * @param {Qt.rgba} baseColor - The base (background) color.
     * @param {Qt.rgba} targetColor - The resulting color after compositing.
     * @param {number} overlayOpacity - The overlay opacity (0-1).
     * @returns {Qt.rgba} The solved overlay color
     */
    function solveOverlayColor(baseColor, targetColor, overlayOpacity) {
        const bc = Qt.color(baseColor);
        const tc = Qt.color(targetColor);
        let invA = 1.0 - overlayOpacity;

        let r = (tc.r - bc.r * invA) / overlayOpacity;
        let g = (tc.g - bc.g * invA) / overlayOpacity;
        let b = (tc.b - bc.b * invA) / overlayOpacity;

        return Qt.rgba(clamp01(r), clamp01(g), clamp01(b), overlayOpacity);
    }
}
