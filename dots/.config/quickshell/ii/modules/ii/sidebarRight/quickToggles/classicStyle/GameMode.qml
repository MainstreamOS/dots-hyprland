import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell
import Quickshell.Io

QuickToggleButton {
    id: root
    buttonIcon: "gamepad"
    toggled: toggled

    onClicked: {
        root.toggled = !root.toggled
        if (root.toggled) {
            // Hyprland 0.55 Lua mode: `hyprctl keyword` is rejected
            // ("keyword can't work with non-legacy parsers. Use eval."), so
            // every entry-into-game-mode keyword has to be wrapped in
            // hl.config via hyprctl eval.
            Quickshell.execDetached(["hyprctl", "eval",
                'hl.config({' +
                    'animations = { enabled = false },' +
                    'decoration = {' +
                        'rounding = 0,' +
                        'blur = { enabled = false },' +
                        'shadow = { enabled = false }' +
                    '},' +
                    'general = {' +
                        'gaps_in = 0,' +
                        'gaps_out = 0,' +
                        'border_size = 1,' +
                        'allow_tearing = true' +
                    '}' +
                '})'])
        } else {
            Quickshell.execDetached(["hyprctl", "reload"])
        }
    }
    Process {
        id: fetchActiveState
        running: true
        command: ["bash", "-c", `test "$(hyprctl getoption animations:enabled -j | jq ".int")" -ne 0`]
        onExited: (exitCode, exitStatus) => {
            root.toggled = exitCode !== 0 // Inverted because enabled = nonzero exit
        }
    }
    StyledToolTip {
        text: Translation.tr("Game mode")
    }
}