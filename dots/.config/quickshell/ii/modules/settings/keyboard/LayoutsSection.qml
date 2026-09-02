import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentSection {
    id: root
    icon: "keyboard"
    title: Translation.tr("Keyboard Layouts")

    readonly property string xkbLayoutList: "/usr/share/X11/xkb/rules/base.lst"
    readonly property string customGeneralConf: Quickshell.env("HOME") + "/.config/hypr/custom/general.lua"

    // Every layout XKB exposes on the current system. The picker intentionally
    // reads base.lst instead of carrying a stale, hand-maintained country list.
    property var availableLayouts: []
    property var selectedLayouts: []
    property bool catalogLoaded: false

    function layoutForCode(code) {
        return availableLayouts.find(layout => layout.code === code && !layout.variant)
    }

    function layoutId(layout) {
        return layout.code + ":" + (layout.variant || "")
    }

    function displayName(layout) {
        const selected = typeof layout === "string" ? { code: layout, variant: "" } : layout
        const known = availableLayouts.find(candidate => layoutId(candidate) === layoutId(selected))
        return known ? known.name : selected.code + (selected.variant ? " — " + selected.variant : "")
    }

    function setSelectedLayouts(codes, variants) {
        const layouts = codes
            .map((code, index) => ({
                code: code,
                variant: (variants && variants[index]) || ""
            }))
            .filter(layout => layout.code !== "custom")
        selectedLayouts = layouts.length > 0 ? layouts : [{ code: "us", variant: "" }]
        return layouts.length !== codes.length
    }

    function addLayout(layout) {
        if (!layout || selectedLayouts.some(selected => layoutId(selected) === layoutId(layout)))
            return
        selectedLayouts = [...selectedLayouts, {
            code: layout.code,
            variant: layout.variant || ""
        }]
        applyLayouts()
    }

    function removeLayout(layout) {
        // Hyprland needs one layout at all times; keeping the final one also
        // prevents the layout-cycle shortcut from becoming a no-op by accident.
        if (selectedLayouts.length <= 1)
            return
        selectedLayouts = selectedLayouts.filter(selected => layoutId(selected) !== layoutId(layout))
        applyLayouts()
    }

    function applyLayouts() {
        const layouts = selectedLayouts.map(layout => layout.code).join(",")
        const variants = selectedLayouts.map(layout => layout.variant || "").join(",")
        if (!layouts)
            return

        // Apply now, then store an update-safe override loaded after the base
        // Hyprland configuration. Layout identifiers come from XKB's base.lst,
        // but the writer validates them again before writing Lua.
        Quickshell.execDetached([
            "hyprctl", "eval",
            'hl.config({ input = { kb_layout = "' + layouts + '", kb_variant = "' + variants + '" } })'
        ])
        layoutWriter.command = ["python3", Quickshell.shellPath("scripts/keyboard/write-layouts.py"), root.customGeneralConf, layouts, variants]
        layoutWriter.running = false
        layoutWriter.running = true
    }

    Process {
        id: layoutCatalogProc
        // base.lst contains layouts first and variants afterwards. A tab makes
        // descriptions with spaces unambiguous for SplitParser.
        // `custom` is XKB's placeholder for a user-supplied definition, not
        // a selectable layout that this settings panel can configure.
        command: ["awk", '/^! layout/{in_layout=1; next} /^! variant/{exit} in_layout && NF >= 2 && $1 != \"custom\" {code=$1; $1=\"\"; sub(/^[[:space:]]+/, \"\"); print code \"\\t\" $0}', root.xkbLayoutList]
        stdout: SplitParser {
            onRead: data => {
                const fields = data.trim().split("\t")
                if (fields.length < 2)
                    return
                root.availableLayouts = [...root.availableLayouts, {
                    code: fields[0],
                    name: fields.slice(1).join("\t")
                }]
            }
        }
        onExited: {
            root.availableLayouts = [...root.availableLayouts,
                {
                    code: "us",
                    variant: "dvorak",
                    name: Translation.tr("English (US) — Dvorak")
                },
                {
                    code: "us",
                    variant: "colemak",
                    name: Translation.tr("English (US) — Colemak")
                },
                {
                    code: "us",
                    variant: "colemak_dh",
                    name: Translation.tr("English (US) — Colemak-DH")
                },
                {
                    code: "us",
                    variant: "workman",
                    name: Translation.tr("English (US) — Workman")
                },
                {
                    code: "us",
                    variant: "dvp",
                    name: Translation.tr("English (US) — Programmer Dvorak")
                },
                {
                    code: "fr",
                    variant: "bepo",
                    name: Translation.tr("French — Bépo")
                },
                {
                    code: "de",
                    variant: "neo",
                    name: Translation.tr("German — Neo 2")
                }
            ]
            root.catalogLoaded = true
        }
    }

    // Hyprland's devices JSON reports the comma-separated layouts but not
    // their variants. Prefer the managed override when it exists so an entry
    // such as US Dvorak survives reopening Settings with its variant intact.
    Process {
        id: persistedLayoutsProc
        command: ["cat", root.customGeneralConf]
        property string configText: ""
        onRunningChanged: if (running) configText = ""
        stdout: StdioCollector {
            onStreamFinished: persistedLayoutsProc.configText = text
        }
        onExited: {
            const block = configText.match(/-- BEGIN keyboard-layouts \(managed by Settings\)\n([\s\S]*?)-- END keyboard-layouts/)
            const layoutsMatch = block && block[1].match(/kb_layout\s*=\s*"([^"]+)"/)
            const variantsMatch = block && block[1].match(/kb_variant\s*=\s*"([^"]*)"/)
            if (layoutsMatch) {
                const removedCustom = root.setSelectedLayouts(
                    layoutsMatch[1].split(",").filter(Boolean),
                    variantsMatch ? variantsMatch[1].split(",") : []
                )
                if (removedCustom)
                    root.applyLayouts()
            } else {
                currentLayoutsProc.running = false
                currentLayoutsProc.running = true
            }
        }
    }

    Process {
        id: currentLayoutsProc
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const keyboards = JSON.parse(text).keyboards || []
                    const mainKeyboard = keyboards.find(keyboard => keyboard.main) || keyboards[0]
                    const layouts = mainKeyboard?.layout?.split(",").filter(Boolean) || []
                    const removedCustom = root.setSelectedLayouts(layouts.length > 0 ? layouts : ["us"], [])
                    if (removedCustom)
                        root.applyLayouts()
                } catch (error) {
                    // Keep a dependable default when Hyprland is not running,
                    // such as when the Settings window is inspected standalone.
                    root.setSelectedLayouts(["us"], [])
                }
            }
        }
    }

    Process {
        id: layoutWriter
        onExited: {
            if (exitCode === 0)
                Quickshell.execDetached(["hyprctl", "reload"])
        }
    }

    Component.onCompleted: {
        layoutCatalogProc.running = true
        persistedLayoutsProc.running = true
    }

        ConfigRow {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: "keyboard"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colSubtext
            }
            StyledText {
                text: Translation.tr("Cycle through enabled layouts with")
                color: Appearance.colors.colSubtext
            }
            Row {
                spacing: 4
                KeyboardKey { key: "CTRL" }
                KeyboardKey { key: Config.options.cheatsheet.superKey || "SUPER" }
                StyledText {
                    text: "+"
                    color: Appearance.colors.colSubtext
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 2
                    rightPadding: 2
                }
                KeyboardKey { key: "K" }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("The selected layouts are available immediately and persist across restarts.")
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        ConfigRow {
            LayoutPicker {
                id: layoutPicker
                Layout.fillWidth: true
                ready: root.catalogLoaded
                layoutIdOf: root.layoutId
                options: root.availableLayouts
                    .filter(layout => !root.selectedLayouts.some(selected => root.layoutId(selected) === root.layoutId(layout)))
            }

            RippleButton {
                Layout.preferredHeight: 40
                Layout.preferredWidth: contentItem.implicitWidth + 24
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                contentItem: RowLayout {
                    spacing: 6
                    anchors.centerIn: parent
                    MaterialSymbol {
                        text: "add"
                        iconSize: 18
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        text: Translation.tr("Add")
                        color: Appearance.colors.colOnPrimary
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
                enabled: root.catalogLoaded && layoutPicker.selectedLayout
                onClicked: root.addLayout(layoutPicker.selectedLayout)
            }
        }

        ContentSubsection {
            title: Translation.tr("Enabled Layouts")

            Repeater {
                model: root.selectedLayouts
                delegate: ConfigRow {
                    required property var modelData

                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.code + " — " + root.displayName(modelData)
                        color: Appearance.colors.colOnLayer1
                    }
                    RippleButton {
                        Layout.preferredHeight: 40
                        Layout.preferredWidth: contentItem.implicitWidth + 24
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colError
                        colBackgroundHover: Appearance.colors.colErrorHover
                        colRipple: Appearance.colors.colErrorActive
                        // The base button hides its background entirely when
                        // disabled, which reads as a stray label beside the
                        // layout rows; keep the fill and let the reduced
                        // opacity convey the state.
                        buttonColor: hovered ? colBackgroundHover : colBackground
                        contentItem: RowLayout {
                            spacing: 6
                            anchors.centerIn: parent
                            MaterialSymbol {
                                text: "close"
                                iconSize: 18
                                color: Appearance.colors.colOnError
                            }
                            StyledText {
                                text: Translation.tr("Remove")
                                color: Appearance.colors.colOnError
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                        enabled: root.selectedLayouts.length > 1
                        onClicked: root.removeLayout(modelData)
                    }
                }
            }
        }
}
