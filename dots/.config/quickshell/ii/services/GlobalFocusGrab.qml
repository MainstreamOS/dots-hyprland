pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import qs
import Quickshell
import Quickshell.Hyprland

/**
 * Manages a HyprlandFocusGrab that's to be shared by all windows.
 * "Persistent" is for windows that should always be included but not closed on dismiss, like bar and onscreen keyboard.
 * "Dismissable" is for stuff like sidebars
 */ 
Singleton {
    id: root

    signal dismissed()

    property list<var> persistent: []
    property list<var> dismissable: []
    property var focusTarget: null

    function dismiss() {
        root.dismissable = [];
        root.focusTarget = null;
        root.dismissed();
    }

    Component.onCompleted: {
        console.log("[GlobalFocusGrab] Initialized");
    }

    function addPersistent(window) {
        if (root.persistent.indexOf(window) === -1) {
            root.persistent.push(window);
        }
    }

    function removePersistent(window) {
        var index = root.persistent.indexOf(window);
        if (index !== -1) {
            root.persistent.splice(index, 1);
        }
    }

    function addDismissable(window) {
        if (root.dismissable.indexOf(window) === -1) {
            root.dismissable.push(window);
        }
        // Admit the new popup before releasing modal search's keyboard focus.
        if (root.focusTarget && root.focusTarget !== window) root.focusTarget = null;
    }

    // Search is modal; admit it before narrowing the grab so the compositor
    // always has a committed surface to focus during the transition.
    function focus(window) {
        root.addDismissable(window);
        Qt.callLater(() => {
            if (root.dismissable.includes(window)) root.focusTarget = window;
        });
    }

    function removeDismissable(window) {
        var index = root.dismissable.indexOf(window);
        if (index !== -1) {
            root.dismissable.splice(index, 1);
        }
        if (root.focusTarget === window) root.focusTarget = null;
    }

    function hasActive(element) {
        // Following the focused item's parents avoids watching every child
        // while a sidebar's notification delegates are being created.
        for (let focused = element?.Window.window?.activeFocusItem; focused; focused = focused.parent) {
            if (focused === element) return true;
        }
        return false;
    }

    HyprlandFocusGrab {
        id: grab
        // Keep the old surfaces admitted until a replacement is visible: an empty
        // grab ends it, and its delayed cleared event would close the popup.
        windows: root.focusTarget?.contentItem.Window.window?.visible ? [root.focusTarget]
            : root.dismissable.some(w => !w?.contentItem.Window.window?.visible)
                || root.dismissable.every(w => !w?.focusable) || root.dismissable.some(w => hasActive(w?.contentItem))
                ? [...root.dismissable, ...root.persistent] : [...root.dismissable]
        active: root.dismissable.length > 0 && !GlobalStates.scrollOverviewOpen
        onCleared: () => {
            if (!GlobalStates.scrollOverviewOpen) root.dismiss();
        }
    }

}
