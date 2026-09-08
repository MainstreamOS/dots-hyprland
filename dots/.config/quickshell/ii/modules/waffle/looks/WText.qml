import QtQuick
import qs.modules.common

Text {
    id: root

    renderType: ScreenScale.renderTypeFor(Screen.name, font.pixelSize)
    verticalAlignment: Text.AlignVCenter
    color: Looks.colors.fg

    font {
        hintingPreference: Font.PreferDefaultHinting
        family: Looks.font.family.ui
        pixelSize: Looks.font.pixelSize.normal
        weight: Looks.font.weight.regular
        variableAxes: Looks.font.variableAxes.ui
    }

    linkColor: Looks.colors.link
}
