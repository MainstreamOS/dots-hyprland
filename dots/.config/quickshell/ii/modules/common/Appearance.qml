import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.functions
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property QtObject m3colors
    property QtObject animation
    property QtObject animationCurves
    property QtObject colors
    property QtObject rounding
    property QtObject font
    property QtObject sizes
    property string syntaxHighlightingTheme
    property int themeRevision: 0

    // Transparency. The quadratic functions were derived from analysis of hand-picked transparency values.
    ColorQuantizer {
        id: wallColorQuant
        property string wallpaperPath: Config.options.background.wallpaperPath
        property bool wallpaperIsVideo: wallpaperPath.endsWith(".mp4") || wallpaperPath.endsWith(".webm") || wallpaperPath.endsWith(".mkv") || wallpaperPath.endsWith(".avi") || wallpaperPath.endsWith(".mov")
        source: Qt.resolvedUrl(wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath)
        depth: 0 // 2^0 = 1 color
        rescaleSize: 10
    }
    property real wallpaperVibrancy: (wallColorQuant.colors[0]?.hslSaturation + wallColorQuant.colors[0]?.hslLightness) / 2
    // The same for both modes: a light surface that can never be seen through
    // reads as harsh beside a dark one that always can.
    property real autoBackgroundTransparency: { // y = 0.5768x^2 - 0.759x + 0.2896
        let x = wallpaperVibrancy
        let y = 0.5768 * (x * x) - 0.759 * (x) + 0.2896
        return Math.max(0, Math.min(0.22, y))
    }
    property real autoContentTransparency: 0.9
    property real backgroundTransparency: Config?.options.appearance.transparency.enable ? Config?.options.appearance.transparency.automatic ? autoBackgroundTransparency : Config?.options.appearance.transparency.backgroundTransparency : 0
    property real contentTransparency: Config?.options.appearance.transparency.automatic ? autoContentTransparency : Config?.options.appearance.transparency.contentTransparency

    // What the bar and the dock are laid over, read along each screen edge
    // rather than across the whole picture: a bright sky over a dark
    // landscape averages out dark, and the sky is what a see-through strip
    // across the top actually shows. The average stands in until it is read.
    property var wallpaperEdges: ({})
    readonly property color wallpaperAverage: wallColorQuant.colors[0] ?? m3colors.m3background
    function wallpaperEdge(edge) {
        const read = wallpaperEdges[edge]
        return read !== undefined ? read : wallpaperAverage
    }
    readonly property string wallpaperFile: FileUtils.trimFileProtocol(wallColorQuant.wallpaperIsVideo
        ? Config.options.background.thumbnailPath : wallColorQuant.wallpaperPath)
    onWallpaperFileChanged: wallEdgeDebounce.restart()
    Timer {
        id: wallEdgeDebounce
        interval: 300
        onTriggered: {
            if (root.wallpaperFile === "") {
                root.wallpaperEdges = ({})
                return
            }
            wallEdgeSampler.exec({ command: ["magick", "-define", "jpeg:size=256x144", root.wallpaperFile,
                "-delete", "1--1", "-thumbnail", "64x36!",
                "(", "-clone", "0", "-gravity", "north", "-crop", "64x3+0+0", "+repage", "-scale", "1x1!", ")",
                "(", "-clone", "0", "-gravity", "south", "-crop", "64x3+0+0", "+repage", "-scale", "1x1!", ")",
                "(", "-clone", "0", "-gravity", "west", "-crop", "4x36+0+0", "+repage", "-scale", "1x1!", ")",
                "(", "-clone", "0", "-gravity", "east", "-crop", "4x36+0+0", "+repage", "-scale", "1x1!", ")",
                "-delete", "0", "-format", "%[hex:p{0,0}]\\n", "info:"] })
        }
    }
    Process {
        id: wallEdgeSampler
        stdout: StdioCollector {
            onStreamFinished: {
                const hex = text.trim().split("\n").map(line => line.trim().slice(0, 6))
                // Kept until the new picture is read, so a change of wallpaper
                // does not pass through the average on its way and turn the
                // icons twice.
                root.wallpaperEdges = hex.length === 4 && hex.every(h => /^[0-9a-fA-F]{6}$/.test(h))
                    ? { top: "#" + hex[0], bottom: "#" + hex[1], left: "#" + hex[2], right: "#" + hex[3] }
                    : ({})
            }
        }
    }

    // Which way the content on a surface is drawn. The surface is judged as it
    // actually shows, see-through parts and all, and as it would show either
    // way, since some of it turns with the content. The palette's tones are
    // kept while they read, and otherwise unless the opposite ones read
    // clearly better against every part.
    readonly property bool autoIconContrast: Config.options?.appearance.autoIconContrast ?? true
    function worstContrast(ink, places) {
        return Math.min(...places.map(bg => ColorUtils.contrastRatio(ink, bg)))
    }
    function contentFlipped(places, turnedPlaces) {
        if (!autoIconContrast)
            return false
        const own = worstContrast(m3colors.m3onSurface, places)
        return own < 4.5 && worstContrast(ColorUtils.mirrorLightness(m3colors.m3onSurface), turnedPlaces) > own * 1.25
    }
    // A color someone picked in a middle tone leaves both of the palette's
    // inks short, and there the inks are carried to white or black anyway, so
    // the side whose far end reads better is the one to take.
    function extremeFlipped(places) {
        if (!autoIconContrast)
            return false
        const own = worstContrast(m3colors.darkmode ? "white" : "black", places)
        return own < 4.5 && worstContrast(m3colors.darkmode ? "black" : "white", places) > own
    }
    function laidOver(surface, edge, shown) {
        return shown ? ColorUtils.composite(surface, wallpaperEdge(edge)) : wallpaperEdge(edge)
    }
    readonly property color barBackdrop: laidOver(colors.colBarBackground, sizes.barEdge, Config.options?.bar.showBackground)
    readonly property color dockBackdrop: laidOver(colors.colDockBackground, sizes.dockEdge,
        Config.options?.dock.showBackground)
    // The same edges under the strip and the dock as they come. The palette's
    // inks were chosen to stand off these, so a surface the user has colored
    // is held to what they show here, and the stock one is left exactly as is.
    readonly property color barStockBackdrop: laidOver(ColorUtils.applyAlpha(colors.colLayer0, colors.barStockAlpha),
        sizes.barEdge, Config.options?.bar.showBackground)
    readonly property color dockStockBackdrop: laidOver(ColorUtils.applyAlpha(colors.colLayer0, colors.dockStockAlpha),
        sizes.dockEdge, Config.options?.dock.showBackground)
    // The bar and the dock read as one set, so while the dock is there it
    // decides which way the content on both is drawn: the bar's strip and the
    // groups in the palette's own color follow it. A group someone picked a
    // color for is a surface of its own and is judged by itself, so a pill
    // set light on a dark strip gets dark icons however dark the strip is.
    // Line-separated groups have no pill, and sit on the strip like the rest.
    readonly property bool dockLeads: Config.options?.dock.enable ?? true
    // Only while the dock's side still reads on the bar about as well as the
    // other side would: a dock set near black beside a stock light bar would
    // otherwise hand the bar light icons it could not show.
    function followsDock(places) {
        if (!dockLeads)
            return false
        const dockSide = worstContrast(dockContent.darkmode ? "white" : "black", places)
        const otherSide = worstContrast(dockContent.darkmode ? "black" : "white", places)
        return dockSide >= 3 && dockSide * 1.5 >= otherSide
    }
    function barPillPlaces(strip, pill, turned) {
        if (Config.options?.bar.borderless)
            return [strip]
        return [ColorUtils.composite(turned ? ColorUtils.mirrorLightness(pill) : pill, strip)]
    }
    // Only a palette pill given an opacity of its own turns: the stock one is
    // a faint tint that turning would only lose against the strip.
    readonly property bool barPillTurns: colors.barWidgetPick === "" && (Config.options?.bar.widgetOpacity ?? -1) >= 0
    readonly property var barPillAsIs: barPillPlaces(barBackdrop, colors.colBarWidget, false)
    // And only when its content does not read on it as it is and turning it
    // helps. A see-through pill turned for nothing sinks into the strip it
    // was drawn to stand from.
    readonly property bool barPillTurned: {
        if (!barPillTurns || !barContent.flipped)
            return false
        const ink = ColorUtils.mirrorLightness(m3colors.m3onSurface)
        const asIs = worstContrast(ink, barPillAsIs)
        return asIs < 4.5 && worstContrast(ink, barPillPlaces(barBackdrop, colors.colBarWidget, true)) > asIs
    }
    // The groups the dock's side would be drawn on: turned, when they can turn
    // and the dock's content is turned.
    readonly property var barPillForDock: barPillPlaces(barBackdrop, colors.colBarWidget, barPillTurns && dockContent.flipped)
    readonly property color barStockPill: ColorUtils.applyAlpha(colors.colLayer1, colors.barWidgetStockAlpha)
    readonly property var barStockPillPlaces: barPillPlaces(barStockBackdrop, barStockPill, false)
    // The widget groups as drawn.
    readonly property color colBarPill: barPillTurned ? ColorUtils.mirrorLightness(colors.colBarWidget) : colors.colBarWidget
    readonly property SurfaceContent barContent: SurfaceContent {
        m3: root.m3colors
        palette: root.colors
        backdrops: root.barPillPlaces(root.barBackdrop, root.colors.colBarWidget, root.barPillTurned)
        stockBackdrops: root.barStockPillPlaces
        adaptive: root.autoIconContrast
        flipped: root.colors.barWidgetPick !== "" && !Config.options?.bar.borderless
            ? root.contentFlipped(root.barPillAsIs, root.barPillAsIs) || root.extremeFlipped(root.barPillAsIs)
            : root.followsDock(root.barPillForDock) ? root.dockContent.flipped
            : root.contentFlipped(root.barPillAsIs, root.barPillPlaces(root.barBackdrop, root.colors.colBarWidget, root.barPillTurns))
        // Judged on this surface's own stock places, which are what its stock
        // tokens are measured against, whatever the dock decided.
        stockFlipped: root.contentFlipped(root.barStockPillPlaces, root.barStockPillPlaces)
    }
    readonly property SurfaceContent barStripContent: SurfaceContent {
        m3: root.m3colors
        palette: root.colors
        backdrops: [root.barBackdrop]
        stockBackdrops: [root.barStockBackdrop]
        adaptive: root.autoIconContrast
        flipped: root.followsDock(backdrops) ? root.dockContent.flipped : root.contentFlipped(backdrops, backdrops)
        stockFlipped: root.contentFlipped(stockBackdrops, stockBackdrops)
    }
    readonly property SurfaceContent dockContent: SurfaceContent {
        m3: root.m3colors
        palette: root.colors
        backdrops: [root.dockBackdrop]
        stockBackdrops: [root.dockStockBackdrop]
        adaptive: root.autoIconContrast
        flipped: root.contentFlipped(backdrops, backdrops)
        stockFlipped: root.contentFlipped(stockBackdrops, stockBackdrops)
    }

    // The colors content is drawn in on a surface that can be turned the other
    // way, under the names colors and m3colors already give them, so a widget
    // moves onto one by changing a prefix. Turned, every tone keeps its hue
    // and takes the opposite lightness, so the accent comes across with it
    // rather than falling back to gray.
    component SurfaceContent: QtObject {
        property var m3
        property var palette
        // Off, every token is the palette's own, untouched by the surface.
        property bool adaptive: true
        property bool flipped: false
        // The opaque colors the content is laid on, the one most of it sits
        // on first, and the same places on the stock surfaces, index for
        // index, with which way the content would be drawn there.
        property var backdrops: ["black"]
        property var stockBackdrops: ["black"]
        property bool stockFlipped: false
        readonly property real textContrast: 4.5
        readonly property real markContrast: 3
        // Whether the content reads as it does in dark mode, for the places
        // that choose between two tokens by mode.
        readonly property bool darkmode: m3.darkmode !== flipped
        function tone(c) { return flipped ? ColorUtils.mirrorLightness(c) : c }
        function standing(c, backdrop) { return ColorUtils.contrastRatio(ColorUtils.composite(c, backdrop), backdrop) }
        function onStock(c) { return stockFlipped ? ColorUtils.mirrorLightness(c) : c }
        // One of the palette's own colors, from where it starts, carried toward
        // another until it stands off each place (the first, or every one) as
        // far as the stock surface shows it there, up to `most`. The palette
        // dims against its own surface, and a lightened or darkened one can
        // swallow what it dimmed; on the stock surface nothing has to move.
        function held(c, start, toward, most, everywhere) {
            if (!adaptive)
                return c
            let out = start
            for (let i = 0; i < (everywhere ? backdrops.length : 1); ++i)
                out = ColorUtils.mixForContrast(out, toward, backdrops[i], Math.min(most, standing(onStock(c), stockBackdrops[i])))
            return out
        }
        // The palette places its faint marks and fills a set way from its own
        // surface toward the ink. Turning them the way the ink turns only holds
        // on the palette's own surfaces: on a mid-tone one a separator mirrored
        // from light to dark ends up on the far side of the surface from icons
        // mirrored from dark to light. So each keeps the share of the way from
        // surface to ink it has on the stock surface, measured in lightness,
        // and is set that far across the surface as it is now.
        function across(c, full, paletteFull) {
            if (!adaptive)
                return c
            if (flipped === stockFlipped && Qt.colorEqual(backdrops[0], stockBackdrops[0]))
                return tone(c)
            const from = Qt.color(stockBackdrops[0]).hslLightness
            const span = Qt.color(onStock(paletteFull)).hslLightness - from
            // A share far outside the span means surface and ink sit too close
            // to measure it by, so the mark stays where the palette put it.
            const share = Math.abs(span) < 0.01 ? 1 : (Qt.color(onStock(c)).hslLightness - from) / span
            if (share < -1 || share > 2)
                return tone(c)
            const here = Qt.color(backdrops[0]).hslLightness
            const start = Qt.color(tone(c))
            const lightness = ColorUtils.clamp01(here + share * (Qt.color(full).hslLightness - here))
            // Kept as colorful as it was rather than as saturated: the same HSL
            // saturation at a middle lightness is several times the color, and
            // a pale tint moved there would turn vivid.
            const room = l => 1 - Math.abs(2 * l - 1)
            const chroma = start.hslSaturation * room(start.hslLightness)
            return Qt.hsla(start.hslHue, room(lightness) > 0 ? Math.min(1, chroma / room(lightness)) : 0, lightness, start.a)
        }
        // Text drawn on one of the fills rather than on the surface, held
        // against that fill up to text contrast, or to what the pair has on
        // the stock surface where that is less. A middle-toned fill can leave
        // the text's own side short, and then it crosses to the side that reads.
        function onFill(c, fill, paletteFill) {
            const start = across(c, m3onSurface, m3.m3onSurface)
            if (!adaptive)
                return start
            const under = ColorUtils.composite(fill, backdrops[0])
            const need = Math.min(textContrast, ColorUtils.contrastRatio(onStock(c), onStock(paletteFill)))
            const lighter = ColorUtils.relativeLuminance(start) > ColorUtils.relativeLuminance(under)
            const own = lighter ? "white" : "black"
            const other = lighter ? "black" : "white"
            const ownReach = ColorUtils.contrastRatio(own, under)
            const toward = ownReach >= need || ownReach >= ColorUtils.contrastRatio(other, under) ? own : other
            return ColorUtils.mixForContrast(start, toward, under, need)
        }
        // Text and icons, wherever the content sits.
        function ink(c) { return held(c, tone(c), darkmode ? "white" : "black", textContrast, true) }
        // The accent only has to stand out as a mark.
        function accent(c) { return held(c, tone(c), darkmode ? "white" : "black", markContrast, false) }
        // A dimmed ink moves toward the ink it was dimmed from and stops at
        // four fifths of that ink's contrast, so it still reads as the fainter.
        function dim(c, full, paletteFull) {
            return held(c, across(c, full, paletteFull), full,
                Math.min(markContrast, standing(full, backdrops[0]) / 1.25), false)
        }
        // A see-through wash of one of these colors, made less see-through the
        // same way when the surface would swallow it.
        function faded(c, opacity) {
            const wash = ColorUtils.transparentize(c, 1 - opacity)
            if (!adaptive)
                return wash
            const stock = stockFlipped === flipped ? wash : ColorUtils.mirrorLightness(wash)
            return ColorUtils.mixForContrast(wash, c, backdrops[0], Math.min(markContrast,
                standing(c, backdrops[0]) / 1.25, standing(stock, stockBackdrops[0])))
        }
        readonly property color colOnLayer0: ink(palette.colOnLayer0)
        readonly property color colOnLayer1: ink(palette.colOnLayer1)
        readonly property color colOnLayer1Inactive: dim(palette.colOnLayer1Inactive, colOnLayer1, palette.colOnLayer1)
        readonly property color colOnLayer2: ink(palette.colOnLayer2)
        readonly property color colOnSurfaceVariant: ink(palette.colOnSurfaceVariant)
        readonly property color colSubtext: dim(palette.colSubtext, colOnLayer0, palette.colOnLayer0)
        readonly property color colPrimary: accent(palette.colPrimary)
        // Rebuilt the palette's way once the accent has had to move, so a
        // hovered or pressed accent does not fall back to the faint one.
        readonly property color colPrimaryHover: Qt.colorEqual(colPrimary, tone(palette.colPrimary))
            ? tone(palette.colPrimaryHover) : ColorUtils.mix(colPrimary, colLayer1Hover, 0.87)
        readonly property color colPrimaryActive: Qt.colorEqual(colPrimary, tone(palette.colPrimary))
            ? tone(palette.colPrimaryActive) : ColorUtils.mix(colPrimary, colLayer1Active, 0.7)
        readonly property color colOnPrimary: tone(palette.colOnPrimary)
        readonly property color colTertiary: tone(palette.colTertiary)
        readonly property color colError: tone(palette.colError)
        readonly property color colSecondaryContainer: across(palette.colSecondaryContainer, m3onSurface, m3.m3onSurface)
        readonly property color colSecondaryContainerHover: across(palette.colSecondaryContainerHover, m3onSurface, m3.m3onSurface)
        readonly property color colSecondaryContainerActive: across(palette.colSecondaryContainerActive, m3onSurface, m3.m3onSurface)
        readonly property color colOnSecondaryContainer: onFill(palette.colOnSecondaryContainer, colSecondaryContainer, palette.colSecondaryContainer)
        readonly property color colLayer0: across(palette.colLayer0, colOnLayer0, palette.colOnLayer0)
        readonly property color colLayer0Border: dim(palette.colLayer0Border, colOnLayer0, palette.colOnLayer0)
        readonly property color colLayer1: across(palette.colLayer1, colOnLayer1, palette.colOnLayer1)
        readonly property color colLayer1Hover: across(palette.colLayer1Hover, colOnLayer1, palette.colOnLayer1)
        readonly property color colLayer1Active: across(palette.colLayer1Active, colOnLayer1, palette.colOnLayer1)
        readonly property color colOutlineVariant: dim(palette.colOutlineVariant, colOnLayer0, palette.colOnLayer0)
        readonly property color m3onSurface: ink(m3.m3onSurface)
        readonly property color m3onSurfaceVariant: ink(m3.m3onSurfaceVariant)
        // The palette's subtext is this very color, so the two are held as one.
        readonly property color m3outline: colSubtext
        readonly property color m3primary: accent(m3.m3primary)
        readonly property color m3onPrimary: tone(m3.m3onPrimary)
        readonly property color m3secondaryContainer: across(m3.m3secondaryContainer, m3onSurface, m3.m3onSurface)
        readonly property color m3onSecondaryContainer: onFill(m3.m3onSecondaryContainer, m3secondaryContainer, m3.m3secondaryContainer)
        readonly property color m3error: tone(m3.m3error)
    }

    m3colors: QtObject {
        property bool darkmode: true
        property bool transparent: false
        property color m3background: "#141313"
        property color m3onBackground: "#e6e1e1"
        property color m3surface: "#141313"
        property color m3surfaceDim: "#141313"
        property color m3surfaceBright: "#3a3939"
        property color m3surfaceContainerLowest: "#0f0e0e"
        property color m3surfaceContainerLow: "#1c1b1c"
        property color m3surfaceContainer: "#201f20"
        property color m3surfaceContainerHigh: "#2b2a2a"
        property color m3surfaceContainerHighest: "#363435"
        property color m3onSurface: "#e6e1e1"
        property color m3surfaceVariant: "#49464a"
        property color m3onSurfaceVariant: "#cbc5ca"
        property color m3inverseSurface: "#e6e1e1"
        property color m3inverseOnSurface: "#313030"
        property color m3outline: "#948f94"
        property color m3outlineVariant: "#49464a"
        property color m3shadow: "#000000"
        property color m3scrim: "#000000"
        property color m3surfaceTint: "#cbc4cb"
        property color m3sourceColor: "#cbc4cb"
        property color m3primary: "#cbc4cb"
        property color m3onPrimary: "#322f34"
        property color m3primaryContainer: "#2d2a2f"
        property color m3onPrimaryContainer: "#bcb6bc"
        property color m3inversePrimary: "#615d63"
        property color m3secondary: "#cac5c8"
        property color m3onSecondary: "#323032"
        property color m3secondaryContainer: "#4d4b4d"
        property color m3onSecondaryContainer: "#ece6e9"
        property color m3tertiary: "#d1c3c6"
        property color m3onTertiary: "#372e30"
        property color m3tertiaryContainer: "#31292b"
        property color m3onTertiaryContainer: "#c1b4b7"
        property color m3error: "#ffb4ab"
        property color m3onError: "#690005"
        property color m3errorContainer: "#93000a"
        property color m3onErrorContainer: "#ffdad6"
        property color m3primaryFixed: "#e7e0e7"
        property color m3primaryFixedDim: "#cbc4cb"
        property color m3onPrimaryFixed: "#1d1b1f"
        property color m3onPrimaryFixedVariant: "#49454b"
        property color m3secondaryFixed: "#e6e1e4"
        property color m3secondaryFixedDim: "#cac5c8"
        property color m3onSecondaryFixed: "#1d1b1d"
        property color m3onSecondaryFixedVariant: "#484648"
        property color m3tertiaryFixed: "#eddfe1"
        property color m3tertiaryFixedDim: "#d1c3c6"
        property color m3onTertiaryFixed: "#211a1c"
        property color m3onTertiaryFixedVariant: "#4e4447"
        property color m3success: "#B5CCBA"
        property color m3onSuccess: "#213528"
        property color m3successContainer: "#374B3E"
        property color m3onSuccessContainer: "#D1E9D6"
        property color term0: "#EDE4E4"
        property color term1: "#B52755"
        property color term2: "#A97363"
        property color term3: "#AF535D"
        property color term4: "#A67F7C"
        property color term5: "#B2416B"
        property color term6: "#8D76AD"
        property color term7: "#272022"
        property color term8: "#0E0D0D"
        property color term9: "#B52755"
        property color term10: "#A97363"
        property color term11: "#AF535D"
        property color term12: "#A67F7C"
        property color term13: "#B2416B"
        property color term14: "#8D76AD"
        property color term15: "#221A1A"
    }

    colors: QtObject {
        property color colSubtext: m3colors.m3outline
        // Layer 0
        property color colLayer0Base: ColorUtils.mix(m3colors.m3background, m3colors.m3primary, Config.options.appearance.extraBackgroundTint ? 0.99 : 1)
        property color colLayer0: ColorUtils.transparentize(colLayer0Base, root.backgroundTransparency)
        property color colOnLayer0: m3colors.m3onBackground
        property color colLayer0Hover: ColorUtils.transparentize(ColorUtils.mix(colLayer0, colOnLayer0, 0.9, root.contentTransparency))
        property color colLayer0Active: ColorUtils.transparentize(ColorUtils.mix(colLayer0, colOnLayer0, 0.8, root.contentTransparency))
        property color colLayer0Border: ColorUtils.mix(root.m3colors.m3outlineVariant, colLayer0, 0.4)

        // A themable surface is the same three ideas everywhere it appears: a
        // color slot per mode, an opacity that may defer to the stock one, and
        // the interface's own color when neither is set. Stated once so the
        // next surface to become themable is two calls rather than a copy.
        readonly property var hexColor: /^#[0-9a-fA-F]{6}$/
        // Only a color Qt can actually paint may leave the pick: a slot that
        // arrives malformed — a hand-edit, a bad import — reads as unpicked
        // rather than wedging every binding downstream of it.
        function modePick(dark, light) {
            const v = (m3colors.darkmode ? dark : light) ?? ""
            return colors.hexColor.test(v) ? v : ""
        }
        // A negative opacity means the surface never had one chosen, so it is
        // drawn at whatever strength the interface already gave it.
        function surfaceColor(pick, base, opacity, stockAlpha) {
            return ColorUtils.applyAlpha(pick !== "" ? pick : base,
                (opacity ?? -1) < 0 ? stockAlpha : opacity)
        }

        // The strip and the dock are both drawn on layer 0, so they start from
        // one number rather than two that merely happen to agree.
        readonly property real layer0StockAlpha: colLayer0.a
        readonly property string barBackgroundPick: modePick(Config.options?.bar.backgroundColorDark, Config.options?.bar.backgroundColorLight)
        // A notch reads as part of the screen edge rather than something laid
        // over it, so it starts opaque instead of at the strip's usual alpha.
        readonly property real barStockAlpha: root.sizes.barIsNotch ? 1 : layer0StockAlpha
        property color colBarBackground: surfaceColor(barBackgroundPick, colLayer0, Config.options?.bar.backgroundOpacity, barStockAlpha)
        // The float style's outline wears the strip's own alpha: a hairline
        // that kept full strength while the strip went see-through read as a
        // wire rectangle floating around nothing.
        // The same surface with its alpha taken off. A shape drawn beside
        // another and lapping it by a pixel composites that lap twice, which
        // reads as a seam once either is see through. Painting both opaque
        // inside a group and fading the group instead blends the lap away.
        readonly property color colBarBackgroundOpaque: Qt.rgba(colBarBackground.r, colBarBackground.g, colBarBackground.b, 1)
        readonly property color colDockBackgroundOpaque: Qt.rgba(colDockBackground.r, colDockBackground.g, colDockBackground.b, 1)
        readonly property string dockGlowPick: modePick(Config.options?.dock.glowColorDark, Config.options?.dock.glowColorLight)
        // The halo's stock is the palette's lightest tone, so it reads as
        // light cast by the icon rather than a sticker laid behind it.
        property color colDockGlow: dockGlowPick !== "" ? dockGlowPick : m3colors.m3primaryFixed
        // The outline is the palette's own recipe, the outline tone laid over
        // the surface, made with the surface as drawn: a picked color gets an
        // edge in its own hue, and the outline tone follows the content's side.
        property color colBarBackgroundBorder: ColorUtils.applyAlpha(
            ColorUtils.mix(root.barStripContent.colOutlineVariant, colBarBackground, 0.4), colBarBackground.a)
        // The shadow the same way: a slab of shade around a strip that has
        // faded from sight reads as a decoration around nothing.
        property color colBarShadow: ColorUtils.applyAlpha(colShadow, colShadow.a * colBarBackground.a)
        // The blur floor these surfaces are given in hypr/hyprland/rules.lua.
        // Kept here so a transparency slider can tell where its surface stops
        // being frosted. The two have to be changed together.
        readonly property real blurFloor: 0.35
        // The faintest a blurred surface can be set and still be frosted. Under
        // this the compositor drops the blur outright rather than by degrees,
        // so a slider running past it reads as a cliff partway along an
        // otherwise even track. A hair over, so the end of the track is above
        // the drop rather than on it.
        readonly property real surfaceOpacityFloor: Math.min(1, root.colors.blurFloor + 0.005)
        readonly property string dockPick: modePick(Config.options?.dock.backgroundColorDark, Config.options?.dock.backgroundColorLight)
        // The dock's notch is the strip's shape set down on the far edge, so
        // it starts from the strip's alpha too. Opaque also leaves its sweeps
        // with no blur edge to show: what is blurred behind a surface is
        // settled per pixel with nothing in between, and that line falls
        // across the very curves this style is shaped around.
        readonly property real dockStockAlpha: (Config.options?.dock.cornerStyle ?? "float") === "hug"
            ? 1 : layer0StockAlpha
        property color colDockBackground: surfaceColor(dockPick, colLayer0, Config.options?.dock.backgroundOpacity, dockStockAlpha)
        property color colDockBackgroundBorder: ColorUtils.applyAlpha(
            ColorUtils.mix(root.dockContent.colOutlineVariant, colDockBackground, 0.4), colDockBackground.a)
        // The notched dock carries its own alpha on the container rather than on
        // each piece, so the outline goes on opaque there and is let down with
        // everything else, instead of being faded twice.
        readonly property color colDockBackgroundBorderOpaque: Qt.rgba(colDockBackgroundBorder.r, colDockBackgroundBorder.g, colDockBackgroundBorder.b, 1)
        property color colDockShadow: ColorUtils.applyAlpha(colShadow, colShadow.a * colDockBackground.a)
        readonly property string dockBadgePick: modePick(Config.options?.dock.badgeColorDark, Config.options?.dock.badgeColorLight)
        readonly property string dockBadgeTextPick: modePick(Config.options?.dock.badgeTextColorDark, Config.options?.dock.badgeTextColorLight)
        // The count badge sits on the icon to be read, not on the surface to
        // be seen through, so it keeps full strength however faint the dock
        // behind it is set.
        property color colDockBadge: dockBadgePick !== "" ? dockBadgePick : colPrimary
        property color colDockBadgeText: dockBadgeTextPick !== "" ? dockBadgeTextPick : m3colors.m3onPrimary
        // Layer 1
        property color colLayer1Base: m3colors.m3surfaceContainerLow
        property color colLayer1: ColorUtils.solveOverlayColor(colLayer0Base, colLayer1Base, 1 - root.contentTransparency);
        // colLayer1 carries only the opacity an overlay needs to look right on
        // top of a solid layer 0 — about a tenth — which is why widget groups
        // vanish once the strip beneath them stops being solid.
        readonly property real barWidgetStockAlpha: colLayer1.a
        // The slot for the mode on screen; the other waits for its mode.
        readonly property string barWidgetPick: modePick(Config.options?.bar.widgetColorDark, Config.options?.bar.widgetColorLight)
        property color colBarWidget: surfaceColor(barWidgetPick, colLayer1, Config.options?.bar.widgetOpacity, barWidgetStockAlpha)
        property color colOnLayer1: m3colors.m3onSurfaceVariant;
        property color colOnLayer1Inactive: ColorUtils.mix(colOnLayer1, colLayer1, 0.45);
        property color colLayer1Hover: ColorUtils.transparentize(ColorUtils.mix(colLayer1, colOnLayer1, 0.92), root.contentTransparency)
        property color colLayer1Active: ColorUtils.transparentize(ColorUtils.mix(colLayer1, colOnLayer1, 0.85), root.contentTransparency);
        // Layer 2
        property color colLayer2Base: m3colors.m3surfaceContainer
        property color colLayer2: ColorUtils.solveOverlayColor(colLayer1Base, colLayer2Base, 1 - root.contentTransparency)
        property color colLayer2Hover: ColorUtils.solveOverlayColor(colLayer1Base, ColorUtils.mix(colLayer2Base, colOnLayer2, 0.90), 1 - root.contentTransparency)
        property color colLayer2Active: ColorUtils.solveOverlayColor(colLayer1Base, ColorUtils.mix(colLayer2Base, colOnLayer2, 0.80), 1 - root.contentTransparency);
        property color colLayer2Disabled: ColorUtils.solveOverlayColor(colLayer1Base, ColorUtils.mix(colLayer2Base, m3colors.m3background, 0.8), 1 - root.contentTransparency);
        property color colOnLayer2: m3colors.m3onSurface;
        property color colOnLayer2Disabled: ColorUtils.mix(colOnLayer2, m3colors.m3background, 0.4);
        // Layer 3
        property color colLayer3Base: m3colors.m3surfaceContainerHigh
        property color colLayer3: ColorUtils.solveOverlayColor(colLayer2Base, colLayer3Base, 1 - root.contentTransparency)
        property color colLayer3Hover: ColorUtils.solveOverlayColor(colLayer2Base, ColorUtils.mix(colLayer3Base, colOnLayer3, 0.90), 1 - root.contentTransparency)
        property color colLayer3Active: ColorUtils.solveOverlayColor(colLayer2Base, ColorUtils.mix(colLayer3Base, colOnLayer3, 0.80), 1 - root.contentTransparency);
        property color colOnLayer3: m3colors.m3onSurface;
        // Layer 4
        property color colLayer4Base: m3colors.m3surfaceContainerHighest
        property color colLayer4: ColorUtils.solveOverlayColor(colLayer3Base, colLayer4Base, 1 - root.contentTransparency)
        property color colLayer4Hover: ColorUtils.solveOverlayColor(colLayer3Base, ColorUtils.mix(colLayer4Base, colOnLayer4, 0.90), 1 - root.contentTransparency)
        property color colLayer4Active: ColorUtils.solveOverlayColor(colLayer3Base, ColorUtils.mix(colLayer4Base, colOnLayer4, 0.80), 1 - root.contentTransparency);
        property color colOnLayer4: m3colors.m3onSurface;
        // Primary
        property color colPrimary: m3colors.m3primary
        property color colOnPrimary: m3colors.m3onPrimary
        property color colPrimaryHover: ColorUtils.mix(colors.colPrimary, colLayer1Hover, 0.87)
        property color colPrimaryActive: ColorUtils.mix(colors.colPrimary, colLayer1Active, 0.7)
        property color colPrimaryContainer: m3colors.m3primaryContainer
        property color colPrimaryContainerHover: ColorUtils.mix(colors.colPrimaryContainer, colors.colOnPrimaryContainer, 0.9)
        property color colPrimaryContainerActive: ColorUtils.mix(colors.colPrimaryContainer, colors.colOnPrimaryContainer, 0.8)
        property color colOnPrimaryContainer: m3colors.m3onPrimaryContainer
        // Secondary
        property color colSecondary: m3colors.m3secondary
        property color colSecondaryHover: ColorUtils.mix(m3colors.m3secondary, colLayer1Hover, 0.85)
        property color colSecondaryActive: ColorUtils.mix(m3colors.m3secondary, colLayer1Active, 0.4)
        property color colOnSecondary: m3colors.m3onSecondary
        property color colSecondaryContainer: m3colors.m3secondaryContainer
        property color colSecondaryContainerHover: ColorUtils.mix(m3colors.m3secondaryContainer, m3colors.m3onSecondaryContainer, 0.90)
        property color colSecondaryContainerActive: ColorUtils.mix(m3colors.m3secondaryContainer, m3colors.m3onSecondaryContainer, 0.54)
        property color colOnSecondaryContainer: m3colors.m3onSecondaryContainer
        // Tertiary
        property color colTertiary: m3colors.m3tertiary
        property color colTertiaryHover: ColorUtils.mix(m3colors.m3tertiary, colLayer1Hover, 0.85)
        property color colTertiaryActive: ColorUtils.mix(m3colors.m3tertiary, colLayer1Active, 0.4)
        property color colTertiaryContainer: m3colors.m3tertiaryContainer
        property color colTertiaryContainerHover: ColorUtils.mix(m3colors.m3tertiaryContainer, m3colors.m3onTertiaryContainer, 0.90)
        property color colTertiaryContainerActive: ColorUtils.mix(m3colors.m3tertiaryContainer, colLayer1Active, 0.54)
        property color colOnTertiary: m3colors.m3onTertiary
        property color colOnTertiaryContainer: m3colors.m3onTertiaryContainer
        // Surface
        property color colBackgroundSurfaceContainer: ColorUtils.transparentize(m3colors.m3surfaceContainer, root.backgroundTransparency)
        property color colSurfaceContainerLow: ColorUtils.solveOverlayColor(m3colors.m3background, m3colors.m3surfaceContainerLow, 1 - root.contentTransparency)
        property color colSurfaceContainer: ColorUtils.solveOverlayColor(m3colors.m3surfaceContainerLow, m3colors.m3surfaceContainer, 1 - root.contentTransparency)
        property color colSurfaceContainerHigh: ColorUtils.solveOverlayColor(m3colors.m3surfaceContainer, m3colors.m3surfaceContainerHigh, 1 - root.contentTransparency)
        property color colSurfaceContainerHighest: ColorUtils.solveOverlayColor(m3colors.m3surfaceContainerHigh, m3colors.m3surfaceContainerHighest, 1 - root.contentTransparency)
        property color colSurfaceContainerHighestHover: ColorUtils.mix(m3colors.m3surfaceContainerHighest, m3colors.m3onSurface, 0.95)
        property color colSurfaceContainerHighestActive: ColorUtils.mix(m3colors.m3surfaceContainerHighest, m3colors.m3onSurface, 0.85)
        property color colOnSurface: m3colors.m3onSurface
        property color colOnSurfaceVariant: m3colors.m3onSurfaceVariant
        // Misc
        property color colTooltip: m3colors.m3inverseSurface
        property color colOnTooltip: m3colors.m3inverseOnSurface
        property color colScrim: ColorUtils.transparentize(m3colors.m3scrim, 0.5)
        property color colShadow: ColorUtils.transparentize(m3colors.m3shadow, 0.7)
        property color colOutline: m3colors.m3outline
        property color colOutlineVariant: m3colors.m3outlineVariant
        property color colError: m3colors.m3error
        property color colErrorHover: ColorUtils.mix(m3colors.m3error, colLayer1Hover, 0.85)
        property color colErrorActive: ColorUtils.mix(m3colors.m3error, colLayer1Active, 0.7)
        property color colOnError: m3colors.m3onError
        property color colErrorContainer: m3colors.m3errorContainer
        property color colErrorContainerHover: ColorUtils.mix(m3colors.m3errorContainer, m3colors.m3onErrorContainer, 0.90)
        property color colErrorContainerActive: ColorUtils.mix(m3colors.m3errorContainer, m3colors.m3onErrorContainer, 0.70)
        property color colOnErrorContainer: m3colors.m3onErrorContainer
    }

    rounding: QtObject {
        property int unsharpen: 2
        property int unsharpenmore: 6
        property int verysmall: 8
        property int small: 12
        property int normal: 17
        property int large: 23
        property int verylarge: 30
        property int full: 9999
        property int screenRounding: large
        property int windowRounding: 18
        // What "the interface decides" means for the bar's two shape sliders,
        // named so the mark on their tracks and the fallback stay one value.
        readonly property real barWidgetStock: small
        readonly property real barWidget: (Config.options?.bar.widgetRadius ?? -1) >= 0
            ? Config.options.bar.widgetRadius : barWidgetStock
        // As round as the strip's corners are allowed to get. Named so the
        // slider and the mark on it read the same number rather than one
        // carrying a copy.
        readonly property real barFloatMax: 30
        // The notch curves as far as it can by default, the way its dock
        // does, so the two read as one shape. A floating strip keeps the
        // roundness the rest of the interface uses.
        readonly property real barFloatStock: root.sizes.barIsNotch
            ? barFloatMax : windowRounding
        readonly property real barFloat: (Config.options?.bar.floatRadius ?? -1) >= 0
            ? Config.options.bar.floatRadius : barFloatStock
        // The dock's roundness tracks run to this, and the marks on them are
        // stated as a share of it so a mark can never promise a place the
        // track does not have.
        readonly property real dockRoundMax: 40
        // How far the flare track runs, kept apart from the number above so the
        // stock shapes stay where they are. The flares are their own pieces
        // beside the body rather than corners of it, so they are not capped at
        // half its height the way the body is, and a taller dock needs a longer
        // sweep to turn as gently as a shorter one. Bounded by the dock's own
        // body, past which the curve wants more height than the body has and
        // stops meeting its edge, which reads as the ends coming apart. Set a
        // little under the body rather than at it: the last part of the sweep
        // is where the two surfaces have least to overlap on, and it lets go
        // before the body does.
        // A fixed track, so the handle keeps its place when the icons resize
        // the dock underneath it. Double the stock reaches past the tallest
        // dock the icon slider can build, so nothing is out of reach.
        readonly property real dockFlareMax: dockRoundMax * 2
        // What the body can actually hold, which the drawn sweep is held to.
        // Unlike the track this follows the icons, because it is a fact about
        // the dock rather than a choice about the control.
        readonly property real dockFlareFit:
            (root.sizes.dockHeight - root.sizes.elevationMargin) * 0.96
        // Hugging wants a rounder body than a floating one: the curve that
        // leaves the edge reads as part of it only if the corner above is
        // generous enough to answer it.
        // Notch is meant to read as the bar's own shape, so its two stocks are
        // the pair that gets it there rather than shares of the number above:
        // a long sweep at the ends, and a body turned just enough to meet it.
        readonly property real dockNotchFlareStock: 52
        readonly property real dockNotchBodyStock: 32
        readonly property real dockCornerStock: Config.options?.dock.cornerStyle === "hug"
            ? dockNotchFlareStock : large
        readonly property real dock: (Config.options?.dock.radius ?? -1) >= 0
            ? Config.options.dock.radius : dockCornerStock
        // The pair facing the desktop keeps a slight roundness of its own,
        // settled rather than derived: following the roundness above would
        // drag this one's mark along every time that slider moved, and would
        // leave the pair answering to a control rect has put away.
        // The notched dock carries its roundness right up to the cap and keeps
        // the desktop-facing pair nearly as round, so the body reads as one
        // continuous curve between the two ends rather than a slab with corners
        // taken off. Every other style keeps the slight roundness it had.
        readonly property real dockTopStock: Config.options?.dock.cornerStyle === "hug"
            ? dockNotchBodyStock : dockRoundMax * 0.10
        readonly property real dockTop: (Config.options?.dock.topRadius ?? -1) >= 0
            ? Config.options.dock.topRadius : dockTopStock
        // The roundness the dock's body actually shows. Floating, that is the
        // body's own; set down on an edge, the corners facing the edge are
        // square and the visible pair is the one facing the desktop. Anything
        // shaped to match the dock wants this rather than either slider.
        readonly property real dockBody: (Config.options?.dock.cornerStyle ?? "float") !== "float"
            ? dockTop : dock
    }

    font: QtObject {
        property QtObject family: QtObject {
            property string main: Config.options.appearance.fonts.main
            property string numbers: Config.options.appearance.fonts.numbers
            property string title: Config.options.appearance.fonts.title
            property string iconMaterial: "Material Symbols Rounded"
            property string iconNerd: Config.options.appearance.fonts.iconNerd
            property string monospace: Config.options.appearance.fonts.monospace
            property string reading: Config.options.appearance.fonts.reading
            property string expressive: Config.options.appearance.fonts.expressive
        }
        property QtObject variableAxes: QtObject {
            property var main: ({
                "wght": 450,
                "wdth": 100,
            })
            property var numbers: ({
                "wght": 450,
            })
            property var title: ({ // Slightly bold weight for title
                "wght": 550, // Weight (Lowered to compensate for increased grade)
            })
        }
        property QtObject pixelSize: QtObject {
            property int smallest: 10
            property int smaller: 12
            property int smallie: 13
            property int small: 15
            property int normal: 16
            property int large: 17
            property int larger: 19
            property int huge: 22
            property int hugeass: 23
            property int title: huge
        }
    }

    animationCurves: QtObject {
        readonly property list<real> expressiveFastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1] // Default, 350ms
        readonly property list<real> expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1] // Default, 500ms
        readonly property list<real> expressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1] // Default, 650ms
        readonly property list<real> expressiveEffects: [0.34, 0.80, 0.34, 1.00, 1, 1] // Default, 200ms
        readonly property list<real> emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property list<real> emphasizedFirstHalf: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82]
        readonly property list<real> emphasizedLastHalf: [5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property list<real> emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1]
        readonly property list<real> emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
        readonly property list<real> standard: [0.2, 0, 0, 1, 1, 1]
        readonly property list<real> standardAccel: [0.3, 0, 1, 1, 1, 1]
        readonly property list<real> standardDecel: [0, 0, 0, 1, 1, 1]
        readonly property real expressiveFastSpatialDuration: 350
        readonly property real expressiveDefaultSpatialDuration: 500
        readonly property real expressiveSlowSpatialDuration: 650
        readonly property real expressiveEffectsDuration: 200
    }

    animation: QtObject {
        property QtObject elementMove: QtObject {
            property int duration: animationCurves.expressiveDefaultSpatialDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveDefaultSpatial
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMove.duration
                    easing.type: root.animation.elementMove.type
                    easing.bezierCurve: root.animation.elementMove.bezierCurve
                }
            }
        }

        property QtObject elementMoveSmall: QtObject {
            property int duration: animationCurves.expressiveFastSpatialDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveFastSpatial
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMoveSmall.duration
                    easing.type: root.animation.elementMoveSmall.type
                    easing.bezierCurve: root.animation.elementMoveSmall.bezierCurve
                }
            }
        }

        property QtObject elementMoveEnter: QtObject {
            property int duration: 400
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedDecel
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementMoveEnter.duration
                    easing.type: root.animation.elementMoveEnter.type
                    easing.bezierCurve: root.animation.elementMoveEnter.bezierCurve
                }
            }
        }

        property QtObject elementMoveExit: QtObject {
            property int duration: 200
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedAccel
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementMoveExit.duration
                    easing.type: root.animation.elementMoveExit.type
                    easing.bezierCurve: root.animation.elementMoveExit.bezierCurve
                }
            }
        }

        property QtObject elementMoveFast: QtObject {
            property int duration: animationCurves.expressiveEffectsDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveEffects
            property int velocity: 850
            property Component colorAnimation: Component { ColorAnimation {
                duration: root.animation.elementMoveFast.duration
                easing.type: root.animation.elementMoveFast.type
                easing.bezierCurve: root.animation.elementMoveFast.bezierCurve
            }}
            property Component numberAnimation: Component { NumberAnimation {
                alwaysRunToEnd: true
                duration: root.animation.elementMoveFast.duration
                easing.type: root.animation.elementMoveFast.type
                easing.bezierCurve: root.animation.elementMoveFast.bezierCurve
            }}
        }

        property QtObject elementResize: QtObject {
            property int duration: 300
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasized
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementResize.duration
                    easing.type: root.animation.elementResize.type
                    easing.bezierCurve: root.animation.elementResize.bezierCurve
                }
            }
        }

        property QtObject clickBounce: QtObject {
            property int duration: 400
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveDefaultSpatial
            property int velocity: 850
            property Component numberAnimation: Component { NumberAnimation {
                alwaysRunToEnd: true
                duration: root.animation.clickBounce.duration
                easing.type: root.animation.clickBounce.type
                easing.bezierCurve: root.animation.clickBounce.bezierCurve
            }}
        }
        
        property QtObject scroll: QtObject {
            property int duration: 200
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: root.animationCurves.standardDecel
        }

        property QtObject menuDecel: QtObject {
            property int duration: 350
            property int type: Easing.OutExpo
        }
    }

    sizes: QtObject {
        property real baseBarHeight: 40
        // A floating strip spans the whole screen unless it is told otherwise,
        // as a percentage so one setting reads the same on every monitor
        // rather than leaving a wide screen barely trimmed and a narrow one
        // squeezed to a stub.
        // The notch is set down on the edge, so at the full width its ends
        // land in the screen's corners and the curves beside them have
        // nowhere to go. It stops a little short of that by default, which is
        // also as far as its slider goes.
        readonly property bool barIsNotch: Config.options?.bar.cornerStyle === 3
        // The styles that draw a strip of their own rather than dressing the
        // whole window: they share the width, the split and the shadow.
        readonly property bool barFloats: barIsNotch || Config.options?.bar.cornerStyle === 1
        // How far the style may be asked to reach, which is also where it
        // starts. The notch is set down on the edge, so at the whole width its
        // ends land in the screen's corners with nowhere to put the curves
        // beside them.
        readonly property real barFloatWidthMax: barIsNotch ? 95 : 100
        readonly property real barWidthKey: barIsNotch ? (Config.options?.bar.notchWidth ?? -1)
            : (Config.options?.bar.floatWidth ?? -1)
        readonly property real barFloatWidth: barWidthKey >= 0
            ? Math.min(barWidthKey, barFloatWidthMax) : barFloatWidthMax
        // Which edge the bar occupies, and where the dock lands after its
        // configured edge is flipped off the bar's — shared by the dock, the
        // overview's clearance and the settings picker so they can never
        // disagree.
        property string barEdge: Config.options.bar.vertical
            ? (Config.options.bar.bottom ? "right" : "left")
            : (Config.options.bar.bottom ? "bottom" : "top")
        property string dockEdge: {
            const flip = { top: "bottom", bottom: "top", left: "right", right: "left" };
            // config.json is hand-editable and every consumer picks its edge by
            // negation, so an unrecognised value would anchor the dock to all
            // four edges at once instead of falling back to one.
            const want = flip[Config.options.dock.position] ? Config.options.dock.position : "bottom";
            return want === root.sizes.barEdge ? flip[want] : want;
        }
        // Which edge each sidebar opens from. A vertical bar gathers every
        // control onto one side of the screen, so the panels it opens belong
        // on that side too rather than a reach across the display. A vertical
        // bar only ever sits left or right, so these stay left/right.
        property string sidebarLeftEdge: Config.options.bar.vertical ? root.sizes.barEdge : "left"
        property string sidebarRightEdge: Config.options.bar.vertical ? root.sizes.barEdge : "right"
        // Whether the two share an edge, and so cannot both be shown.
        property bool sidebarsShareEdge: root.sizes.sidebarLeftEdge === root.sizes.sidebarRightEdge
        // The dock's visible thickness plus its screen gap at the configured
        // icon size. The overview clears the dock's edge by it; a dock that has
        // shrunk its icons to fit a short screen is thinner than this, so that
        // clearance can only err long, never short.
        // The dock is as thick as its icons ask: one slider drives the icon,
        // and the surface grows around it, keeping the stock look identical
        // at the stock icon size.
        // The icon size the dock ships with. Whatever is sized in proportion to
        // the icons is measured from it, so a dock left alone looks the same as
        // it always did and everything grows together once it is changed.
        property real dockIconStock: 40
        // The size asked for. A dock shows this or the largest size its own
        // screen can run edge to edge, whichever is smaller, so this stays
        // exactly what was asked for and the slider and the file keep one
        // meaning on every screen.
        property real dockIconSize: (Config.options?.dock.iconSize ?? -1) >= 0
            ? Config.options.dock.iconSize : root.sizes.dockIconStock
        // The bottom of the settings track. A screen too short even for this
        // has nothing left to give up, so it truncates rather than drawing
        // icons no slider could have asked for.
        readonly property real dockIconMin: 16
        // Thickness, reserved extent and hover headroom as functions of an
        // icon size rather than only of the configured one, so a dock showing
        // smaller icons derives all three the same way and they cannot drift.
        function dockHeightFor(iconSize) {
            return iconSize + 25;
        }
        function dockExtentFor(iconSize) {
            return root.sizes.dockHeightFor(iconSize) + root.sizes.elevationMargin + root.sizes.hyprlandGapsOut;
        }
        property real dockHeight: root.sizes.dockHeightFor(root.sizes.dockIconSize)
        property real dockExtent: root.sizes.dockExtentFor(root.sizes.dockIconSize)
        // How far a hovered icon grows, as a percentage of itself. Each
        // effect keeps its own key, stock and ceiling, named so the track,
        // the mark on it and the clamp all read the same numbers: the wave
        // has room to be dramatic, the glow lifts only its one icon a shade,
        // so the halo reads as attention rather than motion, and swapping
        // effects swaps back to what each had. The clamp still stands
        // between a hand-edited value and the track.
        readonly property real dockHoverMagnifyMax: Config.options?.dock.hoverEffect === "glow" ? 100 : 200
        readonly property real dockHoverMagnifyStock: Config.options?.dock.hoverEffect === "glow" ? 25 : 135
        readonly property real dockHoverMagnifyKey: Config.options?.dock.hoverEffect === "glow"
            ? (Config.options?.dock.glowMagnify ?? -1) : (Config.options?.dock.hoverMagnify ?? -1)
        readonly property real dockHoverMagnify: dockHoverMagnifyKey >= 0
            ? Math.min(dockHoverMagnifyKey, dockHoverMagnifyMax) : dockHoverMagnifyStock
        // How strongly the halo blooms, as a percentage of its full reach.
        readonly property real dockGlowIntensityStock: 35
        readonly property real dockGlowIntensity: (Config.options?.dock.glowIntensity ?? -1) >= 0
            ? Math.min(Config.options.dock.glowIntensity, 100) : dockGlowIntensityStock
        // How far the halo reaches past the icon it grows from, which is the
        // blur's own radius and nothing at all for the effects that draw none.
        readonly property real dockGlowReachMax: 28
        readonly property real dockGlowReach: Config.options?.dock.hoverEffect === "glow"
            ? dockGlowReachMax * dockGlowIntensity / 100 : 0
        // Growing nothing needs no room: off collapses the scale, and with it
        // the headroom the dock reserves and the size its icons rasterize at.
        property real dockMaxScale: Config.options?.dock.hoverEffect === "off" ? 1
            : 1 + dockHoverMagnify / 100
        // The room a magnified icon needs beyond the dock to be drawn whole.
        // It grows away from the screen from the edge it sits on, so it climbs
        // by its own size again over the scale, and a fixed figure that suited
        // the stock icons cut the tops off larger ones. The window is sized by
        // this and the hover strip is offset past it, so the two cannot drift.
        // The room kept above the icons for what hovering can do to them: the
        // growth, and the halo that reaches past whatever it grew to. Sized
        // for the most the effect can be asked for rather than for what it is
        // asked right now, because the window's size and the margin that sets
        // the dock inside it both read this: the margin moves with the frame,
        // the size waits on the compositor to answer, so a headroom that
        // follows a dial walks the dock up and down under the hand turning it.
        // Reserving the ceiling costs nothing to look at: the room is
        // transparent, masked out of the pointer, and the space the dock
        // claims from other windows is measured from its own height elsewhere.
        function dockMagnifyHeadroomFor(iconSize) {
            if (Config.options?.dock.hoverEffect === "off") return 0;
            const peak = 1 + root.sizes.dockHoverMagnifyMax / 100;
            return iconSize * (peak - 1) + (Config.options?.dock.hoverEffect === "glow" ? root.sizes.dockGlowReachMax * peak : 0);
        }
        property real dockMagnifyHeadroom: root.sizes.dockMagnifyHeadroomFor(root.sizes.dockIconSize)
        Behavior on dockMagnifyHeadroom {
            animation: root.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        property real barHeight: Config.options.bar.cornerStyle === 1 ? 
            (baseBarHeight + root.sizes.hyprlandGapsOut * 2) : baseBarHeight
        property real barCenterSideModuleWidth: Config.options?.bar.verbose ? 360 : 140
        property real barCenterSideModuleWidthShortened: 280
        property real barCenterSideModuleWidthHellaShortened: 190
        property real barShortenScreenWidthThreshold: 1200 // Shorten if screen width is at most this value
        property real barHellaShortenScreenWidthThreshold: 1000 // Shorten even more...
        property real elevationMargin: 10
        // The top-left rectangle the hot corner answers in. Shared, because
        // the overview has to answer in the same one: while it is open the
        // pointer no longer reaches the corner's own surface.
        //
        // It has to end before the bar's first widget begins, since it sits
        // on a surface above the bar and takes every hover, click and scroll
        // inside it: a strip that ran along the top edge covered half the
        // height of the workspace pill and opened the overview instead of
        // switching workspaces. The first widget starts at the bar's
        // screenRounding inset, and a few pixels short of that keeps the
        // pill's hover halo clear as well. A pointer pushed into the corner
        // stops at the screen edge, so a small rectangle is still easy to hit
        // on purpose and hard to hit on the way to something else.
        property real hotCornerWidth: root.rounding.screenRounding - 3
        property real hotCornerHeight: 19
        property real fabShadowRadius: 5
        property real fabHoveredShadowRadius: 7
        property real hyprlandGapsOut: 5
        property real mediaControlsWidth: 440
        property real mediaControlsHeight: 160
        property real notificationPopupWidth: 410
        property real osdWidth: 180
        property real searchWidthCollapsed: 210
        property real searchWidth: 360
        property real sidebarWidth: 460
        property real sidebarWidthExtended: 750
        property real baseVerticalBarWidth: 46
        property real verticalBarWidth: Config.options.bar.cornerStyle === 1 ? 
            (baseVerticalBarWidth + root.sizes.hyprlandGapsOut * 2) : baseVerticalBarWidth
        property real wallpaperSelectorWidth: 1200
        property real wallpaperSelectorHeight: 690
        property real wallpaperSelectorItemMargins: 8
        property real wallpaperSelectorItemPadding: 6
    }

    syntaxHighlightingTheme: root.m3colors.darkmode ? "Monokai" : "ayu Light"
}
