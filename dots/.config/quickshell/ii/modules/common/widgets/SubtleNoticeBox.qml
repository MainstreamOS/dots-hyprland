import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The quiet cousin of NoticeBox: an aside that sits beside the controls it
 * explains rather than announcing over them, tinted just enough to read as
 * a note. Placement stays with the caller — where an aside belongs is the
 * page's call, not the note's.
 */
Rectangle {
    id: root
    property string materialIcon: "info"
    property string text: ""
    radius: Appearance.rounding.small
    color: ColorUtils.applyAlpha(Appearance.m3colors.m3primary, 0.12)
    implicitHeight: noteRow.implicitHeight + 16
    RowLayout {
        id: noteRow
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8
        MaterialSymbol {
            text: root.materialIcon
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.m3colors.m3primary
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.small
            text: root.text
        }
    }
}
