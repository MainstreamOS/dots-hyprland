import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property string title
    property string icon: ""
    property bool mirrorIcon: false
    // titleExtra sits against the title; headerExtra is pushed to the far end
    // of the row by the spacer between them.
    property alias titleExtra: titleExtraContainer.data
    property alias headerExtra: headerExtraContainer.data
    default property alias contentData: sectionContent.data

    Layout.fillWidth: true
    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        
        OptionalMaterialSymbol {
            icon: root.icon
            iconSize: Appearance.font.pixelSize.hugeass
            transform: Scale { xScale: root.mirrorIcon ? -1 : 1; origin.x: Appearance.font.pixelSize.hugeass / 2 }
        }
        StyledText {
            text: root.title
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Medium
            color: Appearance.colors.colOnSecondaryContainer
        }

        RowLayout {
            id: titleExtraContainer
            spacing: 8
        }

        Item { Layout.fillWidth: true }
        
        RowLayout {
            id: headerExtraContainer
            spacing: 8
        }
    }

    ColumnLayout {
        id: sectionContent
        Layout.fillWidth: true
        spacing: 4

    }
}
