import QtQuick

// Gives the text field or area it sits in the shell's editing menu on a right
// click. The field still sets `ContextMenu.menu: null` itself, or the
// toolkit's own menu opens as well.
//
// The menu is built on the first right click rather than with the field: it
// asks the field whether there is anything to paste, and that question
// reaches the clipboard — cheap where something owns the selection and
// answers, unbounded where nothing does. A field the user only ever types
// into should not have to ask.
Item {
    id: root
    property Item target: parent
    anchors.fill: parent

    Loader {
        id: menuLoader
        active: false
        sourceComponent: TextFieldContextMenu {
            target: root.target
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: eventPoint => {
            menuLoader.active = true;
            menuLoader.item.openAt(eventPoint.position.x, eventPoint.position.y);
        }
    }
}
