import qs.modules.common
import qs.modules.common.widgets
import QtQuick

GroupButton {
    id: button

    horizontalPadding: 8
    verticalPadding: 0

    baseWidth: contentItem.implicitWidth + horizontalPadding * 2
    clickedWidth: baseWidth + 14
    implicitHeight: 30

    buttonRadius: down ? Appearance.rounding.verysmall : Appearance.rounding.small

    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colBackgroundActive: Appearance.colors.colLayer2Active

    contentItem: StyledText {
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: Appearance.font.pixelSize.small
        text: button.buttonText
        color: Appearance.m3colors.m3onSurface
    }
}
