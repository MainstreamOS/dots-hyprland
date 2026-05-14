pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property real padding: 4
    implicitWidth: QsWindow?.window?.screen.width * 0.7 ?? 0
    implicitHeight: QsWindow?.window?.screen.height * 0.7 ?? 0

    // Fork divergence from upstream: order categories explicitly rather
    // than relying on the first-seen-in-`hyprctl binds -j` order. We add
    // a bunch of categories upstream doesn't have (Master / Scrolling /
    // Monocle Layout, Gaming, User) and want them grouped sensibly with
    // the upstream ones. Anything not in the list sorts to the end
    // alphabetically. Empty string ("") at the very end is the
    // "Uncategorized" bucket — kept so we don't lose binds whose
    // description omits a category prefix.
    readonly property var preferredCategoryOrder: [
        "Shell",
        "Window",
        "Workspace",
        "Apps",
        "Master Layout",
        "Scrolling Layout",
        "Monocle Layout",
        "Screen",
        "Media",
        "Virtual machines",
        "Session",
        "Gaming",
        "Utilities",
        "User"
    ]

    function sortedCategories() {
        const cats = HyprlandKeybinds.keybindCategories.slice()
        cats.sort((a, b) => {
            const ia = root.preferredCategoryOrder.indexOf(a)
            const ib = root.preferredCategoryOrder.indexOf(b)
            if (ia === -1 && ib === -1) return a.localeCompare(b)
            if (ia === -1) return 1
            if (ib === -1) return -1
            return ia - ib
        })
        return [...cats, ""]
    }

    StyledFlickable {
        id: flickable
        anchors.fill: parent
        anchors.margins: Appearance.rounding.small
        contentHeight: height
        contentWidth: flow.implicitWidth
        Flow {
            id: flow
            height: flickable.height
            flow: Flow.TopToBottom
            spacing: 12
            Repeater {
                model: root.sortedCategories()
                delegate: CheatsheetKeybindsCategory {
                    required property var modelData
                    categoryName: modelData
                }
            }
        }
    }
}
