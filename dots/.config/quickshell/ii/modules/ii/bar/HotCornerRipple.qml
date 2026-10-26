pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common

// A top screen corner (ripple, trigger area, dwell and holds) whose trigger picks
// its action. Its own PanelWindow per monitor keeps it in place whatever the bar does.
Variants {
    id: root
    model: root.action !== null ? Quickshell.screens : []
    // Which top corner this is, and its trigger: "off", "sidebar", or an
    // overview ("default", "scrolloverview"). The trigger picks the action.
    property bool right: false
    property string trigger: "off"
    readonly property QtObject overviewAction: HotCornerOverviewAction { mode: root.trigger }
    readonly property QtObject sidebarAction: HotCornerSidebarAction {}
    readonly property QtObject action: root.trigger === "sidebar" ? root.sidebarAction
        : (root.trigger === "default" || root.trigger === "scrolloverview") ? root.overviewAction : null

    PanelWindow {
        id: ripplePanel
        required property ShellScreen modelData
        screen: modelData
        // The corners step aside for a fullscreen window, a game above all, as the bar
        // does; hidden rather than click-through, so no surface is left on top of it.
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(ripplePanel.screen)
        readonly property bool hasFullscreenWindow: Hyprland.workspaces.values.some(w => w.active
            && w.monitor?.name === ripplePanel.monitor?.name && w.toplevels.values.some(t => t.wayland?.fullscreen))
        visible: !hasFullscreenWindow

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
            left: !root.right
            right: root.right
        }
        implicitWidth: 360
        implicitHeight: 360
        color: "transparent"

        // Input region is just the small trigger area in the top-left —
        // the rest of the 360×360 panel (where the ripple rings expand
        // into) lets pointer events fall through to whatever is
        // underneath (bar widgets, dock, windows).
        // Nothing at all while the action is off, so a disabled corner keeps
        // nothing from the bar or what lies beneath it.
        mask: Region {
            item: triggerArea.enabled ? triggerArea : null
        }

        Connections {
            target: root.action
            function onFired() {
                ripplePanel.acknowledge();
            }
        }
        function acknowledge() {
            ripplePanel.trigger();
            // Whatever fired this has just acted on the corner's behalf,
            // the overview closing itself from the same rectangle included.
            // The pointer lands back on this surface the moment that other
            // surface lets go of it, and Hyprland synthesises an entry for
            // a pointer that never moved. Without holding the corner off,
            // that entry reads as a fresh approach and opens again what was
            // just closed.
            triggerArea.toggleCooldown = true;
            triggerArea.awaitingExit = true;
            cooldownTimer.restart();
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
                x: root.right ? parent.width - width / 2 : -width / 2
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
        // Sits in the panel's corner = the screen's corner, and ends before
        // the bar's first or last widget: this surface is above the bar, so
        // anything inside the rectangle never reaches what is under it.
        MouseArea {
            id: triggerArea
            width: Appearance.sizes.hotCornerWidth
            height: Appearance.sizes.hotCornerHeight
            x: root.right ? parent.width - width : 0
            y: 0

            // The shake-to-locate magnifier writes this file while it holds
            // the screen. Watched rather than asked, because the two are
            // separate processes and a shell that starts mid-effect still has
            // to see it.
            property bool magnifying: false
            FileView {
                // No /tmp fallback: the writer keeps the marker in the
                // runtime directory, and watching a different place would
                // either miss a real effect or, worse, latch onto a file left
                // there by something else and hold the corner disabled. With
                // no runtime directory this path cannot resolve, which reads
                // as no effect running — the safe way to be wrong.
                path: `${Quickshell.env("XDG_RUNTIME_DIR")}/shake-zoom.active`
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
                        const fromLeft = at.x - (win?.screen?.x ?? 0);
                        const localX = root.right ? (win?.screen?.width ?? 0) - 1 - fromLeft : fromLeft;
                        const localY = at.y - (win?.screen?.y ?? 0);
                        if (localX < 0 || localY < 0 || localX >= triggerArea.width || localY >= triggerArea.height)
                            return;
                        root.action?.act();
                    }
                }
            }

            // Brief cooldown after a "default" toggle. The layer-shell
            // focus shift when the overview opens can synthesize a fresh
            // onEntered (even with the cursor still inside) — without
            // this guard the next dwell would instantly toggle the
            // overview back off. 500ms is well past any settle race but
            // still short enough that a deliberate away-and-back gesture
            // is unaffected.
            property bool toggleCooldown: false

            // Set whenever the corner has just been acted on, and cleared only
            // by the pointer actually leaving the rectangle. A timed hold is
            // not enough on its own: after a close the pointer is still in the
            // corner, so the moment the hold expires the next twitch reads as a
            // fresh approach and opens again what was just closed. Coming back
            // has to mean coming back.
            property bool awaitingExit: false

            // Only a trigger of "off" disables the corner, not a missing
            // scrolloverview plugin: `GlobalStates.scrollOverviewEnabled` re-polls via
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
            enabled: root.action !== null
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
                    if (triggerArea.awaitingExit) return;
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

            Timer {
                id: cooldownTimer
                interval: 500
                onTriggered: triggerArea.toggleCooldown = false
            }

            onEntered: {
                // Armed in both states: the action decides whether this
                // opens or closes, so a second visit takes back the first.
                dwellTimer.restart();
            }
            onExited: {
                dwellTimer.stop();
                triggerArea.awaitingExit = false;
            }
            // The corner sits over the bar's end, so a scroll here does what
            // it does on the bar beside it, for actions that take one.
            onWheel: event => {
                if (event.angleDelta.y !== 0 && typeof root.action?.scroll === "function")
                    root.action.scroll(event.angleDelta.y > 0);
            }
        }
    }
}
