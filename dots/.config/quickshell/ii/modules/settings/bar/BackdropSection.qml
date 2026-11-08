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

    readonly property int backdropPresetIndex: BackdropPresets.indexFor(root.surface)

    ConfigRow {
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        OptionalMaterialSymbol {
            icon: "auto_awesome"
            Layout.alignment: Qt.AlignVCenter
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 6
            text: Translation.tr("Blur preset")
            color: Appearance.colors.colOnSecondaryContainer
        }
        StyledComboBox {
            textRole: "displayName"
            Layout.fillWidth: false
            Layout.preferredWidth: 220 * Appearance.font.textGrowth
            model: root.backdropPresetIndex >= 0 ? BackdropPresets.all
                : BackdropPresets.all.concat([{ displayName: Translation.tr("Custom") }])
            currentIndex: root.backdropPresetIndex >= 0 ? root.backdropPresetIndex : BackdropPresets.all.length
            onActivated: index => {
                if (BackdropPresets.all[index])
                    BackdropPresets.apply(BackdropPresets.all[index]);
            }
            StyledToolTip {
                text: Wallpapers.isVideoFile(Config.options.background.wallpaperPath)
                    ? Translation.tr("Frost and Glass need a picture wallpaper. With a video one, this stays see-through instead.")
                    : Translation.tr("Frost and Glass show a blurred copy of the wallpaper behind this surface, like the desktop widgets.")
            }
        }
    }

    SavePresetRow {
        canSave: root.backdropPresetIndex < 0
        canDelete: root.backdropPresetIndex >= BackdropPresets.shipped.length
        reservedNames: BackdropPresets.shipped.map(preset => preset.displayName).concat([Translation.tr("Custom")])
        onSaveRequested: name => BackdropPresets.save(name, root.surface)
        onDeleteRequested: BackdropPresets.remove(BackdropPresets.all[root.backdropPresetIndex].displayName)
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
