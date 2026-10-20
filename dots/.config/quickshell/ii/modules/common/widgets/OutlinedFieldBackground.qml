import QtQuick
import qs.modules.common

// A field on the row surface with a thin outline, as the Dynamic Island's
// fields are. The outline takes the accent while the field has focus.
Rectangle {
    property bool focused: false

    radius: 8
    border.width: 1
    border.color: focused ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
    color: Appearance.surfaces.row
}
