import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.sidebarRight.notifications
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    radius: Appearance.rounding.normal
    // A card on the Dynamic Island's raised surface, as its panels' cards are.
    color: Appearance.surfaces.raised

    NotificationList {
        anchors.fill: parent
        anchors.margins: 5
    }
}
