import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

// Previous or next photo in the full-screen viewer.
RippleButton {
    id: root
    required property int direction

    anchors.verticalCenter: parent.verticalCenter
    z: 60
    implicitWidth: 40
    implicitHeight: 40
    buttonRadius: 20
    colBackground: ColorUtils.transparentize("black", 0.45)
    colBackgroundHover: ColorUtils.transparentize("black", 0.25)
    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        text: root.direction < 0 ? "chevron_left" : "chevron_right"
        iconSize: 24
        color: "white"
    }
    StyledToolTip {
        text: root.direction < 0 ? Translation.tr("Previous photo (Left arrow)") : Translation.tr("Next photo (Right arrow)")
    }
}
