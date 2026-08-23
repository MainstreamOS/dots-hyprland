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

            exclusiveZone: root.pinned ? (Config.options?.dock.height ?? 70) + Appearance.sizes.hyprlandGapsOut : 0

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

            implicitWidth: dockRoot.dockVertical ? dockRoot.dockExtent + 60 : dockBackground.implicitWidth
            implicitHeight: dockRoot.dockVertical ? dockBackground.implicitHeight : dockRoot.dockExtent + 60
            WlrLayershell.namespace: "quickshell:dock" + (dockRoot.dockEdge === "bottom" ? ""
                : dockRoot.dockEdge.charAt(0).toUpperCase() + dockRoot.dockEdge.slice(1))
            WlrLayershell.layer: GlobalStates.overviewOpen ? WlrLayer.Overlay : WlrLayer.Top
            color: "transparent"

            mask: Region {
                item: dockMouseArea
            }

            MouseArea {
                id: dockMouseArea
                // Offset from the window's center-facing side: past the 60px
                // magnify headroom when revealed, and far enough to push the
                // strip off the screen edge when hidden — keeping only the
                // hover strip while hover-to-reveal is on.
                readonly property real slide: 60 + (dockRoot.reveal ? 1
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
                        Rectangle { // The real rectangle that is visible
                            id: dockVisualBackground
                            property real margin: Appearance.sizes.elevationMargin
                            anchors.fill: parent
                            // The screen gap sits on the edge side, the
                            // shadow's breathing room on the center side.
                            anchors.topMargin: dockRoot.dockEdge === "top" ? Appearance.sizes.hyprlandGapsOut : dockRoot.dockVertical ? 0 : Appearance.sizes.elevationMargin
                            anchors.bottomMargin: dockRoot.dockEdge === "bottom" ? Appearance.sizes.hyprlandGapsOut : dockRoot.dockVertical ? 0 : Appearance.sizes.elevationMargin
                            anchors.leftMargin: dockRoot.dockEdge === "left" ? Appearance.sizes.hyprlandGapsOut : dockRoot.dockVertical ? Appearance.sizes.elevationMargin : 0
                            anchors.rightMargin: dockRoot.dockEdge === "right" ? Appearance.sizes.hyprlandGapsOut : dockRoot.dockVertical ? Appearance.sizes.elevationMargin : 0
                            color: Config.options.dock.showBackground ? Appearance.colors.colDockBackground : "transparent"
                            border.width: Config.options.dock.showBackground ? 1 : 0
                            border.color: Appearance.colors.colDockBackgroundBorder
                            radius: Appearance.rounding.large
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
                                Layout.alignment: dockRoot.dockVertical ? Qt.AlignHCenter : Qt.AlignVCenter
                                Layout.topMargin: dockRoot.dockEdge === "bottom" ? Appearance.sizes.hyprlandGapsOut : 0 // why does this work
                                Layout.bottomMargin: dockRoot.dockEdge === "top" ? Appearance.sizes.hyprlandGapsOut : 0
                                Layout.leftMargin: dockRoot.dockEdge === "right" ? Appearance.sizes.hyprlandGapsOut : 0
                                Layout.rightMargin: dockRoot.dockEdge === "left" ? Appearance.sizes.hyprlandGapsOut : 0
                                GroupButton {
                                    // Pin button
                                    baseWidth: 35
                                    baseHeight: 35
                                    clickedWidth: baseWidth
                                    clickedHeight: baseHeight + 20
                                    buttonRadius: Appearance.rounding.normal
                                    toggled: root.pinned
                                    onClicked: root.pinned = !root.pinned
                                    contentItem: MaterialSymbol {
                                        text: "keep"
                                        horizontalAlignment: Text.AlignHCenter
                                        iconSize: Appearance.font.pixelSize.larger
                                        color: root.pinned ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                                    }
                                }
                            }
                            DockSeparator {}
                            DockApps {
                                id: dockApps
                                buttonPadding: dockRow.padding
                            }
                            DockSeparator {}
                            DockButton {
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
