import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Right-click popup for ActiveWindow: names the workspace the bar is showing,
// or clears the name so the window titles come back.
StyledPopup {
    id: root
    property bool open: false
    // Set once when the popup opens rather than followed, since keybinds still
    // switch workspaces while typing and the name belongs to the one clicked.
    property int workspaceId: -1
    readonly property string currentName: WorkspaceNames.nameFor(root.workspaceId)
    forceShow: open
    showOnHover: false
    // When it went away by a click elsewhere, so the owner can tell that click
    // from one meant to open it again.
    property real dismissedAt: 0
    onDismissed: {
        root.open = false;
        root.dismissedAt = Date.now();
    }

    // The contents are built once with the bar and kept between openings, so
    // each opening starts the field over here rather than on creation.
    onOpenChanged: if (open) Qt.callLater(() => {
        nameField.text = root.currentName;
        nameField.selectAll();
        nameField.forceActiveFocus();
    })

    function save() {
        WorkspaceNames.setName(root.workspaceId, nameField.text);
        root.open = false;
    }

    function clear() {
        WorkspaceNames.setName(root.workspaceId, "");
        root.open = false;
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8

        // Held here because the popup itself only takes the one item it
        // shows. While the field has the keyboard the bars count as part of
        // this popup, so a click on them does not put it away; a sidebar or
        // the overview opening over it is taken as moving on instead.
        Connections {
            target: GlobalStates
            function onSidebarLeftOpenChanged() { if (GlobalStates.sidebarLeftOpen) root.open = false; }
            function onSidebarRightOpenChanged() { if (GlobalStates.sidebarRightOpen) root.open = false; }
            function onOverviewOpenChanged() { if (GlobalStates.overviewOpen) root.open = false; }
        }

        StyledPopupHeaderRow {
            icon: "edit"
            label: Translation.tr("Name workspace %1").arg(root.workspaceId)
        }

        ToolbarTextField {
            id: nameField
            Layout.fillHeight: false
            Layout.fillWidth: true
            implicitWidth: 240
            implicitHeight: 40
            colBackground: Appearance.colors.colLayer2
            // The popup window is only as big as its card, so the stock
            // right-click menu would open clipped and out of reach.
            ContextMenu.menu: null
            maximumLength: 40
            placeholderText: Translation.tr("Workspace %1").arg(root.workspaceId)
            onAccepted: root.save()
            Keys.onEscapePressed: root.open = false
        }

        StyledText {
            Layout.fillWidth: true
            Layout.maximumWidth: 240
            wrapMode: Text.WordWrap
            text: Translation.tr("Shown instead of window titles until you clear it")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 4

            DialogButton {
                buttonText: Translation.tr("Clear")
                enabled: root.currentName.length > 0
                onClicked: root.clear()
            }
            DialogButton {
                buttonText: Translation.tr("Save")
                onClicked: root.save()
            }
        }
    }
}
