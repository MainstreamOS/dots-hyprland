import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Saves settings that match no preset under a name, or deletes the saved preset in use.
ColumnLayout {
    id: root
    property bool canSave: false
    property bool canDelete: false
    // Names a saved preset can't take, which belong to the shipped ones.
    property var reservedNames: []
    signal saveRequested(string name)
    signal deleteRequested()

    readonly property string typedName: nameField.text.trim()
    readonly property bool nameAllowed: typedName.length > 0
        && !reservedNames.some(name => name.toLowerCase() === typedName.toLowerCase())

    function save() {
        if (!root.nameAllowed)
            return;
        root.saveRequested(root.typedName);
        nameField.text = "";
    }

    Layout.fillWidth: true
    Layout.leftMargin: 8
    Layout.rightMargin: 8
    visible: canSave || canDelete
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        visible: root.canSave
        spacing: 8
        MaterialTextField {
            id: nameField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Preset name")
            maximumLength: 40
            onAccepted: root.save()
        }
        RippleButtonWithIcon {
            materialIcon: "bookmark_add"
            mainText: Translation.tr("Save preset")
            enabled: root.nameAllowed
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            onClicked: root.save()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.canDelete
        Item {
            Layout.fillWidth: true
        }
        RippleButtonWithIcon {
            materialIcon: "delete"
            mainText: Translation.tr("Delete preset")
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            onClicked: root.deleteRequested()
        }
    }
}
