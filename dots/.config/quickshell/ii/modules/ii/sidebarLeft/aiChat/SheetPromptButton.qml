import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Button of the unsaved chat prompt.
RippleButton {
    id: root

    property string iconName
    property string label
    property bool primary: false

    Layout.fillWidth: true
    implicitHeight: 34
    buttonRadius: Appearance.rounding.verysmall
    colBackground: root.primary ? Appearance.colors.colPrimary : Appearance.colors.colLayer1
    colBackgroundHover: root.primary ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer1Hover

    contentItem: RowLayout {
        anchors.centerIn: parent
        spacing: 6
        MaterialSymbol {
            text: root.iconName
            iconSize: Appearance.font.pixelSize.normal
            color: root.primary ? Appearance.m3colors.m3onPrimary : Appearance.colors.colSubtext
        }
        StyledText {
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: root.primary ? Font.DemiBold : Font.Normal
            color: root.primary ? Appearance.m3colors.m3onPrimary : Appearance.m3colors.m3onSurface
        }
    }
}
