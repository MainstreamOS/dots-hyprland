import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

// The paired phone's battery and unread messages. Clicking opens the sidebar's Phone tab.
MouseArea {
    id: root
    readonly property int charge: Phone.device?.charge ?? -1
    readonly property int unread: (Phone.conversations ?? []).filter(item => !Phone.isOutgoing(item) && !item.read).length
    readonly property string chargeText: root.charge >= 0 ? Translation.tr("%1%").arg(root.charge) : ""

    implicitWidth: row.implicitWidth + 8
    implicitHeight: Config.options.bar.vertical ? row.implicitHeight + 8 : Appearance.sizes.baseBarHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    acceptedButtons: Qt.LeftButton
    onClicked: {
        Phone.wanted = true;
        SidebarLeftTabs.showTab("phone");
    }

    GridLayout {
        id: row
        anchors.centerIn: parent
        columns: Config.options.bar.vertical ? 1 : 2
        rowSpacing: 0
        columnSpacing: 3

        Item {
            Layout.alignment: Qt.AlignCenter
            implicitWidth: icon.implicitWidth
            implicitHeight: icon.implicitHeight

            MaterialSymbol {
                id: icon
                anchors.centerIn: parent
                text: !Phone.reachable ? "phonelink_off" : "smartphone"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.barContent.colOnLayer1
            }
            Rectangle {
                visible: root.unread > 0
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: -1
                anchors.rightMargin: -2
                width: 8
                height: 8
                radius: 4
                color: Appearance.barContent.colPrimary
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignCenter
            visible: Phone.reachable && text.length > 0
            text: root.chargeText
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.barContent.colOnLayer1
        }
    }

    StyledPopup {
        hoverTarget: root
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4
            StyledPopupHeaderRow {
                icon: "smartphone"
                label: Phone.device?.name ?? Translation.tr("Phone")
            }
            StyledPopupValueRow {
                icon: "link"
                label: Translation.tr("Status")
                value: Phone.reachable ? Translation.tr("Connected") : Translation.tr("Not reachable")
            }
            StyledPopupValueRow {
                visible: root.charge >= 0
                icon: "battery_full"
                label: Translation.tr("Battery")
                value: root.chargeText
            }
            StyledPopupValueRow {
                visible: root.unread > 0
                icon: "chat"
                label: Translation.tr("Unread")
                value: String(root.unread)
            }
        }
    }
}
