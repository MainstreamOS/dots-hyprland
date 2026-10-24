import qs.modules.common
import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: root
    required property var modelData
    signal chosen(string emoji)

    focusPolicy: Qt.TabFocus
    buttonRadius: Appearance.rounding.small
    Accessible.name: modelData.description
    onClicked: root.chosen(modelData.emoji)
    contentItem: StyledText {
        text: root.modelData.emoji
        font.pixelSize: 24
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    StyledToolTip { text: root.modelData.description }
}
