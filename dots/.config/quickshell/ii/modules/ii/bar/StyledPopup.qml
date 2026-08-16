import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

LazyLoader {
    id: root

    property Item hoverTarget
    default property Item contentItem
    property real popupBackgroundMargin: 0
    // Manual-show path for right-click / click-triggered popups. When
    // showOnHover is false the popup ignores hover entirely and only obeys
    // forceShow; hoverTarget is still required for positioning math.
    property bool forceShow: false
    property bool showOnHover: true

    // A hover popup goes away with the pointer, but a click-triggered one has
    // nothing to close it. Callers that set showOnHover false should clear
    // their open flag from here, so clicking away puts the popup down.
    signal dismissed()

    active: forceShow || (showOnHover && hoverTarget && hoverTarget.containsMouse)

    component: PanelWindow {
        id: popupWindow
        color: "transparent"

        // Taking focus is what keeps the bar out of the grab: while every
        // dismissable is unfocusable the grab also covers the persistent
        // windows, and a click on the bar would then count as clicking inside
        // it. A menu should close whatever you click next, the bar included.
        WlrLayershell.keyboardFocus: root.showOnHover ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand

        // Only the click-triggered popups take part: a hover popup closes when
        // the pointer leaves and has nothing to tell the grab, so registering
        // one and then listening for a dismissal it can never act on would put
        // a connection on every bar widget you happen to hover over.
        Component.onCompleted: if (!root.showOnHover) GlobalFocusGrab.addDismissable(popupWindow)
        Component.onDestruction: if (!root.showOnHover) GlobalFocusGrab.removeDismissable(popupWindow)

        Connections {
            enabled: !root.showOnHover
            target: GlobalFocusGrab
            function onDismissed(): void {
                root.dismissed();
            }
        }

        anchors.left: !Config.options.bar.vertical || (Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.right: Config.options.bar.vertical && Config.options.bar.bottom
        anchors.top: Config.options.bar.vertical || (!Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.bottom: !Config.options.bar.vertical && Config.options.bar.bottom

        implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin
        implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin

        mask: Region {
            item: popupBackground
        }

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        margins {
            // These margins place the WINDOW, but what should center on the
            // widget is the visible pill, which sits inset from the window's
            // anchored edge by the shadow padding below. Subtracting that
            // inset — written as the same expression the background uses —
            // keeps the pill centred rather than shifted by a shadow's width.
            left: {
                if (!Config.options.bar.vertical) return root.QsWindow?.mapFromItem(
                    root.hoverTarget, 
                    (root.hoverTarget.width - popupBackground.implicitWidth) / 2
                        - (Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.left)), 0
                ).x;
                return Appearance.sizes.verticalBarWidth
            }
            top: {
                if (!Config.options.bar.vertical) return Appearance.sizes.barHeight;
                return root.QsWindow?.mapFromItem(
                    root.hoverTarget, 0,
                    (root.hoverTarget.height - popupBackground.implicitHeight) / 2
                        - (Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.top))
                ).y;
            }
            right: Appearance.sizes.verticalBarWidth
            bottom: Appearance.sizes.barHeight
        }
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay

        StyledRectangularShadow {
            target: popupBackground
        }

        Rectangle {
            id: popupBackground
            readonly property real margin: 10
            anchors {
                fill: parent
                leftMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.left)
                rightMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.right)
                topMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.top)
                bottomMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.bottom)
            }
            implicitWidth: root.contentItem.implicitWidth + margin * 2
            implicitHeight: root.contentItem.implicitHeight + margin * 2
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.small
            children: [root.contentItem]

            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }
    }
}
