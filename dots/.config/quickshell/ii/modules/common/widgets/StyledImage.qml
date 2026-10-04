import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Image {
    id: styledImage
    // image:// sources (theme, tray icons) load on the main thread: the icon provider's
    // QIcon::fromTheme is not thread-safe, and a background load corrupts memory.
    asynchronous: !String(source).startsWith("image://")
    retainWhileLoading: true
    property bool fadeIn: true
    // retainWhileLoading keeps the last frame through a reload (new size or file);
    // hasFrame keeps it shown then instead of fading out and back in.
    property bool hasFrame: false
    visible: opacity > 0
    opacity: (status === Image.Ready || (status === Image.Loading && hasFrame)) ? 1 : 0
    Behavior on opacity {
        enabled: styledImage.fadeIn
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    property list<string> fallbacks: []
    property int currentFallbackIndex: 0

    onStatusChanged: {
        if (status === Image.Ready)
            hasFrame = true;
        else if (status === Image.Null || status === Image.Error)
            hasFrame = false;
        if (status === Image.Error && currentFallbackIndex < fallbacks.length) {
            source = fallbacks[currentFallbackIndex];
            currentFallbackIndex += 1;
        }
    }

    sourceSize: {
        const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
        return Qt.size(width * dpr, height * dpr);
    }
}
