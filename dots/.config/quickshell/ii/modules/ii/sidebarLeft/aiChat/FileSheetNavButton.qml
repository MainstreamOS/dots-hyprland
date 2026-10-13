import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// Back, forward and parent folder buttons of the file sheet.
RippleButton {
    id: root

    property string iconName
    property string tip
    property bool sheetShown: false

    implicitWidth: 28
    implicitHeight: 28
    buttonRadius: Appearance.rounding.small
    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover
    opacity: enabled ? 1 : 0.35

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        text: root.iconName
        iconSize: 18
        color: Appearance.colors.colSubtext
    }

    StyledToolTip {
        extraVisibleCondition: root.sheetShown
        text: root.tip
    }
}
