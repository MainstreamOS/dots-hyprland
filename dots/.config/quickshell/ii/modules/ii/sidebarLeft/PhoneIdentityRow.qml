import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// A phone's icon, name and status, as the Phone tab's header and the phone chooser show them.
// Anything placed inside follows on the right.
RowLayout {
    id: root
    // The phone shown, or null when there is none yet.
    property var device: null
    property string name: device?.name ?? ""
    readonly property bool reachable: device?.reachable ?? false
    readonly property string status: {
        if (!root.device)
            return Translation.tr("Ready");
        if (!root.reachable)
            return Translation.tr("Not reachable");
        const charge = root.device.charge ?? -1;
        if (charge < 0)
            return Translation.tr("Connected");
        return root.device.charging ? Translation.tr("%1% · Charging").arg(charge) : Translation.tr("%1% · Connected").arg(charge);
    }
    spacing: 8

    Rectangle {
        Layout.preferredWidth: 30
        Layout.preferredHeight: 30
        radius: 9
        color: ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer1, 0.55)
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.reachable ? "smartphone" : "phonelink_off"
            iconSize: 17
            color: root.reachable ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 1
        StyledText {
            Layout.fillWidth: true
            text: root.name
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
            elide: Text.ElideRight
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 5
            Rectangle {
                Layout.preferredWidth: 6
                Layout.preferredHeight: 6
                radius: 3
                color: root.reachable ? Appearance.m3colors.m3success : Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                text: root.status
                font.pixelSize: Appearance.font.scaled(11)
                font.weight: Font.Medium
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }
    }
}
