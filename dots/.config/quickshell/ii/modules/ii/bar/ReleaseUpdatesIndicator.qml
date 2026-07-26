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

    // Red and yellow are fixed rather than themed: on a cool palette the theme's
    // own error colour lands as a washed-out pink, and "install this promptly"
    // is not something the wallpaper should get a say in. The red matches the
    // badge Discord puts on its own tray icon, so the two read as one kind of
    // alert. Blue and white are the ordinary text colours and do follow it.
    readonly property var dotColors: ({
        "red": "#ed4646",
        "yellow": "#fdd835",
        "blue": Appearance.m3colors.m3primary,
        "white": Appearance.colors.colOnLayer1
    })

    // CustomIcon is a plain Item and carries no implicit size of its own. The
    // extra width on the right is the gutter the dot sits in — the M is solid
    // to all four corners, so a badge laid over it would be unreadable.
    implicitWidth: icon.width + 4 + 7
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
            leftMargin: 2
            verticalCenter: parent.verticalCenter
        }
        // 238x104 in the source, kept to that ratio. Sized so the M itself
        // still lands at the same width it did alone and the stream strokes
        // account for the rest. The viewBox padding is scaled to survive this
        // size — too little and antialiasing shaves the outer stems.
        width: 36
        height: 16
        source: "mainstream-symbolic.svg"
        colorize: true
        color: Appearance.colors.colOnLayer1

        Rectangle {
            anchors {
                left: parent.right
                leftMargin: 1
                top: parent.top
                // Above the mark's cap rather than level with it, so it reads
                // as a badge on the icon instead of part of the artwork.
                topMargin: -3
            }
            implicitWidth: 6
            implicitHeight: 6
            radius: height / 2
            color: root.dotColors[ReleaseUpdates.severity] ?? Appearance.colors.colOnLayer1
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
