import QtQuick
import qs.modules.common
import QtQuick.Controls

TextInput {
    id: root
    renderType: ScreenScale.renderTypeFor(Screen.name)
    verticalAlignment: Text.AlignVCenter
    color: Looks.colors.fg

    font {
        hintingPreference: Font.PreferFullHinting
        family: Looks.font.family.ui
        pixelSize: Looks.font.pixelSize.large
        weight: Looks.font.weight.regular
    }

    selectionColor: Looks.colors.selection
    selectedTextColor: Looks.colors.selectionFg
}
