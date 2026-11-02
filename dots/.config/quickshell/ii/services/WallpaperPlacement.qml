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
    // A swap's picture stays behind a backdrop until the effect has come part of
    // the way, then fades in over this many milliseconds.
    signal freeze(string screenName)
    signal release(string screenName, real fadeMs)

    function publish(screenName, placement) {
        const next = Object.assign({}, root.screens);
        if (placement)
            next[screenName] = placement;
        else
            delete next[screenName];
        root.screens = next;
    }
}
