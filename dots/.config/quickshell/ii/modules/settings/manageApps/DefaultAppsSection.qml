pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// One row per job, each naming the app that does it. Picking a different app
// writes the file types that job covers and, where a key launches it, the app
// that key opens.
ContentSection {
    id: root
    icon: "apps"
    title: Translation.tr("Default Apps")

    StyledText {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        text: Translation.tr("The app that opens when you double click a file or press its shortcut key.")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: DefaultApps.roles

        delegate: Rectangle {
            id: roleRow
            required property var modelData

            Layout.fillWidth: true
            implicitHeight: 60
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 10
                spacing: 12

                MaterialSymbol {
                    text: roleRow.modelData.icon
                    iconSize: Appearance.font.pixelSize.hugeass
                    color: Appearance.colors.colOnLayer1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: roleRow.modelData.label
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: roleRow.modelData.hint
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }

                AppPicker {
                    Layout.preferredWidth: 210
                    roleKey: roleRow.modelData.key
                    currentId: DefaultApps.idFor(roleRow.modelData.key)
                    busy: DefaultApps.busyRole === roleRow.modelData.key
                    // A role a key launches always has an app: with nothing
                    // picked, the config runs the first of its built-in list
                    // that is installed. Saying so beats an empty field that
                    // reads as though the key does nothing.
                    placeholderText: !DefaultApps.loaded
                        ? Translation.tr("Checking…")
                        : roleRow.modelData.keyed
                            ? Translation.tr("Chosen automatically")
                            : Translation.tr("Choose an app")
                    onPicked: entryId => DefaultApps.setDefault(roleRow.modelData.key, entryId)
                }
            }
        }
    }
}
