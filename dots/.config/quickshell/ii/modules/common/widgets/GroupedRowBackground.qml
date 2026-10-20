import QtQuick
import qs.modules.common

// A row of a grouped list in the Dynamic Island's style: the group's first and last rows take the
// outer radius and the rows between stay nearly square, so the rows read as one rounded block.
Rectangle {
    required property int index
    required property int count
    property real outerRadius: Appearance.rounding.normal - 3
    property real innerRadius: 4
    readonly property bool firstRow: index === 0
    readonly property bool lastRow: index === count - 1
    topLeftRadius: firstRow ? outerRadius : innerRadius
    topRightRadius: firstRow ? outerRadius : innerRadius
    bottomLeftRadius: lastRow ? outerRadius : innerRadius
    bottomRightRadius: lastRow ? outerRadius : innerRadius
}
