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
        model: IslandPanels.shownOrder
        delegate: IslandPanelRow {
            count: IslandPanels.shownOrder.length
        }
    }
    ConfigSwitch {
        buttonIcon: "share_reviews"
        text: Translation.tr("LocalSend when dragging files")
        checked: IslandPanels.enabled("localsend")
        onCheckedChanged: IslandPanels.setEnabled("localsend", checked)
    }
    Repeater {
        model: IslandPanels.hiddenOrder
        delegate: IslandPanelRow {
            count: IslandPanels.hiddenOrder.length
        }
    }
    ConfigResetButton {
        buttonText: Translation.tr("Reset panels")
        onClicked: {
            Config.options.bar.island.panelOrder = Config.defaultIslandPanels;
            Config.options.bar.island.disabledPanels = [];
        }
    }
}
