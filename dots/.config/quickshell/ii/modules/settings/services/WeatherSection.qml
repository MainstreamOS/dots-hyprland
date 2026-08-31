import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The weather block, shown on both the Bar page and the Services page. One
 * copy, because two copies were kept in step by hand.
 *
 * Nothing here reaches for a service singleton. This page runs in its own
 * process, and touching one would have it look the machine's position up every
 * time the page is opened.
 */
ContentSection {
    id: root
    icon: "cloud"
    title: Translation.tr("Weather")

    ConfigSwitch {
        buttonIcon: "assistant_navigation"
        text: Translation.tr("Enable GPS based location")
        checked: Config.options.bar.weather.enableGPS
        onCheckedChanged: {
            Config.options.bar.weather.enableGPS = checked;
        }
    }

    MaterialTextArea {
        Layout.fillWidth: true
        enabled: !Config.options.bar.weather.enableGPS
        placeholderText: Translation.tr("City name")
        text: Config.options.bar.weather.city
        wrapMode: TextEdit.Wrap
        onTextChanged: {
            Config.options.bar.weather.city = text;
        }
    }

    ContentSubsection {
        title: Translation.tr("Temperature unit")

        ConfigSelectionArray {
            // The only writer of this key anywhere, which is what lets "auto"
            // mean the question has not been answered rather than a state
            // something else could have put here. `useUSCS` is kept in step
            // only so a rollback to a release predating this finds the answer.
            currentValue: Config.options.bar.weather.units
            onSelected: newValue => {
                Config.options.bar.weather.units = newValue;
                if (newValue !== "auto")
                    Config.options.bar.weather.useUSCS = (newValue === "uscs");
            }
            options: [
                {
                    displayName: Translation.tr("Automatic"),
                    value: "auto"
                },
                {
                    displayName: Translation.tr("Celsius"),
                    value: "metric"
                },
                {
                    displayName: Translation.tr("Fahrenheit"),
                    value: "uscs"
                },
            ]
        }
    }

    ConfigSpinBox {
        icon: "av_timer"
        text: Translation.tr("Polling interval (m)")
        value: Config.options.bar.weather.fetchInterval
        from: 5
        to: 50
        stepSize: 5
        onValueChanged: {
            Config.options.bar.weather.fetchInterval = value;
        }
    }
}
