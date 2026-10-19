import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

// A round button in the bottom right corner of a video.
RippleButton {
    id: root
    property string iconName
    property string tip

    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 6
    implicitWidth: 30
    implicitHeight: 30
    buttonRadius: Appearance.rounding.full
    colBackground: ColorUtils.transparentize("black", 0.45)
    colBackgroundHover: ColorUtils.transparentize("black", 0.25)

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: root.iconName
        iconSize: Appearance.font.pixelSize.larger
        color: "white"
    }

    StyledToolTip {
        text: root.tip
    }
}
