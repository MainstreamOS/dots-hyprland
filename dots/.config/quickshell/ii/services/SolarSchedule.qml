pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

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

    // Location is the only thing in this shell that asks the network where the
    // machine is. What is taken from it is the last position whose clock agreed
    // with this one, because a sunrise only means anything against the clock it
    // is compared to. The weather deliberately reads the other position: it
    // wants the place it was told about.
    readonly property real latitude: Location.solarLatitude
    readonly property real longitude: Location.solarLongitude
    readonly property bool locationKnown: Location.solarKnown

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
}
