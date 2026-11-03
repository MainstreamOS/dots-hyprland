import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Under the dock's Frost preset, the part of the wallpaper the dock shows, blurred
 * and hazed the way the dock's own is, so the launcher reads as the same material.
 * Drawn below the surface it fills, whose color then goes on top as the dock's does.
 */
Item {
    id: root
    property real radius: 0
    // Off where the surface sits on another surface rather than over the desktop.
    property bool wanted: true
    readonly property bool shown: root.wanted && Appearance.launcherSamplesWallpaper
        && (wallpaperSource.item?.available ?? false)
    // Empty until the dock on this screen has sampled; until then the surface's own part stands in.
    readonly property rect dockSample: GlobalStates.dockWindows[QsWindow.window?.screen?.name ?? ""]?.backdropSample
        ?? Qt.rect(0, 0, 0, 0)

    // Where the surface sits in its window, read through every parent and Translate,
    // so the sample follows it as the launcher scrolls, slides in and lays itself out.
    readonly property point placed: {
        let x = 0, y = 0;
        for (let item = root; item; item = item.parent) {
            x += item.x;
            y += item.y;
        }
        for (const shift of root.shifts) {
            x += shift.x;
            y += shift.y;
        }
        return Qt.point(x, y);
    }
    // A transform list can't be bound to, so its Translates are gathered once laid out.
    property var shifts: []
    function gatherShifts() {
        const found = [];
        for (let item = root; item; item = item.parent) {
            for (let i = 0; i < item.transform.length; i++) {
                const shift = item.transform[i];
                if (typeof shift.x === "number" && typeof shift.y === "number")
                    found.push(shift);
            }
        }
        root.shifts = found;
    }
    Component.onCompleted: Qt.callLater(root.gatherShifts)

    anchors.fill: parent
    z: -1

    Loader {
        id: wallpaperSource
        active: root.wanted && Appearance.launcherSamplesWallpaper
        sourceComponent: ScreenWallpaperSource {}
    }
    SurfaceBackdrop {
        anchors.fill: parent
        visible: root.shown
        settings: Config.options.dock.backdrop
        source: wallpaperSource.item
        topLeftRadius: root.radius
        topRightRadius: root.radius
        bottomLeftRadius: root.radius
        bottomRightRadius: root.radius
        trackX: root.placed.x
        trackY: root.placed.y
        sampleRect: root.dockSample
    }
}
