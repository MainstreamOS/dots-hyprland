import QtQuick
import qs
import qs.services

// Drag a file (or files) from a file manager onto a bar media widget to open
// the media controls popup in LocalSend transfer mode. The popup's own drop
// area finalizes the drop; this one opens it on hover so the user has a
// visible target to release on. One component under both bars' widgets, so a
// drag means the same thing whichever bar the widget is on.
DropArea {
    id: root

    // What the controls popup lines itself up with when the drag opens it.
    required property Item popupAnchorItem

    z: 5

    onEntered: (drag) => {
        if (!drag.hasUrls) return;
        // While a send is in flight, ignore new drags so the running upload
        // isn't disturbed; the user can finish the current send (or wait for
        // it) before starting another.
        if (LocalSend.state === LocalSend.stateSending) return;
        GlobalStates.mediaWidgetItem = root.popupAnchorItem;
        GlobalStates.mediaTransferActive = true;
        GlobalStates.mediaControlsOpen = true;
    }
    onDropped: (drop) => {
        if (LocalSend.state === LocalSend.stateSending) return;
        const urls = (drop.urls ?? []).map(u => String(u));
        if (urls.length > 0) GlobalStates.mediaTransferUrls = urls;
        drop.accept(Qt.CopyAction);
    }
}
