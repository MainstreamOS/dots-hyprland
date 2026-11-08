import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RowLayout {
    id: root
    property real uiScale: QsWindow.window?.uiScale ?? 1
    required property string icon
    required property string label
    required property string value
    spacing: 4 * root.uiScale

    MaterialSymbol {
        text: root.icon
        color: Appearance.colors.colOnSurfaceVariant
        iconSize: Appearance.font.basePixelSize.large * root.uiScale
    }
    StyledText {
        text: root.label
        color: Appearance.colors.colOnSurfaceVariant
    }
    StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignRight
        visible: root.value !== ""
        color: Appearance.colors.colOnSurfaceVariant
        text: root.value
    }
}
