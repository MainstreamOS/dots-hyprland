import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common

/**
 * The editing menu for a text field, drawn the way the shell draws every
 * other context menu rather than the way the toolkit draws its own.
 *
 * A field showing dots instead of characters keeps its content out of the
 * clipboard: cut and copy stay disabled however much is selected.
 */
ContextMenuPopup {
    id: root

    required property Item target

    readonly property bool secret: root.target.echoMode !== undefined
        && root.target.echoMode !== TextInput.Normal

    contentItem: ColumnLayout {
        spacing: 0

        ContextMenuItem {
            iconName: "content_cut"
            label: Translation.tr("Cut")
            enabled: !root.secret && !root.target.readOnly && root.target.selectedText.length > 0
            onClicked: {
                root.target.cut()
                root.close()
            }
        }
        ContextMenuItem {
            iconName: "content_copy"
            label: Translation.tr("Copy")
            enabled: !root.secret && root.target.selectedText.length > 0
            onClicked: {
                root.target.copy()
                root.close()
            }
        }
        ContextMenuItem {
            iconName: "content_paste"
            label: Translation.tr("Paste")
            enabled: !root.target.readOnly && root.target.canPaste
            onClicked: {
                root.target.paste()
                root.close()
            }
        }

        ContextMenuSeparator {}

        ContextMenuItem {
            iconName: "select_all"
            label: Translation.tr("Select all")
            enabled: root.target.length > 0
            onClicked: {
                root.target.selectAll()
                root.close()
            }
        }
    }
}
