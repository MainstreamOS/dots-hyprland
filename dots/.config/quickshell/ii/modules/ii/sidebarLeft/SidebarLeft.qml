import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property bool detach: false
    // Not bound: "Pinned by default" decides it on each open, and a toggle
    // holds until the next one.
    property bool pin: false
    readonly property bool extend: sidebarLoader.item?.extend ?? false
    property Component contentComponent: SidebarLeftContent {}
    property Item sidebarContent
    property bool detachedFocusPending: false

    function focusDetached() {
        if (!root.detachedFocusPending) return;
        if (!root.detach || !GlobalStates.sidebarLeftOpen) {
            root.detachedFocusPending = false;
            return;
        }
        const window = HyprlandData.windowList.find(w => w.pid === Quickshell.processId
            && w.title === detachedSidebarLoader.item?.title);
        if (!window) return;
        root.detachedFocusPending = false;
        // Like the dock, target the window's address: Wayland activation can
        // be ignored, and focus alone does not raise a covered floating window.
        Hyprland.dispatch(`hl.dsp.focus({window = "address:${window.address}"})`);
        if (window.floating) Hyprland.dispatch(`MainstreamRaiseFloat("address:${window.address}")`);
    }

    Connections {
        target: HyprlandData
        enabled: root.detachedFocusPending
        function onWindowListChanged() { root.focusDetached(); }
    }

    function toggleDetach() {
        root.detach = !root.detach;
    }

    function openDetached() {
        root.detach = true;
        GlobalStates.sidebarLeftOpen = true;
    }

    function reattach() {
        root.detach = false;
        GlobalStates.sidebarLeftOpen = true;
    }

    function toggleExtend() {
        if (root.detach || !sidebarLoader.item)
            return;
        sidebarLoader.item.extend = !sidebarLoader.item.extend;
    }

    Process { // Dodge cursor away, pin, move cursor back
        id: pinWithFunnyHyprlandWorkaroundProc
        property var hook: null
        property int cursorX;
        property int cursorY;
        function doIt() {
            command = ["hyprctl", "cursorpos"]
            hook = (output) => {
                cursorX = parseInt(output.split(",")[0]);
                cursorY = parseInt(output.split(",")[1]);
                doIt2();
            }
            running = true;
        }
        function doIt2(output) {
            command = ["bash", "-c", "hyprctl dispatch 'hl.dsp.cursor.move({x=9999,y=9999})'"];
            hook = () => {
                doIt3();
            }
            running = true;
        }
        function doIt3(output) {
            root.pin = !root.pin;
            command = ["bash", "-c", `sleep 0.01; hyprctl dispatch 'hl.dsp.cursor.move({x=${cursorX},y=${cursorY}})'`];
            hook = null
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                // The last step has nothing to run after it.
                if (pinWithFunnyHyprlandWorkaroundProc.hook)
                    pinWithFunnyHyprlandWorkaroundProc.hook(text);
            }
        }
    }

    Binding {
        target: GlobalStates
        property: "sidebarLeftPinned"
        value: GlobalStates.sidebarLeftOpen && root.pin && !root.detach
    }
    Binding {
        target: GlobalStates
        property: "sidebarLeftDetached"
        value: root.detach
    }
    Binding {
        target: GlobalStates
        property: "sidebarLeftWidth"
        value: sidebarLoader.item?.sidebarWidth ?? Appearance.sizes.sidebarWidth
    }

    // The strip the pinned sidebar reserves, and where, for the surfaces
    // raised over it with the overview that would otherwise keep clear of it.
    Binding {
        target: GlobalStates
        property: "sidebarLeftZone"
        value: GlobalStates.sidebarLeftOpen && root.pin && !root.detach
            ? (sidebarLoader.item?.sidebarWidth ?? 0) : 0
    }
    Binding {
        target: GlobalStates
        property: "sidebarLeftScreen"
        value: sidebarLoader.item?.screen?.name ?? ""
    }

    // How far in from its edge the sidebar reaches while it is open without
    // reserving that room, so popups on the same edge can sit beside it.
    Binding {
        target: GlobalStates
        property: "sidebarLeftCover"
        value: GlobalStates.sidebarLeftOpen && !root.pin && !root.detach
            ? (sidebarLoader.item?.sidebarWidth ?? Appearance.sizes.sidebarWidth) : 0
    }

    function togglePin() {
        if (root.detach)
            return;
        if (!root.pin) pinWithFunnyHyprlandWorkaroundProc.doIt()
        else root.pin = !root.pin;
    }

    function applyPinnedByDefault() {
        root.pin = Config.options?.sidebar?.pinnedOnStartup ?? true;
    }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen)
                root.applyPinnedByDefault();
        }
    }

    Connections {
        target: SidebarLeftTabs
        function onRequestTab(tabId) {
            GlobalStates.sidebarLeftOpen = true;
            // An already open detached sidebar may be behind another window
            // or minimized. Selecting its page alone does not bring it back.
            if (root.detach && detachedSidebarLoader.item) {
                root.detachedFocusPending = true;
                detachedSidebarLoader.item.minimized = false;
                Qt.callLater(root.focusDetached);
            }
        }
    }

    Component.onCompleted: {
        root.applyPinnedByDefault();
        root.sidebarContent = contentComponent.createObject(null, {
            "scopeRoot": root,
        });
        sidebarLoader.item.contentParent.children = [root.sidebarContent];
    }

    onDetachChanged: {
        if (root.detach) {
            GlobalFocusGrab.removeDismissable(sidebarLoader.item) // Remove sidebar from the focus grab system
            sidebarContent.parent = null; // Detach content from sidebar
            sidebarLoader.active = false; // Unload sidebar
            detachedSidebarLoader.active = true; // Load detached window
            detachedSidebarLoader.item.contentParent.children = [sidebarContent];
        } else {
            sidebarContent.parent = null; // Detach content from window
            detachedSidebarLoader.active = false; // Unload detached window
            sidebarLoader.active = true; // Load sidebar
            sidebarLoader.item.contentParent.children = [sidebarContent];
        }
    }

    Loader {
        id: sidebarLoader
        active: true
        
        sourceComponent: PanelWindow { // Window
            id: panelWindow
            visible: GlobalStates.sidebarLeftOpen
            
            property bool extend: false
            property real sidebarWidth: panelWindow.extend ? Appearance.sizes.sidebarWidthExtended : Appearance.sizes.sidebarWidth
            property var contentParent: sidebarLeftBackground

            function hide() {
                GlobalStates.sidebarLeftOpen = false
            }

            exclusionMode: ExclusionMode.Normal
            exclusiveZone: (root.pin && GlobalStates.sidebarLeftOpen) ? sidebarWidth : 0
            // Pinned, the sidebar's reserved space moves every window beside
            // it as it comes and goes, and Hyprland reports no window event
            // for that, so the window list everything else reads would keep
            // the old positions. Showing and hiding it pinned does the same;
            // see onVisibleChanged below.
            onExclusiveZoneChanged: HyprlandData.refreshSoon()
            implicitWidth: Appearance.sizes.sidebarWidthExtended + Appearance.sizes.elevationMargin
            WlrLayershell.namespace: "quickshell:sidebarLeft"
            // Hyprland 0.49: OnDemand is Exclusive, Exclusive just breaks click-outside-to-close
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            readonly property bool onRight: Appearance.sizes.sidebarLeftEdge === "right"
            // An auto-hidden bar slides in over this edge without reserving its
            // room, so the card shortens to sit beside it as it comes in.
            property real barInset: GlobalStates.barOverlapScreens.includes(panelWindow.screen?.name ?? "")
                ? Appearance.sizes.baseBarHeight + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0) : 0
            Behavior on barInset {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            anchors {
                top: true
                left: !panelWindow.onRight
                right: panelWindow.onRight
                bottom: true
            }

            mask: Region {
                item: sidebarLeftBackground
            }

            // Pinned, the sidebar stays up while the desktop is used: it
            // leaves the shared focus grab, so a click on a window goes to that
            // window instead of closing the sidebar, and the keyboard follows
            // the click there and back. Unpinned, it closes on a click outside
            // again. Super+A and Escape still close it either way.
            function syncFocusGrab() {
                if (panelWindow.visible && !root.pin)
                    GlobalFocusGrab.addDismissable(panelWindow);
                else
                    GlobalFocusGrab.removeDismissable(panelWindow);
            }
            onVisibleChanged: {
                panelWindow.syncFocusGrab();
                if (root.pin) HyprlandData.refreshSoon();
            }
            Connections {
                target: root
                function onPinChanged() {
                    panelWindow.syncFocusGrab();
                }
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    if (!root.pin)
                        panelWindow.hide();
                }
            }

            // Content
            StyledRectangularShadow {
                target: sidebarLeftBackground
                radius: sidebarLeftBackground.radius
            }
            Rectangle {
                id: sidebarLeftBackground
                anchors.top: parent.top
                anchors.topMargin: Appearance.sizes.hyprlandGapsOut + (Config.options.bar.bottom ? 0 : panelWindow.barInset)
                // Held against whichever edge the panel opens from, so the
                // card keeps its screen gap there and the width animation
                // below grows inward rather than off the display. Placed by x
                // rather than by trading a left anchor for a right one: while
                // the trade is under way both hold, which stretches the card
                // to the whole window and leaves it that wide.
                x: panelWindow.onRight ? parent.width - width - Appearance.sizes.hyprlandGapsOut
                    : Appearance.sizes.hyprlandGapsOut
                width: panelWindow.sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                height: parent.height - Appearance.sizes.hyprlandGapsOut * 2 - panelWindow.barInset
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                radius: RoundedCorners.on ? Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1 : 0

                Behavior on width {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.hide();
                    }
                }
            }
        }
    }

    Loader {
        id: detachedSidebarLoader
        active: false

        sourceComponent: FloatingWindow {
            id: detachedSidebarRoot
            title: Translation.tr("Sidebar")
            property var contentParent: detachedSidebarBackground
            color: "transparent"

            visible: GlobalStates.sidebarLeftOpen
            onVisibleChanged: {
                if (!visible) GlobalStates.sidebarLeftOpen = false;
            }
            
            Rectangle {
                id: detachedSidebarBackground
                anchors.fill: parent
                color: Appearance.colors.colLayer0
            }
        }
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen
        }

        function toggleDetach(): void {
            root.toggleDetach();
        }

        function openDetached(): void {
            root.openDetached();
        }

        function reattach(): void {
            root.reattach();
        }

        function close(): void {
            GlobalStates.sidebarLeftOpen = false
        }

        function open(): void {
            GlobalStates.sidebarLeftOpen = true
        }

        function openTab(tabId: string): void {
            SidebarLeftTabs.showTab(tabId);
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftOpen"
        description: "Opens left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftClose"
        description: "Closes left sidebar on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = false;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggleDetach"
        description: "Detach left sidebar into a window/Attach it back"

        onPressed: root.toggleDetach()
    }

    GlobalShortcut {
        name: "sidebarLeftOpenDetached"
        description: "Open left sidebar detached into a window"

        onPressed: root.openDetached()
    }

    GlobalShortcut {
        name: "sidebarLeftReattach"
        description: "Reattach left sidebar back to screen edge"

        onPressed: root.reattach()
    }

}
