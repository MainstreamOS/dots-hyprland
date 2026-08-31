pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common

// Top-left hot corner — owns both the GNOME-style ripple visual AND
// the trigger MouseArea. Living in its own per-monitor PanelWindow
// (rather than nested inside Bar.qml's hover region) means the corner
// stays anchored to the screen's top-left regardless of bar position
// (top / bottom / vertical) — or even bar absence.
//
// One panel per monitor. Listens on GlobalStates.hotCornerTriggered()
// so every monitor's ripple fires together; this keeps the wiring
// simple at the cost of a redundant animation on monitors that don't
// actually have the bar attached. Adjust by gating on `modelData.name`
// if it ever matters in a multi-monitor setup.
Variants {
    id: root
    model: Quickshell.screens

    PanelWindow {
        id: ripplePanel
        required property ShellScreen modelData
        screen: modelData

        // Three independent ripple progress values so we can stagger
        // their start times and produce the "three concentric waves"
        // effect. 0 = mid-animation, 1 = idle. All three sit at 1 until
        // trigger() fires.
        property real progress0: 1
        property real progress1: 1
        property real progress2: 1

        // Hardcoded compressed cascade. Inner timings (per-ring
        // animation length and two stagger delays) scale proportionally
        // from 1060ms native: anim 700/1060, stagger 1 180/1060,
        // stagger 2 360/1060. (stagger 2 + animation) sums to exactly
        // 1.0 × cycle, so the last ring finishes exactly when the
        // cycle ends.
        readonly property int cycleDurationMs: 530
        readonly property int rippleAnimDuration: Math.round(cycleDurationMs * 700 / 1060)
        readonly property int stagger1Delay: Math.round(cycleDurationMs * 180 / 1060)
        readonly property int stagger2Delay: Math.round(cycleDurationMs * 360 / 1060)

        function trigger() {
            // Skip the cascade entirely when the user has turned the
            // ripple toggle off. The overview-open delay timer below
            // also collapses to 0ms in that case so the corner-trigger
            // feels instantaneous instead of awkwardly pausing for a
            // missing animation.
            if (Config?.options.bar.hotCorners.animationEnabled === false) return;
            progress0 = 0;
            ripple0Anim.restart();
            ripple1Delay.restart();
            ripple2Delay.restart();
        }

        WlrLayershell.namespace: "quickshell:hotCornerRipple"
        // Created in IllogicalImpulseFamily after the bar so most
        // compositors stack the ripple above (Hyprland orders
        // layer-shell surfaces by creation within a layer).
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            left: true
        }
        implicitWidth: 360
        implicitHeight: 360
        color: "transparent"

        // Input region is just the small trigger area in the top-left —
        // the rest of the 360×360 panel (where the ripple rings expand
        // into) lets pointer events fall through to whatever is
        // underneath (bar widgets, dock, windows).
        mask: Region {
            item: triggerArea
        }

        Connections {
            target: GlobalStates
            function onHotCornerTriggered() {
                ripplePanel.trigger();
            }
        }

        // Register with the global focus grab as a persistent surface so
        // entering the corner's trigger area doesn't dismiss whatever
        // dismissable overlay is currently open (the default overview,
        // sidebars, etc.). Without this, the moment the cursor enters
        // the hot corner panel Hyprland's focus grab considers it
        // "outside" the grabbed surfaces and fires onCleared → dismiss,
        // closing the overview before the dwell timer can route the
        // hover into the close-toggle path.
        Component.onCompleted: GlobalFocusGrab.addPersistent(ripplePanel)
        Component.onDestruction: GlobalFocusGrab.removePersistent(ripplePanel)

        // Three rings emanating from (0, 0) of the panel = the top-left
        // corner. Outlined (border-only) rather than filled so the three
        // concentric waves stay visually distinct — filled circles of
        // the same colour blend into one big shape since the inner ones
        // paint over the outer ones.
        Repeater {
            model: 3
            Rectangle {
                required property int index
                readonly property real localProgress: index === 0 ? ripplePanel.progress0
                                                    : index === 1 ? ripplePanel.progress1
                                                    :               ripplePanel.progress2
                x: -width / 2
                y: -height / 2
                width: 224
                height: 224
                radius: width / 2
                color: "transparent"
                border.color: Appearance.colors.colPrimary
                border.width: 11
                opacity: (1 - localProgress) * 0.7
                scale: 0.3 + localProgress * 0.93
                transformOrigin: Item.Center
            }
        }

        // Stagger timers — each fires its own ripple's animation
        // proportionally after the previous one starts, so visually you
        // get a wave-1 → wave-2 → wave-3 cascade with overlap.
        Timer {
            id: ripple1Delay
            interval: ripplePanel.stagger1Delay
            onTriggered: {
                ripplePanel.progress1 = 0;
                ripple1Anim.restart();
            }
        }
        Timer {
            id: ripple2Delay
            interval: ripplePanel.stagger2Delay
            onTriggered: {
                ripplePanel.progress2 = 0;
                ripple2Anim.restart();
            }
        }

        NumberAnimation {
            id: ripple0Anim
            target: ripplePanel
            property: "progress0"
            from: 0
            to: 1
            duration: ripplePanel.rippleAnimDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            id: ripple1Anim
            target: ripplePanel
            property: "progress1"
            from: 0
            to: 1
            duration: ripplePanel.rippleAnimDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            id: ripple2Anim
            target: ripplePanel
            property: "progress2"
            from: 0
            to: 1
            duration: ripplePanel.rippleAnimDuration
            easing.type: Easing.OutCubic
        }

        // ── Trigger MouseArea ────────────────────────────────────────
        // Sits at the top-left of the panel = top-left of the screen.
        // Tighter activation region (60% of the original 176×32) so the
        // user has to commit a bit more to the corner before the dwell
        // timer arms.
        MouseArea {
            id: triggerArea
            width: 106
            height: 19
            x: 0
            y: 0

            // The shake-to-locate magnifier writes this file while it holds
            // the screen. Watched rather than asked, because the two are
            // separate processes and a shell that starts mid-effect still has
            // to see it.
            property bool magnifying: false
            FileView {
                path: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/shake-zoom.active`
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
                onLoaded: triggerArea.magnifying = true
                onLoadFailed: triggerArea.magnifying = false
            }

            // Asked once per dwell. A pointer the compositor puts somewhere
            // other than this corner did not approach it, whatever the enter
            // event said.
            Process {
                id: cursorCheck
                command: ["hyprctl", "-j", "cursorpos"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        let at = null;
                        try {
                            at = JSON.parse(text);
                        } catch (e) {
                            return; // No answer is not permission to fire.
                        }
                        const win = triggerArea.QsWindow.window;
                        const localX = at.x - (win?.screen?.x ?? 0);
                        const localY = at.y - (win?.screen?.y ?? 0);
                        if (localX < 0 || localY < 0 || localX >= triggerArea.width || localY >= triggerArea.height)
                            return;
                        triggerArea.act();
                    }
                }
            }

            // Resolve the configured trigger once and reuse — keeps the
            // binding logic in one place. Falls back to "off" if Config
            // isn't ready yet.
            readonly property string trigger: Config?.options.bar.hotCorners.trigger ?? "off"

            // Brief cooldown after a "default" toggle. The layer-shell
            // focus shift when the overview opens can synthesize a fresh
            // onEntered (even with the cursor still inside) — without
            // this guard the next dwell would instantly toggle the
            // overview back off. 500ms is well past any settle race but
            // still short enough that a deliberate away-and-back gesture
            // is unaffected.
            property bool toggleCooldown: false

            // Disable only when the user explicitly set the trigger to "off".
            //
            // Previously this also disabled when scrolloverview plugin wasn't
            // loaded, but `GlobalStates.scrollOverviewEnabled` re-polls via
            // `hyprctl plugin list` on every Hyprland `configreloaded` event
            // — including the plugin unload+load cycle in our custom/general.lua
            // layer.opened workaround. If the user's cursor was inside the
            // corner during that ~100ms re-poll window, MouseArea disable
            // would drop the hover state; on re-enable, Qt doesn't synthesize
            // a fresh onEntered until the cursor exits and re-enters. Result:
            // hot corner "fails to activate every so often" until the user
            // moves the cursor away.
            //
            // The dispatch invocation already handles the not-loaded case
            // gracefully (hyprctl eval prints a Lua error and exits non-zero,
            // no overview opens). Tradeoff: a permanently-unloaded plugin
            // leaves the ripple firing into nothing — but that's better than
            // missed activations on a working setup.
            enabled: trigger !== "off"
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton

            // Dwell timer prevents two failure modes:
            //  1. Casual brushing past the corner while moving toward
            //     other parts of the screen.
            //  2. The layer-shell regrab race when the built-in overview
            //     closes: at that moment this MouseArea suddenly receives
            //     hover for a cursor that was already there, firing
            //     onEntered with overviewOpen already transitioned to
            //     false. Requiring the cursor to actually rest in the
            //     corner briefly filters those spurious entries.
            Timer {
                id: dwellTimer
                interval: 50
                onTriggered: {
                    if (triggerArea.toggleCooldown) return;
                    // Nothing while the screen is magnified. Down there the
                    // pointer is being pushed against an edge to pan the view,
                    // not taken to a corner on purpose.
                    if (triggerArea.magnifying) return;
                    // An entry is not proof the pointer arrived. A focus grab
                    // refreshes pointer focus across every surface it lists,
                    // this panel among them, so Hyprland synthesises an enter
                    // for a pointer that never moved and may be on another
                    // screen entirely. Ask the compositor where it actually is
                    // and drop anything that disagrees. One round trip per
                    // approach to the corner.
                    cursorCheck.running = false;
                    cursorCheck.running = true;
}
            }

            // Runs only once the compositor has confirmed the pointer.
            function act() {

                    const trig = triggerArea.trigger;

                    // Close path: "default" with overview already open
                    // toggles it off and fires the ripple in parallel
                    // with the overview's own fade-out (Overlay > Top
                    // layer, so the cascade stays visible above the
                    // closing overview). Symmetric with the open path's
                    // visual feedback, just without the open delay —
                    // the close itself happens immediately.
                    if (trig === "default" && GlobalStates.overviewOpen) {
                        GlobalStates.hotCornerTriggered();
                        GlobalStates.overviewOpen = false;
                        triggerArea.toggleCooldown = true;
                        cooldownTimer.restart();
                        return;
                    }

                    // Close path: "scrolloverview" with its overview already
                    // up toggles it off — call the dispatcher that
                    // overview("off") returns and fire the ripple in parallel,
                    // mirroring the "default" close above. Runs before the
                    // dismissable check (like default) so the corner can always
                    // close it.
                    if (trig === "scrolloverview" && GlobalStates.scrollOverviewOpen) {
                        GlobalStates.hotCornerTriggered();
                        Quickshell.execDetached(["hyprctl", "eval",
                            '(function() local f = hl.plugin.scrolloverview.overview("off") if type(f) == "function" then f() end end)()']);
                        triggerArea.toggleCooldown = true;
                        cooldownTimer.restart();
                        return;
                    }

                    // Skip the open path when an unrelated dismissable
                    // overlay (cheatsheet, sidebar, media controls, …)
                    // is up. Those overlays activate Hyprland's focus
                    // grab via GlobalFocusGrab.addDismissable, and grab
                    // activation refreshes pointer focus across the
                    // listed surfaces — which includes this panel via
                    // the persistent registration above. If the cursor
                    // sits inside the trigger region at that moment,
                    // Hyprland synthesizes a fresh onEntered here and
                    // the dwell + delay sequence would re-fire the
                    // corner alongside the overlay the user actually
                    // opened. Default-trigger close runs earlier above
                    // and returns before this check, so toggling the
                    // dots overview off via the corner still works.
                    if (GlobalFocusGrab.dismissable.length > 0) return;

                    // Open path (both scrolloverview and default): emit
                    // the global trigger signal so every monitor's ripple
                    // fires together (trigger() is a no-op when the
                    // ripple toggle is off), then the delay timer below
                    // opens the matching overview after the cascade.
                    GlobalStates.hotCornerTriggered();
                    delayTimer.restart();

                    // Cooldown both triggers so a focus-grab re-entry
                    // synthesized right after opening can't immediately
                    // toggle the overview back off.
                    triggerArea.toggleCooldown = true;
                    cooldownTimer.restart();
                            }

            Timer {
                id: cooldownTimer
                interval: 500
                onTriggered: triggerArea.toggleCooldown = false
            }
            // Self-healing dispatch for the scrolloverview plugin.
            //
            // Failure mode: the layer.opened workaround in custom/general.lua
            // does an `hyprctl plugin unload + 100ms + load` cycle every
            // time Quickshell's layer surface registers (which happens on
            // initial Hyprland start AND on every Quickshell reload). The
            // cycle is fire-and-forget — if the re-load races with the
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
            // — see HyprCtl.cpp:1108) doesn't trip over.
            Process {
                id: dispatchProc
                // Upstream's dispatcher refactor (scroll-overview afa8fc8) changed
                // overview(arg): outside a __lua keybind it no longer dispatches —
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
                    if (triggerArea.trigger === "scrolloverview") {
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
                    } else if (triggerArea.trigger === "default") {
                        GlobalStates.overviewWorkspacesOnly = true;
                        GlobalStates.overviewOpen = true;
                    }
                }
            }

            onEntered: {
                // Arm the dwell for both triggers in both states — the dwell
                // handler does the open-vs-close decision, so a second hover
                // toggles the overview off (scrolloverview included now).
                dwellTimer.restart();
            }
            onExited: dwellTimer.stop()
        }
    }
}
