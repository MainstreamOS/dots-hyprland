pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Sunrise and sunset for wherever this machine is.
 *
 * Only the coordinates come off the network; the times themselves are worked
 * out here. That is what keeps the three properties the night light schedule
 * depends on. The answer comes out on the machine's own clock, which is the
 * clock the schedule is compared against, so a located position in another
 * timezone cannot shift the window. It survives a boot with no network once a
 * location has been stored. And a sun that never rises or never sets is
 * reported as itself rather than as a midnight to midnight window, which a
 * from and to pair reads as on for every minute of the day.
 */
Singleton {
    id: root

    // Resolved in the main shell alone. The settings app reads the same file
    // and looks nothing up, so opening a page cannot start a second lookup and
    // the two processes always describe the same window.
    property bool lookupEnabled: false
    function load() {
        root.lookupEnabled = true;
    }

    property real latitude: 0
    property real longitude: 0
    property string locationLabel: ""
    property bool locationKnown: false

    // Trimmed, because the standard paths come back as file:// URLs and this
    // one is handed to a shell as well as to a FileView.
    readonly property string cachePath: FileUtils.trimFileProtocol(`${Directories.state}/solar-location.json`)

    // Re-derived every minute, which costs a few dozen floating point
    // operations and settles every staleness question at once: the date
    // rolling over, a resume from suspend and a daylight saving jump all
    // correct themselves on the next tick with no network and no timer.
    readonly property var events: root.locationKnown ? root.solarEvents(root.latitude, root.longitude, DateTime.clock.date) : null

    // "unknown" until a location is known, then "ready", "polarDay" or
    // "polarNight".
    readonly property string state: root.events ? root.events.state : "unknown"
    readonly property bool valid: root.state === "ready"
    readonly property string sunrise: root.valid ? root.events.sunrise : ""
    readonly property string sunset: root.valid ? root.events.sunset : ""

    // The NOAA sunrise equation. `date` is only read for its calendar day; the
    // result is expressed in whatever timezone this machine is set to, because
    // it is built back up through a Date rather than carried as an offset.
    function solarEvents(lat, lon, date) {
        const rad = Math.PI / 180;
        const julian = ms => ms / 86400000 + 2440587.5;
        const midnight = new Date(date.getFullYear(), date.getMonth(), date.getDate());
        const day = Math.round(julian(midnight.getTime()) - 2451545.0 + 0.0008);

        const meanSolarNoon = day - lon / 360;
        const anomaly = (357.5291 + 0.98560028 * meanSolarNoon) % 360;
        const center = 1.9148 * Math.sin(anomaly * rad) + 0.02 * Math.sin(2 * anomaly * rad) + 0.0003 * Math.sin(3 * anomaly * rad);
        const eclipticLongitude = (anomaly + center + 282.9372) % 360;
        const transit = 2451545.0 + meanSolarNoon + 0.0053 * Math.sin(anomaly * rad) - 0.0069 * Math.sin(2 * eclipticLongitude * rad);
        const declination = Math.asin(Math.sin(eclipticLongitude * rad) * Math.sin(23.4397 * rad));

        // The standard altitude of -0.833 degrees puts the crossing at the
        // moment the disc's upper limb clears the horizon, refraction included.
        const hourAngle = (Math.sin(-0.833 * rad) - Math.sin(lat * rad) * Math.sin(declination)) / (Math.cos(lat * rad) * Math.cos(declination));
        if (hourAngle > 1)
            return {
                state: "polarNight"
            };
        if (hourAngle < -1)
            return {
                state: "polarDay"
            };

        const half = Math.acos(hourAngle) / rad / 360;
        const clockTime = jd => {
            const at = new Date((jd - 2440587.5) * 86400000);
            return String(at.getHours()).padStart(2, "0") + ":" + String(at.getMinutes()).padStart(2, "0");
        };
        return {
            state: "ready",
            sunrise: clockTime(transit - half),
            sunset: clockTime(transit + half)
        };
    }

    // The directory has to be made in the same breath as the write, because a
    // detached mkdir has not finished by the time a separate write runs, and a
    // location that never reaches disk is looked up again on every boot, which
    // is the one thing a machine with no network cannot do. The path and the
    // payload arrive as arguments rather than inside the script, so a place
    // name carrying a quote stays data.
    function store(lat, lon, label) {
        const payload = JSON.stringify({
            lat: lat,
            lon: lon,
            label: label
        });
        Quickshell.execDetached(["bash", "-c", 'mkdir -p "$(dirname "$0")" && printf "%s" "$1" > "$0"', root.cachePath, payload]);
    }

    function applyLocation(lat, lon, label) {
        root.latitude = lat;
        root.longitude = lon;
        root.locationLabel = label;
        root.locationKnown = true;
    }

    FileView {
        id: cache
        path: root.cachePath
        printErrors: false
        onLoaded: {
            try {
                const stored = JSON.parse(cache.text());
                if (typeof stored.lat === "number" && typeof stored.lon === "number")
                    root.applyLocation(stored.lat, stored.lon, stored.label ?? "");
            } catch (e) {
                // A truncated or hand-edited file just means no location yet;
                // the lookup below replaces it.
            }
        }
    }

    // ip-api is asked for the offset as well as the position, because a
    // position whose clock disagrees with this machine's is the shape a VPN
    // exit node has, and its sunrise would be wrong by that whole difference.
    // An hour of slack keeps a daylight saving changeover from being read as
    // one. `fields` is explicit so the offset is actually in the reply.
    Process {
        id: locator
        running: false
        command: ["curl", "-s", "--max-time", "10", "http://ip-api.com/json/?fields=status,lat,lon,city,offset"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0)
                    return;
                try {
                    const found = JSON.parse(text);
                    if (found.status !== "success")
                        return;
                    const localOffset = -new Date().getTimezoneOffset() * 60;
                    if (typeof found.offset === "number" && Math.abs(found.offset - localOffset) > 3600)
                        return;
                    root.applyLocation(found.lat, found.lon, found.city ?? "");
                    root.store(found.lat, found.lon, found.city ?? "");
                } catch (e) {
                    console.log("[SolarSchedule] location lookup failed: " + e);
                }
            }
        }
    }

    // One lookup per session once the shell asks for it. A stored location is
    // still refreshed, since a machine that moved would otherwise keep the old
    // sun forever, but the stored one stays in force until the reply lands.
    onLookupEnabledChanged: if (root.lookupEnabled)
        locator.running = true
}
