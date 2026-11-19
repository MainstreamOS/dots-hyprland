import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// One feature with its state: a header, the actions under it, and a second
// segment that opens beneath for a form or a confirmation.
ColumnLayout {
    id: root
    property string icon: ""
    // Follows the pill unless a card sets its own.
    property color iconColor: {
        if (root.pillTone === "success")
            return Appearance.m3colors.m3success;
        if (root.pillTone === "accent")
            return Appearance.colors.colPrimary;
        return Appearance.colors.colOnLayer1;
    }
    property string title: ""
    property string pillText: ""
    // "success" | "accent" | "neutral"
    property string pillTone: "neutral"
    property string description: ""
    // An unavailable card stays on the page, muted, with its actions disabled.
    property bool available: true
    property bool detailVisible: false
    property alias detail: detailColumn.data
    default property alias content: mainColumn.data

    readonly property real padding: Appearance.rounding.small
    readonly property real joinRadius: Appearance.rounding.unsharpenmore

    Layout.fillWidth: true
    spacing: 2
    enabled: root.available

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: mainColumn.implicitHeight + root.padding * 2
        color: Appearance.colors.colLayer1
        topLeftRadius: Appearance.rounding.normal
        topRightRadius: Appearance.rounding.normal
        bottomLeftRadius: root.detailVisible ? root.joinRadius : Appearance.rounding.normal
        bottomRightRadius: root.detailVisible ? root.joinRadius : Appearance.rounding.normal

        ColumnLayout {
            id: mainColumn
            anchors.fill: parent
            anchors.margins: root.padding
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                MaterialSymbol {
                    text: root.icon
                    iconSize: Appearance.font.pixelSize.hugeass
                    color: root.available ? root.iconColor : Appearance.colors.colSubtext
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: root.pillText.length === 0
                            text: root.title
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: root.available ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                        }

                        StatusPill {
                            visible: root.pillText.length > 0
                            caption: root.pillText
                            tone: root.pillTone
                        }

                        Item {
                            visible: root.pillText.length > 0
                            Layout.fillWidth: true
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.description.length > 0
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: root.description
                    }
                }
            }
        }
    }

    Rectangle {
        visible: root.detailVisible
        Layout.fillWidth: true
        implicitHeight: detailColumn.implicitHeight + root.padding * 2
        color: Appearance.colors.colLayer1
        topLeftRadius: root.joinRadius
        topRightRadius: root.joinRadius
        bottomLeftRadius: Appearance.rounding.normal
        bottomRightRadius: Appearance.rounding.normal

        ColumnLayout {
            id: detailColumn
            anchors.fill: parent
            anchors.margins: root.padding
            spacing: 10
        }
    }
}
