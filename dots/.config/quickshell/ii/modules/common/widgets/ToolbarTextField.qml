import QtQuick
import Quickshell
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.widgets

TextField {
    id: filterField

    property real uiScale: QsWindow.window?.uiScale ?? 1
    readonly property QtObject fontSizes: Appearance.font.sizesFor(QsWindow.window)
    property alias colBackground: background.color
    property alias radius: background.radius

    Layout.fillHeight: true
    implicitWidth: 200 * filterField.uiScale
    padding: 10 * filterField.uiScale

    placeholderTextColor: Appearance.colors.colSubtext
    color: Appearance.colors.colOnLayer1
    font {
        family: Appearance.font.family.main
        pixelSize: filterField.fontSizes.small * filterField.uiScale
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    renderType: (QsWindow.window?.nativeTextRendering ?? false) ? Text.NativeRendering : Text.QtRendering
    selectedTextColor: Appearance.colors.colOnSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer

    background: Rectangle {
        id: background
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.full
    }

    // The toolkit grows its own editing menu on a right click; leaving it in
    // place would open both.
    ContextMenu.menu: null

    TextFieldContextMenuArea {}
}
