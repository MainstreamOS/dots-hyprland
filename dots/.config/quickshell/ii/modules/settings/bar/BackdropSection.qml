import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Solid, Frost and Glass for a surface with a background: the bar or the dock.
ContentSection {
    id: root
    // The surface's config: holds backdrop, backgroundOpacity and showBackground.
    required property var surface

    icon: "blur_on"
    title: Translation.tr("Backdrop")

    // Each preset fills in the settings below, which stay free to change. Solid is the stock look.
    readonly property var backdropPresets: [
        { displayName: Translation.tr("Solid"), enable: false, opacity: -1, blur: 24, haze: 0, magnification: 1, offsetX: 0, offsetY: 0 },
        { displayName: Translation.tr("Frost"), enable: true, opacity: 0.4, blur: 56, haze: 0.16, magnification: 1, offsetX: 0, offsetY: 0 },
        { displayName: Translation.tr("Glass"), enable: true, opacity: 0.55, blur: 24, haze: 0, magnification: 1.25, offsetX: 24, offsetY: 12 },
    ]
    readonly property int backdropPresetIndex: {
        const b = root.surface.backdrop;
        const near = (one, other) => Math.abs(one - other) < 0.01;
        return root.backdropPresets.findIndex(p => p.enable === b.enable && near(p.opacity, root.surface.backgroundOpacity)
            && (!p.enable || (near(p.blur, b.blur) && near(p.haze, b.haze) && near(p.magnification, b.magnification)
                && near(p.offsetX, b.offsetX) && near(p.offsetY, b.offsetY))));
    }


        ConfigRow {
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            OptionalMaterialSymbol {
                icon: "auto_awesome"
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 6
                text: Translation.tr("Blur preset")
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledComboBox {
                textRole: "displayName"
                Layout.fillWidth: false
                Layout.preferredWidth: 220
                model: root.backdropPresetIndex >= 0 ? root.backdropPresets
                    : root.backdropPresets.concat([{ displayName: Translation.tr("Custom") }])
                currentIndex: root.backdropPresetIndex >= 0 ? root.backdropPresetIndex : root.backdropPresets.length
                onActivated: index => {
                    const preset = root.backdropPresets[index];
                    if (!preset)
                        return;
                    const b = root.surface.backdrop;
                    b.enable = preset.enable;
                    b.blur = preset.blur;
                    b.haze = preset.haze;
                    b.magnification = preset.magnification;
                    b.offsetX = preset.offsetX;
                    b.offsetY = preset.offsetY;
                    root.surface.backgroundOpacity = preset.opacity;
                    root.surface.showBackground = true;
                }
                StyledToolTip {
                    text: Wallpapers.isVideoFile(Config.options.background.wallpaperPath)
                        ? Translation.tr("Frost and Glass need a picture wallpaper. With a video one, this stays see-through instead.")
                        : Translation.tr("Frost and Glass show a blurred copy of the wallpaper behind this surface, like the desktop widgets.")
                }
            }
        }

        ConfigSlider {
            visible: root.surface.backdrop.enable
            text: Translation.tr("Blur amount")
            value: root.surface.backdrop.blur
            usePercentTooltip: false
            buttonIcon: "deblur"
            from: 4
            to: 64
            onMoved: root.surface.backdrop.blur = value
        }
        ConfigSlider {
            visible: root.surface.backdrop.enable
            text: Translation.tr("Haze")
            value: root.surface.backdrop.haze
            buttonIcon: "foggy"
            from: 0
            to: 0.5
            onMoved: root.surface.backdrop.haze = value
        }
        ConfigSlider {
            visible: root.surface.backdrop.enable
            text: Translation.tr("Magnification")
            value: root.surface.backdrop.magnification
            buttonIcon: "zoom_in"
            from: 1
            to: 2
            onMoved: root.surface.backdrop.magnification = value
        }
        ConfigSlider {
            visible: root.surface.backdrop.enable
            text: Translation.tr("Horizontal offset")
            value: root.surface.backdrop.offsetX
            usePercentTooltip: false
            buttonIcon: "swap_horiz"
            from: -200
            to: 200
            onMoved: root.surface.backdrop.offsetX = Math.round(value)
        }
        ConfigSlider {
            visible: root.surface.backdrop.enable
            text: Translation.tr("Vertical offset")
            value: root.surface.backdrop.offsetY
            usePercentTooltip: false
            buttonIcon: "swap_vert"
            from: -200
            to: 200
            onMoved: root.surface.backdrop.offsetY = Math.round(value)
        }
}
