import QtQuick
import qs.services
import qs.modules.common

Rectangle {
    property real uiScale: 1
    radius: RoundedCorners.on ? Appearance.rounding.dockBody * uiScale : 0
    color: Appearance.launcherWorkspaceBackground
}
