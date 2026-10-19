import qs.services
import qs.modules.common
import qs.modules.common.widgets

ConfigSelectionArray {
    currentValue: Appearance.sizes.barIsIsland ? "island" : "bar"
    onSelected: newValue => Config.pickBarMode(newValue)
    options: [
        { displayName: Translation.tr("Traditional bar"), icon: "toolbar", value: "bar" },
        { displayName: Translation.tr("Dynamic Island"), icon: "dynamic_feed", value: "island" }
    ]
}
