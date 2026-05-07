import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property bool hdrActive: false
    property bool barOpen: true
    property bool crosshairOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool mediaControlsOpen: false
    property bool mediaTransferActive: false
    property var mediaTransferUrls: []
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    // When true alongside overviewOpen, the overview shows only the
    // workspace previews — search bar and app drawer chrome are hidden.
    // Set by Bar.qml's hot corner when its trigger is configured for
    // "default overview" so that path opens a clean workspace switcher.
    // Auto-resets to false whenever overviewOpen flips to false.
    property bool overviewWorkspacesOnly: false
    onOverviewOpenChanged: {
        if (!overviewOpen) overviewWorkspacesOnly = false;
    }
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false
    property string openFolderId: ""  // Set by dock to open a folder in the app drawer
    // Whether the hyprland-scroll-overview plugin is currently loaded into
    // Hyprland. Bar.qml's top-left hot corner (dwell timer + ripple + dispatch
    // to `scrolloverview:overview on`) gates on this so neither the ripple
    // animation nor the dispatcher fires when the user has turned the plugin
    // off via Settings → Hot Corners → Scrolling Overview. Initial value is
    // taken from `hyprctl plugin list` at startup; the InterfaceConfig toggle
    // updates it directly when it loads/unloads the plugin.
    property bool scrollOverviewEnabled: false

    // Fired by Bar.qml's top-left hot corner once its dwell timer elapses
    // and the dispatch to scroll-overview goes out. HotCornerRipple listens
    // to this and plays a GNOME-style expanding-circle animation. Decoupling
    // via GlobalStates means the ripple's lifetime / visibility is
    // independent of the bar's per-monitor LazyLoader.
    signal hotCornerTriggered()

    onSidebarRightOpenChanged: {
        if (GlobalStates.sidebarRightOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }

    onMediaControlsOpenChanged: {
        if (!GlobalStates.mediaControlsOpen) {
            // Keep transfer state while a send is in flight so the user can
            // reopen the popup to check progress. Other states (idle / sent /
            // error) clear so the next bar click goes back to the player and
            // a stale Error doesn't bleed into the next session.
            if (LocalSend.state !== LocalSend.stateSending) {
                GlobalStates.mediaTransferActive = false;
                GlobalStates.mediaTransferUrls = [];
                LocalSend.reset();
            }
        }
    }

    // ── HDR detection: poll hyprctl for active HDR color management ──
    Process {
        id: hdrCheckProc
        command: ["hyprctl", "monitors", "-j"]
        property string output: ""
        stdout: SplitParser {
            onRead: data => hdrCheckProc.output += data
        }
        onExited: {
            try {
                let monitors = JSON.parse(hdrCheckProc.output);
                root.hdrActive = monitors.some(m =>
                    m.colorManagementPreset === "hdr" || m.colorManagementPreset === "hdredid"
                );
            } catch(e) {
                root.hdrActive = false;
            }
            hdrCheckProc.output = "";
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" || event.name === "monitoraddedv2" || event.name === "monitorremoved")
                hdrCheckProc.running = true;

            // Refresh scrolloverview load state whenever Hyprland reloads
            // configs — covers the InterfaceConfig toggle path (which runs
            // `hyprctl plugin load|unload` followed by `hyprctl reload`) as
            // well as any external plugin lifecycle changes.
            if (event.name === "configreloaded")
                scrollOverviewCheckProc.running = true;

            // Scroll-overview (Hyprland plugin) emits these on open/close
            // via g_pEventManager->postEvent. While the overview is up
            // we force fakeScreenRounding to 0 so the workspace cards
            // don't show rounded-corner artifacts where rounded windows
            // and rounded screen corners disagree; the user's previous
            // setting is captured on open and restored on close.
            // _savedFakeScreenRounding == -1 is the "not currently
            // overridden" sentinel — guards against double-open events
            // accidentally clobbering the saved value.
            if (event.name === "scrolloverview") {
                if (event.data === "open") {
                    if (root._savedFakeScreenRounding < 0) {
                        root._savedFakeScreenRounding = Config.options.appearance.fakeScreenRounding;
                        Config.options.appearance.fakeScreenRounding = 0;
                    }
                } else if (event.data === "close") {
                    if (root._savedFakeScreenRounding >= 0) {
                        Config.options.appearance.fakeScreenRounding = root._savedFakeScreenRounding;
                        root._savedFakeScreenRounding = -1;
                    }
                }
            }
        }
    }

    // Saved fakeScreenRounding while a scroll-overview session is
    // active; -1 when no override is in effect.
    property int _savedFakeScreenRounding: -1

    // Determine whether scrolloverview is loaded right now. Re-run after every
    // configreload (which happens both for normal `hyprctl reload` and right
    // after `hyprctl plugin load|unload`) so the state stays accurate without
    // the InterfaceConfig toggle having to push a value here directly.
    // `hyprctl -i 0 …` selects the first (and almost always only) live
    // Hyprland instance from `hyprctl instances` rather than relying on
    // the inherited HYPRLAND_INSTANCE_SIGNATURE env var. The env var
    // can go stale across Hyprland restarts (Quickshell keeps the value
    // it was launched with, even if Hyprland respawns), in which case
    // bare `hyprctl plugin list` connects to a dead socket and returns
    // nothing — leaving scrollOverviewEnabled false and the hot corner
    // disabled even with the plugin actually loaded.
    Process {
        id: scrollOverviewCheckProc
        command: ["hyprctl", "-i", "0", "plugin", "list"]
        property string output: ""
        stdout: SplitParser {
            onRead: data => scrollOverviewCheckProc.output += data
        }
        onExited: {
            root.scrollOverviewEnabled = /^Plugin\s+scrolloverview\b/m.test(scrollOverviewCheckProc.output);
            scrollOverviewCheckProc.output = "";
        }
    }

    Component.onCompleted: {
        hdrCheckProc.running = true;
        scrollOverviewCheckProc.running = true;
        // Hyprland's IPC socket isn't always ready at the exact moment
        // Quickshell's Component.onCompleted fires (visible as a brief
        // "ConnectionRefusedError" in the log on startup). The first
        // scrollOverviewCheckProc run can therefore return empty,
        // leaving scrollOverviewEnabled stuck at false until the next
        // configreloaded event. Retry after a short delay so the hot
        // corner becomes responsive without the user having to run
        // `hyprctl reload`.
        scrollOverviewStartupRetry.start();
    }

    Timer {
        id: scrollOverviewStartupRetry
        interval: 1500
        repeat: false
        onTriggered: scrollOverviewCheckProc.running = true
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"

        onPressed: {
            root.superDown = true
        }
        onReleased: {
            root.superDown = false
        }
    }
}