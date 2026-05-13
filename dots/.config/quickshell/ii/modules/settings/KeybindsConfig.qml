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
    // Lua format: hl.define_submap("name", function() hl.bind(...) end).
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
    block = "\\n-- " + marker + " — capture submap used by the settings keybinds editor; do not remove\\n"
    block += "hl.define_submap(\\"" + marker + "\\", function()\\n"
    block += "    hl.bind(\\"Escape\\", hl.dsp.submap(\\"reset\\"))\\n"
    block += "end)\\n"
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
    // op is one of: append, replace, delete, override, delete_with_unbind_cleanup.
    // Emits Hyprland-0.55 Lua syntax:
    //   hl.bind("MODS + KEY", DISPATCHER_CLOSURE, {OPTIONS})
    //   hl.unbind("MODS + KEY")
    // Bind types (binde/bindl/bindd/bindm/bindle/...) become entries in the
    // options table. Dispatchers are mapped to hl.dsp.* closures via a lookup
    // table; unknown dispatchers fall back to a Lua function that shells out
    // to `hyprctl dispatch 'hl.dsp.<form>'` so the bind is still functional.
    function _editFile(op, payload) {
        const py = `
import json, os, sys
path = os.path.expanduser(os.path.expandvars(sys.argv[1]))
op = sys.argv[2]
data = json.loads(sys.argv[3])
if not os.path.isfile(path):
    open(path, 'a').close()
lines = open(path).read().split("\\n")

# bind type → list of option keys to set true. 'description' is special
# (set with the actual comment string if present).
BIND_TYPE_OPTS = {
    "bind":   [],
    "bindd":  ["description"],
    "binde":  ["repeating"],
    "binded": ["repeating", "description"],
    "bindl":  ["locked"],
    "bindle": ["locked", "repeating"],
    "bindld": ["locked", "description"],
    "bindel": ["locked", "repeating"],
    "bindm":  ["mouse"],
    "bindn":  ["non_consuming"],
    "bindt":  ["transparent"],
    "bindr":  ["release"],
    "bindo":  ["long_press"],
    "bindi":  ["ignore_mods"],
    "bindid": ["ignore_mods", "description"],
    "bindit": ["ignore_mods", "transparent"],
    "binditn":["ignore_mods", "transparent", "non_consuming"],
    "bindp":  [],  # # silent submit — rare; treat as plain bind
}

# Map hyprlang dispatcher names to Lua dispatcher expression builders.
# Each entry is a function args (string, may be empty) → Lua expression.
def dsp_exec(args):     return 'hl.dsp.exec_cmd("' + lua_esc(args) + '")'
def dsp_exit(args):     return 'hl.dsp.exit()'
def dsp_killactive(_):  return 'hl.dsp.window.close()'
def dsp_pin(_):         return 'hl.dsp.window.pin()'
def dsp_pseudo(_):      return 'hl.dsp.window.pseudo()'
def dsp_centerwin(_):   return 'hl.dsp.window.center()'
def dsp_togglefloat(_): return 'hl.dsp.window.float({action = "toggle"})'
def dsp_fullscreen(a):  return 'hl.dsp.window.fullscreen({mode = "' + ("maximized" if a.strip() == "1" else "fullscreen") + '"})'
def dsp_movewin(a):     return 'hl.dsp.window.move({direction = "' + a.strip() + '"})'
def dsp_resizewin(_):   return 'hl.dsp.window.resize()'
def dsp_swapwin(a):     return 'hl.dsp.window.swap({direction = "' + a.strip() + '"})'
def dsp_movefocus(a):   return 'hl.dsp.focus({direction = "' + a.strip() + '"})'
def dsp_workspace(a):   return 'hl.dsp.focus({workspace = "' + a.strip() + '"})'
def dsp_movetows(a):    return 'hl.dsp.window.move({workspace = "' + a.strip() + '"})'
def dsp_movetowssilent(a): return 'hl.dsp.window.move({workspace = "' + a.strip() + '", follow = false})'
def dsp_togglespecial(a):  return 'hl.dsp.workspace.toggle_special("' + (a.strip() or "special") + '")'
def dsp_focuswindow(a): return 'hl.dsp.focus({window = "' + a.strip() + '"})'
def dsp_layoutmsg(a):   return 'hl.dsp.layout("' + a.strip() + '")'
def dsp_submap(a):      return 'hl.dsp.submap("' + a.strip() + '")'
def dsp_global(a):      return 'hl.dsp.global("' + a.strip() + '")'
def dsp_event(a):       return 'hl.dsp.event("' + a.strip() + '")'
def dsp_dpms(a):        return 'hl.dsp.dpms({action = "' + (a.strip() or "toggle") + '"})'
def dsp_pass(a):        return 'hl.dsp.pass({window = "' + a.strip() + '"})'
def dsp_focuscurrentorlast(_): return 'hl.dsp.focus({last = true})'
def dsp_focusurgentorlast(_):  return 'hl.dsp.focus({urgent_or_last = true})'
def dsp_focusmonitor(a):       return 'hl.dsp.focus({monitor = "' + a.strip() + '"})'
def dsp_bringactivetotop(_):   return 'hl.dsp.window.bring_to_top()'
def dsp_alterzorder(a):        return 'hl.dsp.window.alter_zorder("' + a.strip() + '")'
def dsp_togglegroup(_):        return 'hl.dsp.group.toggle()'
def dsp_changegroupactive(a):  return 'hl.dsp.group.' + ("next" if a.strip() in ("","f","forward") else "prev") + '()'
def dsp_moveoutofgroup(_):     return 'hl.dsp.group.move_window({forward = true})'

DSP_MAP = {
    "exec": dsp_exec, "execr": dsp_exec, "exec-once": dsp_exec,
    "exit": dsp_exit,
    "killactive": dsp_killactive, "closewindow": dsp_killactive,
    "pin": dsp_pin,
    "pseudo": dsp_pseudo,
    "centerwindow": dsp_centerwin,
    "togglefloating": dsp_togglefloat,
    "fullscreen": dsp_fullscreen,
    "movewindow": dsp_movewin,
    "resizewindow": dsp_resizewin,
    "swapwindow": dsp_swapwin,
    "movefocus": dsp_movefocus,
    "workspace": dsp_workspace,
    "movetoworkspace": dsp_movetows,
    "movetoworkspacesilent": dsp_movetowssilent,
    "togglespecialworkspace": dsp_togglespecial,
    "focuswindow": dsp_focuswindow,
    "layoutmsg": dsp_layoutmsg,
    "submap": dsp_submap,
    "global": dsp_global,
    "event": dsp_event,
    "dpms": dsp_dpms,
    "pass": dsp_pass,
    "focuscurrentorlast": dsp_focuscurrentorlast,
    "focusurgentorlast": dsp_focusurgentorlast,
    "focusmonitor": dsp_focusmonitor,
    "bringactivetotop": dsp_bringactivetotop,
    "alterzorder": dsp_alterzorder,
    "togglegroup": dsp_togglegroup,
    "changegroupactive": dsp_changegroupactive,
    "moveoutofgroup": dsp_moveoutofgroup,
}

def lua_esc(s):
    # Escape backslashes and double quotes for a Lua double-quoted string.
    return s.replace("\\\\", "\\\\\\\\").replace('"', '\\\\"')

def fmt_dispatcher(disp, args):
    fn = DSP_MAP.get(disp)
    if fn is not None:
        return fn(args)
    # Unknown dispatcher — fall back to a function that shells out through
    # hyprctl dispatch with the Lua-mode wrapper string. Slow but correct.
    full = disp + ((" " + args) if args else "")
    return 'function() hl.exec_cmd("hyprctl dispatch \\'' + full + '\\'") end'

def fmt_lua_key(mods, key):
    parts = [m for m in (mods or []) if m]
    if key:
        parts.append(key)
    return " + ".join(parts)

def fmt_opts(bind_type, comment):
    opts = []
    fl = BIND_TYPE_OPTS.get(bind_type, [])
    for flag in fl:
        if flag == "description":
            if comment:
                opts.append('description = "' + lua_esc(comment) + '"')
        else:
            opts.append(flag + " = true")
    if not opts:
        return ""
    return ", {" + ", ".join(opts) + "}"

def fmt_bind(b):
    mods = b.get("mods") or []
    key = b.get("key", "")
    disp = b.get("dispatcher", "")
    args = b.get("args", "") or ""
    bt = b.get("bindType", "bind")
    comment = b.get("comment", "") or ""
    key_str = fmt_lua_key(mods, key)
    dsp_str = fmt_dispatcher(disp, args)
    opts_str = fmt_opts(bt, comment)
    return 'hl.bind("' + key_str + '", ' + dsp_str + opts_str + ')'

def fmt_unbind(mods, key):
    return 'hl.unbind("' + fmt_lua_key(mods, key) + '")'

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
    // Normalize a mod list for combo comparison: drop blanks, lower-case,
    // sort. SUPER+SHIFT and shift+super collapse to the same key.
    function _normMods(mods) {
        return (mods || []).filter(m => m).map(m => String(m).toLowerCase()).sort().join("+")
    }

    // Drop the "d" (description) flag for functional equivalence:
    // bindd → bind, binded → binde, bindld → bindl, bindid → bindi.
    // Description is cheatsheet-only metadata; everything else (e=repeating,
    // l=locked, m=mouse, n=non-consuming, etc.) changes behavior and stays.
    function _stripDescFlag(bt) {
        const map = { bindd: "bind", binded: "binde", bindld: "bindl", bindid: "bindi" }
        return map[bt] || bt
    }

    // Does `bind` functionally match some bind in hyprland/keybinds.lua?
    // Compares stripped-bindType + mod set + key + dispatcher + args. Ignores
    // description/comment — those are cosmetic. When this returns true,
    // the override evaporates instead of being written, so the row pops
    // back to locked-with-override-icon on the next reload.
    function _matchesDefault(bind) {
        const defaults = HyprlandKeybindsRaw.defaultData.binds || []
        const tMods = _normMods(bind.mods)
        const tKey = String(bind.key || "").toLowerCase()
        const tBT = _stripDescFlag(bind.bindType || "bind")
        const tDisp = bind.dispatcher || ""
        const tArgs = String(bind.args || "").trim()
        for (const d of defaults) {
            if (_stripDescFlag(d.bindType || "bind") !== tBT) continue
            if (_normMods(d.mods) !== tMods) continue
            if (String(d.key || "").toLowerCase() !== tKey) continue
            if ((d.dispatcher || "") !== tDisp) continue
            if (String(d.args || "").trim() !== tArgs) continue
            return true
        }
        return false
    }

    function actionAdd(bind) {
        if (_matchesDefault(bind)) {
            // Adding a duplicate of a default — no-op, don't pollute the file.
            return
        }
        _bindKeyword(bind)
        _editFile("append", { bind: bind })
    }

    function actionEdit(oldBind, newBind) {
        if (_matchesDefault(newBind)) {
            // Edit restored the bind to its default. Strip the user bind line
            // and any matching `hl.unbind` partner — the post-write reload
            // will re-establish the default. Mirrors actionDelete's path.
            _unbindKeyword(oldBind.mods, oldBind.key)
            _editFile("delete_with_unbind_cleanup", {
                lineNumber: oldBind.lineNumber,
                mods: oldBind.mods,
                key: oldBind.key
            })
            return
        }
        _unbindKeyword(oldBind.mods, oldBind.key)
        _bindKeyword(newBind)
        _editFile("replace", { lineNumber: oldBind.lineNumber, bind: newBind })
    }

    function actionOverride(lockedBind, newBind) {
        if (_matchesDefault(newBind)) {
            // "Override" with identical-to-default values — nothing to write.
            return
        }
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
                    text: Translation.tr("Click the edit icon to replace one in your custom file.")
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
