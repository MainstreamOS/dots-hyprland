pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    property var contentColors: Appearance.islandContent
    spacing: 2 * Appearance.sizes.islandScale

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 106 * Appearance.sizes.islandScale
        topLeftRadius: (Appearance?.rounding?.normal ?? 17) * Appearance.sizes.islandScale
        topRightRadius: (Appearance?.rounding?.normal ?? 17) * Appearance.sizes.islandScale
        bottomLeftRadius: 5 * Appearance.sizes.islandScale
        bottomRightRadius: 5 * Appearance.sizes.islandScale
        color: Appearance.surfaces.raised

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10 * Appearance.sizes.islandScale
            anchors.topMargin: 8 * Appearance.sizes.islandScale
            anchors.bottomMargin: 8 * Appearance.sizes.islandScale
            spacing: 6 * Appearance.sizes.islandScale

            RowLayout {
                Layout.fillWidth: true
                spacing: 10 * Appearance.sizes.islandScale

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Weather.cityName || Translation.tr("Weather")
                        color: root.contentColors.colOnSurfaceVariant
                        font.pixelSize: 13 * Appearance.sizes.islandScale
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        spacing: 8 * Appearance.sizes.islandScale

                        StyledText {
                            text: Weather.data.temp
                            color: root.contentColors.colOnLayer0
                            font.pixelSize: 32 * Appearance.sizes.islandScale
                            font.weight: Font.Medium
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Weather.condition
                            color: root.contentColors.colOnSurfaceVariant
                            font.pixelSize: 12 * Appearance.sizes.islandScale
                            elide: Text.ElideRight
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: !Weather.lastReply ? "cloud" : Weather.lastReply.current?.is_day === 0 && Weather.lastReply.current?.weather_code <= 1
                        ? "bedtime" : Icons.getWeatherIcon(Weather.data.wCode) || "cloud"
                    color: root.contentColors.colOnLayer0
                    iconSize: 44 * Appearance.sizes.islandScale
                }

                IslandButton {
                    contentColors: root.contentColors
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 28 * Appearance.sizes.islandScale
                    implicitWidth: 28 * Appearance.sizes.islandScale
                    symbol: "refresh"
                    enabled: !Weather.refreshing
                    Accessible.name: Translation.tr("Refresh weather")
                    onClicked: Weather.getData()
                    StyledToolTip { text: Weather.refreshing ? Translation.tr("Updating weather…") : Translation.tr("Updated: %1").arg(Weather.data.lastRefresh) }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10 * Appearance.sizes.islandScale

                RowLayout {
                    spacing: 4 * Appearance.sizes.islandScale
                    MaterialSymbol { text: "thermostat"; iconSize: 14 * Appearance.sizes.islandScale; color: root.contentColors.colSubtext }
                    StyledText { text: Translation.tr("Feels like %1").arg(Weather.data.tempFeelsLike); font.pixelSize: 11 * Appearance.sizes.islandScale; color: root.contentColors.colSubtext }
                }

                StyledText { text: "·"; font.pixelSize: 11 * Appearance.sizes.islandScale; color: root.contentColors.colSubtext }

                RowLayout {
                    spacing: 4 * Appearance.sizes.islandScale
                    MaterialSymbol { text: "air"; iconSize: 14 * Appearance.sizes.islandScale; color: root.contentColors.colSubtext }
                    StyledText { text: Weather.data.wind; font.pixelSize: 11 * Appearance.sizes.islandScale; color: root.contentColors.colSubtext }
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    visible: Weather.data.humidity && Weather.data.humidity !== "--"
                    spacing: 4 * Appearance.sizes.islandScale
                    MaterialSymbol { text: "humidity_mid"; iconSize: 14 * Appearance.sizes.islandScale; color: root.contentColors.colSubtext }
                    StyledText { text: Weather.data.humidity; font.pixelSize: 11 * Appearance.sizes.islandScale; color: root.contentColors.colSubtext }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 94 * Appearance.sizes.islandScale
        topLeftRadius: 5 * Appearance.sizes.islandScale
        topRightRadius: 5 * Appearance.sizes.islandScale
        bottomLeftRadius: (Appearance?.rounding?.normal ?? 17) * Appearance.sizes.islandScale
        bottomRightRadius: (Appearance?.rounding?.normal ?? 17) * Appearance.sizes.islandScale
        color: Appearance.surfaces.raised

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10 * Appearance.sizes.islandScale
            spacing: 4 * Appearance.sizes.islandScale

            Repeater {
                model: Weather.hourlyForecast
                Item {
                    id: forecastHour
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1 * Appearance.sizes.islandScale
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 3 * Appearance.sizes.islandScale

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: DateTime.formatTimeOfDay(forecastHour.modelData.time)
                            color: root.contentColors.colSubtext
                            font.pixelSize: 11 * Appearance.sizes.islandScale
                        }

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: !forecastHour.modelData.isDay && forecastHour.modelData.code <= 1
                                ? "bedtime" : Icons.getWeatherIcon(Weather.wmoToWwo(forecastHour.modelData.code)) || "cloud"
                            iconSize: 20 * Appearance.sizes.islandScale
                            color: root.contentColors.colOnLayer0
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: forecastHour.modelData.temperature
                            color: root.contentColors.colOnLayer0
                            font.pixelSize: 13 * Appearance.sizes.islandScale
                            font.weight: Font.Medium
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 2 * Appearance.sizes.islandScale
                            MaterialSymbol { text: "water_drop"; iconSize: 10 * Appearance.sizes.islandScale; color: root.contentColors.colPrimary }
                            StyledText { text: forecastHour.modelData.rain; color: root.contentColors.colSubtext; font.pixelSize: 10 * Appearance.sizes.islandScale }
                        }
                    }
                }
            }

            StyledText {
                visible: !Weather.hourlyForecast.length
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Weather.refreshing ? Translation.tr("Loading forecast…") : Translation.tr("Hourly forecast unavailable")
                font.pixelSize: 12 * Appearance.sizes.islandScale
                color: root.contentColors.colOnSurfaceVariant
            }
        }
    }
}
