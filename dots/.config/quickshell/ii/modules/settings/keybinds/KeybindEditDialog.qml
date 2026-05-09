pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Modal dialog to add, edit, or override a keybind.
 *
 * Mirrors the layout pattern of WindowDialog.qml (scrim + centered card)
 * but is sized larger and lays out its content as a vertical form.
 */
Rectangle {
    id: root

    // External API
    property bool show: false
    property var dispatchers   // Dispatchers QtObject instance
    property var allBinds: []  // for conflict detection: array of merged binds
    property string mode: "add" // "add" | "edit" | "override"

    // Pre-fill values (set before show=true)
    property string initialBindType: "bind"
    property var initialMods: []
    property string initialKey: ""
    property string initialDispatcher: ""
    property string initialArgs: ""
    property string initialCategoryId: ""

    signal applied(string bindType, var mods, string key, string dispatcher, string args)
    signal dismissed()

    // Internal mutable state
    property string _bindType: "bind"
    property bool _superMod: false
    property bool _shiftMod: false
    property bool _ctrlMod: false
    property bool _altMod: false
    property string _key: ""
    property string _categoryId: "apps"
    property string _dispatcher: ""
    property string _args: ""
    property bool _isMouseMode: false
    property string _mouseButton: ""
    property bool _modelReady: false

    // Reparent to the Window's content item so the modal scrim covers the
    // full window, not just the layout slot inside ContentPage's flickable.
    Component.onCompleted: {
        const w = root.Window ? root.Window.window : null
        if (w && w.contentItem)
            parent = w.contentItem
    }
    anchors.fill: parent
    color: root.show ? Appearance.colors.colScrim : ColorUtils.transparentize(Appearance.colors.colScrim)
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
    visible: card.implicitHeight > 0

    onShowChanged: {
        if (show) {
            _resetFromInitial()
            cardHeightAnim.easing.bezierCurve = Appearance.animationCurves.emphasizedDecel
        } else {
            cardHeightAnim.easing.bezierCurve = Appearance.animationCurves.emphasizedAccel
        }
        card.implicitHeight = show ? card.targetHeight : 0
    }

    function _resetFromInitial() {
        _bindType = initialBindType || "bind"
        _superMod = initialMods.indexOf("SUPER") >= 0 || initialMods.indexOf("Super") >= 0
        _shiftMod = initialMods.indexOf("SHIFT") >= 0 || initialMods.indexOf("Shift") >= 0
        _ctrlMod  = initialMods.indexOf("CTRL")  >= 0 || initialMods.indexOf("Ctrl")  >= 0
                                                       || initialMods.indexOf("CONTROL") >= 0
        _altMod   = initialMods.indexOf("ALT")   >= 0 || initialMods.indexOf("Alt")   >= 0
        _isMouseMode = (_bindType === "bindm") || /^mouse:/.test(initialKey)
        if (_isMouseMode) {
            _mouseButton = initialKey
            _key = ""
        } else {
            _key = initialKey || ""
            _mouseButton = ""
        }
        _dispatcher = initialDispatcher || ""
        _args = initialArgs || ""

        if (initialCategoryId && initialCategoryId.length > 0) {
            _categoryId = initialCategoryId
        } else if (_isMouseMode) {
            _categoryId = "mouse_button"
        } else if (initialDispatcher && root.dispatchers) {
            _categoryId = root.dispatchers.categorizeBind(_bindType, initialDispatcher)
            if (_categoryId === "advanced" && _bindType.indexOf("bind") === 0)
                _categoryId = "apps"
        } else {
            _categoryId = "apps"
        }
        _modelReady = true
    }

    function _collectMods() {
        const m = []
        if (_superMod) m.push("SUPER")
        if (_shiftMod) m.push("SHIFT")
        if (_ctrlMod)  m.push("CTRL")
        if (_altMod)   m.push("ALT")
        return m
    }

    function _effectiveKey() {
        return _isMouseMode ? _mouseButton : _key
    }

    function _conflictMessage() {
        const mods = _collectMods()
        const key = _effectiveKey()
        if (!key) return ""
        const probe = root.dispatchers ? root.dispatchers.combo(mods, key) : null
        if (!probe) return ""
        for (let i = 0; i < allBinds.length; i++) {
            const b = allBinds[i]
            const c = root.dispatchers.combo(b.mods || [], b.key || "")
            if (c === probe) {
                if (root.mode === "edit"
                        && (b.mods || []).join("+") === root.initialMods.join("+")
                        && b.key === root.initialKey)
                    continue
                if (root.mode === "override" && !b.isOwned) continue
                return Translation.tr("Conflicts with %1: %2")
                    .arg(root.dispatchers.formatShortcut(b.mods || [], b.key || ""))
                    .arg(root.dispatchers.formatBindAction(b.bindType || "bind", b.dispatcher || "", b.args || ""))
            }
        }
        return ""
    }

    function _canApply() {
        if (!_effectiveKey()) return false
        if (!_dispatcher) return false
        const argType = _argType()
        if (argType === "command" && (!_args || _args.length === 0)) return false
        return true
    }

    function _argType() {
        if (_isMouseMode) {
            // bindm only takes movewindow / resizewindow with no args
            return "none"
        }
        if (!root.dispatchers) return "none"
        const info = root.dispatchers.dispatcherInfo(_dispatcher)
        return info ? info.argType : "text"
    }

    function _doApply() {
        const mods = _collectMods()
        const key = _effectiveKey()
        const bt = _isMouseMode ? "bindm" : _bindType
        const disp = _dispatcher
        const args = (_argType() === "none") ? "" : _args
        applied(bt, mods, key, disp, args)
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: { root.show = false; root.dismissed() }
        cursorShape: Qt.ArrowCursor
    }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh
        implicitWidth: Math.min(parent.width - 60, 527)

        property real targetHeight: contentLayout.implicitHeight + radius * 2 + 16
        readonly property real targetY: parent.height / 2 - card.implicitHeight / 2
        y: root.show ? targetY : (targetY - 60)

        Behavior on implicitHeight {
            NumberAnimation {
                id: cardHeightAnim
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: cardHeightAnim.duration
                easing.type: cardHeightAnim.easing.type
                easing.bezierCurve: cardHeightAnim.easing.bezierCurve
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: (m) => m.accepted = true
            cursorShape: Qt.ArrowCursor
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: card.radius
            contentWidth: width
            contentHeight: contentLayout.implicitHeight
            clip: true
            opacity: root.show ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: contentLayout
                width: parent.width
                spacing: 10

                StyledText {
                    text: root.mode === "edit"     ? Translation.tr("Edit keybind")
                        : root.mode === "override" ? Translation.tr("Override keybind")
                        :                            Translation.tr("Add keybind")
                    color: Appearance.colors.colOnLayer1
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.larger
                        variableAxes: Appearance.font.variableAxes.title
                    }
                }

                // ── Trigger mode tabs ────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [
                            { id: "key",   label: Translation.tr("Key combination") },
                            { id: "mouse", label: Translation.tr("Mouse button")    }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 25
                            radius: Appearance.rounding.full
                            readonly property bool sel: (modelData.id === "mouse") === root._isMouseMode
                            color: sel ? Appearance.colors.colPrimary
                                       : (mouseArea.containsMouse ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer2)
                            border.width: sel ? 0 : 1
                            border.color: Appearance.colors.colOutlineVariant
                            Behavior on color { ColorAnimation { duration: 100 } }
                            StyledText {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: parent.sel ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                            MouseArea {
                                id: mouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const wantMouse = (modelData.id === "mouse")
                                    if (root._isMouseMode === wantMouse) return
                                    root._isMouseMode = wantMouse
                                    if (wantMouse) {
                                        if (root._bindType !== "bindm") root._bindType = "bindm"
                                        root._categoryId = "mouse_button"
                                        // Pick first bindm dispatcher as default
                                        const keys = Object.keys(root.dispatchers.bindmDispatchers)
                                        if (keys.length > 0) root._dispatcher = keys[0]
                                    } else {
                                        if (root._bindType === "bindm") root._bindType = "bind"
                                        root._categoryId = "apps"
                                        root._dispatcher = "exec"
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Trigger capture ──────────────────────────────────────────
                StyledText {
                    text: Translation.tr("Trigger")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                KeybindCaptureItem {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56
                    mouseMode: root._isMouseMode
                    onChordCaptured: (mods, key, isMouse) => {
                        root._superMod = mods.indexOf("SUPER") >= 0
                        root._shiftMod = mods.indexOf("SHIFT") >= 0
                        root._ctrlMod  = mods.indexOf("CTRL")  >= 0
                        root._altMod   = mods.indexOf("ALT")   >= 0
                        if (isMouse) {
                            root._mouseButton = key
                        } else {
                            root._key = key
                        }
                    }
                    onCancelled: { /* no-op */ }
                }

                // ── Manual modifier toggles ──────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [
                            { id: "super", label: "Super" },
                            { id: "shift", label: "Shift" },
                            { id: "ctrl",  label: "Ctrl"  },
                            { id: "alt",   label: "Alt"   }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 22
                            radius: Appearance.rounding.full
                            readonly property bool active:
                                  modelData.id === "super" ? root._superMod
                                : modelData.id === "shift" ? root._shiftMod
                                : modelData.id === "ctrl"  ? root._ctrlMod
                                :                            root._altMod
                            color: active ? Appearance.colors.colSecondaryContainer
                                          : (modArea.containsMouse ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer2)
                            border.width: 1
                            border.color: active ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            Behavior on color { ColorAnimation { duration: 100 } }
                            StyledText {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: parent.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                            MouseArea {
                                id: modArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if      (modelData.id === "super") root._superMod = !root._superMod
                                    else if (modelData.id === "shift") root._shiftMod = !root._shiftMod
                                    else if (modelData.id === "ctrl")  root._ctrlMod  = !root._ctrlMod
                                    else if (modelData.id === "alt")   root._altMod   = !root._altMod
                                }
                            }
                        }
                    }
                }

                // ── Key/mouse field ───────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: !root._isMouseMode
                    StyledText {
                        text: Translation.tr("Key")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        Layout.preferredWidth: 60
                    }
                    MaterialTextField {
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("e.g. Q, Return, F1")
                        text: root._key
                        onTextEdited: root._key = text
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: root._isMouseMode
                    StyledText {
                        text: Translation.tr("Button")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        Layout.preferredWidth: 60
                    }
                    StyledComboBox {
                        id: mouseBtnCombo
                        Layout.fillWidth: true
                        textRole: "label"
                        valueRole: "value"
                        property var presets: root.dispatchers ? root.dispatchers.mouseButtonPresets : []
                        model: presets
                        onActivated: (idx) => {
                            if (idx >= 0 && idx < presets.length) root._mouseButton = presets[idx].value
                        }
                        currentIndex: {
                            for (let i = 0; i < presets.length; i++)
                                if (presets[i].value === root._mouseButton) return i
                            return -1
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Appearance.colors.colOutlineVariant; opacity: 0.5 }

                // ── Action category & dispatcher ─────────────────────────────
                StyledText {
                    text: Translation.tr("Action")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: !root._isMouseMode
                    StyledText { text: Translation.tr("Category"); Layout.preferredWidth: 90; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small }
                    StyledComboBox {
                        id: categoryCombo
                        Layout.fillWidth: true
                        textRole: "label"
                        valueRole: "id"
                        property var visibleCats: {
                            if (!root.dispatchers) return []
                            return root.dispatchers.categories.filter(c => c.id !== "advanced" && c.id !== "mouse_button")
                        }
                        model: visibleCats
                        currentIndex: {
                            for (let i = 0; i < visibleCats.length; i++)
                                if (visibleCats[i].id === root._categoryId) return i
                            return 0
                        }
                        onActivated: (idx) => {
                            if (idx >= 0 && idx < visibleCats.length) {
                                const cat = visibleCats[idx]
                                root._categoryId = cat.id
                                if (cat.dispatchers.length > 0) {
                                    root._dispatcher = cat.dispatchers[0].id
                                    root._args = ""
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StyledText { text: Translation.tr("Action"); Layout.preferredWidth: 90; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small }
                    StyledComboBox {
                        id: actionCombo
                        Layout.fillWidth: true
                        textRole: "label"
                        valueRole: "id"
                        property var visibleDisp: {
                            if (!root.dispatchers) return []
                            if (root._isMouseMode) {
                                return Object.keys(root.dispatchers.bindmDispatchers).map(id => ({ id: id, label: root.dispatchers.bindmDispatchers[id], argType: "none" }))
                            }
                            const cat = root.dispatchers.categoryById(root._categoryId)
                            return cat ? cat.dispatchers : []
                        }
                        model: visibleDisp
                        currentIndex: {
                            for (let i = 0; i < visibleDisp.length; i++)
                                if (visibleDisp[i].id === root._dispatcher) return i
                            return -1
                        }
                        onActivated: (idx) => {
                            if (idx >= 0 && idx < visibleDisp.length) {
                                root._dispatcher = visibleDisp[idx].id
                                root._args = ""
                            }
                        }
                    }
                }

                // ── Dynamic argument widget ──────────────────────────────────
                Loader {
                    Layout.fillWidth: true
                    active: root._argType() !== "none"
                    visible: active
                    sourceComponent: argSwitch
                }

                Component {
                    id: argSwitch
                    Item {
                        implicitHeight: argLoader.item ? argLoader.item.implicitHeight : 0
                        Loader {
                            id: argLoader
                            anchors.fill: parent
                            sourceComponent: {
                                const t = root._argType()
                                if (t === "command")        return cmdComp
                                if (t === "workspace")      return workspaceComp
                                if (t === "fullscreen_mode") return fsComp
                                if (t === "direction")      return dirComp
                                if (t === "group_dir")      return groupDirComp
                                if (t === "dpms")           return dpmsComp
                                if (t === "optional_text")  return optTextComp
                                return textComp
                            }
                        }
                    }
                }

                Component {
                    id: cmdComp
                    RowLayout {
                        spacing: 8
                        StyledText { text: Translation.tr("Command"); Layout.preferredWidth: 90; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small }
                        MaterialTextField {
                            Layout.fillWidth: true
                            placeholderText: "kitty, firefox, …"
                            text: root._args
                            onTextEdited: root._args = text
                        }
                    }
                }

                Component {
                    id: textComp
                    RowLayout {
                        spacing: 8
                        StyledText { text: Translation.tr("Argument"); Layout.preferredWidth: 90; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small }
                        MaterialTextField {
                            Layout.fillWidth: true
                            text: root._args
                            onTextEdited: root._args = text
                        }
                    }
                }

                Component {
                    id: optTextComp
                    RowLayout {
                        spacing: 8
                        StyledText { text: Translation.tr("Name"); Layout.preferredWidth: 90; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small }
                        MaterialTextField {
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("(optional)")
                            text: root._args
                            onTextEdited: root._args = text
                        }
                    }
                }

                Component {
                    id: workspaceComp
                    ColumnLayout {
                        spacing: 6
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            StyledText { text: Translation.tr("Workspace"); Layout.preferredWidth: 90; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small }
                            StyledComboBox {
                                Layout.fillWidth: true
                                textRole: "label"
                                valueRole: "value"
                                property var presets: root.dispatchers ? root.dispatchers.workspacePresets : []
                                model: presets
                                currentIndex: {
                                    for (let i = 0; i < presets.length; i++)
                                        if (presets[i].value === root._args) return i
                                    return -1
                                }
                                onActivated: (idx) => {
                                    if (idx >= 0 && idx < presets.length) root._args = presets[idx].value
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            StyledText { text: Translation.tr("Custom"); Layout.preferredWidth: 90; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small }
                            MaterialTextField {
                                Layout.fillWidth: true
                                placeholderText: Translation.tr("Override preset")
                                text: root._args
                                onTextEdited: root._args = text
                            }
                        }
                    }
                }

                Component {
                    id: fsComp
                    RowLayout {
                        spacing: 8
                        StyledText { text: Translation.tr("Mode"); Layout.preferredWidth: 90; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small }
                        StyledComboBox {
                            Layout.fillWidth: true
                            textRole: "label"
                            valueRole: "value"
                            property var modes: root.dispatchers ? root.dispatchers.fullscreenModes : []
                            model: modes
                            currentIndex: {
                                for (let i = 0; i < modes.length; i++)
                                    if (modes[i].value === root._args) return i
                                return 0
                            }
                            onActivated: (idx) => { if (idx >= 0 && idx < modes.length) root._args = modes[idx].value }
                        }
                    }
                }

                Component {
                    id: dirComp
                    RowLayout {
                        spacing: 6
                        StyledText { text: Translation.tr("Direction"); Layout.preferredWidth: 90; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small }
                        Repeater {
                            model: root.dispatchers ? root.dispatchers.directionChoices : []
                            delegate: Rectangle {
                                required property var modelData
                                implicitWidth: 36
                                implicitHeight: 36
                                radius: Appearance.rounding.full
                                readonly property bool active: modelData.value === root._args
                                color: active ? Appearance.colors.colPrimary
                                              : (dirArea.containsMouse ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer2)
                                border.width: 1
                                border.color: active ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                                Behavior on color { ColorAnimation { duration: 100 } }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    iconSize: 18
                                    color: parent.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                                }
                                MouseArea {
                                    id: dirArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root._args = modelData.value
                                }
                                StyledToolTip { text: modelData.label }
                            }
                        }
                    }
                }

                Component {
                    id: groupDirComp
                    RowLayout {
                        spacing: 8
                        StyledText { text: Translation.tr("Direction"); Layout.preferredWidth: 90; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small }
                        StyledComboBox {
                            Layout.fillWidth: true
                            textRole: "label"
                            valueRole: "value"
                            property var choices: root.dispatchers ? root.dispatchers.groupDirChoices : []
                            model: choices
                            currentIndex: {
                                for (let i = 0; i < choices.length; i++)
                                    if (choices[i].value === root._args) return i
                                return 0
                            }
                            onActivated: (idx) => { if (idx >= 0 && idx < choices.length) root._args = choices[idx].value }
                        }
                    }
                }

                Component {
                    id: dpmsComp
                    RowLayout {
                        spacing: 8
                        StyledText { text: Translation.tr("Action"); Layout.preferredWidth: 90; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small }
                        StyledComboBox {
                            Layout.fillWidth: true
                            textRole: "label"
                            valueRole: "value"
                            property var choices: root.dispatchers ? root.dispatchers.dpmsChoices : []
                            model: choices
                            currentIndex: {
                                for (let i = 0; i < choices.length; i++)
                                    if (choices[i].value === root._args) return i
                                return 0
                            }
                            onActivated: (idx) => { if (idx >= 0 && idx < choices.length) root._args = choices[idx].value }
                        }
                    }
                }

                // ── Bind type ────────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: !root._isMouseMode
                    StyledText { text: Translation.tr("Type"); Layout.preferredWidth: 90; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.small }
                    StyledComboBox {
                        Layout.fillWidth: true
                        textRole: "label"
                        valueRole: "id"
                        property var types: root.dispatchers ? root.dispatchers.bindTypes.filter(t => t.id !== "bindm") : []
                        model: types
                        currentIndex: {
                            for (let i = 0; i < types.length; i++)
                                if (types[i].id === root._bindType) return i
                            return 0
                        }
                        onActivated: (idx) => { if (idx >= 0 && idx < types.length) root._bindType = types[idx].id }
                    }
                }

                // ── Conflict warning ─────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: warnText.implicitHeight + 16
                    visible: root._conflictMessage().length > 0
                    radius: Appearance.rounding.normal
                    color: Qt.rgba(Appearance.colors.colError.r, Appearance.colors.colError.g, Appearance.colors.colError.b, 0.12)
                    border.width: 1
                    border.color: Appearance.colors.colError
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8
                        MaterialSymbol { text: "warning"; iconSize: 18; color: Appearance.colors.colError }
                        StyledText {
                            id: warnText
                            Layout.fillWidth: true
                            text: root._conflictMessage()
                            color: Appearance.colors.colError
                            font.pixelSize: Appearance.font.pixelSize.small
                            wrapMode: Text.Wrap
                        }
                    }
                }

                // ── Action buttons ───────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: { root.show = false; root.dismissed() }
                    }
                    DialogButton {
                        buttonText: root.mode === "override" ? Translation.tr("Override") : Translation.tr("Apply")
                        enabled: root._canApply()
                        colText: enabled ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        onClicked: root._doApply()
                    }
                }
            }
        }
    }
}
