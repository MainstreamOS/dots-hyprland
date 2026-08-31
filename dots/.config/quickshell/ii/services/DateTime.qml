pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    id: root

    property var clock: SystemClock {
        id: clock
        precision: {
            if (Config.options.time.secondPrecision || GlobalStates.screenLocked)
                return SystemClock.Seconds;
            return SystemClock.Minutes;
        }
    }
    property string time: Qt.locale().toString(clock.date, Config.options?.time.format ?? "hh:mm")
    property string shortDate: Qt.locale().toString(clock.date, Config.options?.time.shortDateFormat ?? "dd/MM")
    property string date: Qt.locale().toString(clock.date, Config.options?.time.dateWithYearFormat ?? "dd/MM/yyyy")
    property string longDate: Qt.locale().toString(clock.date, Config.options?.time.dateFormat ?? "dddd, dd/MM")
    property string collapsedCalendarFormat: Qt.locale().toString(clock.date, "dddd, MMMM dd")
    property string uptime: "0h, 0m"

    // Every clock reading in the shell follows the one format the bar clock
    // uses, so a system set to 24-hour is never asked about AM or PM on a
    // schedule. Qt spells the meridiem "AP" or "ap", and no other token in a
    // time format carries an "a", which is what makes the test hold up
    // against a hand-written format string.
    readonly property string clockFormat: Config.options?.time.format ?? "hh:mm"
    readonly property bool use12HourClock: /a/i.test(root.clockFormat)
    readonly property string amText: /A/.test(root.clockFormat) ? "AM" : "am"
    readonly property string pmText: /A/.test(root.clockFormat) ? "PM" : "pm"

    // Schedules persist as "HH:mm" 24-hour whatever the clock shows, because
    // the services acting on them (Hyprsunset, the day and night theme
    // scheduler) read the number pair straight out of the string.
    function parseTimeOfDay(timeStr) {
        const parts = String(timeStr ?? "").split(":");
        const hour = parseInt(parts[0], 10);
        const minute = parseInt(parts[1], 10);
        if (isNaN(hour) || isNaN(minute) || hour < 0 || hour > 23 || minute < 0 || minute > 59)
            return null;
        return {
            hour: hour,
            minute: minute
        };
    }

    function timeOfDayString(hour, minute) {
        return String(hour).padStart(2, "0") + ":" + String(minute).padStart(2, "0");
    }

    function formatTimeOfDay(timeStr) {
        const time = root.parseTimeOfDay(timeStr);
        if (!time)
            return "—";
        if (!root.use12HourClock)
            return root.timeOfDayString(time.hour, time.minute);
        return ((time.hour % 12) || 12) + ":" + String(time.minute).padStart(2, "0") + " " + (time.hour < 12 ? root.amText : root.pmText);
    }

    Timer {
        interval: 10
        running: true
        repeat: true
        onTriggered: {
            fileUptime.reload();
            const textUptime = fileUptime.text();
            const uptimeSeconds = Number(textUptime.split(" ")[0] ?? 0);

            // Convert seconds to days, hours, and minutes
            const days = Math.floor(uptimeSeconds / 86400);
            const hours = Math.floor((uptimeSeconds % 86400) / 3600);
            const minutes = Math.floor((uptimeSeconds % 3600) / 60);

            // Build the formatted uptime string
            let formatted = "";
            if (days > 0)
                formatted += `${days}d`;
            if (hours > 0)
                formatted += `${formatted ? ", " : ""}${hours}h`;
            if (minutes > 0 || !formatted)
                formatted += `${formatted ? ", " : ""}${minutes}m`;
            uptime = formatted;
            interval = Config.options?.resources?.updateInterval ?? 3000;
        }
    }

    FileView {
        id: fileUptime

        path: "/proc/uptime"
    }
}
