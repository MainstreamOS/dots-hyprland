pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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

            // Disable entirely when:
            //  - trigger is "off", OR
            //  - trigger is "scrolloverview" but the plugin isn't loaded
            //    (no dispatcher to talk to).
            // "default" is always enabled — the built-in overview is
            // part of the shell, not a separate plugin.
            enabled: {
                if (trigger === "off") return false;
                if (trigger === "scrolloverview") return GlobalStates.scrollOverviewEnabled;
                return true; // "default"
            }
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

                    // "scrolloverview" doesn't toggle on a second hit
                    // while the overview is up.
                    if (trig === "scrolloverview" && GlobalStates.overviewOpen) return;

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

                    if (trig === "default") {
                        triggerArea.toggleCooldown = true;
                        cooldownTimer.restart();
                    }
                }
            }
            Timer {
                id: cooldownTimer
                interval: 500
                onTriggered: triggerArea.toggleCooldown = false
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
                    if (GlobalStates.overviewOpen) return;
                    if (triggerArea.trigger === "scrolloverview") {
                        Hyprland.dispatch("scrolloverview:overview on");
                    } else if (triggerArea.trigger === "default") {
                        GlobalStates.overviewWorkspacesOnly = true;
                        GlobalStates.overviewOpen = true;
                    }
                }
            }

            onEntered: {
                // For scrolloverview: don't re-arm if the overview is
                // already up — we'd just be triggering it again.
                // For default: still arm so a second corner-hit toggles
                // the overview off (the dwell handler does the
                // open-vs-close decision).
                if (GlobalStates.overviewOpen && triggerArea.trigger !== "default") return;
                dwellTimer.restart();
            }
            onExited: dwellTimer.stop()
        }
    }
}
