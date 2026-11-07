import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: button
    property real uiScale: QsWindow.window?.uiScale ?? 1
    property var contentColors: Appearance.barContent

    required default property Item content
    property bool extraActiveCondition: false

    implicitHeight: Math.max(content.implicitHeight, 26 * button.uiScale)
    implicitWidth: implicitHeight
    colBackgroundHover: button.contentColors.colLayer1Hover
    colRipple: button.contentColors.colLayer1Active
    contentItem: content

}
