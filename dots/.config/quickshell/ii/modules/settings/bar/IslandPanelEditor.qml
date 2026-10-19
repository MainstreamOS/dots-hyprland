pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 4
    Repeater {
        model: IslandPanels.order.filter(id => id !== "localsend")
        delegate: RowLayout {
            id: row
            required property string modelData
            required property int index
            Layout.fillWidth: true
            spacing: 4
            ConfigSwitch {
                text: IslandPanels.entry(row.modelData)?.name ?? row.modelData
                buttonIcon: IslandPanels.entry(row.modelData)?.icon ?? "widgets"
                checked: IslandPanels.enabled(row.modelData)
                onCheckedChanged: IslandPanels.setEnabled(row.modelData, checked)
            }
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                enabled: row.index > 0
                Accessible.name: Translation.tr("Move up")
                onClicked: IslandPanels.move(row.modelData, -1)
                contentItem: MaterialSymbol { anchors.centerIn: parent; text: "arrow_upward"; iconSize: 18 }
            }
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                enabled: row.index < IslandPanels.order.length - 2
                Accessible.name: Translation.tr("Move down")
                onClicked: IslandPanels.move(row.modelData, 1)
                contentItem: MaterialSymbol { anchors.centerIn: parent; text: "arrow_downward"; iconSize: 18 }
            }
        }
    }
    ConfigSwitch {
        buttonIcon: "share_reviews"
        text: Translation.tr("LocalSend when dragging files")
        checked: IslandPanels.enabled("localsend")
        onCheckedChanged: IslandPanels.setEnabled("localsend", checked)
    }
    ConfigResetButton {
        buttonText: Translation.tr("Reset panels")
        onClicked: {
            Config.options.bar.island.panelOrder = Config.defaultIslandPanels;
            Config.options.bar.island.disabledPanels = [];
        }
    }
}
