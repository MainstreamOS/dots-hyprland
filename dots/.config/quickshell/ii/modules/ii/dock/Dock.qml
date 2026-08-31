import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
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
            // Both hug and rect set the dock down on the edge; what differs is
            // the pair of corners that touches it, curving outward or squared
            // off. The pair facing the desktop keeps its own roundness either
            // way.
            readonly property bool dockHugging: Config.options.dock.cornerStyle !== "float"
            readonly property bool dockFlares: Config.options.dock.cornerStyle === "hug"
            // Only the notch draws pieces beside the body, so only it needs the
            // group flattened before the surface is faded, and only it needs the
            // room outside the body that those pieces occupy.
            // The lap the fix hides only shows through a see-through surface,
            // so a fully opaque one skips the flattening pass and its texture.
            readonly property bool notchSeamFix: dockFlares && Config.options.dock.showBackground
                && Appearance.colors.colDockBackground.a < 1
            readonly property real flareBleed: notchSeamFix ? Appearance.rounding.dock : 0
            // The screen gap sits on the edge side, the shadow's breathing room
            // on the center side. Hugging leaves no gap on the edge side: the
            // concave corners have nothing to curve into if the dock floats
            // away from it.
            readonly property real edgeGap: dockHugging ? 0 : Appearance.sizes.hyprlandGapsOut
            // Where the body sits inside its group, said once for the body and
            // for the shade that follows it, the two no longer sharing an
            // anchor. The group's bleed only exists on the sides the curves
            // hang from, so it is only given back there.
            readonly property real bodyInsetTop: (dockEdge === "top" ? edgeGap : dockVertical ? 0 : Appearance.sizes.elevationMargin) + (dockVertical ? flareBleed : 0)
            readonly property real bodyInsetBottom: (dockEdge === "bottom" ? edgeGap : dockVertical ? 0 : Appearance.sizes.elevationMargin) + (dockVertical ? flareBleed : 0)
            readonly property real bodyInsetLeft: (dockEdge === "left" ? edgeGap : dockVertical ? Appearance.sizes.elevationMargin : 0) + (dockVertical ? 0 : flareBleed)
            readonly property real bodyInsetRight: (dockEdge === "right" ? edgeGap : dockVertical ? Appearance.sizes.elevationMargin : 0) + (dockVertical ? 0 : flareBleed)
            readonly property real deskRadius: dockHugging
                ? Appearance.rounding.dockTop : Appearance.rounding.dock
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

            // The dock's visible thickness plus its screen gap; the extra 60
            // beyond it is headroom on the center-facing side so magnified
            // icons can overflow without window clipping.
            readonly property real dockExtent: Appearance.sizes.dockExtentFor(dockRoot.fittedIconSize)

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
                item: dockMouseArea
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

                width: dockRoot.dockVertical ? dockRoot.dockExtent : implicitWidth
                height: dockRoot.dockVertical ? implicitHeight : dockRoot.dockExtent
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
                        width: dockRoot.dockVertical ? parent.width - Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut : implicitWidth
                        height: dockRoot.dockVertical ? implicitHeight : parent.height - Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut

                        // The shade stays out of the group. It is meant to be seen
                        // through, and its colour already carries the surface's alpha,
                        // so fading it again with the group would square that. It
                        // anchors to the group with the body's own insets, the body no
                        // longer being a sibling of this loader.
                        Loader {
                            active: Config.options.dock.showBackground
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

                            // The outward curves, drawn beside the surface the way
                            // the bar draws the ones under its own hug corners.
                            Loader {
                                active: dockRoot.dockFlares && Config.options.dock.showBackground
                                anchors.fill: dockVisualBackground
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
                                implicitSize: Appearance.rounding.dock
                                color: dockRoot.notchSeamFix ? Appearance.colors.colDockBackgroundOpaque
                                    : Appearance.colors.colDockBackground
                            }

                            // The curves at the two ends of a horizontal dock.
                            Component {
                                id: endFlares
                                Item {
                                    DockFlare {
                                        anchors.right: parent.left
                                        anchors.rightMargin: -1
                                        anchors.top: dockRoot.dockEdge === "top" ? parent.top : undefined
                                        anchors.bottom: dockRoot.dockEdge === "bottom" ? parent.bottom : undefined
                                        corner: dockRoot.dockEdge === "top" ? RoundCorner.CornerEnum.TopRight
                                            : RoundCorner.CornerEnum.BottomRight
                                    }
                                    DockFlare {
                                        anchors.left: parent.right
                                        anchors.leftMargin: -1
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
                                        anchors.bottomMargin: -1
                                        anchors.left: dockRoot.dockEdge === "left" ? parent.left : undefined
                                        anchors.right: dockRoot.dockEdge === "right" ? parent.right : undefined
                                        corner: dockRoot.dockEdge === "left" ? RoundCorner.CornerEnum.BottomLeft
                                            : RoundCorner.CornerEnum.BottomRight
                                    }
                                    DockFlare {
                                        anchors.top: parent.bottom
                                        anchors.topMargin: -1
                                        anchors.left: dockRoot.dockEdge === "left" ? parent.left : undefined
                                        anchors.right: dockRoot.dockEdge === "right" ? parent.right : undefined
                                        corner: dockRoot.dockEdge === "left" ? RoundCorner.CornerEnum.TopLeft
                                            : RoundCorner.CornerEnum.TopRight
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
                                color: !Config.options.dock.showBackground ? "transparent"
                                    : dockRoot.notchSeamFix ? Appearance.colors.colDockBackgroundOpaque
                                    : Appearance.colors.colDockBackground
                                // The outward curves are drawn as their own pieces
                                // and carry no outline, so a border on the body
                                // would run a seam down the join. Hugging means one
                                // continuous surface or none.
                                border.width: Config.options.dock.showBackground && !dockRoot.dockFlares ? 1 : 0
                                border.color: Appearance.colors.colDockBackgroundBorder
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
                                        color: root.pinned ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
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
                                    color: Appearance.colors.colOnLayer0
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
