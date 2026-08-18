import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * The way home a settings section keeps: quiet, small, and shown only while
 * something in the section differs from stock. The caller owns the visible
 * condition and the click, because only it knows which keys make up "stock";
 * this owns the chrome, so every section's way home reads the same.
 */
RippleButton {
    id: root
    implicitHeight: 30
    implicitWidth: resetRow.implicitWidth + 18
    buttonRadius: Appearance.rounding.small
    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active
    contentItem: RowLayout {
        id: resetRow
        anchors.centerIn: parent
        spacing: 4
        MaterialSymbol {
            text: "restart_alt"
            iconSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
        StyledText {
            text: root.buttonText
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }
}
