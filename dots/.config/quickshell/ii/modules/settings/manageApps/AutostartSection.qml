pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// What opens on its own when you log in, with a switch beside each one and a
// way to add another. Apps you added come first; the rest arrive with the
// system and can be switched off but not dropped.
ContentSection {
    id: root
    icon: "rocket_launch"
    title: Translation.tr("Auto Start Apps")

    StyledText {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        text: Translation.tr("These open on their own after you log in. Turning one off does not uninstall it.")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
    }

    StyledText {
        Layout.fillWidth: true
        visible: AutostartApps.loaded && AutostartApps.entries.length === 0
        text: Translation.tr("Nothing starts on its own yet.")
        color: Appearance.colors.colSubtext
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: AutostartApps.entries

        delegate: Rectangle {
            id: appRow
            required property var modelData

            Layout.fillWidth: true
            implicitHeight: 60
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            opacity: AutostartApps.busyId === appRow.modelData.id ? 0.6 : 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 6
                spacing: 12

                IconImage {
                    implicitSize: 32
                    source: Quickshell.iconPath(
                        appRow.modelData.icon.length > 0
                            ? appRow.modelData.icon
                            : AppSearch.guessIcon(appRow.modelData.id),
                        "application-x-executable")
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: appRow.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: appRow.modelData.description.length > 0
                            ? appRow.modelData.description
                            : (appRow.modelData.source === "added"
                                ? Translation.tr("Added by you")
                                : Translation.tr("Comes with your system"))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }

                // Only an app added here can be dropped. One the system starts
                // stays in the list with its switch off, which is the whole of
                // what can be done about it without root.
                RippleButton {
                    visible: appRow.modelData.source === "added"
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 34
                    implicitHeight: 34
                    enabled: AutostartApps.busyId === ""
                    onClicked: AutostartApps.remove(appRow.modelData.id)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "delete"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colSubtext
                    }
                    StyledToolTip { text: Translation.tr("Remove from this list") }
                }

                StyledSwitch {
                    Layout.rightMargin: 6
                    checked: appRow.modelData.enabled
                    enabled: AutostartApps.busyId === ""
                    // The list is the authority: a switch reflects the file on
                    // disk, and a click asks for a change rather than assuming
                    // one, so a write that fails leaves the switch telling the
                    // truth.
                    animateChanges: AutostartApps.loaded
                    onToggled: {
                        checked = Qt.binding(() => appRow.modelData.enabled);
                        AutostartApps.setEnabled(appRow.modelData.id, !appRow.modelData.enabled);
                    }
                }
            }
        }
    }

    AppPicker {
        Layout.fillWidth: true
        Layout.topMargin: 4
        fieldIcon: "add"
        currentId: ""
        placeholderText: Translation.tr("Add an app")
        busy: AutostartApps.busyId !== ""
        onPicked: entryId => AutostartApps.add(entryId)
    }

    SubtleNoticeBox {
        Layout.fillWidth: true
        Layout.topMargin: 4
        materialIcon: "schedule"
        text: Translation.tr("A change here takes effect the next time you log in. Nothing opens or closes right now.")
    }
}
