import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Offered by both the Dock and the Quick page, in the same order.
ConfigSelectionArray {
    currentValue: Config.options.dock.cornerStyle
    onSelected: newValue => Appearance.sizes.pickDockStyle(newValue)
    // In the Bar page's order, each named for the bar style it
    // matches. Notch, set down on the edge with a curve leaving
    // each end, keeps the stored value "hug" so a config or a theme
    // written before the rename still selects it, and the Hug strip
    // is stored as "span".
    options: [
        { displayName: Translation.tr("Float"), icon: "page_header", value: "float" },
        { displayName: Translation.tr("Notch"), icon: "call_to_action", value: "hug" },
        { displayName: Translation.tr("Hug"), icon: "line_curve", value: "span" },
        { displayName: Translation.tr("Rect"), icon: "toolbar", value: "rect" }
    ]
}
