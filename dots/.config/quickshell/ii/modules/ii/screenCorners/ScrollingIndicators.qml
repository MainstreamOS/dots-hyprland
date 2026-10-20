pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root
    readonly property bool enabled: Config.options.interactions.showWorkspaceNavigationArrows
        && !GlobalStates.sessionLocked && !GlobalStates.overviewOpen
        && !GlobalStates.scrollOverviewOpen && GlobalStates.windowOverviewScreen === ""
    readonly property bool scrolling: enabled && HyprlandData.monitors.some(m =>
        !m.specialWorkspace?.id && m.dpmsStatus !== false
        && HyprlandData.workspaceById[m.activeWorkspace?.id]?.tiledLayout === "scrolling"
        && !HyprlandData.workspaceById[m.activeWorkspace?.id]?.hasfullscreen)

    // Panning the scrolling tape sends no window-move IPC event, so poll slowly,
    // and only while a scrolling layout is on screen.
    Timer {
        interval: 500
        repeat: true
        running: root.scrolling
        onTriggered: HyprlandData.updateWindowList()
    }

    Process {
        id: navigation
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) console.warn("Could not navigate workspace windows:", exitCode);
            HyprlandData.updateWindowList();
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: output
            required property ShellScreen modelData
            readonly property var monitor: HyprlandData.monitors.find(m => m.name === modelData.name)
            readonly property var workspace: HyprlandData.workspaceById[monitor?.activeWorkspace?.id]
            readonly property bool enabled: root.enabled && monitor?.dpmsStatus !== false
                && !monitor?.specialWorkspace?.id && ["scrolling", "monocle"].includes(workspace?.tiledLayout) && !workspace.hasfullscreen
            readonly property bool monocle: workspace?.tiledLayout === "monocle"
            readonly property var tiledWindows: !enabled ? [] : HyprlandData.windowList.filter(win =>
                win.workspace?.id === workspace.id && win.monitor === monitor.id
                && win.mapped && !win.hidden && !win.floating && !win.pinned)
            readonly property var reserved: monitor?.reserved ?? [0, 0, 0, 0]
            readonly property var indicatorInsets: {
                const insets = reserved.slice();
                const dock = GlobalStates.dockWindows[modelData.name];
                if (dock?.visible && dock.reveal) {
                    const edge = dock.dockEdge === "left" ? 0 : dock.dockEdge === "right" ? 2 : -1;
                    if (edge >= 0) insets[edge] = Math.max(insets[edge],
                        Appearance.sizes.dockHeightFor(dock.fittedIconSize) + Appearance.sizes.dockEdgeGap);
                }
                return insets;
            }
            readonly property real left: (monitor?.x ?? 0) + reserved[0]
            readonly property real top: (monitor?.y ?? 0) + reserved[1]
            readonly property real right: (monitor?.x ?? 0) + modelData.width - reserved[2]
            readonly property real bottom: (monitor?.y ?? 0) + modelData.height - reserved[3]
            readonly property var nextWindows: {
                const targets = [null, null, null, null];
                const scores = [Infinity, Infinity, Infinity, Infinity];
                if (!enabled || monocle) return targets;
                for (const win of tiledWindows) {
                    if (!win.at || !win.size) continue;
                    const outside = [win.at[0] < left - 1, win.at[0] + win.size[0] > right + 1,
                        win.at[1] < top - 1, win.at[1] + win.size[1] > bottom + 1];
                    const distances = [-(win.at[0] + win.size[0]), win.at[0], -(win.at[1] + win.size[1]), win.at[1]];
                    for (let edge = 0; edge < 4; edge++) {
                        if (!outside[edge]) continue;
                        if (distances[edge] < scores[edge] || (distances[edge] === scores[edge]
                                && (win.focusHistoryID ?? Infinity) < (targets[edge]?.focusHistoryID ?? Infinity))) {
                            targets[edge] = win;
                            scores[edge] = distances[edge];
                        }
                    }
                }
                return targets;
            }
            readonly property var overflow: monocle
                ? [tiledWindows.length > 1, tiledWindows.length > 1, false, false]
                : nextWindows.map(win => win !== null)

            function reveal(edge) {
                if (!enabled || navigation.running) return;
                if (monocle) {
                    if (edge > 1 || tiledWindows.length < 2) return;
                    navigation.command = ["hyprctl", "eval", `(function()
                        local workspace = hl.get_active_workspace(${monitor.id})
                        if not workspace or workspace.id ~= ${workspace.id}
                            or workspace.tiled_layout ~= "monocle" or workspace.has_fullscreen then return end
                        local cursor = hl.get_cursor_pos()
                        hl.dispatch(hl.dsp.focus({workspace = ${workspace.id}}))
                        hl.dispatch(hl.dsp.layout("${edge === 0 ? "cycleprev" : "cyclenext"}"))
                        if cursor then hl.dispatch(hl.dsp.cursor.move({x = cursor.x, y = cursor.y})) end
                    end)()`];
                    navigation.running = true;
                    return;
                }
                const win = nextWindows[edge];
                if (!win || !/^0x[0-9a-f]+$/i.test(win.address)) return;
                // Fit explicitly even when follow_focus is off. Keep the pointer
                // over the arrow instead of letting focus warp it into the window.
                navigation.command = ["hyprctl", "eval", `(function()
                    local cursor = hl.get_cursor_pos()
                    hl.dispatch(hl.dsp.focus({window = "address:${win.address}"}))
                    hl.dispatch(hl.dsp.layout("fit_into_view"))
                    if cursor then hl.dispatch(hl.dsp.cursor.move({x = cursor.x, y = cursor.y})) end
                end)()`];
                navigation.running = true;
            }

            Variants {
                model: [0, 1, 2, 3]

                PanelWindow {
                    id: indicator
                    required property int modelData
                    readonly property bool horizontal: modelData < 2
                    readonly property int shadowPadding: 4
                    screen: output.modelData
                    visible: output.overflow[modelData]
                    color: "transparent"
                    implicitWidth: (horizontal ? 28 : 40) + shadowPadding * 2
                    implicitHeight: (horizontal ? 40 : 28) + shadowPadding * 2
                    anchors { top: true; left: true }
                    margins {
                        left: indicator.modelData === 0 ? output.indicatorInsets[0] + 4 - indicator.shadowPadding
                            : indicator.modelData === 1 ? output.modelData.width - output.indicatorInsets[2] - indicator.width - 4 + indicator.shadowPadding
                            : (output.modelData.width + output.reserved[0] - output.reserved[2] - indicator.width) / 2
                        top: indicator.modelData === 2 ? output.reserved[1] + 4 - indicator.shadowPadding
                            : indicator.modelData === 3 ? output.modelData.height - output.reserved[3] - indicator.height - 4 + indicator.shadowPadding
                            : (output.modelData.height + output.reserved[1] - output.reserved[3] - indicator.height) / 2
                    }
                    exclusionMode: ExclusionMode.Ignore
                    exclusiveZone: -1
                    WlrLayershell.namespace: "quickshell:scrollingIndicator"
                    WlrLayershell.layer: WlrLayer.Top
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    mask: Region { item: arrowButton }

                    WorkspaceNavigationButton {
                        id: arrowButton
                        anchors.fill: parent
                        anchors.margins: indicator.shadowPadding
                        iconName: ["chevron_left", "chevron_right", "expand_less", "expand_more"][indicator.modelData]
                        Accessible.name: indicator.modelData === 0 || indicator.modelData === 2 ? Translation.tr("Back") : Translation.tr("Next")
                        onClicked: output.reveal(indicator.modelData)
                    }
                }
            }
        }
    }
}
