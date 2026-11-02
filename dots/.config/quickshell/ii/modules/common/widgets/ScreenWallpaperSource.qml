import QtQuick
import Quickshell
import qs.services

/**
 * This window's screen wallpaper, unseen and placed where it shows on screen,
 * for FastBlurred to sample. A blur hides detail, so half the pixels will do.
 */
Item {
    id: root
    readonly property var window: QsWindow.window
    readonly property var placement: WallpaperPlacement.screens[window?.screen?.name ?? ""] ?? null
    // Stays true while a later picture loads, so a swap doesn't take the blur down with it.
    property bool loadedOnce: false
    readonly property bool available: !!placement && !placement.video && loadedOnce
    readonly property alias picture: picture

    // The window's content item lasts through every hide and show, so the picture moves
    // into it once and stays. Moved while Qt is still handing items their window, it
    // could keep one that is then deleted and crash the shell, so the move waits.
    property Item host: null
    function adopt() {
        const item = root.window?.contentItem;
        if (item && item !== root.host)
            root.host = item;
    }
    onWindowChanged: Qt.callLater(root.adopt)
    Component.onCompleted: Qt.callLater(root.adopt)

    // A layer anchored to neither of a pair of opposite edges sits centered between them.
    function origin(start, end, startMargin, endMargin, screenSize, windowSize) {
        return start ? startMargin : end ? screenSize - windowSize - endMargin : (screenSize - windowSize) / 2;
    }

    Connections {
        target: WallpaperPlacement
        function onFreeze(screenName) {
            if (screenName === root.window?.screen?.name) picture.backdropFreeze();
        }
        function onRelease(screenName, fadeMs) {
            if (screenName === root.window?.screen?.name) picture.backdropRelease(fadeMs);
        }
    }

    Image {
        id: picture
        signal backdropFreeze()
        signal backdropRelease(real fadeMs)
        onStatusChanged: if (status === Image.Ready) root.loadedOnce = true
        // Measured from the window itself, whatever the surface asking is inside of.
        parent: root.host ?? root
        visible: false
        x: (root.placement?.x ?? 0) - root.origin(root.window?.anchors?.left, root.window?.anchors?.right, root.window?.margins?.left ?? 0, root.window?.margins?.right ?? 0, root.window?.screen?.width ?? 0, root.window?.width ?? 0)
        y: (root.placement?.y ?? 0) - root.origin(root.window?.anchors?.top, root.window?.anchors?.bottom, root.window?.margins?.top ?? 0, root.window?.margins?.bottom ?? 0, root.window?.screen?.height ?? 0, root.window?.height ?? 0)
        width: root.placement?.width ?? 0
        height: root.placement?.height ?? 0
        source: root.placement && !root.placement.video ? root.placement.path : ""
        sourceSize: Qt.size(Math.ceil(width / 2), Math.ceil(height / 2))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
    }
}
