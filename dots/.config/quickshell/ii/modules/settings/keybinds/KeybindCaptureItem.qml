pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Focusable surface for capturing a key chord or mouse button.
 *
 * Activates a Hyprland submap (`qs_keybind_capture`) while capturing
 * so existing binds don't fire. Emits `chordCaptured(mods, key, isMouse)`
 * on a real key press; emits `cancelled()` on Escape or focus loss.
 *
 * Mouse mode swaps in a MouseArea overlay that captures clicks instead.
 */
FocusScope {
    id: root

    property bool capturing: false
    property bool mouseMode: false
    property string submapName: "qs_keybind_capture"

    signal chordCaptured(var mods, string key, bool isMouse)
    signal cancelled()

    implicitWidth: 200
    implicitHeight: 80

    function start() {
        if (capturing) return
        capturing = true
        forceActiveFocus()
        // Push capture submap to suppress active binds while recording.
        if (!mouseMode)
            Quickshell.execDetached(["hyprctl", "dispatch", "submap", submapName])
    }

    function stop() {
        if (!capturing) return
        capturing = false
        if (!mouseMode)
            Quickshell.execDetached(["hyprctl", "dispatch", "submap", "global"])
    }

    onCapturingChanged: if (!capturing) focus = false

    // Map a Qt event into (mods[], hyprlandKeyName).
    function _qtModsToHypr(qtMods) {
        const out = []
        if (qtMods & Qt.MetaModifier)    out.push("SUPER")
        if (qtMods & Qt.ControlModifier) out.push("CTRL")
        if (qtMods & Qt.AltModifier)     out.push("ALT")
        if (qtMods & Qt.ShiftModifier)   out.push("SHIFT")
        return out
    }

    function _qtKeyToHypr(qtKey, eventText) {
        // Modifier-only press → null (will be ignored)
        if (qtKey === Qt.Key_Shift || qtKey === Qt.Key_Control
                || qtKey === Qt.Key_Alt || qtKey === Qt.Key_Meta
                || qtKey === Qt.Key_Super_L || qtKey === Qt.Key_Super_R)
            return null

        // Letters: use uppercase from Qt enum range
        if (qtKey >= Qt.Key_A && qtKey <= Qt.Key_Z)
            return String.fromCharCode("A".charCodeAt(0) + (qtKey - Qt.Key_A))

        // Digits
        if (qtKey >= Qt.Key_0 && qtKey <= Qt.Key_9)
            return String.fromCharCode("0".charCodeAt(0) + (qtKey - Qt.Key_0))

        // Function keys
        if (qtKey >= Qt.Key_F1 && qtKey <= Qt.Key_F35)
            return "F" + (1 + qtKey - Qt.Key_F1)

        // Special keys → X11 keysym names that Hyprland accepts.
        const map = {}
        map[Qt.Key_Return]    = "Return"
        map[Qt.Key_Enter]     = "KP_Enter"
        map[Qt.Key_Tab]       = "Tab"
        map[Qt.Key_Backtab]   = "Tab"
        map[Qt.Key_Backspace] = "BackSpace"
        map[Qt.Key_Delete]    = "Delete"
        map[Qt.Key_Insert]    = "Insert"
        map[Qt.Key_Home]      = "Home"
        map[Qt.Key_End]       = "End"
        map[Qt.Key_PageUp]    = "Prior"
        map[Qt.Key_PageDown]  = "Next"
        map[Qt.Key_Up]        = "Up"
        map[Qt.Key_Down]      = "Down"
        map[Qt.Key_Left]      = "Left"
        map[Qt.Key_Right]     = "Right"
        map[Qt.Key_Space]     = "space"
        map[Qt.Key_Comma]     = "comma"
        map[Qt.Key_Period]    = "period"
        map[Qt.Key_Slash]     = "slash"
        map[Qt.Key_Backslash] = "backslash"
        map[Qt.Key_Semicolon] = "semicolon"
        map[Qt.Key_Apostrophe] = "apostrophe"
        map[Qt.Key_BracketLeft]  = "bracketleft"
        map[Qt.Key_BracketRight] = "bracketright"
        map[Qt.Key_BraceLeft]    = "braceleft"
        map[Qt.Key_BraceRight]   = "braceright"
        map[Qt.Key_Minus]     = "minus"
        map[Qt.Key_Equal]     = "equal"
        map[Qt.Key_Plus]      = "plus"
        map[Qt.Key_QuoteLeft] = "grave"
        map[Qt.Key_AsciiTilde] = "asciitilde"
        if (map[qtKey] !== undefined) return map[qtKey]

        // Last resort: use eventText if it's a single printable char.
        if (eventText && eventText.length === 1) {
            const ch = eventText.charCodeAt(0)
            if (ch >= 0x20 && ch < 0x7f) return eventText
        }
        return null
    }

    Keys.onPressed: (event) => {
        if (!capturing) return

        // Escape always cancels.
        if (event.key === Qt.Key_Escape) {
            event.accepted = true
            root.stop()
            root.cancelled()
            return
        }

        if (root.mouseMode) {
            // In mouse mode keyboard input is ignored except Escape (handled above).
            event.accepted = true
            return
        }

        const keyName = root._qtKeyToHypr(event.key, event.text)
        if (keyName === null) {
            // Modifier-only press — wait for the actual key.
            event.accepted = true
            return
        }

        const mods = root._qtModsToHypr(event.modifiers)
        event.accepted = true
        root.stop()
        root.chordCaptured(mods, keyName, false)
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        border.width: root.capturing ? 2 : 1
        border.color: root.capturing ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
        color: root.capturing
            ? Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.08)
            : Appearance.colors.colLayer2

        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4
            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: root.capturing ? "fiber_manual_record" : (root.mouseMode ? "mouse" : "keyboard")
                iconSize: 28
                color: root.capturing ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.capturing
                    ? (root.mouseMode ? Translation.tr("Click a mouse button…") : Translation.tr("Press a key combination…"))
                    : Translation.tr("Click to record")
                color: root.capturing ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: root.capturing
                text: Translation.tr("Esc to cancel")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }

    // Click-to-arm overlay (only active when not capturing).
    MouseArea {
        anchors.fill: parent
        visible: !root.capturing
        cursorShape: Qt.PointingHandCursor
        onClicked: root.start()
    }

    // Mouse capture overlay (only in mouse mode while capturing).
    MouseArea {
        anchors.fill: parent
        visible: root.capturing && root.mouseMode
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                         | Qt.BackButton | Qt.ForwardButton
        cursorShape: Qt.CrossCursor
        propagateComposedEvents: false
        preventStealing: true
        onPressed: (mouse) => {
            const map = ({})
            map[Qt.LeftButton]   = "mouse:272"
            map[Qt.RightButton]  = "mouse:273"
            map[Qt.MiddleButton] = "mouse:274"
            map[Qt.BackButton]   = "mouse:275"
            map[Qt.ForwardButton] = "mouse:276"
            const btn = map[mouse.button]
            const mods = root._qtModsToHypr(mouse.modifiers)
            mouse.accepted = true
            root.stop()
            if (btn !== undefined)
                root.chordCaptured(mods, btn, true)
            else
                root.cancelled()
        }
    }

    // Auto-cancel if focus is lost while capturing.
    onActiveFocusChanged: {
        if (capturing && !activeFocus) {
            stop()
            cancelled()
        }
    }
}
