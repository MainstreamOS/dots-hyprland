import QtQuick
import QtQuick.Controls
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
 * exactly what is under the cursor. For a color that isn't on screen yet, the
 * swatch itself opens a picker, and every drag lands live so the thing being
 * colored is its own preview. The preview is an audition, not a decision:
 * Accept keeps it, and closing any other way hands back the color the picker
 * opened with.
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
    // What the swatch shows when the value is absent: a caller whose color
    // can legitimately not exist hands over the stand-in it would use instead
    // (a palette pick). A stand-in keeps moving with the palette while an
    // owned color freezes, and the box dims its hex so the two never read
    // alike — derived from the value itself, so they cannot disagree.
    property string fallback: ""
    readonly property bool ownValue: root.value !== "" || root.fallback === ""
    property real textWidth: 160
    // The width the swatch, the field and the button share, so the row lines
    // up with the sliders around it: the swatch starts where their tracks
    // start and the button ends where their tracks end.
    property real sliderWidth: 0
    signal edited(string newValue)

    onValueChanged: {
        if (picker.visible && !picker.decided && root.value !== picker.lastEmitted) {
            picker.decided = true
            picker.close()
        }
    }

    // Accepts what someone would actually type: with or without the hash, and
    // the three-digit form. Also the eight-digit one, which nobody types but
    // which is what Qt hands back for a color carrying alpha — the leading pair
    // is that alpha, and a swatch that kept it would draw a color nobody chose.
    function normalise(raw) {
        let v = String(raw).trim().replace(/^#/, "").toLowerCase()
        if (/^[0-9a-f]{3}$/.test(v))
            v = v[0] + v[0] + v[1] + v[1] + v[2] + v[2]
        else if (/^[0-9a-f]{8}$/.test(v))
            v = v.slice(2)
        return /^[0-9a-f]{6}$/.test(v) ? "#" + v : ""
    }

    // What the swatch paints and the box shows. A caller handing over a color
    // rather than a typed string has no reason to strip the alpha itself, and
    // an unreadable value here is worse than a wrong one — it cannot be edited
    // back into shape.
    readonly property string displayValue: root.normalise(root.value) || root.value || root.normalise(root.fallback) || root.fallback

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
            id: swatch
            // StyledToolTip reads this off its parent; a bare Rectangle has
            // nothing for it and the tip would never leave the screen.
            property bool hovered: swatchArea.containsMouse
            Layout.fillWidth: true
            Layout.preferredHeight: pickButton.height
            Layout.alignment: Qt.AlignVCenter
            radius: Appearance.rounding.small
            color: root.displayValue
            border.width: 1
            border.color: Appearance.m3colors.m3outline

            MouseArea {
                id: swatchArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: picker.openAtCurrent()
            }
            StyledToolTip {
                extraVisibleCondition: !picker.visible
                text: Translation.tr("Choose a color")
            }

            Popup {
                id: picker

                // Hue lives apart from the color it makes: at the box's white,
                // black and grey edges the color no longer says which hue it
                // came from, and re-deriving it there would slam the box to
                // red mid-drag. Synced from the value when opening, then only
                // the drags move it.
                property real hue: 0
                property real sat: 1
                property real bright: 1

                // The drags commit live so the preview is real, which means
                // dismissing has to be able to take them all back: the value
                // at open is the state a walked-away audition returns to, and
                // only Accept or Reset makes the change a decision.
                property string valueAtOpen: ""
                property bool decided: false
                // What the picker itself last sent out the door. If the value
                // under the popup becomes anything else, the change came from
                // outside — a mode flip rebinding the slot, a theme apply, the
                // section reset — and the picker's remembered world is stale:
                // it closes keeping nothing, because both the audition and the
                // revert would land somewhere they were never made.
                property string lastEmitted: "\u0001"

                function openAtCurrent() {
                    const c = Qt.color(/^#[0-9a-fA-F]{6}$/.test(root.displayValue)
                        ? root.displayValue : "#808080")
                    if (c.hsvHue >= 0)
                        hue = c.hsvHue
                    sat = c.hsvSaturation
                    bright = c.hsvValue
                    valueAtOpen = root.value
                    lastEmitted = "\u0001"
                    decided = false
                    open()
                }

                onClosed: {
                    if (!decided && root.value !== valueAtOpen)
                        root.edited(valueAtOpen)
                }
                // Every drag goes out the same door a typed hex does, so the
                // swatch, the box and whatever is being colored all follow the
                // handle live.
                function commit() {
                    const v = root.normalise(Qt.hsva(hue, sat, bright, 1).toString())
                    lastEmitted = v
                    root.edited(v)
                }

                y: parent.height + 4
                margins: 8
                padding: 10
                enter: Transition { PropertyAnimation { properties: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                exit:  Transition { PropertyAnimation { properties: "opacity"; to: 0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

                background: Item {
                    StyledRectangularShadow { target: pickerBg }
                    Rectangle { id: pickerBg; anchors.fill: parent; radius: Appearance.rounding.normal; color: Appearance.m3colors.m3surfaceContainerHigh }
                }

                contentItem: ColumnLayout {
                    spacing: 10

                    Item {
                        id: svBox
                        implicitWidth: 240
                        implicitHeight: 160

                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.small
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "#ffffff" }
                                GradientStop { position: 1; color: Qt.hsva(picker.hue, 1, 1, 1) }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.small
                            gradient: Gradient {
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 1; color: "#000000" }
                            }
                        }

                        // A dark halo under a white ring: one of the two reads
                        // against whichever corner of the box the handle is in.
                        Rectangle {
                            x: picker.sat * svBox.width - width / 2
                            y: (1 - picker.bright) * svBox.height - height / 2
                            width: 16
                            height: 16
                            radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: "#66000000"
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: width / 2
                                color: "transparent"
                                border.width: 2
                                border.color: "#ffffff"
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            function put(mouse) {
                                picker.sat = Math.max(0, Math.min(1, mouse.x / width))
                                picker.bright = 1 - Math.max(0, Math.min(1, mouse.y / height))
                                picker.commit()
                            }
                            onPressed: mouse => put(mouse)
                            onPositionChanged: mouse => put(mouse)
                        }
                    }

                    Item {
                        id: hueBar
                        implicitWidth: 240
                        implicitHeight: 16

                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.small
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0 / 6; color: "#ff0000" }
                                GradientStop { position: 1 / 6; color: "#ffff00" }
                                GradientStop { position: 2 / 6; color: "#00ff00" }
                                GradientStop { position: 3 / 6; color: "#00ffff" }
                                GradientStop { position: 4 / 6; color: "#0000ff" }
                                GradientStop { position: 5 / 6; color: "#ff00ff" }
                                GradientStop { position: 6 / 6; color: "#ff0000" }
                            }
                        }

                        Rectangle {
                            x: picker.hue * hueBar.width - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            width: 8
                            height: hueBar.height + 4
                            radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: "#66000000"
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: width / 2
                                color: "transparent"
                                border.width: 2
                                border.color: "#ffffff"
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            function put(mouse) {
                                picker.hue = Math.max(0, Math.min(1, mouse.x / width))
                                picker.commit()
                            }
                            onPressed: mouse => put(mouse)
                            onPositionChanged: mouse => put(mouse)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // Only where an absent color means something: a field
                        // that refuses empty has nothing for this to say.
                        RippleButtonWithIcon {
                            visible: root.allowEmpty
                            materialIcon: "format_color_reset"
                            mainText: Translation.tr("Reset")
                            onClicked: {
                                picker.decided = true
                                picker.lastEmitted = ""
                                if (root.value !== "")
                                    root.edited("")
                                picker.close()
                            }
                            StyledToolTip { text: Translation.tr("Hand this color back to the palette") }
                        }

                        Item { Layout.fillWidth: true }

                        RippleButtonWithIcon {
                            materialIcon: "check"
                            mainText: Translation.tr("Accept")
                            onClicked: {
                                picker.decided = true
                                picker.close()
                            }
                        }
                    }
                }
            }
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
            color: root.ownValue ? Appearance.m3colors.m3onSurface : Appearance.colors.colSubtext
            text: root.displayValue
            onEditingFinished: {
                const v = root.normalise(text)
                // An emptied box is the only way of taking a color back off
                // where one is allowed to be absent; without it the field can
                // be given a value but never returned to not having one.
                if (v.length === 0 && root.allowEmpty && String(text).trim().length === 0) {
                    if (root.value !== "")
                        root.edited("")
                // Against what the box shows, not the raw value: the value can
                // arrive wearing the eight-digit dress while the box shows six,
                // and comparing across that gap made a mere focus loss commit
                // an untouched stand-in as an owned pick.
                } else if (v.length > 0 && v !== root.displayValue)
                    root.edited(v)
                // Re-arm the binding rather than assigning text: a plain
                // assignment would sever `text: root.displayValue` for good,
                // so after one edit the box would stop following the picker or
                // an outside change. Qt.binding keeps it tracking — and snaps
                // an unusable entry back to the real value in the same stroke.
                text = Qt.binding(() => root.displayValue)
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
