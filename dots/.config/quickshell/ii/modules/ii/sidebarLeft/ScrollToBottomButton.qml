import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root
    required property ListView target
    // Content-relative end rather than atYEnd: a list with bottom runway
    // (margin) is only atYEnd deep inside the blank space, which would keep
    // this button up permanently. Identical to atYEnd on margin-less lists.
    readonly property bool atContentEnd: target.contentHeight <= target.height
        || target.contentY >= target.originY + target.contentHeight - target.height - 1

    anchors {
        bottom: parent.bottom
        horizontalCenter: parent.horizontalCenter
        bottomMargin: 10
    }

    opacity: !root.atContentEnd ? 1 : 0
    scale: !root.atContentEnd ? 1 : 0.7
    visible: opacity > 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    implicitWidth: contentItem.implicitWidth + 8 * 2
    implicitHeight: contentItem.implicitHeight + 4 * 2

    colBackground: Appearance.colors.colSecondary
    colBackgroundHover: Appearance.colors.colSecondaryHover
    colRipple: Appearance.colors.colSecondaryActive
    buttonRadius: Appearance.rounding.verysmall

    downAction: () => {
        // positionViewAtEnd works from estimated delegate heights and lands
        // short on rich messages. It still runs first to instantiate the
        // tail, then the exact end comes from real geometry, stopping at the
        // content's edge rather than the runway below it.
        target.positionViewAtEnd();
        Qt.callLater(() => {
            if (target.contentHeight > target.height)
                target.contentY = target.originY + target.contentHeight - target.height;
        });
    }

    contentItem: Row {
        id: contentItem
        spacing: 4
        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: "arrow_downward"
            font.pixelSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSecondary
            verticalAlignment: Text.AlignVCenter
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Translation.tr("Scroll to Bottom")
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colOnSecondary
            verticalAlignment: Text.AlignVCenter
        }
    }
}
