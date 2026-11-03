import QtQuick
import qs.services
import qs.modules.common

Rectangle {
    property real uiScale: 1
    property real searchHeight: 48 * uiScale
    readonly property real collapsedWidth: (Appearance.sizes.searchWidthCollapsed + 22 + 8 + 40 * 3 + 6 * 4 + 4 + 14) * uiScale
    implicitHeight: Math.ceil(searchHeight + 8 * uiScale)
    radius: RoundedCorners.on ? searchHeight / 2 + 4 * uiScale : 0
    property alias samplesWallpaper: wallpaperBackdrop.wanted
    color: wallpaperBackdrop.shown ? Appearance.colors.colDockBackground : Appearance.launcherSearchBackground
    LauncherWallpaperBackdrop {
        id: wallpaperBackdrop
        radius: parent.radius
    }
}
