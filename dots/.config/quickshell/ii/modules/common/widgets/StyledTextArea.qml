import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import Quickshell

/**
 * Does not include visual layout, but includes the easily neglected colors.
 */
TextArea {
    id: root
    property var pasteHandler: null

    function cutSelection(): void {
        if (root.readOnly || !root.enabled || root.selectedText.length === 0)
            return;
        const start = root.selectionStart;
        const end = root.selectionEnd;
        Quickshell.clipboardText = root.selectedText;
        root.remove(start, end);
    }

    // Forward before a page's suggestion/send key handler. The editing menu
    // uses the same callback, including when the clipboard only has an image.
    Keys.forwardTo: [clipboardKeys]
    Item {
        id: clipboardKeys
        Keys.onPressed: event => {
            if (event.matches(StandardKey.Cut)) {
                root.cutSelection();
                event.accepted = true;
                return;
            }
            const plain = event.key === Qt.Key_V && event.modifiers === (Qt.ControlModifier | Qt.ShiftModifier);
            if (typeof root.pasteHandler === "function" && (event.matches(StandardKey.Paste) || plain)) {
                root.pasteHandler(plain);
                event.accepted = true;
            }
        }
    }

    renderType: (QsWindow.window?.nativeTextRendering ?? false) ? Text.NativeRendering : Text.QtRendering
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
