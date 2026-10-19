import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common

// A hot corner action: toggle the right sidebar, and change the volume on
// scroll the way the bar's right side does beneath the top-right corner.
// HotCornerRipple provides the corner itself.
Scope {
    id: root

    signal fired()

    // Runs only once the compositor has confirmed the pointer. Closing always
    // works; opening waits while another dismissable overlay is up, for the
    // same synthesized entries the overview corner guards against.
    function act(): void {
        if (!GlobalStates.sidebarRightOpen && GlobalFocusGrab.dismissable.length > 0) return;
        root.fired();
        GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
    }

    function scroll(up: bool): void {
        if (up) Audio.incrementVolume();
        else Audio.decrementVolume();
    }
}
