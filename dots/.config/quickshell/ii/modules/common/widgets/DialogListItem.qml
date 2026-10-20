import qs.modules.common
import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: root
    property bool active: false

    horizontalPadding: Appearance.rounding.large
    verticalPadding: 12

    clip: true
    pointingHandCursor: !active    
    implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
    implicitHeight: contentItem.implicitHeight + verticalPadding * 2
    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    // A row of a grouped list in the Dynamic Island's style; the list's clip rounds the group's ends.
    colBackground: Appearance.surfaces.row
    colBackgroundHover: active ? colBackground : Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active
    buttonRadius: 4
}
