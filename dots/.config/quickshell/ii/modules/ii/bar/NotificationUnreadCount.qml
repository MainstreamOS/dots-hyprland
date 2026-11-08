import Quickshell
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

MaterialSymbol {
    id: root
    property real uiScale: QsWindow.window?.uiScale ?? 1
    readonly property bool showUnreadCount: Config.options.bar.indicators.notifications.showUnreadCount
    text: Notifications.silent ? "notifications_paused" : "notifications"
    iconSize: Appearance.font.basePixelSize.larger * root.uiScale
    color: rightSidebarButton.colText

    Rectangle {
        id: notifPing
        visible: !Notifications.silent && Notifications.unread > 0
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: root.showUnreadCount ? 0 : 1 * root.uiScale
            topMargin: root.showUnreadCount ? 0 : 3 * root.uiScale
        }
        radius: Appearance.rounding.full
        color: Appearance.barContent.colOnLayer0
        z: 1

        implicitHeight: root.showUnreadCount ? Math.max(notificationCounterText.implicitWidth, notificationCounterText.implicitHeight) : 8 * root.uiScale
        implicitWidth: implicitHeight

        StyledText {
            id: notificationCounterText
            visible: root.showUnreadCount
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.basePixelSize.smallest * root.uiScale
            color: Appearance.barContent.colLayer0
            text: Notifications.unread
        }
    }
}
