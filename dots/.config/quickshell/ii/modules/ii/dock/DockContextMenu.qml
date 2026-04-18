import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root

    property var appToplevel
    property Item targetButton
    property alias isOpen: menuLoader.active
    readonly property bool isFolder: appToplevel?.isFolder === true
    readonly property var desktopEntry: (!isFolder && appToplevel) ? DesktopEntries.heuristicLookup(appToplevel.appId) : null
    readonly property bool hasWindows: (appToplevel?.toplevels.length ?? 0) > 0
    readonly property bool hasDesktopActions: (!isFolder && desktopEntry?.actions.length) ?? false
    readonly property bool volumeFeatureEnabled: Config.options.dock.contextMenuVolume.enable
    readonly property string volumeGrouping: Config.options.dock.contextMenuVolume.grouping
    readonly property var audioStreams: (volumeFeatureEnabled && !isFolder && appToplevel) ? Audio.streamsForAppId(appToplevel.appId) : []
    readonly property bool hasAudioStreams: audioStreams.length > 0
    readonly property var audioGroups: {
        if (!hasAudioStreams) return [];
        if (volumeGrouping === "perApp") return [audioStreams];
        return audioStreams.map(n => [n]);
    }

    function open(button, appToplevelData) {
        if (menuLoader.active) {
            menuLoader.active = false;
        }
        targetButton = button;
        appToplevel = appToplevelData;
        menuLoader.active = true;
    }

    function close() {
        menuLoader.active = false;
    }

    Loader {
        id: menuLoader
        active: false
        sourceComponent: PopupWindow {
            id: contextPopup
            visible: true

            anchor {
                item: root.targetButton
                gravity: Edges.Top
                edges: Edges.Top
                adjustment: PopupAdjustment.SlideX
            }

            HyprlandFocusGrab {
                active: true
                windows: [contextPopup]
                onCleared: root.close()
            }

            color: "transparent"
            implicitWidth: menuBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: menuBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

            StyledRectangularShadow {
                target: menuBackground
            }

            Rectangle {
                id: menuBackground
                property real padding: 4

                anchors {
                    bottom: parent.bottom
                    horizontalCenter: parent.horizontalCenter
                    bottomMargin: Appearance.sizes.elevationMargin
                }
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.normal
                implicitWidth: menuColumn.implicitWidth + padding * 2
                implicitHeight: menuColumn.implicitHeight + padding * 2

                ColumnLayout {
                    id: menuColumn
                    anchors {
                        fill: parent
                        margins: parent.padding
                    }
                    spacing: 0

                    // ── Folder-specific options ──────────────
                    // Rename folder (opens popup in rename mode)
                    Loader {
                        active: root.isFolder
                        Layout.fillWidth: true
                        sourceComponent: ContextMenuItem {
                            iconName: "edit"
                            label: "Rename folder"
                            onClicked: {
                                root.close();
                                const folderId = root.appToplevel.appId.substring(TaskbarApps.folderPrefix.length);
                                const folder = AppFolderManager.getFolder(folderId);
                                if (folder && root.targetButton) {
                                    root.targetButton.appListRoot.showFolderPopup(
                                        root.targetButton, folder, true);
                                }
                            }
                        }
                    }

                    // Separator
                    Loader {
                        active: root.isFolder
                        Layout.fillWidth: true
                        sourceComponent: ContextMenuSeparator {}
                    }

                    // Unpin folder
                    Loader {
                        active: root.isFolder
                        Layout.fillWidth: true
                        sourceComponent: ContextMenuItem {
                            iconName: "keep_off"
                            label: "Unpin from dock"
                            onClicked: {
                                const folderId = root.appToplevel.appId.substring(TaskbarApps.folderPrefix.length);
                                TaskbarApps.toggleFolderPin(folderId);
                                root.close();
                            }
                        }
                    }

                    // Separator
                    Loader {
                        active: root.isFolder
                        Layout.fillWidth: true
                        sourceComponent: ContextMenuSeparator {}
                    }

                    // Delete folder
                    Loader {
                        active: root.isFolder
                        Layout.fillWidth: true
                        sourceComponent: ContextMenuItem {
                            iconName: "delete"
                            label: "Delete folder"
                            onClicked: {
                                const folderId = root.appToplevel.appId.substring(TaskbarApps.folderPrefix.length);
                                AppFolderManager.deleteFolder(folderId);
                                root.close();
                            }
                        }
                    }

                    // ── Regular app options ──────────────────

                    // Desktop entry actions
                    Repeater {
                        model: root.hasDesktopActions ? root.desktopEntry.actions : []
                        delegate: ContextMenuItem {
                            required property var modelData
                            Layout.fillWidth: true
                            iconName: modelData.icon ?? ""
                            label: modelData.name
                            onClicked: {
                                modelData.execute();
                                root.close();
                            }
                        }
                    }

                    // Separator after desktop actions
                    Loader {
                        active: root.hasDesktopActions
                        Layout.fillWidth: true
                        sourceComponent: ContextMenuSeparator {}
                    }

                    // Open new instance
                    ContextMenuItem {
                        Layout.fillWidth: true
                        visible: !root.isFolder
                        iconName: "open_in_new"
                        label: "Open new instance"
                        enabled: root.desktopEntry !== null
                        onClicked: {
                            root.desktopEntry?.execute();
                            root.close();
                        }
                    }

                    // Separator
                    ContextMenuSeparator {
                        Layout.fillWidth: true
                        visible: !root.isFolder
                    }

                    // Per-app volume slider + mute (only when app has active audio streams)
                    Loader {
                        active: root.hasAudioStreams && !root.isFolder
                        Layout.fillWidth: true
                        sourceComponent: ColumnLayout {
                            spacing: 0
                            Repeater {
                                model: ScriptModel { values: root.audioGroups }
                                delegate: ContextMenuVolumeRow {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    nodes: modelData
                                }
                            }
                        }
                    }

                    // Separator after volume controls
                    Loader {
                        active: root.hasAudioStreams && !root.isFolder
                        Layout.fillWidth: true
                        sourceComponent: ContextMenuSeparator {}
                    }

                    // Move to workspace (only when has windows)
                    Loader {
                        active: root.hasWindows && !root.isFolder
                        Layout.fillWidth: true
                        sourceComponent: ColumnLayout {
                            spacing: 0

                            ContextMenuItem {
                                Layout.fillWidth: true
                                iconName: "move_item"
                                label: "Move to workspace"
                                enabled: false
                                pointingHandCursor: false
                            }

                            RowLayout {
                                Layout.leftMargin: 8
                                Layout.rightMargin: 8
                                Layout.bottomMargin: 4
                                spacing: 2

                                Repeater {
                                    model: 10
                                    delegate: RippleButton {
                                        id: wsButton
                                        required property int index
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        buttonRadius: Appearance.rounding.small
                                        contentItem: StyledText {
                                            anchors.centerIn: parent
                                            text: String(wsButton.index + 1)
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            horizontalAlignment: Text.AlignHCenter
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                        onClicked: {
                                            const ws = wsButton.index + 1;
                                            for (const toplevel of root.appToplevel.toplevels) {
                                                const addr = `0x${toplevel.HyprlandToplevel?.address}`;
                                                Hyprland.dispatch(`movetoworkspacesilent ${ws},address:${addr}`);
                                            }
                                            root.close();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Pin / Unpin (apps only)
                    ContextMenuItem {
                        Layout.fillWidth: true
                        visible: !root.isFolder
                        iconName: TaskbarApps.isPinned(root.appToplevel?.appId ?? "") ? "keep_off" : "keep"
                        label: TaskbarApps.isPinned(root.appToplevel?.appId ?? "") ? "Unpin" : "Pin to dock"
                        onClicked: {
                            TaskbarApps.togglePin(root.appToplevel.appId);
                            root.close();
                        }
                    }

                    // Separator before close (only when has windows)
                    Loader {
                        active: root.hasWindows && !root.isFolder
                        Layout.fillWidth: true
                        sourceComponent: ContextMenuSeparator {}
                    }

                    // Close window(s) (only when has windows)
                    Loader {
                        active: root.hasWindows && !root.isFolder
                        Layout.fillWidth: true
                        sourceComponent: ContextMenuItem {
                            iconName: "close"
                            label: (root.appToplevel?.toplevels.length ?? 0) > 1 ? "Close all windows" : "Close window"
                            onClicked: {
                                for (const toplevel of root.appToplevel.toplevels) {
                                    toplevel.close();
                                }
                                root.close();
                            }
                        }
                    }
                }
            }
        }
    }

    component ContextMenuItem: RippleButton {
        id: menuItemRoot
        property string iconName
        property string label
        implicitHeight: 36
        implicitWidth: Math.max(itemRow.implicitWidth + 20, 180)
        buttonRadius: Appearance.rounding.small

        contentItem: RowLayout {
            id: itemRow
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 14
            }
            spacing: 8

            MaterialSymbol {
                text: menuItemRoot.iconName
                iconSize: Appearance.font.pixelSize.normal
                color: menuItemRoot.enabled ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3outline
                visible: menuItemRoot.iconName !== ""
                Layout.alignment: Qt.AlignVCenter
            }

            StyledText {
                Layout.fillWidth: true
                text: menuItemRoot.label
                horizontalAlignment: Text.AlignLeft
                font.pixelSize: Appearance.font.pixelSize.small
                color: menuItemRoot.enabled ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3outline
                elide: Text.ElideRight
            }
        }
    }

    component ContextMenuVolumeRow: Item {
        id: volRow
        required property var nodes
        readonly property var primaryNode: (nodes && nodes.length > 0) ? nodes[0] : null
        readonly property bool allMuted: {
            if (!nodes || nodes.length === 0) return false;
            for (const n of nodes) if (!n?.audio?.muted) return false;
            return true;
        }
        readonly property real aggregateVolume: {
            if (!nodes || nodes.length === 0) return 0;
            let sum = 0, count = 0;
            for (const n of nodes) { if (n?.audio) { sum += n.audio.volume; count++; } }
            return count > 0 ? sum / count : 0;
        }
        readonly property string streamTitle: {
            if (!primaryNode) return "";
            if (nodes.length > 1) {
                return `${Audio.appNodeDisplayName(primaryNode)} (${nodes.length})`;
            }
            const media = primaryNode.properties["media.name"];
            if (media) return media;
            return Audio.appNodeDisplayName(primaryNode);
        }
        function setVolumeAll(v) {
            for (const n of nodes) if (n?.audio) n.audio.volume = v;
        }
        function setMutedAll(m) {
            for (const n of nodes) if (n?.audio) n.audio.muted = m;
        }
        implicitHeight: volColumn.implicitHeight + 6
        implicitWidth: Math.max(rowLayout.implicitWidth + 20, 180)

        PwObjectTracker { objects: volRow.nodes ?? [] }

        ColumnLayout {
            id: volColumn
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 10
                topMargin: 3
                bottomMargin: 3
            }
            spacing: 0

            Item {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                Layout.preferredWidth: 0
                implicitHeight: titleText.implicitHeight
                clip: true
                StyledText {
                    id: titleText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: volRow.streamTitle
                    horizontalAlignment: Text.AlignLeft
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSurface
                    elide: Text.ElideRight
                }
            }

        RowLayout {
            id: rowLayout
            Layout.fillWidth: true
            spacing: 6

            RippleButton {
                id: muteBtn
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.rounding.small
                Layout.alignment: Qt.AlignVCenter
                onClicked: volRow.setMutedAll(!volRow.allMuted)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: volRow.allMuted
                        ? "volume_off"
                        : (volRow.aggregateVolume < 0.01 ? "volume_mute"
                            : (volRow.aggregateVolume < 0.5 ? "volume_down" : "volume_up"))
                    iconSize: Appearance.font.pixelSize.normal
                    color: volRow.allMuted ? Appearance.m3colors.m3outline : Appearance.m3colors.m3onSurface
                }
                StyledToolTip {
                    text: volRow.allMuted ? Translation.tr("Click to unmute") : Translation.tr("Click to mute")
                }
            }

            StyledSlider {
                id: volSlider
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                configuration: StyledSlider.Configuration.XS
                from: 0
                to: 1
                value: volRow.aggregateVolume
                onMoved: volRow.setVolumeAll(value)
                opacity: volRow.allMuted ? 0.5 : 1.0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 34
                horizontalAlignment: Text.AlignRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3onSurface
                text: `${Math.round(volRow.aggregateVolume * 100)}%`
            }
        }
        }
    }

    component ContextMenuSeparator: Item {
        Layout.fillWidth: true
        implicitHeight: 9

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 10
                rightMargin: 10
            }
            implicitHeight: 1
            color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
        }
    }
}
