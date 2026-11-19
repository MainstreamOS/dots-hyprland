import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RippleButtonWithIcon {
    id: root
    // "primary" | "tonal" | "danger"
    property string variant: "tonal"
    property string caption: ""
    // Shown in place of the caption while busy, when set.
    property string busyCaption: ""
    property bool busy: false
    // A disabled button loses its fill, so its label goes back to the color
    // that reads on the card behind it.
    readonly property color colContent: {
        if (root.enabled && root.variant === "primary")
            return Appearance.colors.colOnPrimary;
        if (root.enabled && root.variant === "danger")
            return Appearance.colors.colOnErrorContainer;
        return Appearance.colors.colOnSecondaryContainer;
    }

    mainText: root.busy && root.busyCaption.length > 0 ? root.busyCaption : root.caption
    colBackground: {
        if (root.variant === "primary")
            return Appearance.colors.colPrimary;
        if (root.variant === "danger")
            return Appearance.colors.colErrorContainer;
        return Appearance.colors.colLayer2;
    }
    colBackgroundHover: {
        if (root.variant === "primary")
            return Appearance.colors.colPrimaryHover;
        if (root.variant === "danger")
            return Appearance.colors.colErrorContainerHover;
        return Appearance.colors.colLayer2Hover;
    }
    colRipple: {
        if (root.variant === "primary")
            return Appearance.colors.colPrimaryActive;
        if (root.variant === "danger")
            return Appearance.colors.colErrorContainerActive;
        return Appearance.colors.colLayer2Active;
    }

    contentItem: RowLayout {
        spacing: 5

        MaterialSymbol {
            visible: text.length > 0
            text: root.busy ? "hourglass_top" : root.materialIcon
            iconSize: root.fontSizes.larger
            fill: root.materialIconFill ? 1 : 0
            color: root.colContent
        }
        StyledText {
            text: root.mainText
            font.pixelSize: root.fontSizes.small
            color: root.colContent
        }
    }
}
