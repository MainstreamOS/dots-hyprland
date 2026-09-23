import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

// Left-click popup for ActiveWindow once more than one workspace has a name:
// the named workspaces other than the one on screen, each a way straight there.
StyledPopup {
    id: root
    property bool open: false
    property var entries: []
    forceShow: open
    showOnHover: false
    // When it went away by a click elsewhere, so the owner can tell that click
    // from one meant to open it again.
    property real dismissedAt: 0
    onDismissed: {
        root.open = false;
        root.dismissedAt = Date.now();
    }

    function go(id) {
        root.open = false;
        Hyprland.dispatch(`hl.dsp.focus({workspace = ${id}})`);
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 4

        StyledPopupHeaderRow {
            icon: "workspaces"
            label: Translation.tr("Go to workspace")
        }

        Repeater {
            model: root.entries
            delegate: RippleButtonWithIcon {
                id: entryButton
                required property var modelData
                Layout.fillWidth: true
                Layout.minimumWidth: 210
                Layout.maximumWidth: 320
                onClicked: root.go(entryButton.modelData.id)
                mainContentComponent: Component {
                    RowLayout {
                        spacing: 10
                        Rectangle {
                            implicitWidth: Math.max(22, entryNumber.implicitWidth + 10)
                            implicitHeight: 22
                            radius: height / 2
                            color: Appearance.colors.colSecondaryContainer
                            StyledText {
                                id: entryNumber
                                anchors.centerIn: parent
                                text: entryButton.modelData.id
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: entryButton.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSecondaryContainer
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
