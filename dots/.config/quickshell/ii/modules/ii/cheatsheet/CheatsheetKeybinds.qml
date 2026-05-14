pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Cheatsheet keybinds view — Row of Columns, each Column stacks Sections,
 * each Section renders its title + a 2-column grid of (key combo, description)
 * rows. Tree data comes from HyprlandKeybinds.keybinds:
 *
 *   { children: [                  <-- columns (one per `--#!` in keybinds.lua)
 *     { children: [                <-- sections (each `--##! Name`)
 *       { name, keybinds: [...] }  <-- section + its binds
 *     ]}
 *   ]}
 *
 * The legacy hyprlang version (pre-0.55) had this same layout — Lua
 * conversion temporarily simplified it to a flat list, this restores it.
 */
Item {
    id: root
    readonly property var keybinds: HyprlandKeybinds.keybinds
    property real spacing: 20
    property real titleSpacing: 7
    property real padding: 4
    implicitWidth: row.implicitWidth + padding * 2
    implicitHeight: row.implicitHeight + padding * 2

    // Symbol maps — see http://xahlee.info/comp/unicode_computing_symbols.html
    // and https://www.nerdfonts.com/cheat-sheet for the glyph sources.
    property var macSymbolMap: ({
        "Ctrl": "󰘴",
        "Alt": "󰘵",
        "Shift": "󰘶",
        "Space": "󱁐",
        "Tab": "↹",
        "Equal": "󰇼",
        "Minus": "",
        "Print": "",
        "BackSpace": "󰭜",
        "Delete": "⌦",
        "Return": "󰌑",
        "Period": ".",
        "Escape": "⎋"
    })
    property var functionSymbolMap: ({
        "F1":  "󱊫", "F2":  "󱊬", "F3":  "󱊭", "F4":  "󱊮",
        "F5":  "󱊯", "F6":  "󱊰", "F7":  "󱊱", "F8":  "󱊲",
        "F9":  "󱊳", "F10": "󱊴", "F11": "󱊵", "F12": "󱊶",
    })
    property var mouseSymbolMap: ({
        "mouse_up": "󱕐",
        "mouse_down": "󱕑",
        "mouse:272": "L󰍽",
        "mouse:273": "R󰍽",
        "Scroll ↑/↓": "󱕒",
        "Page_↑/↓": "⇞/⇟",
    })

    // `SUPER_L` / `SUPER_R` show only their mod pill — the keycode itself is
    // suppressed since the user thinks of these as "the Super key" releases.
    property var keyBlacklist: ["SUPER_L", "SUPER_R", "Super_L", "Super_R"]
    property var keySubstitutions: Object.assign({
        "SUPER": "",
        "Super": "",
        "mouse_up": "Scroll ↓",    // ikr, weird
        "mouse_down": "Scroll ↑",  // trust me bro
        "mouse:272": "LMB",
        "mouse:273": "RMB",
        "mouse:275": "MouseBack",
        "Slash": "/",
        "Hash": "#",
        "Return": "Enter",
    },
    !!Config.options.cheatsheet.superKey ? {
        "SUPER": Config.options.cheatsheet.superKey,
        "Super": Config.options.cheatsheet.superKey,
    } : {},
    Config.options.cheatsheet.useMacSymbol ? macSymbolMap : {},
    Config.options.cheatsheet.useFnSymbol ? functionSymbolMap : {},
    Config.options.cheatsheet.useMouseSymbol ? mouseSymbolMap : {},
    )

    Row { // Keybind columns
        id: row
        spacing: root.spacing

        Repeater {
            model: root.keybinds.children

            delegate: Column { // One column from each top-level `--#!` block
                spacing: root.spacing
                required property var modelData
                anchors.top: row.top

                Repeater {
                    model: modelData.children

                    delegate: Item { // Section with title + bind grid
                        id: keybindSection
                        required property var modelData
                        implicitWidth: sectionColumn.implicitWidth
                        implicitHeight: sectionColumn.implicitHeight

                        Column {
                            id: sectionColumn
                            anchors.centerIn: parent
                            spacing: root.titleSpacing

                            StyledText {
                                id: sectionTitle
                                font {
                                    family: Appearance.font.family.title
                                    pixelSize: Appearance.font.pixelSize.title
                                    variableAxes: Appearance.font.variableAxes.title
                                }
                                color: Appearance.colors.colOnLayer0
                                text: keybindSection.modelData.name
                            }

                            GridLayout {
                                id: keybindGrid
                                columns: 2
                                columnSpacing: 4
                                rowSpacing: 4

                                Repeater {
                                    model: {
                                        // Build a flat 2-cells-per-bind list: cell A
                                        // = "keys" (key pills), cell B = "comment"
                                        // (description). The GridLayout's columns=2
                                        // wraps automatically.
                                        const result = [];
                                        const binds = keybindSection.modelData.keybinds || [];
                                        for (let i = 0; i < binds.length; i++) {
                                            // Don't mutate the source — work on a
                                            // copy so re-renders see a fresh array.
                                            let mods = (binds[i].mods || []).slice();

                                            if (!Config.options.cheatsheet.splitButtons) {
                                                // Single-pill mode: join the mods +
                                                // key into one label, run subs as
                                                // we go.
                                                for (let j = 0; j < mods.length; j++) {
                                                    mods[j] = root.keySubstitutions[mods[j]] || mods[j];
                                                }
                                                let joined = mods.join(" ");
                                                const k = binds[i].key;
                                                if (!root.keyBlacklist.includes(k)) {
                                                    if (joined.length > 0) joined += " ";
                                                    joined += (root.keySubstitutions[k] || k);
                                                }
                                                mods = [joined];
                                            }

                                            result.push({
                                                "type": "keys",
                                                "mods": mods,
                                                "key": binds[i].key,
                                            });
                                            result.push({
                                                "type": "comment",
                                                "comment": binds[i].comment,
                                            });
                                        }
                                        return result;
                                    }
                                    delegate: Item {
                                        required property var modelData
                                        implicitWidth: keybindLoader.implicitWidth
                                        implicitHeight: keybindLoader.implicitHeight

                                        Loader {
                                            id: keybindLoader
                                            sourceComponent: (modelData.type === "keys") ? keysComponent : commentComponent
                                        }

                                        Component {
                                            id: keysComponent
                                            Row {
                                                spacing: 4
                                                Repeater {
                                                    model: modelData.mods
                                                    delegate: KeyboardKey {
                                                        required property var modelData
                                                        key: root.keySubstitutions[modelData] || modelData
                                                        pixelSize: Config.options.cheatsheet.fontSize.key
                                                    }
                                                }
                                                StyledText {
                                                    id: keybindPlus
                                                    visible: Config.options.cheatsheet.splitButtons
                                                        && !root.keyBlacklist.includes(modelData.key)
                                                        && modelData.mods.length > 0
                                                    text: "+"
                                                }
                                                KeyboardKey {
                                                    id: keybindKey
                                                    visible: Config.options.cheatsheet.splitButtons
                                                        && !root.keyBlacklist.includes(modelData.key)
                                                    key: root.keySubstitutions[modelData.key] || modelData.key
                                                    pixelSize: Config.options.cheatsheet.fontSize.key
                                                    color: Appearance.colors.colOnLayer0
                                                }
                                            }
                                        }

                                        Component {
                                            id: commentComponent
                                            Item {
                                                implicitWidth: commentText.implicitWidth + 8 * 2
                                                implicitHeight: commentText.implicitHeight

                                                StyledText {
                                                    id: commentText
                                                    anchors.centerIn: parent
                                                    font.pixelSize: Config.options.cheatsheet.fontSize.comment || Appearance.font.pixelSize.smaller
                                                    text: modelData.comment
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
