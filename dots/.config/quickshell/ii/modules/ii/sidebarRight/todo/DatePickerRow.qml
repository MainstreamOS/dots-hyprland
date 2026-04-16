import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RowLayout {
    id: root
    property date selectedDate: new Date()
    property bool monthFirst: {
        var fmt = Config.options?.time.dateWithYearFormat ?? "dd/MM/yyyy"
        return fmt.indexOf("MM") < fmt.indexOf("dd")
    }
    spacing: 4

    // Track day/month/year as integers to avoid circular bindings
    property int _day: selectedDate.getDate()
    property int _month: selectedDate.getMonth() + 1
    property int _year: selectedDate.getFullYear()
    property bool _updating: false

    function daysInMonth(month, year) {
        return new Date(year, month + 1, 0).getDate()
    }

    function _syncFromDate() {
        if (_updating) return
        _updating = true
        _day = selectedDate.getDate()
        _month = selectedDate.getMonth() + 1
        _year = selectedDate.getFullYear()
        _updating = false
    }

    function _syncToDate() {
        if (_updating) return
        _updating = true
        var maxDay = Math.min(_day, daysInMonth(_month - 1, _year))
        selectedDate = new Date(_year, _month - 1, maxDay)
        _updating = false
    }

    onSelectedDateChanged: _syncFromDate()

    // First field: month or day depending on dateWithYearFormat
    SpinBox {
        id: firstSpinBox
        from: 1
        to: root.monthFirst ? 12 : root.daysInMonth(root._month - 1, root._year)
        value: root.monthFirst ? root._month : root._day
        editable: true
        implicitWidth: 60
        implicitHeight: 32
        wrap: root.monthFirst

        onValueModified: {
            if (root.monthFirst)
                root._month = value
            else
                root._day = value
            root._syncToDate()
        }

        background: Rectangle {
            radius: Appearance.rounding.verysmall
            border.width: 1
            border.color: Appearance.m3colors.m3outline
            color: "transparent"
        }

        contentItem: TextInput {
            text: firstSpinBox.textFromValue(firstSpinBox.value, firstSpinBox.locale)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: Appearance.font.family.main
            color: Appearance.colors.colOnLayer1
            renderType: Text.NativeRendering
            readOnly: !firstSpinBox.editable
            validator: firstSpinBox.validator
            inputMethodHints: Qt.ImhDigitsOnly
            selectByMouse: true
        }

        up.indicator: Item { implicitWidth: 0; implicitHeight: 0 }
        down.indicator: Item { implicitWidth: 0; implicitHeight: 0 }
    }

    StyledText {
        text: "/"
        color: Appearance.m3colors.m3outline
        font.pixelSize: Appearance.font.pixelSize.small
    }

    // Second field: day or month depending on dateWithYearFormat
    SpinBox {
        id: secondSpinBox
        from: 1
        to: root.monthFirst ? root.daysInMonth(root._month - 1, root._year) : 12
        value: root.monthFirst ? root._day : root._month
        editable: true
        implicitWidth: 60
        implicitHeight: 32
        wrap: !root.monthFirst

        onValueModified: {
            if (root.monthFirst)
                root._day = value
            else
                root._month = value
            root._syncToDate()
        }

        background: Rectangle {
            radius: Appearance.rounding.verysmall
            border.width: 1
            border.color: Appearance.m3colors.m3outline
            color: "transparent"
        }

        contentItem: TextInput {
            text: secondSpinBox.textFromValue(secondSpinBox.value, secondSpinBox.locale)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: Appearance.font.family.main
            color: Appearance.colors.colOnLayer1
            renderType: Text.NativeRendering
            readOnly: !secondSpinBox.editable
            validator: secondSpinBox.validator
            inputMethodHints: Qt.ImhDigitsOnly
            selectByMouse: true
        }

        up.indicator: Item { implicitWidth: 0; implicitHeight: 0 }
        down.indicator: Item { implicitWidth: 0; implicitHeight: 0 }
    }

    StyledText {
        text: "/"
        color: Appearance.m3colors.m3outline
        font.pixelSize: Appearance.font.pixelSize.small
    }

    // Year (always last)
    SpinBox {
        id: yearSpinBox
        from: 2020
        to: 2099
        value: root._year
        editable: true
        implicitWidth: 72
        implicitHeight: 32

        textFromValue: function(value, locale) { return value.toString() }

        onValueModified: {
            root._year = value
            root._syncToDate()
        }

        background: Rectangle {
            radius: Appearance.rounding.verysmall
            border.width: 1
            border.color: Appearance.m3colors.m3outline
            color: "transparent"
        }

        contentItem: TextInput {
            text: yearSpinBox.textFromValue(yearSpinBox.value, yearSpinBox.locale)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: Appearance.font.family.main
            color: Appearance.colors.colOnLayer1
            renderType: Text.NativeRendering
            readOnly: !yearSpinBox.editable
            validator: yearSpinBox.validator
            inputMethodHints: Qt.ImhDigitsOnly
            selectByMouse: true
        }

        up.indicator: Item { implicitWidth: 0; implicitHeight: 0 }
        down.indicator: Item { implicitWidth: 0; implicitHeight: 0 }
    }
}
