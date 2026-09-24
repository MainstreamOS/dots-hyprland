import qs.modules.common
import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: button

    required default property Item content
    property bool extraActiveCondition: false

    implicitHeight: Math.max(content.implicitHeight, 26, content.implicitHeight)
    implicitWidth: implicitHeight
    colBackgroundHover: Appearance.barContent.colLayer1Hover
    colRipple: Appearance.barContent.colLayer1Active
    contentItem: content

}
