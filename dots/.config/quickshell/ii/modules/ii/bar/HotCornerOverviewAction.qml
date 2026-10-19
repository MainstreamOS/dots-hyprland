pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common

// A hot corner action: open or close the overview its corner's trigger
// names. HotCornerRipple provides the corner itself.
Scope {
    id: root

    // The corner's trigger: "default" (built-in overview) or "scrolloverview".
    property string mode: "off"

    // The corner acted, here or through the overview closing itself from the
    // same rectangle (Overview.qml), which goes through the same signal.
    signal fired()
    Connections {
        target: GlobalStates
        function onHotCornerTriggered() {
            root.fired();
        }
    }

    // Runs only once the compositor has confirmed the pointer.
    function act(): void {
        const trig = root.mode;

        // Close path: "default" with overview already open
        // toggles it off and fires the ripple in parallel
        // with the overview's own fade-out (Overlay > Top
        // layer, so the cascade stays visible above the
        // closing overview). Symmetric with the open path's
        // visual feedback, just without the open delay:
        // the close itself happens immediately.
        if (trig === "default" && GlobalStates.overviewOpen) {
            GlobalStates.hotCornerTriggered();
            GlobalStates.overviewOpen = false;
            return;
        }

        // Close path: "scrolloverview" with its overview already
        // up toggles it off: call the dispatcher that
        // overview("off") returns and fire the ripple in parallel,
        // mirroring the "default" close above. Runs before the
        // dismissable check (like default) so the corner can always
        // close it.
        if (trig === "scrolloverview" && GlobalStates.scrollOverviewOpen) {
            GlobalStates.hotCornerTriggered();
            Quickshell.execDetached(["hyprctl", "eval",
                '(function() local f = hl.plugin.scrolloverview.overview("off") if type(f) == "function" then f() end end)()']);
            return;
        }

        // Skip the open path when an unrelated dismissable
        // overlay (cheatsheet, sidebar, media controls, …)
        // is up. Those overlays activate Hyprland's focus
        // grab via GlobalFocusGrab.addDismissable, and grab
        // activation refreshes pointer focus across the
        // listed surfaces, which includes the corner's panel via
        // its persistent registration. If the cursor
        // sits inside the trigger region at that moment,
        // Hyprland synthesizes a fresh onEntered there and
        // the dwell + delay sequence would re-fire the
        // corner alongside the overlay the user actually
        // opened. Default-trigger close runs earlier above
        // and returns before this check, so toggling the
        // dots overview off via the corner still works.
        if (GlobalFocusGrab.dismissable.length > 0) return;

        // Open path (both scrolloverview and default): emit
        // the global trigger signal so every monitor's ripple
        // fires together (and every corner holds off a repeat),
        // then the delay timer below opens the matching overview
        // after the cascade.
        GlobalStates.hotCornerTriggered();
        delayTimer.restart();
    }

    // Self-healing dispatch for the scrolloverview plugin.
    //
    // Failure mode: the layer.opened workaround in custom/general.lua
    // does an `hyprctl plugin unload + 100ms + load` cycle every
    // time Quickshell's layer surface registers (which happens on
    // initial Hyprland start AND on every Quickshell reload). The
    // cycle is fire-and-forget: if the re-load races with the
    // plugin's previous unload, or hyprctl returns "Cannot load a
    // plugin twice" during a transient state, the plugin can end up
    // unloaded. Once unloaded, hl.plugin.scrolloverview is nil and
    // every corner dispatch errors with "attempt to index a nil
    // value (field 'scrolloverview')".
    //
    // The Lua expression below guards on the function existing:
    //   - If loaded → call overview("on")
    //   - If nil → return a sentinel string we can grep for in the
    //     dispatchProc.onExited handler, which then triggers a
    //     force-reload so the NEXT click works.
    //
    // Wrapping in a do/return block keeps the expression a single
    // statement that the hyprctl eval wrap (`return hl.dispatch(<X>)`
    // (see HyprCtl.cpp:1108) doesn't trip over.
    Process {
        id: dispatchProc
        // Upstream's dispatcher refactor (scroll-overview afa8fc8) changed
        // overview(arg): outside a __lua keybind it no longer dispatches;
        // it RETURNS the dispatcher function. So call what it returns. The
        // IIFE keeps it a single expression (the eval wrap can't trip over
        // it) and lets the nil-plugin error still surface: when the plugin's
        // Lua function is missing, indexing it errors with "attempt to index
        // a nil value (field 'scrolloverview')", which onExited greps to
        // trigger the force-reload so the NEXT hover succeeds.
        command: ["hyprctl", "eval",
            '(function() local f = hl.plugin.scrolloverview.overview("on") if type(f) == "function" then f() end end)()']
        property string outBuf: ""
        property string errBuf: ""
        onRunningChanged: if (running) { outBuf = ""; errBuf = "" }
        stdout: SplitParser { onRead: data => dispatchProc.outBuf += data + "\n" }
        stderr: SplitParser { onRead: data => dispatchProc.errBuf += data + "\n" }
        onExited: {
            // Self-heal: scrolloverview's Lua function is missing
            // (plugin transiently unloaded by the layer.opened
            // workaround race in custom/general.lua). Kick a
            // `hyprctl plugin load` async so the next hover works.
            const missing = dispatchProc.outBuf.indexOf("'scrolloverview'") >= 0
                          || dispatchProc.errBuf.indexOf("'scrolloverview'") >= 0;
            if (missing) {
                soReloadProc.running = false;
                soReloadProc.running = true;
            }
        }
    }
    // Force-reload helper for when the scrolloverview plugin has
    // gone missing. Tries `plugin load` directly; the prior unload
    // may or may not have happened cleanly, hence `|| true` so the
    // pipeline doesn't fail if Hyprland already considers it loaded
    // (`Cannot load a plugin twice!`).
    Process {
        id: soReloadProc
        command: ["bash", "-c",
            "hyprctl plugin load " +
            "\"$HOME/.local/share/hyprland/plugins/scrolloverview.so\" 2>&1 || true"]
    }
    Timer {
        // Waits for the full ripple cascade before opening the
        // chosen overview. Action depends on the current trigger:
        //   "scrolloverview" → dispatch the plugin
        //   "default"        → flip overviewOpen with
        //                      workspaces-only mode
        // Ripple disabled (animationEnabled === false) → interval
        // collapses to 0ms so the open is effectively instant.
        id: delayTimer
        interval: Config?.options.bar.hotCorners.animationEnabled === false ? 0 : 530
        onTriggered: {
            if (GlobalStates.overviewOpen || GlobalStates.scrollOverviewOpen) return;
            if (root.mode === "scrolloverview") {
                // Hyprland 0.55 Lua mode: scrolloverview:overview
                // dispatcher (with the colon) is unreachable from
                // hl.dispatch. Route through the addLuaFunction
                // exposure registered by our patched plugin
                // (hl.plugin.scrolloverview.overview). Goes through
                // dispatchProc rather than execDetached so onExited
                // can grep the eval's stderr for the nil-value
                // error and trigger the self-heal reload.
                dispatchProc.running = false;
                dispatchProc.running = true;
            } else if (root.mode === "default"
                    && (Config?.options.overview.enable ?? true)) {
                // With the overview switched off there are no workspace
                // previews to show, and this mode shows nothing else, so
                // opening would put an empty surface over the screen.
                GlobalStates.overviewWorkspacesOnly = true;
                GlobalStates.overviewOpen = true;
            }
        }
    }
}
