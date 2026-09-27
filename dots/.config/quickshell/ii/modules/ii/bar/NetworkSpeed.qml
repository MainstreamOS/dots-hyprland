import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/*
 * Live download and upload speeds. Hovering shows the connection's details,
 * and clicking opens the Wi-Fi list in the right sidebar.
 */
MouseArea {
    id: root
    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: Appearance.sizes.baseBarHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    acceptedButtons: Qt.LeftButton
    // On release, as Resources does, so holding the button still shows the
    // details card when tooltips are set to show on click.
    onClicked: GlobalStates.toggleWifiList()

    RowLayout {
        id: rowLayout

        spacing: 0
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4

        SpeedReading {
            iconName: "arrow_downward"
            value: NetworkUsage.formatRate(NetworkUsage.downloadRate)
        }

        SpeedReading {
            Layout.leftMargin: 6
            iconName: "arrow_upward"
            value: NetworkUsage.formatRate(NetworkUsage.uploadRate)
        }
    }

    NetworkSpeedPopup {
        hoverTarget: root
        // The card would otherwise sit over the Wi-Fi list the click opened.
        showOnHover: !GlobalStates.sidebarRightOpen
    }

    component SpeedReading: RowLayout {
        id: reading
        required property string iconName
        required property string value
        spacing: 2

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            fill: 0
            text: reading.iconName
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.barContent.colOnLayer1
        }

        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: widestReading.width
            implicitHeight: valueText.implicitHeight

            // The widest reading the formatter gives, so the pill holds still
            // as the numbers change under it.
            TextMetrics {
                id: widestReading
                font: valueText.font
                text: "888 MB/s"
            }

            // Kept against its arrow: the room the slot has to spare falls
            // after the reading, not between the arrow and its number.
            StyledText {
                id: valueText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                color: Appearance.barContent.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
                // Tabular figures: every digit is one width, so no reading
                // outgrows the slot measured on eights.
                font.features: ({ "tnum": 1 })
                text: reading.value
            }
        }
    }
}
