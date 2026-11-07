pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Flickable {
    id: root
    property var contentColors: Appearance.islandContent
    property var entries: []
    implicitHeight: 60 * Appearance.sizes.islandScale
    contentWidth: cards.width
    contentHeight: height
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds
    clip: true
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
        spacing: 2 * Appearance.sizes.islandScale
        Repeater {
            model: root.entries
            Rectangle {
                id: card
                required property var modelData
                required property int index
                width: root.entries.length === 1 ? root.width : (root.width - cards.spacing * (root.entries.length - 1)) / root.entries.length
                height: root.height
                topLeftRadius: root.entries.length === 1 ? (Appearance?.rounding?.normal ?? 17) * Appearance.sizes.islandScale : card.index === 0 ? (Appearance?.rounding?.normal ?? 17) * Appearance.sizes.islandScale : 4 * Appearance.sizes.islandScale
                bottomLeftRadius: root.entries.length === 1 ? (Appearance?.rounding?.normal ?? 17) * Appearance.sizes.islandScale : card.index === 0 ? (Appearance?.rounding?.normal ?? 17) * Appearance.sizes.islandScale : 4 * Appearance.sizes.islandScale
                topRightRadius: root.entries.length === 1 ? (Appearance?.rounding?.normal ?? 17) * Appearance.sizes.islandScale : card.index === root.entries.length - 1 ? (Appearance?.rounding?.normal ?? 17) * Appearance.sizes.islandScale : 4 * Appearance.sizes.islandScale
                bottomRightRadius: root.entries.length === 1 ? (Appearance?.rounding?.normal ?? 17) * Appearance.sizes.islandScale : card.index === root.entries.length - 1 ? (Appearance?.rounding?.normal ?? 17) * Appearance.sizes.islandScale : 4 * Appearance.sizes.islandScale
                readonly property color ink: root.contentColors.colOnLayer0
                readonly property bool charging: modelData.state === UPowerDeviceState.Charging
                readonly property real level: Math.max(0, Math.min(1, modelData.percentage))
                readonly property color accent: level <= Config.options.battery.low / 100 && !charging
                    ? root.contentColors.accent(Appearance.colors.colError) : root.contentColors.colPrimary
                color: Appearance.surfaces.raised
                Accessible.role: Accessible.StaticText
                Accessible.name: modelData.label + " · " + Math.round(level * 100) + "% · " + root.details(modelData)
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 9 * Appearance.sizes.islandScale
                    spacing: 3 * Appearance.sizes.islandScale
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 5 * Appearance.sizes.islandScale
                        MaterialSymbol { text: card.modelData.symbol; iconSize: 18 * Appearance.sizes.islandScale; color: card.accent }
                        StyledText { Layout.fillWidth: true; Layout.minimumWidth: 0; text: card.modelData.label; color: card.ink; font.pixelSize: 12 * Appearance.sizes.islandScale; font.weight: Font.Medium; elide: Text.ElideRight; textFormat: Text.PlainText }
                        MaterialSymbol { visible: card.charging; text: "bolt"; iconSize: 14 * Appearance.sizes.islandScale; color: card.accent }
                        StyledText { text: Math.round(card.level * 100) + "%"; font.pixelSize: 13 * Appearance.sizes.islandScale; font.weight: Font.DemiBold; color: card.accent }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.details(card.modelData)
                        font.pixelSize: 10 * Appearance.sizes.islandScale
                        color: root.contentColors.colOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 3 * Appearance.sizes.islandScale
                        radius: 1.5 * Appearance.sizes.islandScale
                        color: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.12)
                        Rectangle { height: parent.height; width: parent.width * card.level; radius: 1.5 * Appearance.sizes.islandScale; color: card.accent }
                    }
                }
            }
        }
    }
}
