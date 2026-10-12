import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Empty state of the Model and Session sheets' lists.
ColumnLayout {
    id: root

    property string icon
    property string title
    property string subtitle

    spacing: 8

    MaterialSymbol {
        Layout.alignment: Qt.AlignHCenter
        text: root.icon
        iconSize: 48
        color: Appearance.colors.colSubtext
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        text: root.title
        font.pixelSize: Appearance.font.pixelSize.normal
        font.weight: Font.DemiBold
        color: Appearance.m3colors.m3onSurface
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        text: root.subtitle
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
}
