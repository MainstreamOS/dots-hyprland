pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ColumnLayout {
    id: root
    spacing: 2
    readonly property color elevatedSurface: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer0, 0.92)

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 106
        topLeftRadius: Appearance?.rounding?.normal ?? 17
        topRightRadius: Appearance?.rounding?.normal ?? 17
        bottomLeftRadius: 5
        bottomRightRadius: 5
        color: root.elevatedSurface

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Weather.cityName || Translation.tr("Weather")
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        spacing: 8

                        StyledText {
                            text: Weather.data.temp
                            color: Appearance.colors.colOnLayer0
                            font.pixelSize: 32
                            font.weight: Font.Medium
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Weather.condition
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: !Weather.lastReply ? "cloud" : Weather.lastReply.current?.is_day === 0 && Weather.lastReply.current?.weather_code <= 1
                        ? "bedtime" : Icons.getWeatherIcon(Weather.data.wCode) || "cloud"
                    color: Appearance.colors.colOnLayer0
                    iconSize: 44
                }

                IslandButton {
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 28
                    implicitWidth: 28
                    symbol: "refresh"
                    enabled: !Weather.refreshing
                    Accessible.name: Translation.tr("Refresh weather")
                    onClicked: Weather.getData()
                    StyledToolTip { text: Weather.refreshing ? Translation.tr("Updating weather…") : Translation.tr("Updated: %1").arg(Weather.data.lastRefresh) }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                RowLayout {
                    spacing: 4
                    MaterialSymbol { text: "thermostat"; iconSize: 14; color: Appearance.colors.colSubtext }
                    StyledText { text: Translation.tr("Feels like %1").arg(Weather.data.tempFeelsLike); font.pixelSize: 11; color: Appearance.colors.colSubtext }
                }

                StyledText { text: "·"; font.pixelSize: 11; color: Appearance.colors.colSubtext }

                RowLayout {
                    spacing: 4
                    MaterialSymbol { text: "air"; iconSize: 14; color: Appearance.colors.colSubtext }
                    StyledText { text: Weather.data.wind; font.pixelSize: 11; color: Appearance.colors.colSubtext }
                }

                Item { Layout.fillWidth: true }

                RowLayout {
                    visible: Weather.data.humidity && Weather.data.humidity !== "--"
                    spacing: 4
                    MaterialSymbol { text: "humidity_mid"; iconSize: 14; color: Appearance.colors.colSubtext }
                    StyledText { text: Weather.data.humidity; font.pixelSize: 11; color: Appearance.colors.colSubtext }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 94
        topLeftRadius: 5
        topRightRadius: 5
        bottomLeftRadius: Appearance?.rounding?.normal ?? 17
        bottomRightRadius: Appearance?.rounding?.normal ?? 17
        color: root.elevatedSurface

        RowLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            Repeater {
                model: Weather.hourlyForecast
                Item {
                    id: forecastHour
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 3

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: DateTime.formatTimeOfDay(forecastHour.modelData.time)
                            color: Appearance.colors.colSubtext
                            font.pixelSize: 11
                        }

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: !forecastHour.modelData.isDay && forecastHour.modelData.code <= 1
                                ? "bedtime" : Icons.getWeatherIcon(Weather.wmoToWwo(forecastHour.modelData.code)) || "cloud"
                            iconSize: 20
                            color: Appearance.colors.colOnLayer0
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: forecastHour.modelData.temperature
                            color: Appearance.colors.colOnLayer0
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 2
                            MaterialSymbol { text: "water_drop"; iconSize: 10; color: Appearance.colors.colPrimary }
                            StyledText { text: forecastHour.modelData.rain; color: Appearance.colors.colSubtext; font.pixelSize: 10 }
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
                font.pixelSize: 12
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }
}
