pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.mediaControls

ColumnLayout {
    id: root
    readonly property bool busy: LocalSend.state === LocalSend.stateSending || LocalSend.receiveSessionActive
    readonly property bool receiving: GlobalStates.mediaReceiveActive && !GlobalStates.mediaTransferActive
    spacing: 6
    Component.onCompleted: {
        if (!receiving) GlobalStates.mediaTransferActive = true;
        GlobalStates.mediaControlsOpen = true;
    }
    RowLayout {
        Layout.fillWidth: true
        IslandButton {
            symbol: "upload"; text: Translation.tr("Send")
            highlighted: !root.receiving
            enabled: !root.busy
            onClicked: {
                GlobalStates.mediaReceiveActive = false;
                GlobalStates.mediaTransferActive = true;
            }
        }
        IslandButton {
            symbol: "download"; text: Translation.tr("Receive")
            highlighted: root.receiving
            enabled: !root.busy
            onClicked: {
                GlobalStates.mediaTransferActive = false;
                GlobalStates.mediaReceiveActive = true;
                if (!LocalSend.receiveActive) LocalSend.startReceive();
            }
        }
        Item { Layout.fillWidth: true }
        StyledText {
            visible: !root.receiving && !GlobalStates.mediaTransferUrls.length
            text: Translation.tr("Drop files here")
            font.pixelSize: 12; color: Appearance.colors.colOnSurfaceVariant
        }
    }
    Loader {
        Layout.fillWidth: true
        Layout.preferredHeight: Appearance.sizes.mediaControlsHeight
        sourceComponent: root.receiving ? receive : send
    }
    Component {
        id: send
        FileTransferPanel {
            fileUrls: GlobalStates.mediaTransferUrls
            targetWidth: root.width
            targetHeight: Appearance.sizes.mediaControlsHeight
            radius: Appearance.rounding.large
        }
    }
    Component {
        id: receive
        ReceivePanel {
            targetWidth: root.width
            targetHeight: Appearance.sizes.mediaControlsHeight
            radius: Appearance.rounding.large
        }
    }
}
