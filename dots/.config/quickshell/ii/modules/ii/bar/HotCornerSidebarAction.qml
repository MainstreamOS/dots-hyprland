import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common

// A hot corner action: toggle the sidebar on the corner's side. The right corner
// also changes the volume on scroll, as the bar's right side does beneath it.
// HotCornerRipple provides the corner itself.
Scope {
    id: root

    property bool right: true

    signal fired()

    // Runs only once the compositor has confirmed the pointer. Closing always
    // works; opening waits while another dismissable overlay is up, for the
    // same synthesized entries the overview corner guards against.
    function act(): void {
        const open = root.right ? GlobalStates.sidebarRightOpen : GlobalStates.sidebarLeftOpen;
        if (!open && GlobalFocusGrab.dismissable.length > 0) return;
        root.fired();
        if (root.right)
            GlobalStates.sidebarRightOpen = !open;
        else
            GlobalStates.sidebarLeftOpen = !open;
    }

    function scroll(up: bool): void {
        if (!root.right) return;
        if (up) Audio.incrementVolume();
        else Audio.decrementVolume();
    }
}
