import QtQuick
import QtQuick.Controls
import qs.modules.common

// A context menu shown as a popup inside another surface: the shared card
// behind it, with the rows set in by its padding. Give it a ColumnLayout of
// ContextMenuItem rows as its contentItem; where it opens and how it closes
// stay with the menu using it.
Popup {
    id: root
    padding: menuCard.padding
    background: ContextMenuCard {
        id: menuCard
    }

    // Opens at a point in the parent's coordinates. A menu that would run past
    // the window's right or bottom edge opens to the left of or above the
    // point instead, and is then held inside the window either way.
    function openAt(px, py) {
        const win = root.parent?.Window;
        if (win && win.width > 0) {
            const at = root.parent.mapToItem(null, px, py);
            const margin = Appearance.sizes.elevationMargin;
            const place = (pos, size, room) => {
                const flipped = pos + size + margin > room ? pos - size : pos;
                return Math.max(margin, Math.min(flipped, room - size - margin));
            };
            // A menu built by this very right click may not have measured
            // itself yet; a typical menu's size stands in until it has.
            px += place(at.x, root.implicitWidth || 200, win.width) - at.x;
            py += place(at.y, root.implicitHeight || 170, win.height) - at.y;
        }
        root.x = px;
        root.y = py;
        root.open();
    }
}
