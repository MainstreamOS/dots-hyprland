pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.keybinds

ContentPage {
    id: root
    forceWidth: true

    readonly property string userPath: HyprlandKeybindsRaw.userPath
    readonly property string captureSubmapName: "qs_keybind_capture"

    property bool showHidden: true
    property string searchTerm: ""

    Dispatchers {
        id: dispatchers
    }

    // ── Merged data ──────────────────────────────────────────────────────
    // Re-derived whenever HyprlandKeybindsRaw.revision changes.
    property var merged: ({ owned: [], locked: [] })

    function _refreshMerged() {
        merged = HyprlandKeybindsRaw.buildMergedList()
    }

    Connections {
        target: HyprlandKeybindsRaw
        function onReloaded() { root._refreshMerged() }
    }

    Component.onCompleted: {
        HyprlandKeybindsRaw.refresh()
        ensureSubmapProc.running = false
        ensureSubmapProc.running = true
        _refreshMerged()
    }

    // ── Ensure capture submap exists in user keybind file ─────────────────
    Process {
        id: ensureSubmapProc
        property string py: `
import os, sys
path = os.path.expanduser(os.path.expandvars(sys.argv[1]))
marker = sys.argv[2]
if not os.path.isfile(path):
    open(path, 'a').close()
text = open(path).read()
if marker not in text:
    block = "\\n# " + marker + " — capture submap used by the settings keybinds editor; do not remove\\n"
    block += "submap = " + marker + "\\n"
    block += "bind = , Escape, submap, global\\n"
    block += "submap = global\\n"
    if not text.endswith("\\n"):
        text += "\\n"
    text += block
    open(path, 'w').write(text)
`
        command: ["python3", "-c", py, root.userPath, root.captureSubmapName]
    }

    // ── Hyprctl helpers ───────────────────────────────────────────────────
    Process { id: applyBindProc }
    Process { id: revertBindProc }
    Process { id: writeFileProc; onExited: Quickshell.execDetached(["hyprctl", "reload"]) }

    function _bindKeyword(b) {
        // hyprctl keyword <bindType> MODS, KEY, DISPATCHER[, ARGS]
        const modsStr = (b.mods || []).filter(m => m).join(" ")
        let value = modsStr + ", " + (b.key || "")
        value += ", " + (b.dispatcher || "")
        if (b.args && b.args.length > 0) value += ", " + b.args
        applyBindProc.command = ["hyprctl", "keyword", b.bindType || "bind", value]
        applyBindProc.running = false
        applyBindProc.running = true
    }

    function _unbindKeyword(mods, key) {
        const modsStr = (mods || []).filter(m => m).join(" ")
        revertBindProc.command = ["hyprctl", "keyword", "unbind", modsStr + ", " + key]
        revertBindProc.running = false
        revertBindProc.running = true
    }

    // Apply edits to the user keybind file via a Python heredoc.
    // op is one of: append, replace, delete, override
    function _editFile(op, payload) {
        const py = `
import json, os, sys
path = os.path.expanduser(os.path.expandvars(sys.argv[1]))
op = sys.argv[2]
data = json.loads(sys.argv[3])
if not os.path.isfile(path):
    open(path, 'a').close()
lines = open(path).read().split("\\n")
def fmt_bind(b):
    mods = " ".join([m for m in (b.get("mods") or []) if m])
    key = b.get("key", "")
    disp = b.get("dispatcher", "")
    args = b.get("args", "") or ""
    bt = b.get("bindType", "bind")
    rest = mods + ", " + key + ", " + disp
    if args:
        rest += ", " + args
    return bt + " = " + rest
def fmt_unbind(mods, key):
    return "unbind = " + " ".join([m for m in (mods or []) if m]) + ", " + key
if op == "append":
    line = fmt_bind(data["bind"])
    if lines and lines[-1] == "":
        lines.insert(len(lines) - 1, line)
    else:
        lines.append(line)
elif op == "replace":
    idx = data["lineNumber"] - 1
    if 0 <= idx < len(lines):
        lines[idx] = fmt_bind(data["bind"])
elif op == "delete":
    idx = data["lineNumber"] - 1
    if 0 <= idx < len(lines):
        del lines[idx]
elif op == "override":
    new_bind = fmt_bind(data["bind"])
    unbind = fmt_unbind(data["origMods"], data["origKey"])
    insertion = [unbind, new_bind]
    if lines and lines[-1] == "":
        for i, l in enumerate(insertion):
            lines.insert(len(lines) - 1, l)
    else:
        lines.extend(insertion)
elif op == "delete_with_unbind_cleanup":
    idx = data["lineNumber"] - 1
    if 0 <= idx < len(lines):
        del lines[idx]
    # Also remove a matching unbind line if present (used when deleting an override)
    unbind_line = fmt_unbind(data["mods"], data["key"])
    lines = [l for l in lines if l.strip() != unbind_line.strip()]
text = "\\n".join(lines)
if not text.endswith("\\n"):
    text += "\\n"
open(path, "w").write(text)
`
        writeFileProc.command = ["python3", "-c", py, root.userPath, op, JSON.stringify(payload)]
        writeFileProc.running = false
        writeFileProc.running = true
    }

    // ── User actions ──────────────────────────────────────────────────────
    function actionAdd(bind) {
        _bindKeyword(bind)
        _editFile("append", { bind: bind })
    }

    function actionEdit(oldBind, newBind) {
        _unbindKeyword(oldBind.mods, oldBind.key)
        _bindKeyword(newBind)
        _editFile("replace", { lineNumber: oldBind.lineNumber, bind: newBind })
    }

    function actionOverride(lockedBind, newBind) {
        _unbindKeyword(lockedBind.mods, lockedBind.key)
        _bindKeyword(newBind)
        _editFile("override", {
            bind: newBind,
            origMods: lockedBind.mods,
            origKey: lockedBind.key
        })
    }

    function actionDelete(bind) {
        _unbindKeyword(bind.mods, bind.key)
        _editFile("delete_with_unbind_cleanup", {
            lineNumber: bind.lineNumber,
            mods: bind.mods,
            key: bind.key
        })
    }

    // ── Filtering ─────────────────────────────────────────────────────────
    function _filterBind(b) {
        if (!root.showHidden && b.isHidden) return false
        if (b.submap && b.submap !== "global") return false
        const term = root.searchTerm.toLowerCase()
        if (!term) return true
        const shortcut = dispatchers.formatShortcut(b.mods || [], b.key || "").toLowerCase()
        const action = dispatchers.formatBindAction(b.bindType || "", b.dispatcher || "", b.args || "").toLowerCase()
        const cat = dispatchers.categoryById(dispatchers.categorizeBind(b.bindType || "", b.dispatcher || "")).label.toLowerCase()
        return shortcut.indexOf(term) >= 0 || action.indexOf(term) >= 0 || cat.indexOf(term) >= 0
    }

    function _binsByCategory() {
        // Only non-hidden binds go into per-dispatcher categories.
        // Hidden binds collect into _hiddenBinds and render as a single
        // group at the bottom — keeps the main view tidy when there are
        // many [hidden]-tagged defaults.
        const result = {}
        for (const cat of dispatchers.categories) result[cat.id] = []
        const owned = (merged.owned || []).filter(_filterBind)
        const locked = (merged.locked || []).filter(_filterBind)
        for (const b of owned) {
            if (b.isHidden) continue
            const cid = dispatchers.categorizeBind(b.bindType || "", b.dispatcher || "")
            if (!result[cid]) result[cid] = []
            result[cid].push(b)
        }
        for (const b of locked) {
            if (b.isHidden) continue
            const cid = dispatchers.categorizeBind(b.bindType || "", b.dispatcher || "")
            if (!result[cid]) result[cid] = []
            result[cid].push(b)
        }
        return result
    }

    function _collectHidden() {
        if (!showHidden) return []
        const all = (merged.owned || []).concat(merged.locked || [])
        return all.filter(b => b && b.isHidden && _filterBind(b))
    }

    property var _bindsByCat: ({})
    property var _hiddenBinds: []
    function _recomputeCategoryMap() {
        _bindsByCat = _binsByCategory()
        _hiddenBinds = _collectHidden()
    }

    onMergedChanged:    _recomputeCategoryMap()
    onShowHiddenChanged: _recomputeCategoryMap()
    onSearchTermChanged: _recomputeCategoryMap()

    function _totalVisible() {
        let n = 0
        for (const k in _bindsByCat) n += _bindsByCat[k].length
        n += (_hiddenBinds || []).length
        return n
    }

    // ── Edit dialog state ─────────────────────────────────────────────────
    property var _editingOldBind: null
    property var _overridingLockedBind: null

    function openAdd() {
        editDialog.mode = "add"
        editDialog.initialBindType = "bind"
        editDialog.initialMods = []
        editDialog.initialKey = ""
        editDialog.initialDispatcher = "exec"
        editDialog.initialArgs = ""
        editDialog.initialCategoryId = "apps"
        editDialog.allBinds = (merged.owned || []).concat(merged.locked || [])
        _editingOldBind = null
        _overridingLockedBind = null
        editDialog.show = true
    }

    function openEdit(bind) {
        editDialog.mode = "edit"
        editDialog.initialBindType = bind.bindType || "bind"
        editDialog.initialMods = bind.mods || []
        editDialog.initialKey = bind.key || ""
        editDialog.initialDispatcher = bind.dispatcher || ""
        editDialog.initialArgs = bind.args || ""
        editDialog.initialCategoryId = dispatchers.categorizeBind(bind.bindType || "", bind.dispatcher || "")
        editDialog.allBinds = (merged.owned || []).concat(merged.locked || [])
        _editingOldBind = bind
        _overridingLockedBind = null
        editDialog.show = true
    }

    function openOverride(bind) {
        editDialog.mode = "override"
        editDialog.initialBindType = bind.bindType || "bind"
        editDialog.initialMods = bind.mods || []
        editDialog.initialKey = bind.key || ""
        editDialog.initialDispatcher = bind.dispatcher || ""
        editDialog.initialArgs = bind.args || ""
        editDialog.initialCategoryId = dispatchers.categorizeBind(bind.bindType || "", bind.dispatcher || "")
        editDialog.allBinds = (merged.owned || []).concat(merged.locked || [])
        _editingOldBind = null
        _overridingLockedBind = bind
        editDialog.show = true
    }

    // ── UI ────────────────────────────────────────────────────────────────
    ContentSection {
        icon: "keyboard"
        title: Translation.tr("Keybinds")

        // Header controls
        ContentSubsection {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    MaterialTextField {
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Filter keybinds…")
                        text: root.searchTerm
                        onTextEdited: root.searchTerm = text
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
                            MaterialSymbol { text: "add"; iconSize: 18; color: Appearance.colors.colOnPrimary }
                            StyledText {
                                text: Translation.tr("Add")
                                color: Appearance.colors.colOnPrimary
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                        onClicked: root.openAdd()
                    }
                }

                StyledText {
                    visible: (root.merged.locked || []).length > 0
                    Layout.fillWidth: true
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: Translation.tr("Click the override icon to replace one in your custom file.")
                    wrapMode: Text.Wrap
                }
            }
        }

        // ── Categorized list ─────────────────────────────────────────────
        Repeater {
            model: dispatchers.categories
            delegate: ContentSubsection {
                required property var modelData
                visible: (root._bindsByCat[modelData.id] || []).length > 0
                title: modelData.label

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: root._bindsByCat[modelData.id] || []
                        delegate: BindRow {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            bind: modelData
                            categoryIcon: root._bindsByCat[modelData.dispatcherCategory] !== undefined
                                ? root._bindsByCat[modelData.dispatcherCategory].icon
                                : ""
                            onEditRequested: root.openEdit(modelData)
                            onOverrideRequested: root.openOverride(modelData)
                            onDeleteRequested: root.actionDelete(modelData)
                        }
                    }
                }
            }
        }

        // ── Hidden binds (always at the bottom) ───────────────────────────
        ContentSubsection {
            visible: (root._hiddenBinds || []).length > 0
            title: Translation.tr("Hidden")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Tagged [hidden] in your config — kept off the cheatsheet but still active.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                }

                Repeater {
                    model: root._hiddenBinds || []
                    delegate: BindRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        bind: modelData
                        onEditRequested: root.openEdit(modelData)
                        onOverrideRequested: root.openOverride(modelData)
                        onDeleteRequested: root.actionDelete(modelData)
                    }
                }
            }
        }

        // Empty state
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            visible: root._totalVisible() === 0
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "search_off"
                    iconSize: 36
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.searchTerm
                        ? Translation.tr("No keybinds match \"%1\"").arg(root.searchTerm)
                        : Translation.tr("No keybinds to show")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    // ── Inline row component ─────────────────────────────────────────────
    component BindRow: Rectangle {
        id: bindRow
        property var bind
        property string categoryIcon: ""
        signal editRequested()
        signal overrideRequested()
        signal deleteRequested()

        readonly property bool isOwned: bind ? !!bind.isOwned : false
        readonly property bool isHidden: bind ? !!bind.isHidden : false

        implicitHeight: rowLayout.implicitHeight + 16
        radius: Appearance.rounding.normal
        color: hoverArea.containsMouse
            ? Appearance.colors.colLayer2Hover
            : ColorUtils.transparentize(Appearance.colors.colLayer2, 1)

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: bindRow.isOwned ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: { if (bindRow.isOwned) bindRow.editRequested() }
        }

        RowLayout {
            id: rowLayout
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            // Hidden indicator
            MaterialSymbol {
                visible: bindRow.isHidden
                text: "visibility_off"
                iconSize: 14
                color: Appearance.colors.colSubtext
                opacity: 0.5
            }

            // Key pills
            Row {
                Layout.preferredWidth: implicitWidth
                spacing: 4
                Repeater {
                    model: (bindRow.bind && bindRow.bind.mods) ? bindRow.bind.mods.filter(m => m && m.length > 0) : []
                    delegate: KeyboardKey {
                        required property var modelData
                        key: modelData
                    }
                }
                StyledText {
                    visible: bindRow.bind && bindRow.bind.mods && bindRow.bind.mods.filter(m => m && m.length > 0).length > 0
                             && bindRow.bind.key && bindRow.bind.key.length > 0
                    text: "+"
                    color: Appearance.colors.colSubtext
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 2
                    rightPadding: 2
                }
                KeyboardKey {
                    visible: bindRow.bind && bindRow.bind.key && bindRow.bind.key.length > 0
                    key: bindRow.bind ? bindRow.bind.key : ""
                }
            }

            // Action description
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: bindRow.bind
                        ? dispatchers.formatBindAction(bindRow.bind.bindType || "", bindRow.bind.dispatcher || "", bindRow.bind.args || "")
                        : ""
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: bindRow.bind && bindRow.bind.comment && bindRow.bind.comment.length > 0
                    text: bindRow.bind ? (bindRow.bind.comment || "") : ""
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }
            }

            // Locked badge — relies on the adjacent Override button's
            // tooltip ("Override this keybind") to convey meaning. Adding
            // a StyledToolTip here would always render (the symbol has no
            // hovered property, so the tooltip's hover gate falls through).
            MaterialSymbol {
                visible: !bindRow.isOwned
                text: "lock"
                iconSize: 16
                color: Appearance.colors.colSubtext
                opacity: 0.6
            }

            // Override button (locked rows)
            RippleButton {
                visible: !bindRow.isOwned
                buttonRadius: Appearance.rounding.full
                implicitWidth: 30
                implicitHeight: 30
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
                colBackgroundHover: Appearance.colors.colLayer3Hover
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "edit"
                    iconSize: 16
                    color: Appearance.colors.colOnLayer1
                }
                onClicked: bindRow.overrideRequested()
                StyledToolTip { text: Translation.tr("Override this keybind") }
            }

            // Edit button (owned rows)
            RippleButton {
                visible: bindRow.isOwned
                buttonRadius: Appearance.rounding.full
                implicitWidth: 30
                implicitHeight: 30
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
                colBackgroundHover: Appearance.colors.colLayer3Hover
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "edit"
                    iconSize: 16
                    color: Appearance.colors.colOnLayer1
                }
                onClicked: bindRow.editRequested()
                StyledToolTip { text: Translation.tr("Edit") }
            }

            // Delete button (owned rows)
            RippleButton {
                visible: bindRow.isOwned
                buttonRadius: Appearance.rounding.full
                implicitWidth: 30
                implicitHeight: 30
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colError, 0.8)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "delete"
                    iconSize: 16
                    color: Appearance.colors.colError
                }
                onClicked: bindRow.deleteRequested()
                StyledToolTip { text: Translation.tr("Delete") }
            }
        }
    }

    // ── Edit dialog overlay ──────────────────────────────────────────────
    // Note: the dialog reparents itself to the Window's content item in
    // its own Component.onCompleted to escape the ContentPage flickable's
    // layout. We don't set anchors here.
    KeybindEditDialog {
        id: editDialog
        z: 1000
        dispatchers: dispatchers
        onApplied: (bindType, mods, key, dispatcher, args) => {
            const newBind = {
                bindType: bindType,
                mods: mods,
                key: key,
                dispatcher: dispatcher,
                args: args
            }
            if (root._editingOldBind) {
                root.actionEdit(root._editingOldBind, newBind)
            } else if (root._overridingLockedBind) {
                root.actionOverride(root._overridingLockedBind, newBind)
            } else {
                root.actionAdd(newBind)
            }
            editDialog.show = false
        }
        onDismissed: { /* no-op */ }
    }
}
