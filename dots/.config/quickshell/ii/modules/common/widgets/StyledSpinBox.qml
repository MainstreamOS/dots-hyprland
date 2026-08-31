import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls

/**
 * Material 3 styled SpinBox component.
 */
SpinBox {
    id: root

    property real baseHeight: 35
    property real radius: Appearance.rounding.small
    property real innerButtonRadius: Appearance.rounding.unsharpen
    // Optional unit string shown after the numeric value (e.g. "%").
    // parseFloat in onTextChanged transparently strips it on edit so
    // typing "75%" parses to 75 and "75" parses to 75 — both round-trip
    // to "75%" via the binding.
    property string suffix: ""
    editable: true

    opacity: root.enabled ? 1 : 0.4

    background: Rectangle {
        color: Appearance.colors.colLayer2
        radius: root.radius
    }

    contentItem: Item {
        implicitHeight: root.baseHeight
        implicitWidth: Math.max(labelText.implicitWidth, 40)

        StyledTextInput {
            id: labelText
            // Fills the room between the two steppers rather than hugging its
            // digits. Hugging left the target as narrow as the number inside
            // it, so a single digit gave a few pixels to hit in a control the
            // better part of a hundred wide, and clicking anywhere else in the
            // middle did nothing at all.
            anchors.fill: parent
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            text: root.value + root.suffix // displayText would make the numbers weird like 1,000 instead of 1000
            color: Appearance.colors.colOnLayer2
            font.family: Appearance.font.family.numbers
            font.variableAxes: Appearance.font.variableAxes.numbers
            font.pixelSize: Appearance.font.pixelSize.small
            validator: root.validator
            onTextChanged: {
                const parsed = parseFloat(text);
                if (!isNaN(parsed)) {
                    root.value = parsed;
                    return;
                }
                // Cleared outright, which is how someone starts again rather
                // than a number they meant: it counts as none, and the field
                // says so instead of sitting blank with no value behind it.
                if (text.length === 0) {
                    root.value = Math.max(root.from, Math.min(root.to, 0));
                    text = root.value + root.suffix;
                }
                // Anything else is a number half typed, a lone minus sign
                // above all, so the last good value stands until it is whole.
            }
            // A half typed value that never became a number would otherwise
            // stay on screen as itself once the field is left.
            onEditingFinished: {
                if (isNaN(parseFloat(text)))
                    text = root.value + root.suffix;
            }
        }
    }

    down.indicator: Rectangle {
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
        }
        implicitHeight: root.baseHeight
        implicitWidth: root.baseHeight
        topLeftRadius: root.radius
        bottomLeftRadius: root.radius
        topRightRadius: root.innerButtonRadius
        bottomRightRadius: root.innerButtonRadius

        color: root.down.pressed ? Appearance.colors.colLayer2Active : 
            root.down.hovered ? Appearance.colors.colLayer2Hover : 
            ColorUtils.transparentize(Appearance.colors.colLayer2)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "remove"
            iconSize: 20
            color: Appearance.colors.colOnLayer2
        }
    }

    up.indicator: Rectangle {
        anchors {
            verticalCenter: parent.verticalCenter
            right: parent.right
        }
        implicitHeight: root.baseHeight
        implicitWidth: root.baseHeight
        topRightRadius: root.radius
        bottomRightRadius: root.radius
        topLeftRadius: root.innerButtonRadius
        bottomLeftRadius: root.innerButtonRadius

        color: root.up.pressed ? Appearance.colors.colLayer2Active : 
            root.up.hovered ? Appearance.colors.colLayer2Hover : 
            ColorUtils.transparentize(Appearance.colors.colLayer2)
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "add"
            iconSize: 20
            color: Appearance.colors.colOnLayer2
        }
    }
}
