import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// One column of the weather panel's forecast: an hour, or a day with its low beside its high.
Item {
    id: root
    property var contentColors: Appearance.islandContent
    property string label
    property string icon
    property string temperature
    property string low
    property string rain

    Layout.fillWidth: true
    Layout.preferredWidth: 1 * Appearance.sizes.islandScale
    Layout.fillHeight: true

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 3 * Appearance.sizes.islandScale

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: root.label
            color: root.contentColors.colSubtext
            font.pixelSize: 11 * Appearance.sizes.islandScale
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: root.icon
            iconSize: 20 * Appearance.sizes.islandScale
            color: root.contentColors.colOnLayer0
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 3 * Appearance.sizes.islandScale
            StyledText {
                text: root.temperature
                color: root.contentColors.colOnLayer0
                font.pixelSize: 13 * Appearance.sizes.islandScale
                font.weight: Font.Medium
            }
            StyledText {
                visible: root.low.length > 0
                text: root.low
                color: root.contentColors.colSubtext
                font.pixelSize: 13 * Appearance.sizes.islandScale
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 2 * Appearance.sizes.islandScale
            MaterialSymbol { text: "water_drop"; iconSize: 10 * Appearance.sizes.islandScale; color: root.contentColors.colPrimary }
            StyledText { text: root.rain; color: root.contentColors.colSubtext; font.pixelSize: 10 * Appearance.sizes.islandScale }
        }
    }
}
