import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// A search bar action; a fixed width holds it to the quiet style's size.
IconToolbarButton {
    id: root
    property real uiScale: 1
    property real fixedWidth: 0

    Layout.minimumWidth: fixedWidth
    Layout.maximumWidth: fixedWidth > 0 ? fixedWidth : Infinity
    padding: 6 * uiScale
    buttonRadius: Appearance.rounding.full * uiScale
    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        iconSize: 22 * root.uiScale
        text: root.text
        color: root.colText
        animateChange: true
    }
}
