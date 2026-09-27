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
        environment: Images.magickEnvironment
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

    // Set while a palette is written in one color at a time. The judging
    // below is costly, and a palette caught halfway is never drawn, so it
    // waits for the last color rather than running again for each one.
    property bool paletteSettling: false
    // Which way the content on a surface is drawn. The surface is judged as it
    // actually shows, see-through parts and all, and as it would show either
    // way, since some of it turns with the content. The palette's tones are
    // kept while they read, and otherwise unless the opposite ones read
    // clearly better against every part.
    readonly property bool autoIconContrast: !paletteSettling && (Config.options?.appearance.autoIconContrast ?? true)
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
    // Whether content on one side, carried to white or to black, reads on
    // every one of the places about as well as the other side would.
    function sideReads(white, places, need) {
        const side = worstContrast(white ? "white" : "black", places)
        const other = worstContrast(white ? "black" : "white", places)
        return side >= (need ?? 3) && side * 1.5 >= other
    }
    // Only while the dock's side still reads on the bar about as well as the
    // other side would: a dock set near black beside a stock light bar would
    // otherwise hand the bar light icons it could not show. A surface that is
    // read rather than glanced at asks for the contrast its text needs. The
    // dock is the one at rest unless another is given.
    function followsDock(places, need, dock) {
        return dockLeads && sideReads((dock ?? dockContent).darkmode, places, need)
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
    readonly property bool barPickedFlipped: contentFlipped(barPillAsIs, barPillAsIs) || extremeFlipped(barPillAsIs)
    // The palette's groups as the dock's side would find them: turned, when
    // they can turn and that side is turned.
    function barPillsFor(white) {
        return barPillPlaces(barBackdrop, colors.colBarWidget, barPillTurns && white !== m3colors.darkmode)
    }
    // Whether the whole bar can be drawn on one side: the strip and the
    // palette's groups by following the dock there, a group someone colored
    // by its own verdict, since that one never follows.
    function barShows(white) {
        if (!sideReads(white, [barBackdrop]))
            return false
        if (Config.options?.bar.borderless)
            return true
        return colors.barWidgetPick !== "" ? barPickedFlipped === (white !== m3colors.darkmode)
            : sideReads(white, barPillsFor(white))
    }
    // Whether a part of the bar that follows the dock onto one side would
    // read less well once carried to the other.
    function barGivesUp(from) {
        const loses = places => worstContrast(from ? "black" : "white", places(!from))
            < worstContrast(from ? "white" : "black", places(from))
        const strip = () => [barBackdrop]
        if (sideReads(from, strip()) && loses(strip))
            return true
        if (Config.options?.bar.borderless || colors.barWidgetPick !== "")
            return false
        return sideReads(from, barPillsFor(from)) && loses(barPillsFor)
    }
    // The dock's side as its own edge of the picture sets it. The bar lies
    // along another edge, and near the point where the dock turns the two can
    // differ just enough to turn the dock alone. So when the bar cannot be
    // drawn on the dock's side, the dock goes with the bar wherever the bar's
    // side stands off the dock as a mark: the dock carries icons and marks,
    // where the bar carries text it cannot be asked to give up. For the same
    // reason it does not go where the part of the bar following it would
    // read less well than it does where it stands. A bar and dock left as
    // they come, with nothing picked, no opacity set and both surfaces shown,
    // are the surfaces the palette's tones were chosen for, so there the dock
    // keeps its own side.
    readonly property bool dockOwnFlipped: contentFlipped([dockBackdrop], [dockBackdrop])
    readonly property bool barDockStock: colors.barBackgroundPick === "" && colors.barWidgetPick === ""
        && colors.dockPick === "" && (Config.options?.bar.backgroundOpacity ?? -1) < 0
        && (Config.options?.bar.widgetOpacity ?? -1) < 0 && (Config.options?.dock.backgroundOpacity ?? -1) < 0
        && (Config.options?.bar.showBackground ?? true) && (Config.options?.dock.showBackground ?? true)
    readonly property bool dockJoinsBar: {
        if (!dockLeads || !autoIconContrast || barDockStock)
            return false
        const own = m3colors.darkmode !== dockOwnFlipped
        return !barShows(own) && barShows(!own) && !barGivesUp(own)
            && worstContrast(own ? "black" : "white", [dockBackdrop]) >= 3
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
            ? root.barPickedFlipped
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
        flipped: root.dockJoinsBar ? !root.dockOwnFlipped : root.dockOwnFlipped
        stockFlipped: root.contentFlipped(stockBackdrops, stockBackdrops)
    }

    // The dim is laid over its window's faint clear color, and both over
    // whatever the dim frosts. The launcher and the dock raised above the
    // dim both lie on it.
    function dimOver(dim, picture) {
        return ColorUtils.composite(ColorUtils.applyAlpha(dim, colors.launcherDimOpacity),
            ColorUtils.composite(colors.colLauncherDimWindow, picture))
    }
    // A surface laid over the dim, and the dim over the picture it frosts.
    // The launcher sits in the middle of the screen, so there the picture is
    // read as a whole rather than along an edge. A surface's shadow is drawn
    // under all of it, not only around it, so a see-through surface shows it
    // too.
    function laidOverDim(surface, shadow, dim, shown, picture) {
        const under = dimOver(dim, picture ?? wallpaperAverage)
        return shown ? ColorUtils.composite(surface, ColorUtils.composite(shadow, under)) : under
    }
    // The dock's surface and shadow as they come, for the places the dock's
    // surface is laid over the dim.
    readonly property color dockStockSurface: ColorUtils.applyAlpha(colors.colLayer0, colors.dockStockAlpha)
    readonly property color dockStockShadow: ColorUtils.applyAlpha(colors.colShadow, colors.colShadow.a * colors.dockStockAlpha)
    // The Hug dock lies flat along its edge the way the Hug bar does and
    // casts no shadow, so none is counted under it. The app list keeps its
    // own whatever the dock does: it floats in the middle of the screen.
    readonly property color dockOwnShadow: sizes.dockSpans ? "transparent" : colors.colDockShadow
    readonly property color dockOwnStockShadow: sizes.dockSpans ? "transparent" : dockStockShadow
    // The dock is raised above the dim while the launcher is open, so there
    // it lies on the dim where the dim frosts the dock's own edge. The
    // launcher keeps its panels clear of the dock's band, so nothing of it
    // lies under the dock.
    readonly property color dockOverLauncherBackdrop: laidOverDim(colors.colDockBackground, dockOwnShadow,
        colors.colLauncherDim, Config.options?.dock.showBackground, wallpaperEdge(sizes.dockEdge))
    readonly property color dockOverLauncherStockBackdrop: laidOverDim(dockStockSurface, dockOwnStockShadow,
        colors.colLayer0Base, Config.options?.dock.showBackground, wallpaperEdge(sizes.dockEdge))
    // The dock as it is drawn while the launcher is open. The bar stays under
    // the dim and keeps following the dock at rest, so this one is judged by
    // itself alone.
    readonly property SurfaceContent dockOverLauncherContent: SurfaceContent {
        m3: root.m3colors
        palette: root.colors
        backdrops: [root.dockOverLauncherBackdrop]
        stockBackdrops: [root.dockOverLauncherStockBackdrop]
        adaptive: root.autoIconContrast
        flipped: root.contentFlipped(backdrops, backdrops)
        stockFlipped: root.contentFlipped(stockBackdrops, stockBackdrops)
    }
    readonly property color launcherBackdrop: laidOverDim(colors.colLauncherPanel, colors.colLauncherShadow,
        colors.colLauncherDim, true)
    readonly property color drawerBackdrop: laidOverDim(colors.colDockBackground, colors.colDockShadow,
        colors.colLauncherDim, Config.options?.dock.showBackground)
    readonly property color launcherStockBackdrop: laidOverDim(ColorUtils.applyAlpha(m3colors.m3surfaceContainer, colors.layer0StockAlpha),
        colors.colShadow, colors.colLayer0Base, true)
    readonly property color drawerStockBackdrop: laidOverDim(dockStockSurface, dockStockShadow,
        colors.colLayer0Base, Config.options?.dock.showBackground)
    // The hairline around the dock's surface is its outline mixed into the
    // surface's own color at the surface's alpha, so it stands off the
    // surface only as far as the outline is from that color. Over the dim
    // the outline is placed against a surface the dim shows through, where
    // it can land on that color and take the line with it. There it is
    // carried the way the line already stands from the surface until it
    // stands off as far as the stock one does on the stock surface, up to
    // what a mark needs. Where that way cannot get so far and the other
    // can, it crosses to the other side of the surface; where neither can,
    // it goes to whichever end stands further. Both lie on the dim over the
    // given picture, with the given shadows under them.
    function borderStanding(outline, surface, under) {
        return ColorUtils.contrastRatio(ColorUtils.composite(colors.surfaceBorder(outline, surface), under),
            ColorUtils.composite(surface, under))
    }
    function dockBorderOverDim(content, picture, shadow, stockShadow) {
        const outline = content.colOutlineVariant
        if (!content.adaptive || !Config.options?.dock.showBackground)
            return colors.dockBorder(outline)
        const surface = colors.colDockBackground
        const under = ColorUtils.composite(shadow, dimOver(colors.colLauncherDim, picture))
        const stockUnder = ColorUtils.composite(stockShadow, dimOver(colors.colLayer0Base, picture))
        const need = Math.min(content.markContrast,
            borderStanding(content.onStock(colors.colOutlineVariant), dockStockSurface, stockUnder))
        const stands = o => borderStanding(o, surface, under)
        const reaches = o => stands(o) >= need - 0.01
        if (reaches(outline))
            return colors.dockBorder(outline)
        const line = ColorUtils.composite(colors.surfaceBorder(outline, surface), under)
        const away = ColorUtils.relativeLuminance(line) > ColorUtils.relativeLuminance(ColorUtils.composite(surface, under))
            ? "white" : "black"
        const back = away === "white" ? "black" : "white"
        const toward = reaches(away) || (!reaches(back) && stands(away) >= stands(back)) ? away : back
        return colors.dockBorder(ColorUtils.mixUntil(outline, toward, reaches))
    }
    // The app list wears the dock's surface, but over the dim rather than
    // the screen's edge, so what reads on the dock need not read on it, and
    // its content is judged where it is. It and the panels take the side of
    // the dock as it is drawn over the dim while their text still reads on
    // it, so the launcher does not turn one way while the dock beside it
    // turns the other. A side that only carries marks is not enough here:
    // this is where names are read.
    readonly property LauncherSurfaceContent launcherContent: LauncherSurfaceContent {
        m3: root.m3colors
        palette: root.colors
        backdrops: [root.launcherBackdrop]
        stockBackdrops: [root.launcherStockBackdrop]
        adaptive: root.autoIconContrast
        holdsFills: true
        flipped: root.followsDock(backdrops, textContrast, root.dockOverLauncherContent)
            ? root.dockOverLauncherContent.flipped : root.contentFlipped(backdrops, backdrops)
        stockFlipped: root.contentFlipped(stockBackdrops, stockBackdrops)
    }
    readonly property LauncherSurfaceContent drawerContent: LauncherSurfaceContent {
        m3: root.m3colors
        palette: root.colors
        backdrops: [root.drawerBackdrop]
        stockBackdrops: [root.drawerStockBackdrop]
        adaptive: root.autoIconContrast
        holdsFills: true
        flipped: root.followsDock(backdrops, textContrast, root.dockOverLauncherContent)
            ? root.dockOverLauncherContent.flipped : root.contentFlipped(backdrops, backdrops)
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
        // Whether a fill keeps at least the edge it has on the stock surface.
        // In the launcher a fill is what shows where the keyboard is and
        // which row is picked, so one that fades into the surface loses the
        // place. On the strip and the dock the fills are hover washes under
        // the pointer, which already shows the place.
        property bool holdsFills: false
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
        // A fill content is set on, placed as a mark is. Placed by lightness
        // alone its share can land on the surface itself, so where fills are
        // held it is then carried toward the ink until it stands off the
        // surface as the palette's fill does on the stock one, however far
        // that is: it is what shows which row is picked, and text held on it
        // crosses sides where it has to.
        function fill(c, full, paletteFull) {
            const placed = across(c, full, paletteFull)
            return holdsFills ? standOff(c, placed, full, backdrops[0], stockBackdrops[0]) : placed
        }
        // A pressed fill is held the same way by contrast alone. The palette
        // sets it off by lightness, which contrast counts, so that already
        // keeps it plainly apart; carried on until its hue shows as well, it
        // crosses the middle away from the hover fill a press ripples over,
        // and text across the two is left no side to read on.
        function flash(c, full, paletteFull) {
            const placed = across(c, full, paletteFull)
            return holdsFills ? heldOff(c, placed, full, backdrops[0], stockBackdrops[0]) : placed
        }
        // One of the palette's fills, from where it starts, carried toward
        // another color until it stands off what it is laid on with the
        // contrast the palette's own has on the same place on the stock
        // surface, up to `most` where one is given.
        function heldOff(c, start, toward, under, stockUnder, most) {
            if (!adaptive)
                return c
            return ColorUtils.mixForContrast(start, toward, under, Math.min(most ?? Infinity, standing(onStock(c), stockUnder)))
        }
        // The same, and then on until the two look as far apart as they do
        // there. The palette sets some fills off its surface by hue more than
        // by lightness, a pale blue row on a pale gray panel, which contrast
        // does not count, and a fill placed on a white or black surface loses
        // its hue and with it the only edge it had.
        function standOff(c, start, toward, under, stockUnder) {
            if (!adaptive)
                return c
            return ColorUtils.mixForDistance(heldOff(c, start, toward, under, stockUnder), toward, under,
                ColorUtils.deltaE(ColorUtils.composite(onStock(c), stockUnder), stockUnder))
        }
        // A fill as it is seen over an opaque color. One given as a list is
        // several laid bottom first, as a ripple spreads over a hover wash.
        function laid(f, under) {
            return (Array.isArray(f) ? f : [f]).reduce((out, layer) => ColorUtils.composite(layer, out), under)
        }
        // The contrast the palette gives this color on one of its fills, laid
        // on the stock surface.
        function stockOn(c, paletteFill) {
            const stock = Array.isArray(paletteFill) ? paletteFill.map(layer => onStock(layer)) : onStock(paletteFill)
            return ColorUtils.contrastRatio(onStock(c), laid(stock, stockBackdrops[0]))
        }
        // Text drawn on one of the fills rather than on the surface, held
        // against that fill up to text contrast, or to what the pair has on
        // the stock surface where that is less. A middle-toned fill can leave
        // the text's own side short, and then it crosses to the side that
        // reads. Where a `reach` past text contrast is given, the text goes on
        // toward it along the side it took, as far as the stock pair allows;
        // the side is still the one the text needs.
        // The stock pair is measured with the fill laid on the stock surface,
        // since a see-through fill is only ever seen that way.
        function onFill(c, fillColor, paletteFill, reach) {
            return onFills(c, [fillColor], [paletteFill], reach)
        }
        // The same for text that lies across several fills at once. It is
        // held on one side of all of them: its own while that reads on every
        // one, or else the side that reads best on the worst of them, so where
        // two fills sit either side of the middle it reads on both about as
        // well as any one color can.
        function onFills(c, fills, paletteFills, reach) {
            return heldOn(across(c, m3onSurface, m3.m3onSurface), c, fills, paletteFills, textContrast, reach)
        }
        function heldOn(start, c, fills, paletteFills, need, reach) {
            if (!adaptive)
                return start
            const unders = fills.map(f => laid(f, backdrops[0]))
            const pairs = paletteFills.map(f => stockOn(c, f))
            const needs = pairs.map(pair => Math.min(need, pair))
            const lighter = ColorUtils.relativeLuminance(start) > ColorUtils.relativeLuminance(unders[0])
            const own = lighter ? "white" : "black"
            const other = lighter ? "black" : "white"
            const stands = side => Math.min(...unders.map((u, i) => ColorUtils.contrastRatio(side, u) / needs[i]))
            const toward = stands(own) >= 1 || stands(own) >= stands(other) ? own : other
            const holds = pairs.map(pair => Math.min(Math.max(need, reach ?? 0), pair))
            // Carried toward that side for one fill, it can pass back over
            // another it already stood off, so each is held again after the
            // rest.
            let out = start
            for (let pass = 0; pass < fills.length; ++pass)
                for (let i = 0; i < fills.length; ++i)
                    out = ColorUtils.mixForContrast(out, toward, unders[i], holds[i])
            return out
        }
        // Text and icons, wherever the content sits.
        function ink(c) { return held(c, tone(c), darkmode ? "white" : "black", textContrast, true) }
        // The accent only has to stand out as a mark.
        function accent(c) { return held(c, tone(c), darkmode ? "white" : "black", markContrast, false) }
        // A dimmed ink moves toward the ink it was dimmed from and stops at
        // four fifths of that ink's contrast, so it still reads as the fainter.
        // One drawn around a fill, as a tile's outline is, is held the same
        // way against that fill, given with the palette's own for it, since
        // the outline is what marks where the fill ends.
        function dim(c, full, paletteFull, fillColor, paletteFill) {
            const start = across(c, full, paletteFull)
            if (fillColor === undefined)
                return held(c, start, full, Math.min(markContrast, standing(full, backdrops[0]) / 1.25), false)
            const under = laid(fillColor, backdrops[0])
            return heldOff(c, start, full, under, laid(onStock(paletteFill), stockBackdrops[0]),
                Math.min(markContrast, standing(full, under) / 1.25))
        }
        // A see-through wash of one of these colors, made less see-through the
        // same way when what it lies on would swallow it: the surface, or the
        // fill given with the palette's own for it.
        function faded(c, opacity, fillColor, paletteFill) {
            const wash = ColorUtils.transparentize(c, 1 - opacity)
            if (!adaptive)
                return wash
            const under = fillColor === undefined ? backdrops[0] : laid(fillColor, backdrops[0])
            const stockUnder = paletteFill === undefined ? stockBackdrops[0] : laid(onStock(paletteFill), stockBackdrops[0])
            const stock = stockFlipped === flipped ? wash : ColorUtils.mirrorLightness(wash)
            return ColorUtils.mixForContrast(wash, c, under, Math.min(markContrast,
                standing(c, under) / 1.25, standing(stock, stockUnder)))
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
        readonly property color colSecondaryContainer: fill(palette.colSecondaryContainer, m3onSurface, m3.m3onSurface)
        readonly property color colSecondaryContainerHover: fill(palette.colSecondaryContainerHover, m3onSurface, m3.m3onSurface)
        readonly property color colSecondaryContainerActive: flash(palette.colSecondaryContainerActive, m3onSurface, m3.m3onSurface)
        readonly property color colOnSecondaryContainer: onFill(palette.colOnSecondaryContainer, colSecondaryContainer, palette.colSecondaryContainer)
        readonly property color colLayer0: across(palette.colLayer0, colOnLayer0, palette.colOnLayer0)
        // The surface's outline drawn around a folder's tile, so the tile is
        // what it has to stand off.
        readonly property color colLayer0BorderOnLayer1: dim(palette.colLayer0Border, colOnLayer0, palette.colOnLayer0,
            colLayer1, palette.colLayer1)
        readonly property color colLayer1: fill(palette.colLayer1, colOnLayer1, palette.colOnLayer1)
        readonly property color colLayer1Hover: fill(palette.colLayer1Hover, colOnLayer1, palette.colOnLayer1)
        readonly property color colLayer1Active: flash(palette.colLayer1Active, colOnLayer1, palette.colOnLayer1)
        readonly property color colOutlineVariant: dim(palette.colOutlineVariant, colOnLayer0, palette.colOnLayer0)
        readonly property color m3onSurface: ink(m3.m3onSurface)
        readonly property color m3primary: accent(m3.m3primary)
        readonly property color m3onPrimary: tone(m3.m3onPrimary)
        readonly property color m3secondaryContainer: fill(m3.m3secondaryContainer, m3onSurface, m3.m3onSurface)
        readonly property color m3onSecondaryContainer: onFill(m3.m3onSecondaryContainer, m3secondaryContainer, m3.m3secondaryContainer)
        readonly property color m3error: tone(m3.m3error)
    }
    // The rest of what the launcher and the app list draw: their rows,
    // tiles, fields and buttons, at rest and as they are picked, pressed
    // and typed into. Only those two carry it, so a new wallpaper or a step
    // of a slider does not work it out again for the bar and the dock,
    // which never draw it.
    component LauncherSurfaceContent: SurfaceContent {
        // A pointer press spreads the pressed fill as a ripple over the
        // resting one, so it has to show on that fill, and pressed text lies
        // across both. The pressed fill is placed against the surface, so it
        // can land on the resting fill, or be carried toward the ink across
        // the side the resting text reads on, which leaves no one color
        // reading on both. The ripple is then set off the resting fill as far
        // as the palette's pressed fill stands off its resting one on the
        // stock surface, toward the text, the palette's way, or away from it:
        // of the two that keep the text reading and reach that far, the one
        // that leaves the pressed row further off what it is laid on, since
        // the ripple fills the row as it spreads. Where neither does, the text
        // comes first. What the resting fill is laid on is given with the same
        // place on the stock surface.
        function ripple(c, pressed, rest, paletteRest, restText, paletteText, under, stockUnder) {
            if (!holdsFills || !adaptive)
                return pressed
            const here = laid(rest, under)
            const stockRest = laid(onStock(paletteRest), stockUnder)
            const light = ColorUtils.relativeLuminance(restText) > ColorUtils.relativeLuminance(here)
            const need = Math.min(textContrast, ColorUtils.contrastRatio(onStock(paletteText), laid(onStock(c), stockRest)))
            const shows = standing(onStock(c), stockRest)
            const holds = f => ColorUtils.contrastRatio(light ? "white" : "black", laid(f, here)) >= need - 0.01
                && standing(f, here) >= shows - 0.01
            if (holds(pressed))
                return pressed
            const toward = ColorUtils.mixForContrast(rest, light ? "white" : "black", here, shows)
            const away = ColorUtils.mixForContrast(rest, light ? "black" : "white", here, shows)
            return holds(toward) && (!holds(away) || standing(toward, under) >= standing(away, under)) ? toward : away
        }
        // A see-through fill with text on it, carried toward another color
        // until the side the text is on reads on it as well as the text does
        // on the palette's own fill on the stock surface. Such a fill shows
        // the surface through it, and one far lighter or darker than the
        // palette's can take away the edge the text needs.
        function heldUnder(fillColor, toward, c, paletteFill) {
            if (!adaptive)
                return fillColor
            const side = ColorUtils.relativeLuminance(tone(c)) > ColorUtils.relativeLuminance(laid(fillColor, backdrops[0])) ? "white" : "black"
            const need = Math.min(textContrast, stockOn(c, paletteFill))
            return ColorUtils.mixUntil(fillColor, toward, f => ColorUtils.contrastRatio(side, laid(f, backdrops[0])) >= need - 0.01)
        }
        // A hover fill that takes the place of a resting one, set off it as
        // far as the palette's own pair stands apart on the stock surface, or
        // the pointer on it does not show. It is carried away from the side
        // the text on it is drawn in, which only helps the text; where that
        // end is not far enough, toward the text's side, as long as the text
        // still reads there and the button still stands off the surface as a
        // mark, or as far as the palette's hover does where that is less.
        // One already set off the resting fill can still sit too close to the
        // surface, and is then carried off the surface until it stands as a
        // mark as well, where the text on it still reads.
        function apartFrom(fillColor, rest, c, paletteFill, paletteRest) {
            if (!holdsFills || !adaptive)
                return fillColor
            const restHere = laid(rest, backdrops[0])
            const shows = ColorUtils.contrastRatio(laid(onStock(paletteFill), stockBackdrops[0]),
                laid(onStock(paletteRest), stockBackdrops[0]))
            const apart = f => ColorUtils.contrastRatio(laid(f, backdrops[0]), restHere) >= shows - 0.01
            const light = ColorUtils.relativeLuminance(tone(c)) > ColorUtils.relativeLuminance(laid(fillColor, backdrops[0]))
            const need = Math.min(textContrast, stockOn(c, paletteFill))
            const reads = f => ColorUtils.contrastRatio(light ? "white" : "black", laid(f, backdrops[0])) >= need - 0.01
            const standsOff = Math.min(markContrast, standing(onStock(paletteFill), stockBackdrops[0]))
            const stands = f => standing(f, backdrops[0]) >= standsOff - 0.01
            if (apart(fillColor)) {
                if (stands(fillColor))
                    return fillColor
                const off = ColorUtils.relativeLuminance(laid(fillColor, backdrops[0]))
                    > ColorUtils.relativeLuminance(backdrops[0]) ? "white" : "black"
                const firmer = ColorUtils.mixUntil(fillColor, off, f => stands(f) && apart(f))
                return stands(firmer) && apart(firmer) && reads(firmer) ? firmer : fillColor
            }
            const away = ColorUtils.mixUntil(fillColor, light ? "black" : "white", apart)
            const toward = ColorUtils.mixUntil(fillColor, light ? "white" : "black", apart)
            return !apart(away) && apart(toward) && reads(toward) && stands(toward) ? toward : away
        }
        // A mark drawn on one of the fills rather than on the surface, held
        // as text on a fill is, up to what a mark needs.
        function markOnFill(c, fillColor, paletteFill) {
            return heldOn(accent(c), c, [fillColor], [paletteFill], markContrast)
        }
        // The subtext where it is read rather than glanced at, as a result's
        // type or an empty list's message is, held as text is, up to what the
        // palette gives it on the stock surface.
        readonly property color colSubtextRead: held(palette.colSubtext,
            across(palette.colSubtext, colOnLayer0, palette.colOnLayer0), colOnLayer0, textContrast, false)
        // The accent where it is read as letters rather than seen as a mark,
        // as the launcher's match highlight is.
        readonly property color colPrimaryInk: ink(palette.colPrimary)
        // A toggled button's accent under the pointer, and the icon on it,
        // which lies on the accent and on that. The hover wash is a little
        // see-through, so it is held where the surface shows through it, and
        // then set off the accent it takes the place of. The icon starts
        // from its own tone rather than a place across the surface, since it
        // is read against the accent.
        readonly property color colPrimaryToggleHover: apartFrom(
            heldUnder(colPrimaryHover, colPrimary, palette.colOnPrimary, palette.colPrimaryHover),
            colPrimary, palette.colOnPrimary, palette.colPrimaryHover, palette.colPrimary)
        readonly property color colOnPrimaryToggle: heldOn(colOnPrimary, palette.colOnPrimary,
            [colPrimary, colPrimaryToggleHover], [palette.colPrimary, palette.colPrimaryHover], textContrast)
        readonly property color colPrimaryContainer: fill(palette.colPrimaryContainer, m3onSurface, m3.m3onSurface)
        readonly property color colPrimaryContainerActive: flash(palette.colPrimaryContainerActive, m3onSurface, m3.m3onSurface)
        readonly property color colOnPrimaryContainer: onFill(palette.colOnPrimaryContainer, colPrimaryContainer, palette.colPrimaryContainer)
        // What a pointer press spreads over the picked row, and the row's
        // text, which lies on both while the ripple spreads.
        readonly property color colPrimaryContainerRipple: ripple(palette.colPrimaryContainerActive, colPrimaryContainerActive,
            colPrimaryContainer, palette.colPrimaryContainer, colOnPrimaryContainer, palette.colOnPrimaryContainer,
            backdrops[0], stockBackdrops[0])
        readonly property color colOnPrimaryContainerActive: onFills(palette.colOnPrimaryContainer,
            [[colPrimaryContainer, colPrimaryContainerRipple], colPrimaryContainer],
            [[palette.colPrimaryContainer, palette.colPrimaryContainerActive], palette.colPrimaryContainer])
        // Pressed from the keyboard with the pointer elsewhere, only the
        // pressed fill is painted.
        readonly property color colOnPrimaryContainerPressed: onFill(palette.colOnPrimaryContainer, colPrimaryContainerActive, palette.colPrimaryContainerActive)
        // A row pressed without being picked, as a touch presses it, keeps
        // its resting text and match letters, held on the ripple's color
        // painted under it.
        readonly property color m3onSurfaceOnRipple: onFill(m3.m3onSurface, colPrimaryContainerRipple, palette.colPrimaryContainerActive)
        readonly property color colSubtextOnRipple: onFill(palette.colSubtext, colPrimaryContainerRipple, palette.colPrimaryContainerActive)
        readonly property color colPrimaryInkOnRipple: heldOn(colPrimaryInk, palette.colPrimary,
            [colPrimaryContainerRipple], [palette.colPrimaryContainerActive], textContrast)
        // Pressed from the keyboard while the focus sits on one of its
        // actions, the row is not picked either, and paints the pressed fill.
        readonly property color m3onSurfacePressed: onFill(m3.m3onSurface, colPrimaryContainerActive, palette.colPrimaryContainerActive)
        readonly property color colSubtextPressed: onFill(palette.colSubtext, colPrimaryContainerActive, palette.colPrimaryContainerActive)
        readonly property color colPrimaryInkPressed: heldOn(colPrimaryInk, palette.colPrimary,
            [colPrimaryContainerActive], [palette.colPrimaryContainerActive], textContrast)
        // The accent laid on the picked row, as the copied entry's check is,
        // and the check drawn on it, which crosses with it where it crosses.
        // A press paints fills set apart from the resting one, and no one
        // accent need stand off all of them, so each press holds its own on
        // the fills it paints, as the row's text does.
        readonly property color colPrimaryOnContainer: markOnFill(palette.colPrimary, colPrimaryContainer, palette.colPrimaryContainer)
        readonly property color colOnPrimaryOnContainer: onFill(palette.colOnPrimary, colPrimaryOnContainer, palette.colPrimary)
        readonly property color colPrimaryOnContainerPressed: markOnFill(palette.colPrimary, colPrimaryContainerActive, palette.colPrimaryContainerActive)
        readonly property color colOnPrimaryOnContainerPressed: onFill(palette.colOnPrimary, colPrimaryOnContainerPressed, palette.colPrimary)
        // A pointer press spreads the ripple over the hover fill, and one
        // that does not hover the row paints the ripple's color under it.
        readonly property color colPrimaryOnContainerActive: heldOn(accent(palette.colPrimary), palette.colPrimary,
            [colPrimaryContainer, [colPrimaryContainer, colPrimaryContainerRipple], colPrimaryContainerRipple],
            [palette.colPrimaryContainer, [palette.colPrimaryContainer, palette.colPrimaryContainerActive],
                palette.colPrimaryContainerActive], markContrast)
        readonly property color colOnPrimaryOnContainerActive: onFill(palette.colOnPrimary, colPrimaryOnContainerActive, palette.colPrimary)
        readonly property color colSecondary: accent(palette.colSecondary)
        // An action button's washes are laid on the picked row rather than
        // the surface, so the row is what they have to stand off, the press
        // by contrast alone as a pressed fill is.
        readonly property color pickedRow: ColorUtils.composite(colPrimaryContainer, backdrops[0])
        readonly property color stockPickedRow: ColorUtils.composite(onStock(palette.colPrimaryContainer), stockBackdrops[0])
        readonly property color colActionHover: holdsFills ? standOff(palette.colSecondaryContainerHover, colSecondaryContainerHover,
            m3onSurface, pickedRow, stockPickedRow) : colSecondaryContainerHover
        readonly property color colActionActive: holdsFills ? heldOff(palette.colSecondaryContainerActive, colSecondaryContainerActive,
            m3onSurface, pickedRow, stockPickedRow) : colSecondaryContainerActive
        // A picked row's text where an action button on it lays its hover
        // wash under the text rather than the row's own fill, and its press
        // spreads as a ripple over that wash.
        readonly property color colOnActionHover: onFill(palette.colOnPrimaryContainer, colActionHover, palette.colSecondaryContainerHover)
        readonly property color colActionRipple: ripple(palette.colSecondaryContainerActive, colActionActive, colActionHover,
            palette.colSecondaryContainerHover, colOnActionHover, palette.colOnPrimaryContainer, pickedRow, stockPickedRow)
        readonly property color colOnActionActive: onFills(palette.colOnPrimaryContainer,
            [[colActionHover, colActionRipple], colActionHover],
            [[palette.colSecondaryContainerHover, palette.colSecondaryContainerActive], palette.colSecondaryContainerHover])
        // Layer 0 text on a hovered, pressed or drop-target tile, which is
        // laid with these fills rather than left on the surface.
        readonly property color colOnLayer0Hover: onFill(palette.colOnLayer0, colSecondaryContainer, palette.colSecondaryContainer)
        readonly property color colOnLayer0Active: onFill(palette.colOnLayer0, colSecondaryContainerActive, palette.colSecondaryContainerActive)
        readonly property color colOnLayer0Drop: onFill(palette.colOnLayer0, ColorUtils.transparentize(colPrimary, 0.5),
            ColorUtils.transparentize(palette.colPrimary, 0.5))
        readonly property color colLayer0Border: dim(palette.colLayer0Border, colOnLayer0, palette.colOnLayer0)
        // A toolbar icon under the pointer sits on the hover wash, and a press
        // spreads the pressed wash over that as a ripple.
        readonly property color colOnSurfaceVariantHover: onFills(palette.colOnSurfaceVariant,
            [colLayer1Hover, [colLayer1Hover, colLayer1Active]], [palette.colLayer1Hover, [palette.colLayer1Hover, palette.colLayer1Active]])
        readonly property color colOnSurfaceVariantHigh: onFill(palette.colOnSurfaceVariant, colSurfaceContainerHigh, palette.colSurfaceContainerHigh)
        // What is typed into a field, and the hint before it, sit on the
        // field's own fill rather than on the surface around it. Where the
        // field allows it, the typed text goes a quarter past what the hint
        // needs, as an ink stands off its dimmed tone, so a query typed in
        // does not pass for the hint; the hint itself is not held back.
        readonly property real hintContrast: Math.min(textContrast, stockOn(palette.colSubtext, palette.colLayer1))
        readonly property color colOnLayer1Field: onFill(palette.colOnLayer1, colLayer1, palette.colLayer1, 1.25 * hintContrast)
        readonly property color colSubtextField: onFill(palette.colSubtext, colLayer1, palette.colLayer1)
        readonly property color m3onSurfaceField: onFill(m3.m3onSurface, colLayer1, palette.colLayer1, 1.25 * hintContrast)
        // The hint's color is the palette's subtext under its m3 name.
        readonly property color m3outlineField: colSubtextField
        // The caret blinks on the field's fill as well, and the focus ring
        // runs along its edge, so both are held there as marks.
        readonly property color colPrimaryOnField: markOnFill(palette.colPrimary, colLayer1, palette.colLayer1)
        readonly property color colLayer2Hover: fill(palette.colLayer2Hover, colOnLayer2, palette.colOnLayer2)
        readonly property color colSurfaceContainerLow: fill(palette.colSurfaceContainerLow, m3onSurface, m3.m3onSurface)
        // The focused workspace's outline is drawn over the edge of its tile,
        // so the tile is what it has to stand off.
        readonly property color colSecondaryOnTile: markOnFill(palette.colSecondary, colSurfaceContainerLow, palette.colSurfaceContainerLow)
        // Its number, a faint wash of the ink, lies on the tile as well.
        readonly property color colTileNumber: faded(colOnLayer1, 0.2, colSurfaceContainerLow, palette.colSurfaceContainerLow)
        readonly property color colSurfaceContainerHigh: fill(palette.colSurfaceContainerHigh, m3onSurface, m3.m3onSurface)
        readonly property color m3onSurfaceVariant: ink(m3.m3onSurfaceVariant)
        // The palette's subtext is this very color, so the two are held as one.
        readonly property color m3outline: colSubtext
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
        // Every style starts from the same see-through, so picking a shape on
        // the style page never changes how solid the bar looks with it.
        readonly property real barStockAlpha: layer0StockAlpha
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
        // Every dock style, the notch and the Hug strip included, starts from
        // the strip's alpha, so picking a shape never changes how solid the
        // dock looks with it.
        readonly property real dockStockAlpha: layer0StockAlpha
        property color colDockBackground: surfaceColor(dockPick, colLayer0, Config.options?.dock.backgroundOpacity, dockStockAlpha)
        // The dock's surface is also drawn over the launcher's dim, as the
        // dock raised above it and as the app list, and each takes its
        // outline from the content drawn there.
        function surfaceBorder(outline, surface) {
            return ColorUtils.applyAlpha(ColorUtils.mix(outline, surface, 0.4), surface.a)
        }
        function dockBorder(outline) {
            return surfaceBorder(outline, colDockBackground)
        }
        property color colDockBackgroundBorder: dockBorder(root.dockContent.colOutlineVariant)
        property color colDockOverLauncherBorder: root.dockBorderOverDim(root.dockOverLauncherContent,
            root.wallpaperEdge(root.sizes.dockEdge), root.dockOwnShadow, root.dockOwnStockShadow)
        property color colDrawerBorder: root.dockBorderOverDim(root.drawerContent, root.wallpaperAverage,
            colDockShadow, root.dockStockShadow)
        property color colDockShadow: ColorUtils.applyAlpha(colShadow, colShadow.a * colDockBackground.a)
        readonly property string dockBadgePick: modePick(Config.options?.dock.badgeColorDark, Config.options?.dock.badgeColorLight)
        readonly property string dockBadgeTextPick: modePick(Config.options?.dock.badgeTextColorDark, Config.options?.dock.badgeTextColorLight)
        // The count badge sits on the icon to be read, not on the surface to
        // be seen through, so it keeps full strength however faint the dock
        // behind it is set.
        property color colDockBadge: dockBadgePick !== "" ? dockBadgePick : colPrimary
        property color colDockBadgeText: dockBadgeTextPick !== "" ? dockBadgeTextPick : m3colors.m3onPrimary
        // The launcher's panels take the dock's pick and transparency, as the
        // app list does by wearing the dock's surface outright, so a style
        // set on the style page reaches everything the launcher draws. Left
        // unpicked, they keep the palette's own container.
        // The panels and the dim take it only while their content is judged
        // against what it is drawn on: otherwise their text keeps the
        // palette's tones, which were chosen for the palette's own surface,
        // and a pick made for the dock can bury them where names are read.
        readonly property string launcherPick: root.autoIconContrast ? dockPick : ""
        readonly property real launcherOpacity: root.autoIconContrast ? (Config.options?.dock.backgroundOpacity ?? -1) : -1
        property color colLauncherPanel: surfaceColor(launcherPick, m3colors.m3surfaceContainer, launcherOpacity, layer0StockAlpha)
        // Drawn under the whole panel, so a see-through one shows it as a
        // gray slab. It keeps its full strength under the stock panel and
        // anything more solid, and fades with a fainter one, as the dock's
        // does with the dock.
        property color colLauncherShadow: ColorUtils.applyAlpha(colShadow, colShadow.a
            * (layer0StockAlpha > 0 ? Math.min(1, colLauncherPanel.a / layer0StockAlpha) : 1))
        // What shows through a near-white layer reads as less than the same
        // share through a near-black one, so light mode lets a little more of
        // the frosted windows through to look as open.
        readonly property real launcherDimOpacity: m3colors.darkmode ? 0.90 : 0.85
        // A fifth of the way to the pick reads plainly in its hue, and it is
        // about as far as the dim can go before a white pick in dark mode
        // leaves the palette's text under 7:1 on it. Past that the dim stops
        // reading as the mode's backdrop and starts reading as the pick's.
        readonly property real launcherDimTint: 0.2
        property color colLauncherDim: launcherPick !== "" ? ColorUtils.mix(launcherPick, colLayer0Base, launcherDimTint) : colLayer0Base
        // The dim's window is cleared to a faint black under the dim, and the
        // launcher is laid over that as well, so the window and the backdrop
        // its content is judged against both take it from here.
        readonly property color colLauncherDimWindow: Qt.rgba(0, 0, 0, 0.01)
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
        // The Hug strip has no corner of its own: the only curve it shows is
        // the screen's rounding, carried round where each end meets the
        // desktop, so that is what matches it.
        // That curve goes square with the bar's own: a Rect bar, which is what
        // turning Rounded Corners off makes of it, leaves both strips square,
        // and the curves come back with the bar's.
        readonly property real dockSpanCorner: Config.options?.bar.cornerStyle === 2 ? 0 : screenRounding
        readonly property real dockBody: root.sizes.dockSpans ? dockSpanCorner
            : (Config.options?.dock.cornerStyle ?? "float") !== "float" ? dockTop : dock
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

    // Whether the shell's bar is up, as the shell last left it in a runtime
    // file. Settings and the Welcome app are processes of their own and never
    // see the bar put away, so this is how the dock's edge rule below reaches
    // the same answer in them as on screen. With no word from the shell the
    // bar is taken to be up. The shell itself answers first hand instead (see
    // GlobalStates), so a toggle is never undone by a write still landing.
    readonly property string barStatePath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/quickshell-bar.state`
    property bool barShownOnFile: true
    FileView {
        id: barStateView
        path: root.barStatePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.barShownOnFile = barStateView.text().trim() !== "hidden"
        onLoadFailed: root.barShownOnFile = true
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
        property string barEdge: root.sizes.barEdgeFor(Config.options.bar.bottom, Config.options.bar.vertical)
        function barEdgeFor(bottom, vertical) {
            return vertical ? (bottom ? "right" : "left") : (bottom ? "bottom" : "top");
        }
        function oppositeEdge(edge) {
            return ({ top: "bottom", bottom: "top", left: "right", right: "left" })[edge] ?? "bottom";
        }
        // The Hug dock runs the whole length of its edge, so it fits only
        // along the edge facing the bar: on either side of the bar it would
        // run across the bar's ends. With the bar put away there is nothing
        // to cross, and any edge will do. Every process goes by the shell's
        // word on whether its bar is up (barShownOnFile above).
        readonly property bool dockSpans: Config.options?.dock.cornerStyle === "span"
        property bool barShown: root.barShownOnFile
        property string dockEdge: {
            const flip = { top: "bottom", bottom: "top", left: "right", right: "left" };
            // config.json is hand-editable and every consumer picks its edge by
            // negation, so an unrecognised value would anchor the dock to all
            // four edges at once instead of falling back to one.
            const want = flip[Config.options.dock.position] ? Config.options.dock.position : "bottom";
            if (root.sizes.dockSpans)
                return root.sizes.barShown ? flip[root.sizes.barEdge] : want;
            return want === root.sizes.barEdge ? flip[want] : want;
        }
        // Whether the dock may be set on an edge in the style it has now.
        function dockEdgeAllowed(edge) {
            return !root.sizes.dockSpans || !root.sizes.barShown
                || edge === root.sizes.oppositeEdge(root.sizes.barEdge);
        }
        // Every page that moves the bar or the dock, or changes the dock's
        // style, does it through these three, so the Hug dock is carried
        // across with the bar however the bar was moved. The saved edge is
        // kept as the one on screen, so the next style starts from it rather
        // than from wherever the dock was before it hugged.
        function placeBar(bottom, vertical) {
            // A Hug dock facing the bar keeps facing it even while the bar is
            // put away. Left behind, it would share the bar's new edge and be
            // sent across the screen each time the bar came and went. One set
            // on another edge while the bar was away keeps that edge.
            const follows = root.sizes.dockSpans
                && root.sizes.dockEdge === root.sizes.oppositeEdge(root.sizes.barEdge);
            Config.options.bar.bottom = bottom;
            Config.options.bar.vertical = vertical;
            if (follows)
                Config.options.dock.position = root.sizes.oppositeEdge(root.sizes.barEdgeFor(bottom, vertical));
        }
        function placeDock(edge) {
            if (!root.sizes.dockEdgeAllowed(edge))
                return;
            if (edge === root.sizes.barEdge) {
                // The bar's own edge is on offer like any other, and asking for
                // it sends the bar across to the far side of its axis rather
                // than refusing. The bar moves first, so the two are never both
                // claiming this edge and the dock is not briefly flipped away
                // from what was just asked.
                Config.options.bar.bottom = !Config.options.bar.bottom;
                Config.options.dock.position = edge;
            } else if (!Config.options.dock.enable || edge !== root.sizes.dockEdge) {
                // Re-picking the edge already shown is a no-op, and writing it
                // would overwrite a saved edge the bar is only borrowing: the
                // dock would stay put once the bar moved away.
                Config.options.dock.position = edge;
            }
            Config.options.dock.enable = true;
        }
        function setDockStyle(style) {
            const onScreen = root.sizes.dockEdge;
            const previous = Config.options.dock.cornerStyle;
            Config.options.dock.cornerStyle = style;
            if (style === "span")
                Config.options.dock.position = root.sizes.barShown
                    ? root.sizes.oppositeEdge(root.sizes.barEdge) : onScreen;
            else if (previous === "span")
                Config.options.dock.position = onScreen;
        }
        // A style picked in Settings, where each style keeps the roundness it
        // was last given. Float rounds all four corners alike and Rect only
        // shapes the pair facing the desktop, so each style is asked for a
        // different pair and only those are carried out and back in. Hug has
        // no corner of its own to keep. The Welcome app sets styles as presets
        // through setDockStyle instead.
        function pickDockStyle(style) {
            const dock = Config.options.dock;
            const previous = dock.cornerStyle;
            if (previous === style)
                return;
            if (previous === "float")
                dock.radiusFloat = dock.radius;
            else if (previous === "rect")
                dock.topRadiusRect = dock.topRadius;
            else if (previous !== "span") {
                dock.radiusNotch = dock.radius;
                dock.topRadiusNotch = dock.topRadius;
            }
            root.sizes.setDockStyle(style);
            if (style === "float") {
                if (dock.radiusFloat >= -1)
                    dock.radius = dock.radiusFloat;
            } else if (style === "rect") {
                if (dock.topRadiusRect >= -1)
                    dock.topRadius = dock.topRadiusRect;
            } else if (style !== "span") {
                if (dock.radiusNotch >= -1)
                    dock.radius = dock.radiusNotch;
                if (dock.topRadiusNotch >= -1)
                    dock.topRadius = dock.topRadiusNotch;
            }
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
        // The size a dock left alone shows. The Hug dock runs end to end like
        // a taskbar, so it starts smaller and stays a slim strip.
        readonly property real dockIconDefault: root.sizes.dockSpans ? 27 : root.sizes.dockIconStock
        // The size asked for. A dock shows this or the largest size its own
        // screen can run edge to edge, whichever is smaller, so this stays
        // exactly what was asked for and the slider and the file keep one
        // meaning on every screen.
        property real dockIconSize: (Config.options?.dock.iconSize ?? -1) >= 0
            ? Config.options.dock.iconSize : root.sizes.dockIconDefault
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
        readonly property real dockHoverMagnifyStock: Config.options?.dock.hoverEffect === "glow" ? 25 : 100
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
        // Where notification popups sit, read by the popup and by the picker in
        // Settings so the spot shown picked is always the one in use. A
        // hand-edited value neither knows lands on the stock corner.
        readonly property string notificationPosition: ["top_left", "top_center", "top_right", "bottom_left", "bottom_center", "bottom_right"]
            .includes(Config.options?.notifications.position) ? Config.options.notifications.position : "top_right"
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
