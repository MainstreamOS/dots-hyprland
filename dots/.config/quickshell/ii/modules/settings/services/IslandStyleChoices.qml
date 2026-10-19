import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The Bar and Quick pages edit the same island shape.
ConfigSelectionArray {
    currentValue: Appearance.sizes.islandShape
    onSelected: newValue => Config.options.bar.island.shape = newValue
    options: [
        { displayName: Translation.tr("Notch"), icon: "call_to_action", value: "notch" },
        { displayName: Translation.tr("Float"), icon: "page_header", value: "float" },
        { displayName: Translation.tr("Rect"), icon: "toolbar", value: "rect" }
    ]
}
