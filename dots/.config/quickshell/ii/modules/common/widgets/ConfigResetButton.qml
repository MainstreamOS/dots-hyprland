import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// A section's way back to stock. The caller owns when it shows and what it resets, since only it knows
// which keys make up stock; this owns the look, the same as the Decorations page's resets.
RippleButtonWithIcon {
    id: root
    materialIcon: "settings_backup_restore"
    mainText: root.buttonText
}
