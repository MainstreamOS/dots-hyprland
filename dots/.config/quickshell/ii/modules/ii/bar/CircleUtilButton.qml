import qs.modules.common
import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: button
    property var contentColors: Appearance.barContent

    required default property Item content
    property bool extraActiveCondition: false

    implicitHeight: Math.max(content.implicitHeight, 26, content.implicitHeight)
    implicitWidth: implicitHeight
    colBackgroundHover: button.contentColors.colLayer1Hover
    colRipple: button.contentColors.colLayer1Active
    contentItem: content

}
