pragma Singleton

import QtQuick
import Quickshell

/**
 * Where each screen's wallpaper sits, published by the background so a surface
 * in another window can sample the same picture in the same place.
 */
Singleton {
    id: root
    property var screens: ({})

    function publish(screenName, placement) {
        const next = Object.assign({}, root.screens);
        if (placement)
            next[screenName] = placement;
        else
            delete next[screenName];
        root.screens = next;
    }
}
