import QtQuick
import QtQuick.Controls

// A context menu shown as a popup inside another surface: the shared card
// behind it, with the rows set in by its padding. Give it a ColumnLayout of
// ContextMenuItem rows as its contentItem; where it opens and how it closes
// stay with the menu using it.
Popup {
    padding: menuCard.padding
    background: ContextMenuCard {
        id: menuCard
    }
}
