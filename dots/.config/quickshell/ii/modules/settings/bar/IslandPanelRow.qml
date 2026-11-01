import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// One panel in the Island's list. A hidden one greys out, and has no place in the order to move.
ConfigSwitch {
    id: row
    required property string modelData
    required property int index
    required property int count
    readonly property bool shown: IslandPanels.enabled(row.modelData)
    text: IslandPanels.entry(row.modelData)?.name ?? row.modelData
    buttonIcon: IslandPanels.entry(row.modelData)?.icon ?? "widgets"
    checked: row.shown
    opacity: row.shown ? 1 : 0.5
    onCheckedChanged: IslandPanels.setEnabled(row.modelData, checked)

    // Dimmed rather than disabled at the ends of the list: a disabled button lets
    // its click through to the row, which would hide the panel.
    trailingControls: [
        RippleButton {
            readonly property bool canMove: row.index > 0
            visible: row.shown
            implicitWidth: 32
            implicitHeight: 24
            hoverEnabled: canMove
            opacity: canMove ? 1 : 0.4
            Accessible.name: Translation.tr("Move up")
            onClicked: IslandPanels.move(row.modelData, -1)
            contentItem: MaterialSymbol { anchors.centerIn: parent; text: "arrow_upward"; iconSize: 18 }
        },
        RippleButton {
            readonly property bool canMove: row.index < row.count - 1
            visible: row.shown
            implicitWidth: 32
            implicitHeight: 24
            hoverEnabled: canMove
            opacity: canMove ? 1 : 0.4
            Accessible.name: Translation.tr("Move down")
            onClicked: IslandPanels.move(row.modelData, 1)
            contentItem: MaterialSymbol { anchors.centerIn: parent; text: "arrow_downward"; iconSize: 18 }
        }
    ]
}
