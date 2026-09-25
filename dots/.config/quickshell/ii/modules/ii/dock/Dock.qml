import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Io
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property bool pinned: Config.options?.dock.pinnedOnStartup ?? false
    onPinnedChanged: GlobalStates.dockPinned = root.pinned
    Component.onCompleted: GlobalStates.dockPinned = root.pinned

    Variants {
        // For each monitor
        model: Quickshell.screens

        Scope {
            id: perScreen
            required property var modelData

            Loader {
                id: dockWindowLoader
                active: true
                // The window is recreated when the edge changes: layer-shell
                // fixes a surface's namespace (and with it the slide-direction
                // rule) at creation, and a live ListView does not survive an
                // orientation flip - delegates keep their old-axis positions.
                property string edge: Appearance.sizes.dockEdge
                onEdgeChanged: {
                    active = false;
                    // A single config write can move the dock and disable it at
                    // once, tearing this Loader down before the turn ends.
                    Qt.callLater(() => { if (dockWindowLoader) dockWindowLoader.active = true; });
                }
                sourceComponent: PanelWindow {
                    id: dockRoot
                    // Window
                    screen: perScreen.modelData
                    visible: !GlobalStates.screenLocked

            // The dock never shares an edge with the bar: a dock stacked on
            // it gets displaced by the bar's exclusive zone and the hover
            // strip lands on the bar instead of the screen edge. The shared
            // resolver flips a configured edge the bar holds.
            readonly property string dockEdge: Appearance.sizes.dockEdge
            // Which corners face the screen and which face the desktop, and
            // whether the pair on the edge curves outward into it.
            // Every style but float sets the dock down on the edge. Between the
            // notch ("hug") and rect what differs is the pair of corners that
            // touches it, curving outward or squared off, and the pair facing
            // the desktop keeps its own roundness either way. The Hug strip
            // ("span") reaches both ends of the edge and has no such pair.
            readonly property bool dockHugging: Config.options.dock.cornerStyle !== "float"
            readonly property bool dockFlares: Config.options.dock.cornerStyle === "hug"
            // The Hug strip is drawn the way the Hug bar draws its own: flush
            // and square along the whole edge, with the screen's rounding
            // carried round each end where the strip meets the desktop.
            readonly property bool dockSpans: Appearance.sizes.dockSpans
            readonly property real spanCorner: Appearance.rounding.dockSpanCorner
            // Those curves reach further from the strip than the room the
            // other styles keep beside their body, so the part that slides is
            // made thicker by the difference, and hidden, they leave the
            // screen with the rest of it.
            readonly property real spanOverhang: dockSpans
                ? Math.max(0, spanCorner - Appearance.sizes.elevationMargin) : 0
            // The strip's outline overlaps its fill, which only shows through
            // a see-through surface, and there the two are painted opaque and
            // faded together the way the notch's pieces are.
            readonly property bool spanSeamFix: dockSpans && Config.options.dock.showBackground
                && Appearance.colors.colDockBackground.a < 1
            // Only the notch draws pieces beside the body, so only it needs the
            // group flattened before the surface is faded, and only it needs the
            // room outside the body that those pieces occupy.
            // The lap the fix hides only shows through a see-through surface,
            // so a fully opaque one skips the flattening pass and its texture.
            readonly property bool notchSeamFix: dockFlares && Config.options.dock.showBackground
                && Appearance.colors.colDockBackground.a < 1
            readonly property real flareBleed: notchSeamFix ? Appearance.rounding.dock : 0
            // How far each curve laps over the body. One covers the hairline a
            // fractional scale can leave between them; the body's outline is a
            // pixel of its own, so the lap has to clear that too or a stub of it
            // is left standing at the join.
            readonly property int flareLap: 1 + (Config.options.dock.showBackground ? 1 : 0)
            // The screen gap sits on the edge side, the shadow's breathing room
            // on the center side. Hugging leaves no gap on the edge side: the
            // concave corners have nothing to curve into if the dock floats
            // away from it.
            readonly property real edgeGap: dockHugging ? 0 : Appearance.sizes.hyprlandGapsOut
            // The room between the body and the desktop-facing side of the
            // part that slides, which the Hug strip's curves hang in.
            readonly property real deskInset: Appearance.sizes.elevationMargin + spanOverhang
            // The Hug strip runs a pixel past both ends of the window, so the
            // screen's own sides never show an edge of it.
            readonly property real endInset: dockSpans ? -1 : flareBleed
            // Where the body sits inside its group, said once for the body and
            // for the shade that follows it, the two no longer sharing an
            // anchor. The group's bleed only exists on the sides the curves
            // hang from, so it is only given back there.
            readonly property real bodyInsetTop: (dockEdge === "top" ? edgeGap : dockVertical ? 0 : deskInset) + (dockVertical ? endInset : 0)
            readonly property real bodyInsetBottom: (dockEdge === "bottom" ? edgeGap : dockVertical ? 0 : deskInset) + (dockVertical ? endInset : 0)
            readonly property real bodyInsetLeft: (dockEdge === "left" ? edgeGap : dockVertical ? deskInset : 0) + (dockVertical ? 0 : endInset)
            readonly property real bodyInsetRight: (dockEdge === "right" ? edgeGap : dockVertical ? deskInset : 0) + (dockVertical ? 0 : endInset)
            readonly property real deskRadius: Appearance.rounding.dockBody
            // Set down on the edge, the corners meeting it are square, whether
            // a curve is drawn beside them or not. Floating, they are the same
            // roundness as the rest of the body.
            readonly property real edgeCornerRadius: dockHugging ? 0 : deskRadius
            readonly property bool dockVertical: dockEdge === "left" || dockEdge === "right"
            // The center-facing side as an Edges value — where popups open.
            readonly property int awayEdges: dockEdge === "bottom" ? Edges.Top
                : dockEdge === "top" ? Edges.Bottom
                : dockEdge === "left" ? Edges.Right : Edges.Left

            property bool reveal: root.pinned || (Config.options?.dock.hoverToReveal && dockMouseArea.containsMouse) || dockApps.requestDockShow || (!ToplevelManager.activeToplevel?.activated) || GlobalStates.overviewOpen || revealGrace.running

            // The dock is raised above the launcher's dim while the launcher
            // is open, and there it takes the colors that read over the dim.
            // Only on the screen the dim is shown on: a dock on another screen
            // keeps its own.
            readonly property DockContent content: DockContent {
                dimmed: GlobalStates.launcherDimScreens.includes(dockRoot.screen?.name ?? "")
            }
            // The content colors as this dock draws them. A button's fill
            // already eases to a new color on the curve the dim fades on, so
            // the buttons take theirs the moment the dim starts and ease with
            // it; the rest pass across on the same curve, and all of it lands
            // with the dim.
            component DockContent: QtObject {
                property bool dimmed: false
                property real over: dimmed ? 1 : 0
                Behavior on over {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                readonly property var rest: Appearance.dockContent
                readonly property var overDim: Appearance.dockOverLauncherContent
                readonly property var settled: dimmed ? overDim : rest
                function blend(atRest, onDim) {
                    return over <= 0 ? atRest : over >= 1 ? onDim : ColorUtils.mix(onDim, atRest, over)
                }
                readonly property color colOnLayer0: blend(rest.colOnLayer0, overDim.colOnLayer0)
                readonly property color m3onPrimary: blend(rest.m3onPrimary, overDim.m3onPrimary)
                readonly property color colPrimary: blend(rest.colPrimary, overDim.colPrimary)
                readonly property color colOutlineVariant: blend(rest.colOutlineVariant, overDim.colOutlineVariant)
                readonly property color colLayer1: blend(rest.colLayer1, overDim.colLayer1)
                // A folder's outline runs around its tile, so the tile is what
                // it has to stand off.
                readonly property color colLayer0BorderOnLayer1: blend(rest.colLayer0BorderOnLayer1, overDim.colLayer0BorderOnLayer1)
                // The window marks of an app that is not the focused one.
                readonly property color colMarkFaint: blend(rest.faded(rest.colOnLayer0, 0.6),
                    overDim.faded(overDim.colOnLayer0, 0.6))
                readonly property color colBorder: blend(Appearance.colors.colDockBackgroundBorder,
                    Appearance.colors.colDockOverLauncherBorder)
                // The notched dock carries its own alpha on the container rather
                // than on each piece, so the outline goes on opaque there and is
                // let down with everything else, which keeps it from being faded
                // twice.
                readonly property color colBorderOpaque: Qt.rgba(colBorder.r, colBorder.g, colBorder.b, 1)
            }

            anchors {
                top: dockRoot.dockEdge !== "bottom"
                bottom: dockRoot.dockEdge !== "top"
                left: dockRoot.dockEdge !== "right"
                right: dockRoot.dockEdge !== "left"
            }

            // How much of this screen the row may run along. The surface is
            // anchored to both ends of its axis, so the compositor has already
            // sized it to the whole output; asking for more is ignored rather
            // than honored, and anything past it is never painted and never
            // clickable. Room another panel has reserved along the same axis
            // comes off, since the dock does not get that either.
            readonly property var monitorData: HyprlandData.monitors.find(m => m.name === dockRoot.screen?.name)
            readonly property real axisBudget: {
                const reserved = dockRoot.monitorData?.reserved ?? [0, 0, 0, 0];
                const along = dockRoot.dockVertical ? ((reserved[1] ?? 0) + (reserved[3] ?? 0)) : ((reserved[0] ?? 0) + (reserved[2] ?? 0));
                const extent = dockRoot.dockVertical ? (dockRoot.screen?.height ?? 0) : (dockRoot.screen?.width ?? 0);
                return extent - along - Appearance.sizes.hyprlandGapsOut * 2;
            }

            // The row is one line, so its length is first degree in the icon
            // size: a part that never moves, and a count of slots that each
            // grow a pixel for every pixel of icon. That is what lets a screen
            // too short for the row solve for the size that fits instead of
            // measuring one. It cannot measure: the row's length is what sizes
            // the things inside it, so reading it back closes a ring, and the
            // ring is animated, so it would settle as a pulse rather than fail
            // as an error. The constants below mirror the row further down and
            // are named for the lines they come from.
            readonly property int appButtonCount: TaskbarApps.apps.filter(a => a?.appId !== "SEPARATOR").length
            readonly property int hairlineCount: TaskbarApps.apps.length - dockRoot.appButtonCount
            readonly property real fittedIconSize: {
                const showPin = Config.options?.dock.showPinButton ?? true;
                const showOverview = Config.options?.dock.showOverviewButton ?? true;
                // Each app button runs 15 past its icon, from the dock's own
                // thickness less the row padding, and carries listView.spacing
                // twice. The ends bring a hairline and two dockRow gaps each,
                // and the overview button its own 15. Plus the row padding and
                // the one hairline inside the list.
                const perButton = 17;
                const fixed = 5 * 2 + 1 + dockRoot.appButtonCount * perButton + dockRoot.hairlineCount * 3 + (showPin ? 1 + 6 : 0) + (showOverview ? 15 + 1 + 6 : 0);
                const slots = (showPin ? 1 : 0) + (showOverview ? 1 : 0) + dockRoot.appButtonCount;
                if (slots <= 0)
                    return Appearance.sizes.dockIconSize;
                const room = Math.floor((dockRoot.axisBudget - fixed) / slots);
                return Math.max(Appearance.sizes.dockIconMin, Math.min(Appearance.sizes.dockIconSize, room));
            }

            // The dock's visible thickness plus its screen gap, and for the Hug
            // strip the reach of its curves; the headroom below is added on
            // the center-facing side so magnified icons can overflow without
            // window clipping.
            readonly property real dockExtent: Appearance.sizes.dockExtentFor(dockRoot.fittedIconSize) + dockRoot.spanOverhang

            // Reached in one step rather than crossed over several frames. This
            // is half of the window's own thickness, and the other half moves at
            // once, so spreading this half out buys no smoothness: it only turns
            // one resize of the layer surface into one per frame. Each of those
            // is answered by the compositor with events that land here as a
            // fresh monitor list, and a fresh list re-solves the fit of every
            // dock on every screen, so a screen narrow enough for its icons to
            // actually resize takes all the others down with it.
            readonly property real magnifyHeadroom: Appearance.sizes.dockMagnifyHeadroomFor(dockRoot.fittedIconSize)

            exclusiveZone: root.pinned ? Appearance.sizes.dockHeightFor(dockRoot.fittedIconSize) + Appearance.sizes.hyprlandGapsOut : 0

            Component.onCompleted: {
                GlobalFocusGrab.addPersistent(dockRoot);
            }
            Component.onDestruction: {
                GlobalFocusGrab.removePersistent(dockRoot);
            }

            // Keep revealed briefly after the overview closes: its full-screen
            // surface steals the dock's hover, so containsMouse is stale-false
            // at close and `reveal` would collapse before the pointer re-enters.
            Timer { id: revealGrace; interval: 600 }
            Connections {
                target: GlobalStates
                function onOverviewOpenChanged() {
                    if (!GlobalStates.overviewOpen) revealGrace.restart();
                }
            }

            implicitWidth: dockRoot.dockVertical ? dockRoot.dockExtent + dockRoot.magnifyHeadroom : dockBackground.implicitWidth
            implicitHeight: dockRoot.dockVertical ? dockBackground.implicitHeight : dockRoot.dockExtent + dockRoot.magnifyHeadroom
            WlrLayershell.namespace: "quickshell:dock" + (dockRoot.dockEdge === "bottom" ? ""
                : dockRoot.dockEdge.charAt(0).toUpperCase() + dockRoot.dockEdge.slice(1))
            WlrLayershell.layer: GlobalStates.overviewOpen ? WlrLayer.Overlay : WlrLayer.Top
            color: "transparent"

            mask: Region {
                item: dockRoot.dockSpans ? spanStripMask : dockMouseArea
                Region { item: dockRoot.dockSpans ? spanIconBand : null }
                Region { item: dockRoot.dockSpans && Config.options.dock.hoverToReveal ? spanRevealSliver : null }
            }

            // How far along the edge the icons reach, with the room every
            // other style keeps at either end of them.
            readonly property real spanIconLength: (dockVertical ? dockHoverRegion.implicitHeight : dockHoverRegion.implicitWidth)
                + Appearance.sizes.elevationMargin * 2
            // Without its surface the Hug strip is only its icons, so it takes
            // the pointer only as far along the edge as they reach, the way
            // every other style does, rather than across an edge that shows
            // nothing.
            readonly property real spanInputLength: Config.options.dock.showBackground ? -1 : spanIconLength
            // Where a run this long starts, centered in that much room and
            // rounded the way anchors round a centered item, so what takes the
            // pointer lines up to the pixel with the icons and with the other
            // styles, whose part that slides is centered by anchors.
            function spanCentered(room, length) {
                const half = size => Math.trunc(size) % 2 ? (size + 1) / 2 : size / 2;
                return half(room) - half(length);
            }
            // The Hug strip takes the pointer on the strip itself. The room the
            // other styles keep around their body would run the whole length
            // of the screen here and take clicks meant for the windows beside
            // it, so that room is kept only beside the icons, below. Bound to
            // the part that slides rather than placed inside it, since a
            // region follows only its own item's geometry.
            Item {
                id: spanStripMask
                readonly property real along: dockRoot.spanInputLength >= 0 ? dockRoot.spanInputLength
                    : dockRoot.dockVertical ? dockMouseArea.height : dockMouseArea.width
                x: dockMouseArea.x + (dockRoot.dockVertical
                    ? (dockRoot.dockEdge === "right" ? dockRoot.deskInset : 0)
                    : dockRoot.spanCentered(dockMouseArea.width, along))
                y: dockMouseArea.y + (dockRoot.dockVertical
                    ? dockRoot.spanCentered(dockMouseArea.height, along)
                    : (dockRoot.dockEdge === "bottom" ? dockRoot.deskInset : 0))
                width: dockRoot.dockVertical ? dockMouseArea.width - dockRoot.deskInset : along
                height: dockRoot.dockVertical ? along : dockMouseArea.height - dockRoot.deskInset
            }
            // The room every other style keeps on the desktop side of its body,
            // here only alongside the icons, so the pointer leaves the dock,
            // and a magnified icon stops taking clicks, as far out as on any
            // other style.
            Item {
                id: spanIconBand
                readonly property real reach: Appearance.sizes.elevationMargin
                x: dockMouseArea.x + (dockRoot.dockVertical
                    ? (dockRoot.dockEdge === "right" ? dockRoot.deskInset - reach : dockMouseArea.width - dockRoot.deskInset)
                    : dockRoot.spanCentered(dockMouseArea.width, dockRoot.spanIconLength))
                y: dockMouseArea.y + (dockRoot.dockVertical
                    ? dockRoot.spanCentered(dockMouseArea.height, dockRoot.spanIconLength)
                    : (dockRoot.dockEdge === "bottom" ? dockRoot.deskInset - reach : dockMouseArea.height - dockRoot.deskInset))
                width: dockRoot.dockVertical ? reach : dockRoot.spanIconLength
                height: dockRoot.dockVertical ? dockRoot.spanIconLength : reach
            }
            // Hidden, the strip has left the screen, and this is the sliver
            // along the edge the pointer brings it back from. It stays while
            // the strip slides in, so the pointer holding it open is never
            // left outside the window on the way.
            Item {
                id: spanRevealSliver
                readonly property real reach: Config.options.dock.hoverRegionHeight
                readonly property real along: dockRoot.spanInputLength >= 0 ? dockRoot.spanInputLength
                    : dockRoot.dockVertical ? parent.height : parent.width
                x: dockRoot.dockVertical ? (dockRoot.dockEdge === "right" ? parent.width - reach : 0)
                    : dockRoot.spanCentered(parent.width, along)
                y: dockRoot.dockVertical ? dockRoot.spanCentered(parent.height, along)
                    : (dockRoot.dockEdge === "bottom" ? parent.height - reach : 0)
                width: dockRoot.dockVertical ? reach : along
                height: dockRoot.dockVertical ? along : reach
            }

            MouseArea {
                id: dockMouseArea
                // Offset from the window's center-facing side: past the
                // magnify headroom when revealed, and far enough to push the
                // strip off the screen edge when hidden — keeping only the
                // hover strip while hover-to-reveal is on. Shares the headroom
                // with the window above, since the two describe one edge.
                readonly property real slide: dockRoot.magnifyHeadroom + (dockRoot.reveal ? 1
                    : Config.options?.dock.hoverToReveal ? (dockRoot.dockExtent - Config.options.dock.hoverRegionHeight)
                    : (dockRoot.dockExtent + 1))

                anchors {
                    topMargin: dockRoot.dockEdge === "bottom" ? dockMouseArea.slide : 0
                    bottomMargin: dockRoot.dockEdge === "top" ? dockMouseArea.slide : 0
                    leftMargin: dockRoot.dockEdge === "right" ? dockMouseArea.slide : 0
                    rightMargin: dockRoot.dockEdge === "left" ? dockMouseArea.slide : 0
                }
                // AnchorChanges rather than conditional anchor bindings: a
                // live edge flip re-evaluates bindings one at a time, passing
                // through an illegal three-anchor state that Qt rejects and
                // leaves the layout wedged. States swap the whole set at once.
                states: [
                    State {
                        name: "edgeBottom"
                        when: dockRoot.dockEdge === "bottom"
                        AnchorChanges {
                            target: dockMouseArea
                            anchors { top: dockMouseArea.parent.top; bottom: undefined; left: undefined; right: undefined; horizontalCenter: dockMouseArea.parent.horizontalCenter; verticalCenter: undefined }
                        }
                    },
                    State {
                        name: "edgeTop"
                        when: dockRoot.dockEdge === "top"
                        AnchorChanges {
                            target: dockMouseArea
                            anchors { top: undefined; bottom: dockMouseArea.parent.bottom; left: undefined; right: undefined; horizontalCenter: dockMouseArea.parent.horizontalCenter; verticalCenter: undefined }
                        }
                    },
                    State {
                        name: "edgeLeft"
                        when: dockRoot.dockEdge === "left"
                        AnchorChanges {
                            target: dockMouseArea
                            anchors { top: undefined; bottom: undefined; left: undefined; right: dockMouseArea.parent.right; horizontalCenter: undefined; verticalCenter: dockMouseArea.parent.verticalCenter }
                        }
                    },
                    State {
                        name: "edgeRight"
                        when: dockRoot.dockEdge === "right"
                        AnchorChanges {
                            target: dockMouseArea
                            anchors { top: undefined; bottom: undefined; left: dockMouseArea.parent.left; right: undefined; horizontalCenter: undefined; verticalCenter: dockMouseArea.parent.verticalCenter }
                        }
                    }
                ]

                Behavior on anchors.topMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on anchors.bottomMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on anchors.leftMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on anchors.rightMargin {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                // The Hug strip runs the whole edge, so the part that slides
                // does too, and hovering anywhere along it keeps the dock up.
                width: dockRoot.dockVertical ? dockRoot.dockExtent : dockRoot.dockSpans ? parent.width : implicitWidth
                height: dockRoot.dockVertical ? (dockRoot.dockSpans ? parent.height : implicitHeight) : dockRoot.dockExtent
                implicitWidth: dockRoot.dockVertical ? dockRoot.dockExtent : dockHoverRegion.implicitWidth + Appearance.sizes.elevationMargin * 2
                implicitHeight: dockRoot.dockVertical ? dockHoverRegion.implicitHeight + Appearance.sizes.elevationMargin * 2 : dockRoot.dockExtent
                hoverEnabled: true

                Item {
                    id: dockHoverRegion
                    anchors.fill: parent
                    implicitWidth: dockBackground.implicitWidth
                    implicitHeight: dockBackground.implicitHeight

                    Item { // Wrapper for the dock background
                        id: dockBackground
                        states: [
                            State {
                                name: "horizontal"
                                when: !dockRoot.dockVertical
                                AnchorChanges {
                                    target: dockBackground
                                    anchors { top: dockBackground.parent.top; bottom: dockBackground.parent.bottom; left: undefined; right: undefined; horizontalCenter: dockBackground.parent.horizontalCenter; verticalCenter: undefined }
                                }
                            },
                            State {
                                name: "vertical"
                                when: dockRoot.dockVertical
                                AnchorChanges {
                                    target: dockBackground
                                    anchors { top: undefined; bottom: undefined; left: dockBackground.parent.left; right: dockBackground.parent.right; horizontalCenter: undefined; verticalCenter: dockBackground.parent.verticalCenter }
                                }
                            }
                        ]

                        implicitWidth: dockRow.implicitWidth + 5 * 2
                        implicitHeight: dockRow.implicitHeight + 5 * 2
                        width: dockRoot.dockVertical ? parent.width - Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut
                            : dockRoot.dockSpans ? parent.width : implicitWidth
                        height: dockRoot.dockVertical ? (dockRoot.dockSpans ? parent.height : implicitHeight)
                            : parent.height - Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut

                        // The shade stays out of the group. It is meant to be seen
                        // through, and its colour already carries the surface's alpha,
                        // so fading it again with the group would square that. It
                        // anchors to the group with the body's own insets, the body no
                        // longer being a sibling of this loader. The Hug strip casts
                        // none, lying flat along its edge the way the Hug bar does.
                        Loader {
                            active: Config.options.dock.showBackground && !dockRoot.dockSpans
                            anchors.fill: dockSurface
                            anchors.topMargin: dockRoot.bodyInsetTop
                            anchors.bottomMargin: dockRoot.bodyInsetBottom
                            anchors.leftMargin: dockRoot.bodyInsetLeft
                            anchors.rightMargin: dockRoot.bodyInsetRight
                            sourceComponent: StyledRectangularShadow {
                                anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
                                target: dockVisualBackground
                                color: Appearance.colors.colDockShadow
                            }
                        }
                        // The curves beside the body lap it by a pixel so a fractional display
                        // scale cannot leave a hairline of desktop in the join. That lap only
                        // goes unseen while nothing is see through, so notched the pair is
                        // painted opaque and faded together here. The group is grown past the
                        // body because the curves hang outside it and flattening clips to the
                        // bounds; the body is pushed back in by the same amount, so it lands
                        // where it always did.
                        Item {
                            id: dockSurface
                            anchors.fill: parent
                            anchors.topMargin: dockRoot.dockVertical ? -dockRoot.flareBleed : 0
                            anchors.bottomMargin: dockRoot.dockVertical ? -dockRoot.flareBleed : 0
                            anchors.leftMargin: dockRoot.dockVertical ? 0 : -dockRoot.flareBleed
                            anchors.rightMargin: dockRoot.dockVertical ? 0 : -dockRoot.flareBleed
                            opacity: dockRoot.notchSeamFix ? Appearance.colors.colDockBackground.a : 1
                            layer.enabled: dockRoot.notchSeamFix
                            layer.smooth: true

                            // The outward curves, drawn beside the surface the way
                            // the bar draws the ones under its own hug corners.
                            Loader {
                                active: dockRoot.dockFlares && Config.options.dock.showBackground
                                anchors.fill: dockVisualBackground
                                // Over the body rather than under it, so the body's
                                // outline along the sides it shares with these is
                                // covered by them and only its top is left showing.
                                z: 1
                                // Between the shadow and the body: above the shadow,
                                // which is cast for a surface that stops at the body
                                // and would otherwise lay a gradient down the join,
                                // and below the body, so the pixel each curve laps
                                // over it is hidden rather than doubled. That lap is
                                // what a fractional display scale needs: the body's
                                // edge can land between pixels, and a curve merely
                                // touching it rounds to the far side and leaves a
                                // hairline of desktop showing through.
                                // Only the pair the edge can actually show is built.
                                // Every curve carries the same size and color, so
                                // each site is left with the two things that differ:
                                // where it hangs and which way it turns.
                                sourceComponent: dockRoot.dockVertical ? sideFlares : endFlares
                            }

                            component DockFlare: RoundCorner {
                                // A sweep bigger than the body it grows from
                                // has nowhere to land and stands above it, so
                                // it is held to what the body can hold however
                                // the roundness was arrived at.
                                implicitSize: Math.min(Appearance.rounding.dock,
                                    Appearance.rounding.dockFlareFit)
                                color: dockRoot.notchSeamFix ? Appearance.colors.colDockBackgroundOpaque
                                    : Appearance.colors.colDockBackground
                                outlineWidth: Config.options.dock.showBackground ? 1 : 0
                                outlineColor: dockRoot.notchSeamFix
                                    ? dockRoot.content.colBorderOpaque
                                    : dockRoot.content.colBorder
                            }

                            // The curves at the two ends of a horizontal dock.
                            Component {
                                id: endFlares
                                Item {
                                    DockFlare {
                                        anchors.right: parent.left
                                        anchors.rightMargin: -dockRoot.flareLap
                                        anchors.top: dockRoot.dockEdge === "top" ? parent.top : undefined
                                        anchors.bottom: dockRoot.dockEdge === "bottom" ? parent.bottom : undefined
                                        corner: dockRoot.dockEdge === "top" ? RoundCorner.CornerEnum.TopRight
                                            : RoundCorner.CornerEnum.BottomRight
                                    }
                                    DockFlare {
                                        anchors.left: parent.right
                                        anchors.leftMargin: -dockRoot.flareLap
                                        anchors.top: dockRoot.dockEdge === "top" ? parent.top : undefined
                                        anchors.bottom: dockRoot.dockEdge === "bottom" ? parent.bottom : undefined
                                        corner: dockRoot.dockEdge === "top" ? RoundCorner.CornerEnum.TopLeft
                                            : RoundCorner.CornerEnum.BottomLeft
                                    }
                                }
                            }

                            // The same two for a dock stood on its side.
                            Component {
                                id: sideFlares
                                Item {
                                    DockFlare {
                                        anchors.bottom: parent.top
                                        anchors.bottomMargin: -dockRoot.flareLap
                                        anchors.left: dockRoot.dockEdge === "left" ? parent.left : undefined
                                        anchors.right: dockRoot.dockEdge === "right" ? parent.right : undefined
                                        corner: dockRoot.dockEdge === "left" ? RoundCorner.CornerEnum.BottomLeft
                                            : RoundCorner.CornerEnum.BottomRight
                                    }
                                    DockFlare {
                                        anchors.top: parent.bottom
                                        anchors.topMargin: -dockRoot.flareLap
                                        anchors.left: dockRoot.dockEdge === "left" ? parent.left : undefined
                                        anchors.right: dockRoot.dockEdge === "right" ? parent.right : undefined
                                        corner: dockRoot.dockEdge === "left" ? RoundCorner.CornerEnum.TopLeft
                                            : RoundCorner.CornerEnum.TopRight
                                    }
                                }
                            }

                            // The Hug strip, reaching out past the body by the
                            // curves at its two ends.
                            Loader {
                                active: dockRoot.dockSpans && Config.options.dock.showBackground
                                anchors.fill: dockVisualBackground
                                anchors.topMargin: dockRoot.dockEdge === "bottom" ? -dockRoot.spanCorner : 0
                                anchors.bottomMargin: dockRoot.dockEdge === "top" ? -dockRoot.spanCorner : 0
                                anchors.leftMargin: dockRoot.dockEdge === "right" ? -dockRoot.spanCorner : 0
                                anchors.rightMargin: dockRoot.dockEdge === "left" ? -dockRoot.spanCorner : 0
                                sourceComponent: DockSpanSurface {}
                            }

                            // The strip and both curves are one outline rather than
                            // pieces laid beside each other the way the Hug bar lays
                            // them, so there is no join for a fractional display scale
                            // to open into a hairline. Worked out along the edge (u)
                            // and out from it (v), then turned to the edge it is on.
                            component DockSpanSurface: Shape {
                                id: spanShape
                                readonly property string edge: dockRoot.dockEdge
                                readonly property real r: dockRoot.spanCorner
                                readonly property real along: dockRoot.dockVertical ? height : width
                                readonly property real out: dockRoot.dockVertical ? width : height
                                readonly property real strip: out - r
                                // Where the screen's sides fall. Only the fill runs on
                                // past them; the curves leave from the sides themselves,
                                // where the Hug bar's corners leave from.
                                readonly property real side: -dockRoot.endInset
                                // The outline is drawn half its width inside the
                                // surface, so the whole line lies on the strip the
                                // way a rectangle's border does.
                                readonly property real inset: 0.5
                                // Mirroring the plane for the edges that lie across
                                // the other way reverses which way a curve turns.
                                readonly property int turn: (edge === "bottom" || edge === "left")
                                    ? PathArc.Counterclockwise : PathArc.Clockwise
                                function px(u, v) {
                                    return edge === "left" ? v : edge === "right" ? width - v : u;
                                }
                                function py(u, v) {
                                    return edge === "top" ? v : edge === "bottom" ? height - v : u;
                                }
                                preferredRendererType: Shape.CurveRenderer
                                opacity: dockRoot.spanSeamFix ? Appearance.colors.colDockBackground.a : 1
                                layer.enabled: dockRoot.spanSeamFix
                                layer.smooth: true

                                ShapePath {
                                    strokeWidth: -1
                                    strokeColor: "transparent"
                                    fillColor: dockRoot.spanSeamFix ? Appearance.colors.colDockBackgroundOpaque
                                        : Appearance.colors.colDockBackground
                                    pathHints: ShapePath.PathSolid | ShapePath.PathNonIntersecting
                                    startX: spanShape.px(0, 0)
                                    startY: spanShape.py(0, 0)
                                    PathLine { x: spanShape.px(0, spanShape.out); y: spanShape.py(0, spanShape.out) }
                                    PathLine { x: spanShape.px(spanShape.side, spanShape.out); y: spanShape.py(spanShape.side, spanShape.out) }
                                    PathArc {
                                        x: spanShape.px(spanShape.side + spanShape.r, spanShape.strip)
                                        y: spanShape.py(spanShape.side + spanShape.r, spanShape.strip)
                                        radiusX: spanShape.r
                                        radiusY: spanShape.r
                                        direction: spanShape.turn
                                    }
                                    PathLine {
                                        x: spanShape.px(spanShape.along - spanShape.side - spanShape.r, spanShape.strip)
                                        y: spanShape.py(spanShape.along - spanShape.side - spanShape.r, spanShape.strip)
                                    }
                                    PathArc {
                                        x: spanShape.px(spanShape.along - spanShape.side, spanShape.out)
                                        y: spanShape.py(spanShape.along - spanShape.side, spanShape.out)
                                        radiusX: spanShape.r
                                        radiusY: spanShape.r
                                        direction: spanShape.turn
                                    }
                                    PathLine { x: spanShape.px(spanShape.along, spanShape.out); y: spanShape.py(spanShape.along, spanShape.out) }
                                    PathLine { x: spanShape.px(spanShape.along, 0); y: spanShape.py(spanShape.along, 0) }
                                    PathLine { x: spanShape.px(0, 0); y: spanShape.py(0, 0) }
                                }

                                ShapePath {
                                    strokeWidth: 1
                                    strokeColor: dockRoot.spanSeamFix ? dockRoot.content.colBorderOpaque
                                        : dockRoot.content.colBorder
                                    fillColor: "transparent"
                                    capStyle: ShapePath.FlatCap
                                    startX: spanShape.px(spanShape.side - spanShape.inset, spanShape.out)
                                    startY: spanShape.py(spanShape.side - spanShape.inset, spanShape.out)
                                    PathArc {
                                        x: spanShape.px(spanShape.side + spanShape.r, spanShape.strip - spanShape.inset)
                                        y: spanShape.py(spanShape.side + spanShape.r, spanShape.strip - spanShape.inset)
                                        radiusX: spanShape.r + spanShape.inset
                                        radiusY: spanShape.r + spanShape.inset
                                        direction: spanShape.turn
                                    }
                                    PathLine {
                                        x: spanShape.px(spanShape.along - spanShape.side - spanShape.r, spanShape.strip - spanShape.inset)
                                        y: spanShape.py(spanShape.along - spanShape.side - spanShape.r, spanShape.strip - spanShape.inset)
                                    }
                                    PathArc {
                                        x: spanShape.px(spanShape.along - spanShape.side + spanShape.inset, spanShape.out)
                                        y: spanShape.py(spanShape.along - spanShape.side + spanShape.inset, spanShape.out)
                                        radiusX: spanShape.r + spanShape.inset
                                        radiusY: spanShape.r + spanShape.inset
                                        direction: spanShape.turn
                                    }
                                }
                            }

                            Rectangle { // The real rectangle that is visible
                                id: dockVisualBackground
                                property real margin: Appearance.sizes.elevationMargin
                                anchors.fill: parent
                                anchors.topMargin: dockRoot.bodyInsetTop
                                anchors.bottomMargin: dockRoot.bodyInsetBottom
                                anchors.leftMargin: dockRoot.bodyInsetLeft
                                anchors.rightMargin: dockRoot.bodyInsetRight
                                // The Hug strip draws its own surface and outline,
                                // and this is left only as where the strip lies.
                                color: !Config.options.dock.showBackground || dockRoot.dockSpans ? "transparent"
                                    : dockRoot.notchSeamFix ? Appearance.colors.colDockBackgroundOpaque
                                    : Appearance.colors.colDockBackground
                                // The outward curves take the outline on along
                                // their sweep and are drawn over the sides they
                                // share with the body, so what is left of this one
                                // is the top, which is the only part on show.
                                border.width: Config.options.dock.showBackground && !dockRoot.dockSpans ? 1 : 0
                                border.color: dockRoot.notchSeamFix
                                    ? dockRoot.content.colBorderOpaque
                                    : dockRoot.content.colBorder
                                // The pair facing the screen edge answers to the
                                // edge roundness; the pair facing the desktop to
                                // the other. A corner that curves outward is drawn
                                // beside the surface rather than on it, so the one
                                // here is squared off and the piece takes over.
                                // Every corner is set below, so this one is left
                                // only for the shadow to read: it takes the visible
                                // pair's roundness, or the shadow would keep a shape
                                // the surface no longer has.
                                radius: dockRoot.deskRadius
                                topLeftRadius: (dockRoot.dockEdge === "top" || dockRoot.dockEdge === "left")
                                    ? dockRoot.edgeCornerRadius : dockRoot.deskRadius
                                topRightRadius: (dockRoot.dockEdge === "top" || dockRoot.dockEdge === "right")
                                    ? dockRoot.edgeCornerRadius : dockRoot.deskRadius
                                bottomLeftRadius: (dockRoot.dockEdge === "bottom" || dockRoot.dockEdge === "left")
                                    ? dockRoot.edgeCornerRadius : dockRoot.deskRadius
                                bottomRightRadius: (dockRoot.dockEdge === "bottom" || dockRoot.dockEdge === "right")
                                    ? dockRoot.edgeCornerRadius : dockRoot.deskRadius
                            }
                        }

                        GridLayout {
                            id: dockRow
                            columns: dockRoot.dockVertical ? 1 : -1
                            rows: dockRoot.dockVertical ? -1 : 1
                            columnSpacing: 3
                            rowSpacing: 3
                            // The row keeps to the room the other styles have,
                            // clear of the Hug strip's curves, so the icons sit
                            // where they would on any other dock.
                            anchors.topMargin: dockRoot.dockEdge === "bottom" ? dockRoot.spanOverhang : 0
                            anchors.bottomMargin: dockRoot.dockEdge === "top" ? dockRoot.spanOverhang : 0
                            anchors.leftMargin: dockRoot.dockEdge === "right" ? dockRoot.spanOverhang : 0
                            anchors.rightMargin: dockRoot.dockEdge === "left" ? dockRoot.spanOverhang : 0
                            states: [
                                State {
                                    name: "horizontal"
                                    when: !dockRoot.dockVertical
                                    AnchorChanges {
                                        target: dockRow
                                        anchors { top: dockRow.parent.top; bottom: dockRow.parent.bottom; left: undefined; right: undefined; horizontalCenter: dockRow.parent.horizontalCenter; verticalCenter: undefined }
                                    }
                                },
                                State {
                                    name: "vertical"
                                    when: dockRoot.dockVertical
                                    AnchorChanges {
                                        target: dockRow
                                        anchors { top: undefined; bottom: undefined; left: dockRow.parent.left; right: dockRow.parent.right; horizontalCenter: undefined; verticalCenter: dockRow.parent.verticalCenter }
                                    }
                                }
                            ]
                            property real padding: 5

                            VerticalButtonGroup {
                                visible: Config.options.dock.showPinButton
                                Layout.alignment: dockRoot.dockVertical ? Qt.AlignHCenter : Qt.AlignVCenter
                                Layout.topMargin: dockRoot.dockEdge === "bottom" ? Appearance.sizes.hyprlandGapsOut : 0 // why does this work
                                Layout.bottomMargin: dockRoot.dockEdge === "top" ? Appearance.sizes.hyprlandGapsOut : 0
                                Layout.leftMargin: dockRoot.dockEdge === "right" ? Appearance.sizes.hyprlandGapsOut : 0
                                Layout.rightMargin: dockRoot.dockEdge === "left" ? Appearance.sizes.hyprlandGapsOut : 0
                                GroupButton {
                                    // Pin button. Sized off the icons like the
                                    // overview button at the far end, so the two
                                    // ends of the dock keep pace with each other
                                    // and with what sits between them.
                                    baseWidth: dockRoot.fittedIconSize
                                    baseHeight: dockRoot.fittedIconSize
                                    clickedWidth: baseWidth
                                    clickedHeight: baseHeight + 20
                                    buttonRadius: Appearance.rounding.normal
                                    colBackgroundHover: dockRoot.content.settled.colLayer1Hover
                                    colBackgroundActive: dockRoot.content.settled.colLayer1Active
                                    colBackgroundToggled: dockRoot.content.settled.colPrimary
                                    colBackgroundToggledHover: dockRoot.content.settled.colPrimaryHover
                                    colBackgroundToggledActive: dockRoot.content.settled.colPrimaryActive
                                    toggled: root.pinned
                                    onClicked: root.pinned = !root.pinned
                                    contentItem: MaterialSymbol {
                                        text: "keep"
                                        horizontalAlignment: Text.AlignHCenter
                                        // Whole pixels: MaterialSymbol rounds the
                                        // optical size axis to keep the font from
                                        // being remapped per value, but the pixel
                                        // size it is given is a font cache key of
                                        // its own, so a fraction here mints a face
                                        // the rounding was meant to prevent.
                                        iconSize: Math.round(Appearance.font.pixelSize.larger
                                            * dockRoot.fittedIconSize / Appearance.sizes.dockIconStock)
                                        color: root.pinned ? dockRoot.content.m3onPrimary : dockRoot.content.colOnLayer0
                                    }
                                }
                            }
                            DockSeparator { visible: Config.options.dock.showPinButton }
                            DockApps {
                                id: dockApps
                                buttonPadding: dockRow.padding
                            }
                            DockSeparator { visible: Config.options.dock.showOverviewButton }
                            DockButton {
                                visible: Config.options.dock.showOverviewButton
                                Layout.fillHeight: !dockRoot.dockVertical
                                Layout.fillWidth: dockRoot.dockVertical
                                onClicked: GlobalStates.overviewOpen = !GlobalStates.overviewOpen
                                topInset: dockRoot.dockVertical ? 0 : Appearance.sizes.hyprlandGapsOut + dockRow.padding
                                bottomInset: dockRoot.dockVertical ? 0 : Appearance.sizes.hyprlandGapsOut + dockRow.padding
                                leftInset: dockRoot.dockVertical ? Appearance.sizes.hyprlandGapsOut + dockRow.padding : 0
                                rightInset: dockRoot.dockVertical ? Appearance.sizes.hyprlandGapsOut + dockRow.padding : 0
                                contentItem: MaterialSymbol {
                                    anchors.fill: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    font.pixelSize: Math.min(parent.width, parent.height) / 2
                                    text: "apps"
                                    color: dockRoot.content.colOnLayer0
                                }
                            }
                        }
                    }
                }
            }
        }
            }
        }
    }
}
