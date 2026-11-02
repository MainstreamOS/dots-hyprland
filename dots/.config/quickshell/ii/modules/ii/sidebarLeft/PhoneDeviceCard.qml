import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Rectangle {
    id: root
    required property var device
    property bool selected: false
    signal chosen()
    implicitHeight: content.implicitHeight + 20
    radius: 14
    color: Appearance.surfaces.raised

    PhoneIdentityRow {
        id: content
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
        device: root.device
        DialogButton {
            buttonText: root.selected ? Translation.tr("Selected") : Translation.tr("Choose")
            enabled: !root.selected
            onClicked: root.chosen()
        }
    }
}
