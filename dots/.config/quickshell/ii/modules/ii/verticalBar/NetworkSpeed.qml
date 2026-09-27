import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import qs.modules.ii.bar as Bar

MouseArea {
    id: root
    implicitHeight: columnLayout.implicitHeight
    implicitWidth: columnLayout.implicitWidth
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    acceptedButtons: Qt.LeftButton
    // On release, so holding the button still shows the details card when
    // tooltips are set to show on click.
    onClicked: GlobalStates.toggleWifiList()

    ColumnLayout {
        id: columnLayout
        spacing: 6
        anchors.fill: parent

        SpeedReading {
            iconName: "arrow_downward"
            value: NetworkUsage.formatRateShort(NetworkUsage.downloadRate)
        }

        SpeedReading {
            iconName: "arrow_upward"
            value: NetworkUsage.formatRateShort(NetworkUsage.uploadRate)
        }
    }

    Bar.NetworkSpeedPopup {
        hoverTarget: root
        showOnHover: !GlobalStates.sidebarRightOpen
    }

    component SpeedReading: ColumnLayout {
        id: reading
        required property string iconName
        required property string value
        Layout.alignment: Qt.AlignHCenter
        spacing: 0

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            fill: 0
            text: reading.iconName
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.barContent.colOnLayer1
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            color: Appearance.barContent.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.features: ({ "tnum": 1 })
            text: reading.value
        }
    }
}
