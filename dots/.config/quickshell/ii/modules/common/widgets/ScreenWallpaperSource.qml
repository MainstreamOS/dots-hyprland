import QtQuick
import Quickshell
import qs.services

/**
 * This window's screen wallpaper, unseen and placed where it shows on screen,
 * for FastBlurred to sample. A blur hides detail, so half the pixels will do.
 */
Image {
    id: root
    readonly property var window: QsWindow.window
    readonly property var placement: WallpaperPlacement.screens[window?.screen?.name ?? ""] ?? null
    readonly property bool available: !!placement && !placement.video && status === Image.Ready

    // A layer anchored to neither of a pair of opposite edges sits centered between them.
    function origin(start, end, screenSize, windowSize) {
        return (start && !end) ? 0 : (end && !start) ? screenSize - windowSize : (start && end) ? 0 : (screenSize - windowSize) / 2;
    }

    parent: window?.contentItem ?? null
    visible: false
    x: (placement?.x ?? 0) - origin(window?.anchors?.left, window?.anchors?.right, window?.screen?.width ?? 0, window?.width ?? 0)
    y: (placement?.y ?? 0) - origin(window?.anchors?.top, window?.anchors?.bottom, window?.screen?.height ?? 0, window?.height ?? 0)
    width: placement?.width ?? 0
    height: placement?.height ?? 0
    source: placement && !placement.video ? placement.path : ""
    sourceSize: Qt.size(Math.ceil(width / 2), Math.ceil(height / 2))
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    smooth: true
}
