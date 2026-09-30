import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common

// One row of a context menu: an icon and a label, with the menu's own hover
// and press tints. It sits in a ColumnLayout on a ContextMenuCard. A row that
// needs more than that puts it in `leading` (before the icon) or `trailing`
// (after the label) rather than drawing a row of its own. A disabled row fades
// the way every button does.
RippleButton {
    id: root

    // Empty leaves the icon out, and the label starts at the row's inset.
    property string iconName: ""
    property real iconRotation: 0
    property string label: ""
    property Component leading: null
    property Component trailing: null

    Layout.fillWidth: true
    implicitHeight: 36
    implicitWidth: Math.max(itemRow.implicitWidth + 24, 200)
    buttonRadius: RoundedCorners.on ? Appearance.rounding.small : 0
    colBackgroundHover: Appearance.colors.colMenuItemHover
    colRipple: Appearance.colors.colMenuItemActive

    contentItem: RowLayout {
        id: itemRow
        anchors {
            fill: parent
            leftMargin: 10
            rightMargin: 14
        }
        spacing: 8

        Loader {
            active: root.leading !== null
            visible: active
            sourceComponent: root.leading
            Layout.alignment: Qt.AlignVCenter
        }

        MaterialSymbol {
            visible: root.iconName !== ""
            text: root.iconName
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.m3colors.m3onSurface
            rotation: root.iconRotation
            Layout.alignment: Qt.AlignVCenter
        }

        StyledText {
            Layout.fillWidth: true
            text: root.label
            horizontalAlignment: Text.AlignLeft
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.m3colors.m3onSurface
            elide: Text.ElideRight
        }

        Loader {
            active: root.trailing !== null
            visible: active
            sourceComponent: root.trailing
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
