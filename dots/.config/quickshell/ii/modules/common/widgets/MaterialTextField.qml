import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls

/**
 * Material 3 styled TextField (filled style)
 * https://m3.material.io/components/text-fields/overview
 * Note: We don't use NativeRendering because it makes the small placeholder text look weird
 */
TextField {
    id: root
    Material.theme: Material.System
    Material.accent: Appearance.m3colors.m3primary
    Material.primary: Appearance.m3colors.m3primary
    Material.background: Appearance.m3colors.m3surface
    Material.foreground: Appearance.m3colors.m3onSurface
    Material.containerStyle: Material.Outlined
    renderType: Text.QtRendering

    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
    selectionColor: Appearance.colors.colSecondaryContainer
    placeholderTextColor: Appearance.m3colors.m3outline
    clip: true

    font {
        family: Appearance.font.family.main
        pixelSize: Appearance?.font.pixelSize.small ?? 15
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    wrapMode: TextEdit.Wrap

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
    }

    // The toolkit grows its own editing menu on a right click; leaving it in
    // place would open both.
    ContextMenu.menu: null

    // Built on the first right click rather than with the field. The menu asks
    // the field whether there is anything to paste, and that question reaches
    // the clipboard: cheap where something owns the selection and answers,
    // unbounded where nothing does. A field the user only ever types into
    // should not have to ask.
    Loader {
        id: editMenuLoader
        active: false
        sourceComponent: TextFieldContextMenu {
            target: root
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: eventPoint => {
            editMenuLoader.active = true;
            editMenuLoader.item.openAt(eventPoint.position.x, eventPoint.position.y);
        }
    }
}
