import qs.modules.common
import QtQuick
import QtQuick.Layouts

Rectangle {
    // Utility and in-list separators share the icons' center; the length scales
    // from the stock dock's 16 px line and stays positive at the smallest icons.
    readonly property real length: dockRoot.fittedIconSize * 0.4
    z: -1
    Layout.alignment: Qt.AlignCenter
    implicitWidth: dockRoot.dockVertical ? length : 1
    implicitHeight: dockRoot.dockVertical ? 1 : length
    color: dockRoot.content.colOutlineVariant
}
