pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.services
import qs.modules.common

Rectangle {
    id: root
    required property var screen
    readonly property alias blurSource: wallpaperBlur
    readonly property bool ready: wallpaper.status !== Image.Loading
    // Sample the same wallpaper region as the dock for the workspace material.
    readonly property rect dockBackdropRect: {
        const dock = GlobalStates.dockWindows[screen?.name ?? ""];
        const rect = dock?.backdropGeometry;
        if (!rect || rect.width <= 0 || rect.height <= 0)
            return Qt.rect(0, height * 0.92, width, height * 0.08);
        const x = dock.dockEdge === "right" ? width - dock.width
            : dock.dockVertical ? 0 : (width - dock.width) / 2;
        const y = dock.dockEdge === "bottom" ? height - dock.height
            : dock.dockVertical ? (height - dock.height) / 2 : 0;
        const left = Math.max(0, Math.min(width - 1, x + rect.x));
        const top = Math.max(0, Math.min(height - 1, y + rect.y));
        return Qt.rect(left, top, Math.min(rect.width, width - left), Math.min(rect.height, height - top));
    }
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
        id: wallpaperBlur
        anchors.fill: parent
        source: wallpaper
        radius: 64
        // Window captures update independently of this static wallpaper.
        cached: true
    }
}
