import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A time of day for a schedule, shown and edited on whichever clock the bar
 * is set to. The value itself is always "HH:mm" on a 24-hour clock.
 */
RowLayout {
    id: root

    property string value: "00:00"
    // "" lets the field cover the whole day. "AM" or "PM" pins it to one half,
    // for a field that can only ever mean one of them, and the pinned half
    // stands in for the meridiem control.
    property string meridiem: ""
    signal edited(string value)

    readonly property var parsed: DateTime.parseTimeOfDay(root.value) ?? ({
            hour: 0,
            minute: 0
        })
    readonly property bool afternoon: root.meridiem === "" ? root.parsed.hour >= 12 : root.meridiem === "PM"

    // The hour range answers to the pin alone, never to the clock format. Were
    // it to move under a live spin box, the box would clamp its own value into
    // the new bounds and report that as an edit, writing the clamped hour over
    // the schedule the moment anyone switched formats.
    readonly property int hourFrom: root.meridiem === "PM" ? 12 : 0
    readonly property int hourTo: root.meridiem === "AM" ? 11 : 23
    // An hour stored outside a pinned half keeps its reading on the way in, so
    // 8 lands on the night side as 20 rather than being dragged to the bound.
    readonly property int displayHour: root.meridiem === "" ? root.parsed.hour : (root.parsed.hour % 12) + root.hourFrom

    function commit(hour, minute) {
        const next = DateTime.timeOfDayString(hour, minute);
        if (next !== root.value)
            root.edited(next);
    }

    spacing: 8

    ConfigSpinBox {
        Layout.preferredWidth: 70
        from: root.hourFrom
        to: root.hourTo
        value: root.displayHour
        // Re-made on a format change rather than reading the format inside the
        // body, because the text is bound to this property and would otherwise
        // go on calling the function it was first handed.
        textFromValue: DateTime.use12HourClock ? (hour => String((hour % 12) || 12)) : (hour => String(hour))
        valueFromText: text => {
            const reading = parseFloat(text);
            if (isNaN(reading) || !DateTime.use12HourClock)
                return reading;
            return (reading % 12) + (root.afternoon ? 12 : 0);
        }
        onValueChanged: root.commit(value, root.parsed.minute)
    }

    StyledText {
        Layout.alignment: Qt.AlignVCenter
        text: ":"
        color: Appearance.colors.colOnLayer1
    }

    ConfigSpinBox {
        Layout.preferredWidth: 70
        from: 0
        to: 59
        value: root.parsed.minute
        onValueChanged: root.commit(root.displayHour, value)
    }

    StyledComboBox {
        Layout.preferredWidth: 80
        Layout.fillWidth: false
        visible: DateTime.use12HourClock && root.meridiem === ""
        model: [DateTime.amText, DateTime.pmText]
        currentIndex: root.afternoon ? 1 : 0
        onActivated: index => root.commit((root.parsed.hour % 12) + (index === 1 ? 12 : 0), root.parsed.minute)
    }

    StyledText {
        Layout.alignment: Qt.AlignVCenter
        visible: DateTime.use12HourClock && root.meridiem !== ""
        text: root.meridiem === "PM" ? DateTime.pmText : DateTime.amText
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.normal
    }
}
