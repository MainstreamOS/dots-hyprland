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

        // Stretched to whatever the field and the button leave, and matched to
        // the field's drawn outline rather than its control height — the
        // Material style holds inset space around the visible box, so the
        // control is taller than what the eye compares against.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: field.background ? field.background.height : field.height
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
            // dropping them lets the box fill the control, which is what the
            // swatch's height is matched against.
            leftPadding: 8
            rightPadding: 8
            topInset: 0
            bottomInset: 0
            Layout.preferredWidth: Math.ceil(hexMetrics.advanceWidth) + leftPadding + rightPadding + 2
            text: root.value
            onEditingFinished: {
                const v = root.normalise(text)
                if (v.length > 0 && v !== root.value)
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
