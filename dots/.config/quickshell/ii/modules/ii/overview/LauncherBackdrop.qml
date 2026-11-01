pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common

Rectangle {
    id: root
    required property var screen
    readonly property bool ready: wallpaper.status !== Image.Loading
    color: Appearance.m3colors.m3background
    clip: true
    Image {
        id: wallpaper
        anchors.fill: parent
        visible: false
        source: MonitorWallpapers.pathFor(root.screen?.name ?? "") || Appearance.wallpaperFile
            || Quickshell.shellPath("assets/images/default_wallpaper.webp")
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio / 2),
            Math.ceil(height * Screen.devicePixelRatio / 2))
    }
    FastBlur {
        anchors.fill: parent
        source: wallpaper
        radius: 64
        // Window captures update independently of this static wallpaper.
        cached: true
    }
}
