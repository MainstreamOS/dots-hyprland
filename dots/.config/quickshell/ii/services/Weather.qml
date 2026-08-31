pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

import qs.modules.common

Singleton {
    id: root

    property int fetchInterval: Config.options.bar.weather.fetchInterval * 60 * 1000

    // Rescheduled without re-firing. The timer starts on its own, so restarting
    // it here would put a request behind every step of the interval spin box.
    onFetchIntervalChanged: refreshTimer.interval = root.fetchInterval

    readonly property bool gps: Config.options.bar.weather.enableGPS
    readonly property string pinnedCity: Config.options.bar.weather.city.trim()

    // A typed city is what this follows when the lookup is switched off. Off
    // with nothing typed has named no place at all, so the looked up one still
    // stands rather than leaving the weather with nowhere to be.
    readonly property bool usePinned: !root.gps && root.pinnedCity.length > 0

    property real pinnedLat: 0
    property real pinnedLon: 0
    property string pinnedName: ""
    property string pinnedCountry: ""
    property bool pinnedValid: false

    readonly property bool locationValid: root.usePinned ? root.pinnedValid : Location.known
    readonly property real latitude: root.usePinned ? root.pinnedLat : Location.latitude
    readonly property real longitude: root.usePinned ? root.pinnedLon : Location.longitude
    readonly property string cityName: root.usePinned ? root.pinnedName : Location.city
    readonly property string countryCode: root.usePinned ? root.pinnedCountry : Location.countryCode

    // The reply that produced what is on screen, kept so that a change of unit
    // is a re-read of what is already here. Asking again would put a round trip
    // behind every change of mind and would leave the choice dead with no
    // network.
    property var lastReply: null

    // Resolved on every read rather than written into the settings file, so a
    // location landing after login writes nothing. "auto" is the shipped value
    // and means no unit has been named; naming one puts it in the file and this
    // last branch is never reached again.
    readonly property bool useUSCS: Config.options.bar.weather.units === "uscs" ? true : Config.options.bar.weather.units === "metric" ? false : Location.usesFahrenheit(root.countryCode)

    // One key for the whole position, so a coordinate pair arriving as two
    // assignments asks for one fetch rather than two.
    readonly property string fetchKey: root.locationValid ? `${root.latitude},${root.longitude}` : ""
    onFetchKeyChanged: if (root.fetchKey.length > 0)
        weatherFetcher.fetch()

    // Nothing known yet says so. A zero reads as a reading, and a bar reporting
    // 0 degrees for a machine that has never reached the network is worse than
    // one reporting nothing at all.
    property var data: ({
        uv: "--",
        humidity: "--",
        sunrise: "--:--",
        sunset: "--:--",
        windDir: "",
        wCode: "113",
        city: "",
        wind: "--",
        precip: "--",
        visib: "--",
        press: "--",
        temp: "--°",
        tempFeelsLike: "--°",
        lastRefresh: "Never",
    })

    function wmoToWwo(wmoCode) {
        const mapping = {
            0: "113", // Clear
            1: "116", // Partly Cloudy
            2: "119", // Cloudy
            3: "122", // Overcast
            45: "143", // Fog
            48: "248", // Fog
            51: "266", // Drizzle
            53: "266",
            55: "266",
            56: "281", // Freezing Drizzle
            57: "284",
            61: "296", // Rain
            63: "302",
            65: "308",
            66: "311", // Freezing Rain
            67: "314",
            71: "326", // Snow
            73: "332",
            75: "338",
            77: "335", // Snow Grains
            80: "353", // Showers
            81: "356",
            82: "359",
            85: "368", // Snow Showers
            86: "371",
            95: "386", // Thunderstorm
            96: "389",
            99: "392"
        };
        return mapping[wmoCode] || "113";
    }

    // `isRerender` is a change of unit rather than a new reading, and the
    // time shown is the time the reading was taken.
    function refineData(weatherJson, isRerender) {
        if (!weatherJson || !weatherJson.current) return;

        let temp = {};
        const current = weatherJson.current;
        const daily = weatherJson.daily;

        temp.uv = current.uv_index || 0;
        temp.humidity = (current.relative_humidity_2m || 0) + "%";
        
        // Extract time from ISO8601 string (e.g., "2024-05-23T05:56")
        const formatTime = (isoStr) => isoStr ? isoStr.split("T")[1] : "0:00";
        temp.sunrise = formatTime(daily.sunrise[0]);
        temp.sunset = formatTime(daily.sunset[0]);
        
        // Wind direction simplified
        const degToDir = (deg) => {
            const dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
            return dirs[Math.round(deg / 45) % 8];
        };
        temp.windDir = degToDir(current.wind_direction_10m || 0);
        
        temp.wCode = root.wmoToWwo(current.weather_code);
        temp.city = root.cityName;

        // Converted here rather than asked for in the URL. The API's
        // precipitation_unit=inch also restates visibility in feet, which the
        // division below reads as meters, and there is no unit parameter for
        // pressure at all. One metric reply serves both units.
        if (root.useUSCS) {
            temp.wind = Math.round(current.wind_speed_10m * 0.621371) + " mph";
            temp.precip = (current.precipitation / 25.4).toFixed(2) + " in";
            temp.visib = Math.round(current.visibility / 1609.34) + " mi";
            // Inches of mercury rather than psi, whose whole real world range
            // is three whole numbers and so carries no information.
            temp.press = (current.pressure_msl * 0.02953).toFixed(2) + " inHg";
            temp.temp = Math.round(current.temperature_2m * 9/5 + 32) + "°F";
            temp.tempFeelsLike = Math.round(current.apparent_temperature * 9/5 + 32) + "°F";
        } else {
            temp.wind = Math.round(current.wind_speed_10m) + " km/h";
            temp.precip = current.precipitation + " mm";
            temp.visib = Math.round(current.visibility / 1000) + " km";
            temp.press = Math.round(current.pressure_msl) + " hPa";
            temp.temp = Math.round(current.temperature_2m) + "°C";
            temp.tempFeelsLike = Math.round(current.apparent_temperature) + "°C";
        }
        
        temp.lastRefresh = isRerender ? root.data.lastRefresh : (DateTime.time + " • " + DateTime.date);
        root.data = temp;
    }

    // A refresh with nothing to fetch against asks for the thing that is
    // missing. A typed name goes through the same wait typing does, so a start
    // and a keystroke cannot both ask for it.
    function getData() {
        if (root.usePinned) {
            if (root.pinnedValid)
                weatherFetcher.fetch();
            else
                pinnedDebounce.restart();
            return;
        }
        if (root.locationValid)
            weatherFetcher.fetch();
        else
            Location.refresh();
    }

    // The name is a URL query value and reaches curl as an argument, so one
    // carrying a space or an ampersand stays one name. The reply carries the
    // country too, which is what lets a typed city decide its own unit with no
    // second request. Keyed on country_code and never on country, which is
    // absent entirely for some territories.
    Process {
        id: geocoder
        running: false
        property string pending: ""
        function fetch(name) {
            // Assigning `running` on a process already running does nothing, so
            // a query issued while one is in flight would be swallowed.
            geocoder.pending = name;
            if (geocoder.running)
                return;
            geocoder.command = ["curl", "-s", "--max-time", "10", `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(name)}&count=1`];
            geocoder.running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const asked = geocoder.pending;
                if (text.length === 0)
                    return;
                try {
                    // A name matching nothing comes back with no results key at
                    // all. The pin is cleared rather than left pointing at the
                    // last place that did match, which would quietly report the
                    // weather somewhere the user has stopped naming.
                    const found = JSON.parse(text)?.results?.[0];
                    if (!found) {
                        root.pinnedValid = false;
                        return;
                    }
                    root.pinnedLat = found.latitude;
                    root.pinnedLon = found.longitude;
                    root.pinnedName = found.name ?? asked;
                    root.pinnedCountry = found.country_code ?? "";
                    root.pinnedValid = true;
                } catch (e) {
                    console.log("[Weather] city lookup failed: " + e);
                }
            }
        }
    }

    // The settings field writes a key at a time, so a name is not looked up
    // until it has stopped changing. That is what keeps a half typed name from
    // being fetched as a place.
    Timer {
        id: pinnedDebounce
        interval: 700
        repeat: false
        onTriggered: if (root.usePinned)
            geocoder.fetch(root.pinnedCity)
    }
    onPinnedCityChanged: {
        root.pinnedValid = false;
        if (root.usePinned)
            pinnedDebounce.restart();
        else
            pinnedDebounce.stop();
    }
    onUsePinnedChanged: if (root.usePinned && !root.pinnedValid)
        pinnedDebounce.restart()

    Process {
        id: weatherFetcher
        // Capped, because assigning `running` on a process already running
        // does nothing, so one request left hanging would swallow every one
        // behind it until the shell restarts.
        function fetch() {
            const url = `https://api.open-meteo.com/v1/forecast?latitude=${root.latitude}&longitude=${root.longitude}&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,pressure_msl,surface_pressure,wind_speed_10m,wind_direction_10m,uv_index,visibility&daily=sunrise,sunset&timezone=auto&forecast_days=1`;
            command = ["curl", "-s", "--max-time", "15", url];
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                try {
                    const weather = JSON.parse(text);
                    root.lastReply = weather;
                    root.refineData(weather, false);
                } catch (e) {
                    console.error(`[WeatherService] Weather Error: ${e.message}`);
                }
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: root.fetchInterval
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.getData()
    }

    // Both units are already in the reply that produced what is on screen, so
    // a change of mind is a re-read. Before the first reply there is nothing to
    // re-read.
    onUseUSCSChanged: if (root.lastReply)
        root.refineData(root.lastReply, true)

    Component.onCompleted: {
        console.info("[WeatherService] Initialized with ip-api and Open-Meteo.");
    }
}
