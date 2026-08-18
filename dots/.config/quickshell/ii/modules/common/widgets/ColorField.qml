import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One colour: a swatch, the hex behind it, and a way to lift one off the screen.
 *
 * Typing is the fallback rather than the point — a colour worth putting in a
 * border is usually already somewhere on the desktop, and hyprpicker returns
 * exactly what is under the cursor.
 */
RowLayout {
    id: root
    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    property string text: ""
    property string buttonIcon: ""
    property string value: "#000000"
    // Whether clearing the box is a way of saying "no color of my own" rather
    // than a typo. Off by default: somewhere like a gradient lane, an empty
    // string is not a color it can draw, and refusing it is the kinder answer.
    property bool allowEmpty: false
    property real textWidth: 170
    // The width the swatch, the field and the button share, so the row lines
    // up with the sliders around it: the swatch starts where their tracks
    // start and the button ends where their tracks end.
    property real sliderWidth: 0
    signal edited(string newValue)

    // Accepts what someone would actually type: with or without the hash, and
    // the three-digit form.
    function normalise(raw) {
        let v = String(raw).trim().replace(/^#/, "").toLowerCase()
        if (/^[0-9a-f]{3}$/.test(v))
            v = v[0] + v[0] + v[1] + v[1] + v[2] + v[2]
        return /^[0-9a-f]{6}$/.test(v) ? "#" + v : ""
    }

    OptionalMaterialSymbol {
        icon: root.buttonIcon
        iconSize: Appearance.font.pixelSize.larger
    }

    StyledText {
        Layout.preferredWidth: root.textWidth
        text: root.text
        elide: Text.ElideRight
        color: Appearance.colors.colOnSecondaryContainer
    }

    RowLayout {
        spacing: 10
        Layout.fillWidth: root.sliderWidth <= 0
        Layout.preferredWidth: root.sliderWidth > 0 ? root.sliderWidth : -1

        // The button is the tallest thing in the row and the one with a hard
        // edge, so the swatch and the field take their height from it and the
        // three read as one control rather than three stacked differently.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: pickButton.height
            Layout.alignment: Qt.AlignVCenter
            radius: Appearance.rounding.small
            color: root.value
            border.width: 1
            border.color: Appearance.m3colors.m3outline
        }

        // Sized to the seven characters a color is, plus the field's own
        // padding and room for the cursor; whatever it gives up, the swatch
        // beside it takes.
        TextMetrics {
            id: hexMetrics
            font: field.font
            text: "#000000"
        }

        MaterialTextField {
            id: field
            // The style's stock padding is meant for sentences; a seven
            // character code needs just enough for itself and the cursor. The
            // insets hold room for a floating label there is none of, and
            // dropping them lets the drawn box fill the control it is given.
            leftPadding: 8
            rightPadding: 8
            topInset: 0
            bottomInset: 0
            Layout.preferredHeight: pickButton.height
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Math.ceil(hexMetrics.advanceWidth) + leftPadding + rightPadding + 2
            text: root.value
            onEditingFinished: {
                const v = root.normalise(text)
                // An emptied box is the only way of taking a color back off
                // where one is allowed to be absent; without it the field can
                // be given a value but never returned to not having one.
                if (v.length === 0 && root.allowEmpty && String(text).trim().length === 0) {
                    if (root.value !== "")
                        root.edited("")
                } else if (v.length > 0 && v !== root.value)
                    root.edited(v)
                // Re-arm the binding rather than assigning text: a plain
                // assignment would sever `text: root.value` for good, so after
                // one edit the box would stop following the picker or an
                // outside change. Qt.binding keeps it tracking — and snaps an
                // unusable entry back to the real value in the same stroke.
                text = Qt.binding(() => root.value)
            }
        }

        RippleButtonWithIcon {
            id: pickButton
            materialIcon: "colorize"
            mainText: Translation.tr("Pick")
            onClicked: pickerProc.running = true
            StyledToolTip { text: Translation.tr("Pick a color from anywhere on screen") }
        }
    }

    Process {
        id: pickerProc
        property string buf: ""
        // Reads what was under the cursor and exits; cancelling prints nothing,
        // which normalise() rejects and the value is left alone. No -a: that
        // copies to the clipboard as a side effect and wants wl-clipboard.
        command: ["hyprpicker", "-f", "hex", "-l"]
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => pickerProc.buf += data }
        onExited: {
            const v = root.normalise(pickerProc.buf)
            if (v.length > 0 && v !== root.value) root.edited(v)
        }
    }
}
