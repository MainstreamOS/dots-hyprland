import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.QsWindow.window?.screen)
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    property string activeWindowAddress: `0x${activeWindow?.HyprlandToplevel?.address}`
    property bool focusingThisMonitor: HyprlandData.activeWorkspace?.monitor == monitor?.name
    property var biggestWindow: HyprlandData.biggestWindowForWorkspace(HyprlandData.monitors[root.monitor?.id]?.activeWorkspace.id)

    // The workspace this bar is showing, and the name given to it from the
    // right-click popup. While there is a name it stands in for the window
    // titles, which otherwise change with every window the pointer focuses.
    readonly property int shownWorkspaceId: root.monitor?.activeWorkspace?.id ?? -1
    readonly property string workspaceName: WorkspaceNames.nameFor(root.shownWorkspaceId)

    // Once more than one workspace has a name, a left click lists the others
    // to jump to. Until then a left click here stays the left sidebar's, as it
    // is everywhere else on this side of the bar.
    readonly property bool canJump: WorkspaceNames.entries.length > 1
    readonly property var otherNamed: WorkspaceNames.entries.filter(entry => entry.id !== root.shownWorkspaceId)

    // Both popups speak for the workspace on screen, so moving to another one
    // puts them away.
    onShownWorkspaceIdChanged: {
        renamePopup.open = false;
        jumpPopup.open = false;
    }

    // Opening either popup first puts away whatever click popup or sidebar is
    // already open, the name box on another monitor's bar included.
    function openOnly(popup) {
        GlobalFocusGrab.dismiss();
        popup.open = true;
    }

    // A click on the title that is what put its own popup away arrives with,
    // or just after, the dismissal, and should not open it straight back up.
    function justDismissed(popup) {
        return Date.now() - popup.dismissedAt < 300;
    }

    // Whether this instance is the variant drawn on a pill. The stock widget
    // sits bare on the strip; the pilled one is a separate entry in the layout
    // catalog, so which look the bar wears is the user's pick rather than ours.
    property bool pilled: false

    // Room between the title and the pill drawn around it, the same the tray
    // and the utility buttons keep, so the three read as the same kind of
    // thing. Zero when there is no pill: against the bare strip the title
    // keeps the exact footprint it has always had.
    readonly property real contentPadding: pilled ? 4 : 0

    // The width the title keeps whatever it says, matching the clock so the two
    // read as the same kind of thing. The lines inside elide into it: they can
    // only do that once something has settled how wide the widget is, and
    // asking for the text's own width answers "as wide as the title is long".
    readonly property real titleWidth: 270

    // Held rather than fitted. Sizing to the title makes the widget as wide as
    // whatever happens to be focused, so the bar rearranged itself around a
    // window being picked up or put down. A set width is the same on every
    // window: short names leave room to spare, long ones elide into it, and
    // nothing beside it ever moves.
    implicitWidth: root.titleWidth

    ColumnLayout {
        id: colLayout

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.contentPadding
        anchors.rightMargin: root.contentPadding
        spacing: -4

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            elide: Text.ElideRight
            text: root.workspaceName.length > 0 ? Translation.tr("Workspace %1").arg(root.shownWorkspaceId) :
                root.focusingThisMonitor && root.activeWindow?.activated && root.biggestWindow ? 
                root.activeWindow?.appId :
                (root.biggestWindow?.class) ?? Translation.tr("Desktop")

        }

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
            elide: Text.ElideRight
            text: root.workspaceName.length > 0 ? root.workspaceName :
                root.focusingThisMonitor && root.activeWindow?.activated && root.biggestWindow ? 
                root.activeWindow?.title :
                (root.biggestWindow?.title) ?? `${Translation.tr("Workspace")} ${monitor?.activeWorkspace?.id ?? 1}`
        }

    }

    // Right-click names the workspace. A left click is only taken while it has
    // something to do here, a list of named workspaces to open or a name box
    // to put away; otherwise it and scrolling go to whatever the section of
    // the bar around the title does with them.
    // As tall as the bar rather than the widget. Inside a pill the widget is
    // laid out with no height of its own, which would leave nothing to click.
    MouseArea {
        id: renameArea
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
        height: Appearance.sizes.baseBarHeight
        acceptedButtons: (root.canJump || renamePopup.open) ? (Qt.LeftButton | Qt.RightButton) : Qt.RightButton
        enabled: WorkspaceNames.ready
        onPressed: event => {
            if (event.button === Qt.LeftButton) {
                if (renamePopup.open) renamePopup.open = false;
                else if (jumpPopup.open) jumpPopup.open = false;
                else if (!root.justDismissed(jumpPopup)) root.openOnly(jumpPopup);
                return;
            }
            if (renamePopup.open) {
                renamePopup.open = false;
                return;
            }
            if (root.justDismissed(renamePopup)) return;
            if (!WorkspaceNames.canName(root.shownWorkspaceId)) return;
            renamePopup.workspaceId = root.shownWorkspaceId;
            root.openOnly(renamePopup);
        }
    }

    WorkspaceRenamePopup {
        id: renamePopup
        hoverTarget: renameArea
    }

    WorkspaceJumpPopup {
        id: jumpPopup
        hoverTarget: renameArea
        entries: root.otherNamed
    }

}
