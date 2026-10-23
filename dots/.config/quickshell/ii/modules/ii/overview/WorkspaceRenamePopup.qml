pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.modules.ii.bar as Bar
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Keep the editor in the launcher's surface so it retains keyboard focus.
ContextMenuPopup {
    id: root
    property int workspaceId: -1
    readonly property string currentName: WorkspaceNames.nameFor(root.workspaceId)
    padding: 12
    implicitWidth: 300
    modal: true
    dim: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    function openFor(workspace, px, py) {
        if (!WorkspaceNames.canName(workspace)) return;
        root.workspaceId = workspace;
        nameField.text = root.currentName;
        root.openAt(px, py);
        Qt.callLater(() => {
            if (!root.visible) return;
            nameField.selectAll();
            nameField.forceActiveFocus();
        });
    }
    function save() {
        WorkspaceNames.setName(root.workspaceId, nameField.text);
        root.close();
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() { if (!GlobalStates.overviewOpen) root.close(); }
    }

    contentItem: ColumnLayout {
        spacing: 10
        Bar.StyledPopupHeaderRow {
            icon: "edit"
            label: Translation.tr("Name workspace %1").arg(root.workspaceId)
        }
        ToolbarTextField {
            id: nameField
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: 40
            maximumLength: 40
            placeholderText: Translation.tr("Workspace %1").arg(root.workspaceId)
            onAccepted: root.save()
            Keys.onEscapePressed: root.close()
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            DialogButton {
                buttonText: Translation.tr("Clear")
                enabled: root.currentName.length > 0
                onClicked: {
                    WorkspaceNames.setName(root.workspaceId, "");
                    root.close();
                }
            }
            Item { Layout.fillWidth: true }
            DialogButton {
                buttonText: Translation.tr("Cancel")
                onClicked: root.close()
            }
            DialogButton {
                buttonText: Translation.tr("Save")
                onClicked: root.save()
            }
        }
    }
}
