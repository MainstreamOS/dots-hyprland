import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions

// The surface every context menu is drawn on, so they all read as one kind of
// thing and a new menu looks like the others without copying anything. The
// rows go inside it, anchored `padding` in from its edges, which keeps a
// highlighted row's own rounded shape floating inside the card. It follows
// Rounded Corners the way the shell's other panels do.
//
// The shadow is its own and deeper than the shared default, which is faint
// enough to vanish over a bright wallpaper or a light page. Deeper rather than
// wider on purpose: a menu kept one elevation margin from a screen edge would
// have a larger blur cut off exactly where it most often opens. It is drawn
// beneath the card and follows its opacity, so nothing using the card may set
// clip on it.
Rectangle {
    id: root

    readonly property real padding: 4
    // For a menu's own buttons that are not ContextMenuItem rows, so they
    // square off with the rows.
    readonly property real rowRadius: RoundedCorners.on ? Appearance.rounding.small : 0

    color: Appearance.m3colors.m3surfaceContainer
    radius: RoundedCorners.on ? Appearance.rounding.normal : 0

    StyledRectangularShadow {
        z: -1
        target: root
        color: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.4)
    }
}
