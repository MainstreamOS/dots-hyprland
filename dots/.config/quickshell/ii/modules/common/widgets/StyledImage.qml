import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Image {
    id: styledImage
    asynchronous: true
    retainWhileLoading: true
    // Off for an image that is already on disk and should simply be there,
    // such as the album art a player card is built with.
    property bool fadeIn: true
    // retainWhileLoading keeps the last frame while the image loads again,
    // for a new size or a new file, so it stays shown through that instead
    // of fading out and back in.
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
