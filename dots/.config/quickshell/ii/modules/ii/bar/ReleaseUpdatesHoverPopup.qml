import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick

// Hover popup for ReleaseUpdatesIndicator, in the same shape the weather and
// clock widgets use. Says which release is waiting and nothing else — the
// right-click popup is where the actions live.
StyledPopup {
    id: root

    StyledPopupHeaderRow {
        anchors.centerIn: parent
        icon: "system_update_alt"
        label: ReleaseUpdates.latest
            ? ReleaseUpdates.availableLine(ReleaseUpdates.latest.version)
            : Translation.tr("Mainstream OS is up to date")
    }
}
