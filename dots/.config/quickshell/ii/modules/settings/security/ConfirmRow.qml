import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RowLayout {
    id: root
    property string prompt: ""
    property string actionText: ""
    property string actionIcon: ""
    property string actionVariant: "danger"
    property bool actionEnabled: true
    signal confirmed()
    signal canceled()

    Layout.fillWidth: true
    spacing: 8

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colOnLayer1
        text: root.prompt
    }

    ActionButton {
        caption: Translation.tr("Cancel")
        onClicked: root.canceled()
    }

    ActionButton {
        variant: root.actionVariant
        materialIcon: root.actionIcon
        caption: root.actionText
        enabled: root.actionEnabled
        onClicked: root.confirmed()
    }
}
