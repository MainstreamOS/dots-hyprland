import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    Layout.fillHeight: !dockRoot.dockVertical
    Layout.fillWidth: dockRoot.dockVertical
    Layout.topMargin: dockRoot.dockEdge === "bottom" ? Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut : 0
    Layout.bottomMargin: dockRoot.dockEdge === "top" ? Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut : 0
    Layout.leftMargin: dockRoot.dockEdge === "right" ? Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut : 0
    Layout.rightMargin: dockRoot.dockEdge === "left" ? Appearance.sizes.elevationMargin - Appearance.sizes.hyprlandGapsOut : 0
    // The square base size both orientations derive from — the pill's
    // thickness minus its inner padding on each side, so buttons and list
    // delegates span the row's cross axis exactly at any configured dock
    // height (a ListView pins delegates to cross-axis 0, so leftover slack
    // would land on the screen-edge side of top and left docks). Derived
    // from plain values rather than implicit sizes to keep the two axes
    // from feeding each other into a binding loop.
    readonly property real dockButtonSize: Appearance.sizes.dockHeight - dockRow.padding * 2
    implicitWidth: dockRoot.dockVertical ? dockButtonSize + leftInset + rightInset : dockButtonSize
    implicitHeight: dockRoot.dockVertical ? dockButtonSize : dockButtonSize + topInset + bottomInset
    buttonRadius: Appearance.rounding.normal

    background.implicitHeight: dockButtonSize
    background.implicitWidth: dockButtonSize
}
