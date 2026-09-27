import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Offered by both the Bar and the Quick page, in the same order.
ConfigSelectionArray {
    currentValue: Config.options.bar.cornerStyle
    onSelected: newValue => RoundedCorners.pickBarStyle(newValue)
    options: [
        { displayName: Translation.tr("Float"), icon: "page_header", value: 1 },
        { displayName: Translation.tr("Notch"), icon: "call_to_action", value: 3 },
        { displayName: Translation.tr("Hug"), icon: "line_curve", value: 0 },
        { displayName: Translation.tr("Rect"), icon: "toolbar", value: 2 }
    ]
}
