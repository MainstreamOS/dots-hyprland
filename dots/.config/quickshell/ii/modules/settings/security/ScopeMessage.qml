import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Under the section the change belongs to, where the page is already scrolled.
ColumnLayout {
    id: root
    property string forScope
    readonly property bool hasError: SystemSecurity.errorScope === root.forScope && SystemSecurity.lastError.length > 0
    readonly property bool hasStatus: SystemSecurity.statusScope === root.forScope && SystemSecurity.statusMessage.length > 0

    Layout.fillWidth: true
    spacing: 2
    visible: root.hasError || root.hasStatus

    StyledText {
        Layout.fillWidth: true
        visible: root.hasError
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.m3colors.m3error
        text: SystemSecurity.lastError
    }
    StyledText {
        Layout.fillWidth: true
        visible: root.hasStatus
        wrapMode: Text.WordWrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colPrimary
        text: SystemSecurity.statusMessage
    }
}
