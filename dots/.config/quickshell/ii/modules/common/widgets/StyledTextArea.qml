import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls

/**
 * Does not include visual layout, but includes the easily neglected colors.
 */
TextArea {
    renderType: ScreenScale.renderTypeFor(Screen.name)
    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer
    placeholderTextColor: Appearance.m3colors.m3outline
    color: Appearance.colors.colOnLayer0
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }

    // The toolkit grows its own editing menu on a right click; leaving it in
    // place would open both.
    ContextMenu.menu: null

    TextFieldContextMenuArea {}
}
