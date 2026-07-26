import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

// Right-click popup for ReleaseUpdatesIndicator: where the widget is told how
// loudly to speak up, since that choice lives nowhere else.
StyledPopup {
    id: root
    property bool open: false
    forceShow: open
    showOnHover: false
    onDismissed: root.open = false

    function setMode(mode) {
        Config.options.updates.release.notify = mode;
        root.open = false;
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 4

        StyledPopupHeaderRow {
            icon: "campaign"
            label: Translation.tr("Release updates")
        }

        RippleButtonWithIcon {
            Layout.fillWidth: true
            Layout.minimumWidth: 210
            materialIcon: "system_update_alt"
            mainText: Translation.tr("Open updates")
            onClicked: {
                root.open = false;
                ReleaseUpdates.openUpdatesPage();
            }
        }
        RippleButtonWithIcon {
            Layout.fillWidth: true
            Layout.minimumWidth: 210
            materialIcon: "history"
            mainText: Translation.tr("What's new")
            onClicked: {
                root.open = false;
                ReleaseUpdates.openChangelog();
            }
        }
        RippleButtonWithIcon {
            Layout.fillWidth: true
            Layout.minimumWidth: 210
            materialIcon: "refresh"
            mainText: Translation.tr("Check now")
            enabled: !ReleaseUpdates.checking
            onClicked: {
                root.open = false;
                ReleaseUpdates.refresh();
            }
        }

        StyledPopupHeaderRow {
            icon: "notifications"
            label: Translation.tr("Tell me with")
        }

        Repeater {
            // No "don't tell me": that is what taking the widget out of the bar
            // layout is for, and hiding the widget from here would take away the
            // only way back to this menu.
            model: [
                { mode: "both",         icon: "notifications", label: Translation.tr("Bar icon and message") },
                { mode: "tray",         icon: "toast",         label: Translation.tr("Bar icon only") },
                { mode: "notification", icon: "chat_bubble",   label: Translation.tr("Message only") }
            ]
            RippleButtonWithIcon {
                required property var modelData
                Layout.fillWidth: true
                Layout.minimumWidth: 210
                materialIcon: modelData.icon
                mainText: modelData.label
                colBackground: ReleaseUpdates.notifyMode === modelData.mode
                    ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colLayer2
                onClicked: root.setMode(modelData.mode)
            }
        }
    }
}
