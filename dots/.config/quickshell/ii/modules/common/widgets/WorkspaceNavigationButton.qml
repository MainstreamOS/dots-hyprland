import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick

RippleButton {
    id: root
    property string iconName
    property real uiScale: 1
    property bool pressedAtRest: true

    focusPolicy: Qt.NoFocus
    buttonRadius: RoundedCorners.on ? Appearance.rounding.small * uiScale : 0
    // These controls sit over windows, not a panel, so they use the surface itself;
    // at rest they keep the pressed tone, the ripple's ink over the hovered surface.
    readonly property color pressedSurface: {
        const surface = ColorUtils.applyAlpha(Appearance.colors.colLayer2Base, 0.78);
        const alpha = colRipple.a + surface.a * (1 - colRipple.a);
        return ColorUtils.applyAlpha(ColorUtils.mix(surface, colRipple,
            surface.a * (1 - colRipple.a) / alpha), alpha);
    }
    colBackground: pressedAtRest ? pressedSurface
        : ColorUtils.applyAlpha(Appearance.colors.colLayer1Base, 0.65)
    colBackgroundHover: pressedAtRest ? ColorUtils.applyAlpha(ColorUtils.mix(pressedSurface,
        Appearance.colors.colOnLayer0, 0.94), 0.86)
        : ColorUtils.applyAlpha(Appearance.colors.colLayer2Base, 0.78)
    colRipple: ColorUtils.applyAlpha(Appearance.colors.colOnLayer0, 0.12)

    StyledRectangularShadow {
        target: root.background
        z: -2
        blur: 4 * root.uiScale
        spread: 0
        offset: Qt.vector2d(0, root.uiScale)
        color: ColorUtils.applyAlpha(Appearance.m3colors.m3shadow, root.hovered ? 0.32 : 0.22)
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
    }

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: root.iconName
        iconSize: 24 * root.uiScale
        color: Appearance.colors.colOnLayer0
    }
}
