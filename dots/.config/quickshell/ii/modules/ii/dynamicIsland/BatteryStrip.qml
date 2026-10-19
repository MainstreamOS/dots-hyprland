pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Flickable {
    id: root
    property var entries: []
    implicitHeight: 60
    contentWidth: cards.width
    contentHeight: height
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    readonly property color elevatedSurface: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer0, 0.92)
    function details(entry) {
        const parts = [];
        if (entry.state === UPowerDeviceState.FullyCharged) parts.push(Translation.tr("Fully charged"));
        else if (entry.state === UPowerDeviceState.Charging) parts.push(Translation.tr("Charging"));
        else if (entry.state === UPowerDeviceState.Discharging) parts.push(Translation.tr("On battery"));
        else parts.push(entry.source || "");
        if (entry.power > 0.01 && Config.options.battery.popup.showPower) parts.push(entry.power.toFixed(2) + " W");
        if (entry.time > 0 && Config.options.battery.popup.showTime) {
            const hours = Math.floor(entry.time / 3600);
            const minutes = Math.floor(entry.time % 3600 / 60);
            const time = hours ? hours + "h " + minutes + "m" : minutes + "m";
            parts.push(time + " " + (entry.state === UPowerDeviceState.Charging ? Translation.tr("until full") : Translation.tr("remaining")));
        }
        return parts.filter(Boolean).join(" · ");
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: event => {
            if (root.contentWidth <= root.width) { event.accepted = false; return; }
            const delta = event.pixelDelta.x || event.pixelDelta.y || (event.angleDelta.x || event.angleDelta.y) / 120 * 160;
            root.contentX = Math.max(0, Math.min(root.contentWidth - root.width, root.contentX - delta));
            event.accepted = true;
        }
    }
    Row {
        id: cards
        height: root.height
        spacing: 2
        Repeater {
            model: root.entries
            Rectangle {
                id: card
                required property var modelData
                required property int index
                width: root.entries.length === 1 ? root.width : (root.width - cards.spacing * (root.entries.length - 1)) / root.entries.length
                height: root.height
                topLeftRadius: root.entries.length === 1 ? (Appearance?.rounding?.normal ?? 17) : card.index === 0 ? (Appearance?.rounding?.normal ?? 17) : 4
                bottomLeftRadius: root.entries.length === 1 ? (Appearance?.rounding?.normal ?? 17) : card.index === 0 ? (Appearance?.rounding?.normal ?? 17) : 4
                topRightRadius: root.entries.length === 1 ? (Appearance?.rounding?.normal ?? 17) : card.index === root.entries.length - 1 ? (Appearance?.rounding?.normal ?? 17) : 4
                bottomRightRadius: root.entries.length === 1 ? (Appearance?.rounding?.normal ?? 17) : card.index === root.entries.length - 1 ? (Appearance?.rounding?.normal ?? 17) : 4
                readonly property color ink: Appearance.colors.colOnLayer0
                readonly property bool charging: modelData.state === UPowerDeviceState.Charging
                readonly property real level: Math.max(0, Math.min(1, modelData.percentage))
                readonly property color accent: level <= Config.options.battery.low / 100 && !charging
                    ? Appearance.colors.colError : Appearance.colors.colPrimary
                color: root.elevatedSurface
                Accessible.role: Accessible.StaticText
                Accessible.name: modelData.label + " · " + Math.round(level * 100) + "% · " + root.details(modelData)
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 9
                    spacing: 3
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5
                        MaterialSymbol { text: card.modelData.symbol; iconSize: 18; color: card.accent }
                        StyledText { Layout.fillWidth: true; Layout.minimumWidth: 0; text: card.modelData.label; font.pixelSize: 12; font.weight: Font.Medium; elide: Text.ElideRight; textFormat: Text.PlainText }
                        MaterialSymbol { visible: card.charging; text: "bolt"; iconSize: 14; color: card.accent }
                        StyledText { text: Math.round(card.level * 100) + "%"; font.pixelSize: 13; font.weight: Font.DemiBold; color: card.accent }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.details(card.modelData)
                        font.pixelSize: 10
                        color: Appearance.colors.colOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 3
                        radius: 1.5
                        color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.12)
                        Rectangle { height: parent.height; width: parent.width * card.level; radius: 1.5; color: card.accent }
                    }
                }
            }
        }
    }
}
