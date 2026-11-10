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
                        text: Weather.data.city || Weather.cityName || Translation.tr("Weather")
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
        id: forecastCard
        Layout.fillWidth: true
        implicitHeight: 94 * Appearance.sizes.islandScale
        topLeftRadius: 5 * Appearance.sizes.islandScale
        topRightRadius: 5 * Appearance.sizes.islandScale
        bottomLeftRadius: (Appearance?.rounding?.normal ?? 17) * Appearance.sizes.islandScale
        bottomRightRadius: (Appearance?.rounding?.normal ?? 17) * Appearance.sizes.islandScale
        color: Appearance.surfaces.raised
        clip: true

        // The coming hours and days take turns every eight seconds while the panel is open. A turn of
        // the wheel picks one at once and starts the count again from there.
        property int page: 0
        property real offset: page * height
        Behavior on offset {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        Timer {
            id: dwell
            running: true
            repeat: true
            interval: 8000
            onTriggered: forecastCard.page = forecastCard.page === 0 && Weather.dailyForecast.length ? 1 : 0
        }

        ControlWheel {
            onStepped: direction => {
                forecastCard.page = direction < 0 ? 1 : 0;
                dwell.restart();
            }
        }

        RowLayout {
            x: 10 * Appearance.sizes.islandScale
            y: 10 * Appearance.sizes.islandScale - forecastCard.offset
            width: forecastCard.width - 20 * Appearance.sizes.islandScale
            height: forecastCard.height - 20 * Appearance.sizes.islandScale
            spacing: 4 * Appearance.sizes.islandScale

            Repeater {
                model: Weather.hourlyForecast
                WeatherForecastColumn {
                    required property var modelData
                    contentColors: root.contentColors
                    label: DateTime.formatTimeOfDay(modelData.time)
                    icon: !modelData.isDay && modelData.code <= 1
                        ? "bedtime" : Icons.getWeatherIcon(Weather.wmoToWwo(modelData.code)) || "cloud"
                    temperature: modelData.temperature
                    rain: modelData.rain
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

        RowLayout {
            x: 10 * Appearance.sizes.islandScale
            y: 10 * Appearance.sizes.islandScale + forecastCard.height - forecastCard.offset
            width: forecastCard.width - 20 * Appearance.sizes.islandScale
            height: forecastCard.height - 20 * Appearance.sizes.islandScale
            spacing: 4 * Appearance.sizes.islandScale

            Repeater {
                model: Weather.dailyForecast
                WeatherForecastColumn {
                    required property var modelData
                    contentColors: root.contentColors
                    // Midday, so no time zone can move the date onto the day before.
                    label: new Date(modelData.date + "T12:00:00").toLocaleDateString(Qt.locale(), "ddd")
                    icon: Icons.getWeatherIcon(Weather.wmoToWwo(modelData.code)) || "cloud"
                    temperature: modelData.high
                    low: modelData.low
                    rain: modelData.rain
                }
            }

            StyledText {
                visible: !Weather.dailyForecast.length
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Weather.refreshing ? Translation.tr("Loading forecast…") : Translation.tr("Daily forecast unavailable")
                font.pixelSize: 12 * Appearance.sizes.islandScale
                color: root.contentColors.colOnSurfaceVariant
            }
        }
    }
}
