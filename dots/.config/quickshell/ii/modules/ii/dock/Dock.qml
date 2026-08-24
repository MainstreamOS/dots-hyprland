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
            readonly property real edgeRadius: Config.options.dock.cornerStyle === "rect"
                ? 0 : Appearance.rounding.dock
            readonly property real deskRadius: dockHugging
                ? Appearance.rounding.dockTop : Appearance.rounding.dock
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

            // The dock's visible thickness plus its screen gap; the extra 60
            // beyond it is headroom on the center-facing side so magnified
            // icons can overflow without window clipping.
            readonly property real dockExtent: Appearance.sizes.dockExtent

            exclusiveZone: root.pinned ? Appearance.sizes.dockHeight + Appearance.sizes.hyprlandGapsOut : 0

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

            implicitWidth: dockRoot.dockVertical ? dockRoot.dockExtent + Appearance.sizes.dockMagnifyHeadroom : dockBackground.implicitWidth
            implicitHeight: dockRoot.dockVertical ? dockBackground.implicitHeight : dockRoot.dockExtent + Appearance.sizes.dockMagnifyHeadroom
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
                readonly property real slide: Appearance.sizes.dockMagnifyHeadroom + (dockRoot.reveal ? 1
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

                        StyledRectangularShadow {
                            target: dockVisualBackground
                            visible: Config.options.dock.showBackground
                            color: Appearance.colors.colDockShadow
                        }
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
                            sourceComponent: Item {
                                RoundCorner {
                                    anchors.right: parent.left
                                    anchors.rightMargin: -1
                                    anchors.top: dockRoot.dockEdge === "top" ? parent.top : undefined
                                    anchors.bottom: dockRoot.dockEdge === "bottom" ? parent.bottom : undefined
                                    anchors.left: dockRoot.dockVertical ? parent.left : undefined
                                    implicitSize: dockRoot.edgeRadius
                                    color: Appearance.colors.colDockBackground
                                    corner: dockRoot.dockEdge === "top" ? RoundCorner.CornerEnum.TopRight
                                        : RoundCorner.CornerEnum.BottomRight
                                    visible: !dockRoot.dockVertical
                                }
                                RoundCorner {
                                    anchors.left: parent.right
                                    anchors.leftMargin: -1
                                    anchors.top: dockRoot.dockEdge === "top" ? parent.top : undefined
                                    anchors.bottom: dockRoot.dockEdge === "bottom" ? parent.bottom : undefined
                                    implicitSize: dockRoot.edgeRadius
                                    color: Appearance.colors.colDockBackground
                                    corner: dockRoot.dockEdge === "top" ? RoundCorner.CornerEnum.TopLeft
                                        : RoundCorner.CornerEnum.BottomLeft
                                    visible: !dockRoot.dockVertical
                                }
                                RoundCorner {
                                    anchors.bottom: parent.top
                                    anchors.bottomMargin: -1
                                    anchors.left: dockRoot.dockEdge === "left" ? parent.left : undefined
                                    anchors.right: dockRoot.dockEdge === "right" ? parent.right : undefined
                                    implicitSize: dockRoot.edgeRadius
                                    color: Appearance.colors.colDockBackground
                                    corner: dockRoot.dockEdge === "left" ? RoundCorner.CornerEnum.BottomLeft
                                        : RoundCorner.CornerEnum.BottomRight
                                    visible: dockRoot.dockVertical
                                }
                                RoundCorner {
                                    anchors.top: parent.bottom
                                    anchors.topMargin: -1
                                    anchors.left: dockRoot.dockEdge === "left" ? parent.left : undefined
                                    anchors.right: dockRoot.dockEdge === "right" ? parent.right : undefined
                                    implicitSize: dockRoot.edgeRadius
                                    color: Appearance.colors.colDockBackground
                                    corner: dockRoot.dockEdge === "left" ? RoundCorner.CornerEnum.TopLeft
                                        : RoundCorner.CornerEnum.TopRight
                                    visible: dockRoot.dockVertical
                                }
                            }
                        }

                        Rectangle { // The real rectangle that is visible
                            id: dockVisualBackground
                            property real margin: Appearance.sizes.elevationMargin
                            anchors.fill: parent
                            // The screen gap sits on the edge side, the
                            // shadow's breathing room on the center side.
                            // Hugging leaves no gap on the edge side: the
                            // concave corners have nothing to curve into if
                            // the dock is floating away from it.
                            readonly property real edgeGap: dockRoot.dockHugging ? 0 : Appearance.sizes.hyprlandGapsOut
                            anchors.topMargin: dockRoot.dockEdge === "top" ? edgeGap : dockRoot.dockVertical ? 0 : Appearance.sizes.elevationMargin
                            anchors.bottomMargin: dockRoot.dockEdge === "bottom" ? edgeGap : dockRoot.dockVertical ? 0 : Appearance.sizes.elevationMargin
                            anchors.leftMargin: dockRoot.dockEdge === "left" ? edgeGap : dockRoot.dockVertical ? Appearance.sizes.elevationMargin : 0
                            anchors.rightMargin: dockRoot.dockEdge === "right" ? edgeGap : dockRoot.dockVertical ? Appearance.sizes.elevationMargin : 0
                            color: Config.options.dock.showBackground ? Appearance.colors.colDockBackground : "transparent"
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
                                ? (dockRoot.dockFlares ? 0 : dockRoot.edgeRadius) : dockRoot.deskRadius
                            topRightRadius: (dockRoot.dockEdge === "top" || dockRoot.dockEdge === "right")
                                ? (dockRoot.dockFlares ? 0 : dockRoot.edgeRadius) : dockRoot.deskRadius
                            bottomLeftRadius: (dockRoot.dockEdge === "bottom" || dockRoot.dockEdge === "left")
                                ? (dockRoot.dockFlares ? 0 : dockRoot.edgeRadius) : dockRoot.deskRadius
                            bottomRightRadius: (dockRoot.dockEdge === "bottom" || dockRoot.dockEdge === "right")
                                ? (dockRoot.dockFlares ? 0 : dockRoot.edgeRadius) : dockRoot.deskRadius
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
                                    baseWidth: Appearance.sizes.dockIconSize
                                    baseHeight: Appearance.sizes.dockIconSize
                                    clickedWidth: baseWidth
                                    clickedHeight: baseHeight + 20
                                    buttonRadius: Appearance.rounding.normal
                                    toggled: root.pinned
                                    onClicked: root.pinned = !root.pinned
                                    contentItem: MaterialSymbol {
                                        text: "keep"
                                        horizontalAlignment: Text.AlignHCenter
                                        iconSize: Appearance.font.pixelSize.larger
                                            * Appearance.sizes.dockIconSize / Appearance.sizes.dockIconStock
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
