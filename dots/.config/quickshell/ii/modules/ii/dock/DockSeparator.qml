import qs.modules.common
import QtQuick
import QtQuick.Layouts

Rectangle {
    // The longer margin sits on the center-facing side, the shorter on the
    // screen-edge side, mirroring the dock background's own asymmetry.
    Layout.topMargin: dockRoot.dockVertical ? 0 : (dockRoot.dockEdge === "bottom" ? Appearance.sizes.elevationMargin : Appearance.sizes.hyprlandGapsOut) + dockRow.padding + Appearance.rounding.normal
    Layout.bottomMargin: dockRoot.dockVertical ? 0 : (dockRoot.dockEdge === "top" ? Appearance.sizes.elevationMargin : Appearance.sizes.hyprlandGapsOut) + dockRow.padding + Appearance.rounding.normal
    Layout.leftMargin: !dockRoot.dockVertical ? 0 : (dockRoot.dockEdge === "right" ? Appearance.sizes.elevationMargin : Appearance.sizes.hyprlandGapsOut) + dockRow.padding + Appearance.rounding.normal
    Layout.rightMargin: !dockRoot.dockVertical ? 0 : (dockRoot.dockEdge === "left" ? Appearance.sizes.elevationMargin : Appearance.sizes.hyprlandGapsOut) + dockRow.padding + Appearance.rounding.normal
    Layout.fillHeight: !dockRoot.dockVertical
    Layout.fillWidth: dockRoot.dockVertical
    implicitWidth: dockRoot.dockVertical ? 0 : 1
    implicitHeight: dockRoot.dockVertical ? 1 : 0
    color: Appearance.colors.colOutlineVariant
}
