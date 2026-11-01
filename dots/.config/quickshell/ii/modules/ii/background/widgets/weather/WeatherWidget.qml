import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "weather"

    readonly property real sizeScale: Config.options.background.widgets.weather.size
    readonly property string accent: Config.options.background.widgets.weather.accent

    implicitHeight: backgroundShape.implicitHeight
    implicitWidth: backgroundShape.implicitWidth

    StyledDropShadow {
        target: backgroundShape
    }

    MaterialShape {
        id: backgroundShape
        anchors.fill: parent
        shape: MaterialShape.Shape.Pill
        color: root.accent ? ColorUtils.mix(root.accent, Appearance.m3colors.m3background, 0.55) : Appearance.colors.colPrimaryContainer
        implicitSize: 200 * root.sizeScale

        StyledText {
            font {
                pixelSize: 80 * root.sizeScale
                family: Appearance.font.family.expressive
                weight: Font.Medium
            }
            color: root.accent || Appearance.colors.colPrimary
            text: Weather.data?.temp.substring(0,Weather.data?.temp.length - 1) ?? "--°"
            anchors {
                right: parent.right
                top: parent.top
                rightMargin: 16 * root.sizeScale
                topMargin: 20 * root.sizeScale
            }
        }

        MaterialSymbol {
            iconSize: 80 * root.sizeScale
            color: root.accent ? ColorUtils.mix(root.accent, Appearance.m3colors.m3onBackground, 0.3) : Appearance.colors.colOnPrimaryContainer
            text: Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud"
            anchors {
                left: parent.left
                bottom: parent.bottom

                leftMargin: 16 * root.sizeScale
                bottomMargin: 20 * root.sizeScale
            }
        }
    }
}
