import QtQuick
import qs.modules.common
import qs.modules.common.widgets

Pill {
    id: root
    property string caption: ""
    // "success" | "accent" | "neutral"
    property string tone: "neutral"

    implicitWidth: captionText.implicitWidth + Appearance.rounding.verysmall * 2
    implicitHeight: captionText.implicitHeight + Appearance.rounding.unsharpenmore
    color: {
        if (root.tone === "success")
            return Appearance.m3colors.m3successContainer;
        if (root.tone === "accent")
            return Appearance.colors.colPrimaryContainer;
        return Appearance.colors.colLayer2;
    }

    StyledText {
        id: captionText
        anchors.centerIn: parent
        text: root.caption
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Medium
        color: {
            if (root.tone === "success")
                return Appearance.m3colors.m3onSuccessContainer;
            if (root.tone === "accent")
                return Appearance.colors.colOnPrimaryContainer;
            return Appearance.colors.colSubtext;
        }
    }
}
