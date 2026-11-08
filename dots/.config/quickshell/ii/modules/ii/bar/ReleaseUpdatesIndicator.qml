import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick

/*
 * Shows only while a Mainstream release is waiting, with a dot whose colour
 * says how urgent it has become. Left click opens the Update page, right
 * click offers the same choices the settings page does.
 */
MouseArea {
    id: root
    property real uiScale: QsWindow.window?.uiScale ?? 1
    // Handed the strip's tones when this sits bare on it rather than in a group.
    property Appearance.SurfaceContent tones: Appearance.barContent

    // CustomIcon is a plain Item and carries no implicit size of its own. The
    // extra width on the right is the gutter the dot sits in — the M is solid
    // to all four corners, so a badge laid over it would be unreadable.
    implicitWidth: icon.width + (4 + 7) * root.uiScale
    // baseBarHeight, not barHeight: this renders without a pill, and on a
    // floating bar barHeight is taller by the gap on each side, which would
    // stretch the row and drop everything sharing it.
    implicitHeight: Appearance.sizes.baseBarHeight

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: !Config.options.bar.tooltips.clickToShow

    onPressed: event => {
        if (event.button === Qt.RightButton) optionsPopup.open = !optionsPopup.open;
        else ReleaseUpdates.openUpdatesPage();
    }

    CustomIcon {
        id: icon
        anchors {
            left: parent.left
            leftMargin: 2 * root.uiScale
            verticalCenter: parent.verticalCenter
        }
        // 238x104 in the source, kept to that ratio. Sized so the M itself
        // still lands at the same width it did alone and the stream strokes
        // account for the rest. The viewBox padding is scaled to survive this
        // size — too little and antialiasing shaves the outer stems.
        width: 36 * root.uiScale
        height: 16 * root.uiScale
        source: "mainstream-symbolic.svg"
        colorize: true
        color: root.tones.colOnLayer1

        UpdateDot {
            anchors {
                left: parent.right
                leftMargin: 1 * root.uiScale
                top: parent.top
                // Above the mark's cap rather than level with it, so it reads
                // as a badge on the icon instead of part of the artwork.
                topMargin: -3 * root.uiScale
            }
            size: 6 * root.uiScale
            tones: root.tones
        }
    }

    ReleaseUpdatesHoverPopup {
        hoverTarget: root
        // Suppress the hover popup whenever the options popup is open so they
        // don't stack on top of each other.
        showOnHover: !optionsPopup.open
    }

    ReleaseUpdatesPopup {
        id: optionsPopup
        hoverTarget: root
    }
}
