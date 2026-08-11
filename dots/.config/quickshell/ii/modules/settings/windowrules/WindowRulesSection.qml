import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF
import qs.modules.common.widgets

ContentSection {
    id: root
    icon: "rule"
    title: Translation.tr("Window rules")

    // The editor edits JSON and never reads Lua back: windowrules.py compiles
    // the whole list into its own generated file on every save, so rules kept
    // by hand elsewhere in the config stay invisible here and untouched.
    readonly property string rulesScript: `${CF.FileUtils.trimFileProtocol(Directories.config)}/quickshell/ii/scripts/hyprland/windowrules.py`
    readonly property string rulesJson: `${CF.FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprland/userrules.json`
    readonly property string rulesLua: `${CF.FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprland/userrules.lua`

    property var rules: []
    property var openWindows: []

    // -1 while the editor is closed; otherwise the index being edited, with
    // rules.length meaning a rule that doesn't exist yet.
    property int editIndex: -1
    readonly property bool editorOpen: editIndex >= 0

    // The editor's working copy, one field per widget so bindings notify.
    property string dName: ""
    property string dClass: ""
    property string dTitle: ""
    property bool dEnabled: true
    property bool dOpacityOn: false
    property real dOpacity: 0.9
    property bool dNoBlur: false
    property bool dFloat: false
    property bool dSizeOn: false
    property int dSizeW: 900
    property int dSizeH: 600
    property bool dCenter: false
    property bool dWorkspaceOn: false
    property int dWorkspaceNum: 1
    property bool dWorkspaceSilent: false
    property bool dPin: false
    property bool dFullscreen: false
    property bool dMaximize: false
    property bool dNoBorder: false
    property bool dNoShadow: false
    property bool dNoRounding: false
    property bool dNoDim: false
    property bool dNoAnim: false
    property bool dTearing: false
    property bool dKeepAspect: false
    property string dIdleInhibit: ""
    property var dCustom: []
    // Match keys and effects a hand-edited or theme-supplied rule can hold that
    // this editor has no widget for (initialClass, xwayland, tile, …). Stashed
    // on open so saving a rule doesn't quietly drop what it didn't show.
    property var dExtraMatch: ({})
    property var dExtraEffects: ({})

    readonly property var editorMatchKeys: ["class", "title"]
    readonly property var editorEffectKeys: [
        "opacity", "noBlur", "float", "size", "center", "workspace", "pin",
        "fullscreen", "maximize", "borderSize", "noShadow", "rounding", "noDim",
        "noAnim", "tearing", "keepAspect", "idleInhibit"]

    readonly property var idleInhibitOptions: [
        { displayName: Translation.tr("Allow sleep"), value: "" },
        { displayName: Translation.tr("Awake while focused"), value: "focus" },
        { displayName: Translation.tr("Awake while fullscreen"), value: "fullscreen" },
        { displayName: Translation.tr("Always awake"), value: "always" },
    ]

    // What the typed pattern catches among the windows open right now — the
    // feedback that saves the user from finding out at next launch that the
    // pattern never matched anything.
    // state: "blank" (nothing typed) | "nopreview" (JS can't compile the
    // pattern) | "matches" (list is what it catches now). Hyprland matches with
    // RE2, not JS regex, so a pattern JS rejects is not necessarily invalid —
    // it only means the preview can't run, never that the rule can't be saved.
    readonly property var liveMatch: {
        if (!root.editorOpen)
            return { state: "blank", list: [] };
        let rc = null, rt = null;
        try {
            if (root.dClass.length > 0) rc = new RegExp(root.dClass);
            if (root.dTitle.length > 0) rt = new RegExp(root.dTitle);
        } catch (e) {
            return { state: "nopreview", list: [] };
        }
        if (!rc && !rt)
            return { state: "blank", list: [] };
        const list = root.openWindows.filter(w =>
            (!rc || rc.test(w.class)) && (!rt || rt.test(w.title)));
        return { state: "matches", list: list };
    }

    readonly property bool draftSaveable: (root.dClass.length > 0 || root.dTitle.length > 0)
        && (root.dOpacityOn || root.dNoBlur || root.dFloat || root.dWorkspaceOn
            || root.dPin || root.dFullscreen || root.dMaximize
            || root.dNoBorder || root.dNoShadow || root.dNoRounding || root.dNoDim
            || root.dNoAnim || root.dTearing || root.dKeepAspect
            || root.dIdleInhibit.length > 0
            || root.dCustom.some(c => c.field.length > 0 && c.value.length > 0))

    function exactPattern(text) {
        return "^(" + text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + ")$";
    }

    // ^(kitty)$ reads as noise on a card; show the plain name when the
    // pattern is just an anchored literal, the raw pattern otherwise.
    function prettyPattern(pattern) {
        const simple = pattern.match(/^\^\(((?:[^()\\|]|\\.)+)\)\$$/);
        return simple ? simple[1].replace(/\\(.)/g, "$1") : pattern;
    }

    function matchSummary(rule) {
        const m = rule.match || {};
        const bits = [];
        if (m.class) bits.push(prettyPattern(m.class));
        if (m.title) bits.push("“" + prettyPattern(m.title) + "”");
        return bits.join(" — ") || "?";
    }

    function effectsSummary(rule) {
        const e = rule.effects || {};
        const parts = [];
        if (e.opacity !== undefined) parts.push(Translation.tr("%1% opacity").arg(Math.round(e.opacity * 100)));
        if (e.noBlur) parts.push(Translation.tr("no frost"));
        if (e.float) parts.push(Translation.tr("floating"));
        if (e.size) parts.push(e.size[0] + "×" + e.size[1]);
        if (e.center) parts.push(Translation.tr("centered"));
        if (e.workspace !== undefined) parts.push(Translation.tr("workspace %1").arg(e.workspace));
        if (e.pin) parts.push(Translation.tr("pinned"));
        if (e.fullscreen) parts.push(Translation.tr("fullscreen"));
        if (e.maximize) parts.push(Translation.tr("maximized"));
        if (e.borderSize === 0) parts.push(Translation.tr("no border"));
        if (e.noShadow) parts.push(Translation.tr("no shadow"));
        if (e.rounding === 0) parts.push(Translation.tr("square corners"));
        if (e.noDim) parts.push(Translation.tr("never dimmed"));
        if (e.noAnim) parts.push(Translation.tr("no animation"));
        if (e.tearing) parts.push(Translation.tr("tearing"));
        if (e.keepAspect) parts.push(Translation.tr("keeps aspect"));
        if (e.idleInhibit) parts.push(Translation.tr("keeps screen awake"));
        for (const c of rule.custom || []) parts.push(c.field);
        return parts.join(" · ");
    }

    // Closing the editor collapses several hundred pixels of content, which
    // leaves the page parked over whatever slid up into the gap. Ride back to
    // this section so what lands on screen is the rule list — with the rule
    // that was just saved on it. The section's own offset is set by the
    // sections above it, so the target holds still while the space below
    // collapses.
    onEditIndexChanged: if (editIndex < 0) Qt.callLater(root.scrollBackToSection)

    function scrollBackToSection() {
        let flick = root.parent;
        while (flick && flick.contentY === undefined)
            flick = flick.parent;
        if (!flick) return;
        const y = flick.contentItem.mapFromItem(root, 0, 0).y - 12;
        scrollBackAnim.target = flick;
        scrollBackAnim.to = Math.max(0, Math.min(y, flick.contentHeight - flick.height));
        scrollBackAnim.restart();
    }

    NumberAnimation {
        id: scrollBackAnim
        property: "contentY"
        duration: Appearance.animation.elementMove.duration
        easing.type: Appearance.animation.elementMove.type
        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
    }

    function openEditor(index) {
        const rule = index < root.rules.length ? root.rules[index] : null;
        const m = rule?.match ?? {};
        const e = rule?.effects ?? {};
        root.dName = rule?.name ?? "";
        root.dClass = m.class ?? "";
        root.dTitle = m.title ?? "";
        root.dEnabled = rule?.enabled ?? true;
        root.dOpacityOn = e.opacity !== undefined;
        root.dOpacity = e.opacity ?? 0.9;
        root.dNoBlur = e.noBlur === true;
        root.dFloat = e.float === true;
        root.dSizeOn = e.size !== undefined;
        root.dSizeW = e.size?.[0] ?? 900;
        root.dSizeH = e.size?.[1] ?? 600;
        root.dCenter = e.center === true;
        const ws = e.workspace !== undefined ? String(e.workspace) : "";
        root.dWorkspaceOn = ws.length > 0;
        root.dWorkspaceNum = parseInt(ws) || 1;
        root.dWorkspaceSilent = ws.includes("silent");
        root.dPin = e.pin === true;
        root.dFullscreen = e.fullscreen === true;
        root.dMaximize = e.maximize === true;
        root.dNoBorder = e.borderSize === 0;
        root.dNoShadow = e.noShadow === true;
        root.dNoRounding = e.rounding === 0;
        root.dNoDim = e.noDim === true;
        root.dNoAnim = e.noAnim === true;
        root.dTearing = e.tearing === true;
        root.dKeepAspect = e.keepAspect === true;
        root.dIdleInhibit = e.idleInhibit ?? "";
        root.dCustom = (rule?.custom ?? []).map(c => ({ field: c.field, value: c.value }));
        const extraMatch = ({}), extraEffects = ({});
        for (const k in m) if (root.editorMatchKeys.indexOf(k) < 0) extraMatch[k] = m[k];
        for (const k in e) if (root.editorEffectKeys.indexOf(k) < 0) extraEffects[k] = e[k];
        root.dExtraMatch = extraMatch;
        root.dExtraEffects = extraEffects;
        root.editIndex = index;
        windowsProc.running = false;
        windowsProc.running = true;
    }

    function collectDraft() {
        // Start from the fields this editor doesn't surface so an edit keeps
        // them; the widgets below overwrite only what they own.
        const effects = Object.assign({}, root.dExtraEffects);
        if (root.dOpacityOn) effects.opacity = Math.round(root.dOpacity * 100) / 100;
        if (root.dNoBlur) effects.noBlur = true;
        if (root.dFloat) {
            effects.float = true;
            if (root.dSizeOn) effects.size = [root.dSizeW, root.dSizeH];
            if (root.dCenter) effects.center = true;
        }
        if (root.dWorkspaceOn)
            effects.workspace = String(root.dWorkspaceNum) + (root.dWorkspaceSilent ? " silent" : "");
        if (root.dPin) effects.pin = true;
        if (root.dFullscreen) effects.fullscreen = true;
        if (root.dMaximize) effects.maximize = true;
        if (root.dNoBorder) effects.borderSize = 0;
        if (root.dNoShadow) effects.noShadow = true;
        if (root.dNoRounding) effects.rounding = 0;
        if (root.dNoDim) effects.noDim = true;
        if (root.dNoAnim) effects.noAnim = true;
        if (root.dTearing) effects.tearing = true;
        if (root.dKeepAspect) effects.keepAspect = true;
        if (root.dIdleInhibit.length > 0) effects.idleInhibit = root.dIdleInhibit;
        const rule = { name: root.dName, enabled: root.dEnabled,
                       match: Object.assign({}, root.dExtraMatch), effects: effects };
        if (root.dClass.length > 0) rule.match.class = root.dClass;
        if (root.dTitle.length > 0) rule.match.title = root.dTitle;
        const custom = root.dCustom.filter(c => c.field.length > 0 && c.value.length > 0);
        if (custom.length > 0) rule.custom = custom;
        return rule;
    }

    function saveDraft() {
        let next = root.rules.slice();
        next[root.editIndex] = collectDraft();
        root.rules = next;
        root.editIndex = -1;
        root.writeRules();
    }

    function removeRule(index) {
        let next = root.rules.slice();
        next.splice(index, 1);
        root.rules = next;
        root.writeRules();
    }

    function moveRule(index, delta) {
        const target = index + delta;
        if (target < 0 || target >= root.rules.length) return;
        let next = root.rules.slice();
        const carried = next.splice(index, 1)[0];
        next.splice(target, 0, carried);
        root.rules = next;
        root.writeRules();
    }

    function setRuleEnabled(index, enabled) {
        let next = root.rules.slice();
        next[index] = Object.assign({}, next[index], { enabled: enabled });
        root.rules = next;
        root.writeRules();
    }

    function writeRules() {
        writerProc.running = false;
        writerProc.stdinEnabled = true;
        writerProc.running = true;
    }

    Component.onCompleted: {
        rulesReader.running = true;
        windowsProc.running = true;
    }

    // A theme apply may carry its own rule set; re-read once it lands.
    Connections {
        target: Config
        function onThemeApplyInProgressChanged() {
            if (Config.themeApplyInProgress) return;
            rulesReader.running = false;
            rulesReader.running = true;
        }
    }

    Process {
        id: rulesReader
        command: ["python3", root.rulesScript, "read", root.rulesJson]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => rulesReader.buf += data }
        onExited: {
            try {
                root.rules = JSON.parse(rulesReader.buf).rules ?? [];
            } catch (e) {}
        }
    }

    Process {
        id: windowsProc
        command: ["python3", root.rulesScript, "windows"]
        property string buf: ""
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => windowsProc.buf += data }
        onExited: {
            try {
                root.openWindows = JSON.parse(windowsProc.buf) ?? [];
            } catch (e) {}
        }
    }

    Process {
        id: writerProc
        command: ["python3", root.rulesScript, "write", root.rulesJson, root.rulesLua]
        property string buf: ""
        stdout: SplitParser { onRead: data => writerProc.buf += data }
        onRunningChanged: {
            if (!running) return;
            buf = "";
            write(JSON.stringify({ rules: root.rules }) + "\n");
            stdinEnabled = false;
        }
        onExited: {
            // The script refused the list (or died): its JSON on disk is
            // still the last good one, so fall back to that rather than
            // keep showing a state that never landed.
            if (!writerProc.buf.startsWith("OK")) {
                rulesReader.running = false;
                rulesReader.running = true;
            }
        }
    }

    component SmallIconButton: RippleButton {
        id: iconBtn
        property string glyph
        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: iconBtn.glyph
            iconSize: 20
            opacity: iconBtn.enabled ? 1 : 0.35
            color: Appearance.colors.colOnLayer1
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        text: Translation.tr("Teach specific apps how to open: where they land, how they look, what they're allowed to do. Later rules win when two disagree.")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        wrapMode: Text.WordWrap
    }

    StyledText {
        visible: root.rules.length === 0 && !root.editorOpen
        Layout.fillWidth: true
        Layout.margins: 8
        text: Translation.tr("No rules yet.")
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: root.rules.length
            delegate: Rectangle {
                id: ruleCard
                required property int index
                readonly property var rule: root.rules[index]
                Layout.fillWidth: true
                color: Appearance.colors.colLayer1
                radius: Appearance.rounding.normal
                implicitHeight: cardRow.implicitHeight + 16
                opacity: rule.enabled ? 1 : 0.6

                RowLayout {
                    id: cardRow
                    anchors {
                        fill: parent
                        leftMargin: 12
                        rightMargin: 8
                        topMargin: 8
                        bottomMargin: 8
                    }
                    spacing: 8

                    StyledSwitch {
                        checked: ruleCard.rule.enabled
                        onToggled: root.setRuleEnabled(ruleCard.index, checked)
                        StyledToolTip { text: Translation.tr("Rule stays on the list but stops applying while off") }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: (ruleCard.rule.name?.length > 0)
                                ? ruleCard.rule.name
                                : root.matchSummary(ruleCard.rule)
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: ((ruleCard.rule.name?.length > 0)
                                ? root.matchSummary(ruleCard.rule) + "  →  "
                                : "") + root.effectsSummary(ruleCard.rule)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }
                    }

                    SmallIconButton {
                        glyph: "keyboard_arrow_up"
                        enabled: ruleCard.index > 0 && !root.editorOpen
                        onClicked: root.moveRule(ruleCard.index, -1)
                    }
                    SmallIconButton {
                        glyph: "keyboard_arrow_down"
                        enabled: ruleCard.index < root.rules.length - 1 && !root.editorOpen
                        onClicked: root.moveRule(ruleCard.index, 1)
                    }
                    SmallIconButton {
                        glyph: "edit"
                        enabled: !root.editorOpen
                        onClicked: root.openEditor(ruleCard.index)
                    }
                    SmallIconButton {
                        glyph: "delete"
                        enabled: !root.editorOpen
                        onClicked: root.removeRule(ruleCard.index)
                    }
                }
            }
        }
    }

    // ── The editor ────────────────────────────────────────────────────────
    // A once-clicked switch keeps its own state over a binding, so a used
    // editor stops following the draft reset. Built fresh on every open and
    // torn down on close, nothing stale survives into the next rule.
    Loader {
        active: root.editorOpen
        visible: active
        Layout.fillWidth: true
        Layout.topMargin: 4

        sourceComponent: Rectangle {
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.normal
            implicitHeight: editorColumn.implicitHeight + 24

            ColumnLayout {
                id: editorColumn
                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 8

                ContentSubsectionLabel {
                    text: Translation.tr("Which windows")
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StyledComboBox {
                        id: windowPicker
                        Layout.fillWidth: true
                        textRole: "displayName"
                        model: [{ displayName: Translation.tr("Pick an open window…"), cls: "" }]
                            .concat(root.openWindows.map(w => ({
                                displayName: w.class + "  —  " + w.title,
                                cls: w.class
                            })))
                        currentIndex: 0
                        onActivated: index => {
                            const cls = model[index]?.cls ?? "";
                            if (cls.length > 0)
                                root.dClass = root.exactPattern(cls);
                            currentIndex = 0;
                        }
                    }
                    SmallIconButton {
                        glyph: "refresh"
                        onClicked: {
                            windowsProc.running = false;
                            windowsProc.running = true;
                        }
                        StyledToolTip { text: Translation.tr("Re-list the windows open right now") }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialTextField {
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("App class (regex)")
                        text: root.dClass
                        onTextChanged: root.dClass = text
                    }
                    MaterialTextField {
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Window title (regex, optional)")
                        text: root.dTitle
                        onTextChanged: root.dTitle = text
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 2
                    spacing: 6
                    MaterialSymbol {
                        text: root.liveMatch.state === "nopreview" ? "info"
                            : root.liveMatch.state === "blank" ? "search"
                            : root.liveMatch.list.length > 0 ? "check_circle" : "visibility_off"
                        iconSize: Appearance.font.pixelSize.normal
                        color: root.liveMatch.state === "matches" && root.liveMatch.list.length > 0
                            ? Appearance.m3colors.m3primary : Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.liveMatch.state === "nopreview" ? Translation.tr("Can't preview this pattern here, but it will still be saved")
                            : root.liveMatch.state === "blank" ? Translation.tr("Pick a window or type a pattern to see what it catches")
                            : root.liveMatch.list.length === 0 ? Translation.tr("Matches none of the windows open right now")
                            : Translation.tr("Matches now: %1").arg(root.liveMatch.list.map(w => w.class).filter((c, i, a) => a.indexOf(c) === i).join(", "))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }

                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Rule name (optional)")
                    text: root.dName
                    onTextChanged: root.dName = text
                }

                ContentSubsectionLabel {
                    text: Translation.tr("Placement")
                }

                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        text: Translation.tr("Open floating")
                        checked: root.dFloat
                        onCheckedChanged: root.dFloat = checked
                    }
                    ConfigSwitch {
                        text: Translation.tr("Open on a workspace")
                        checked: root.dWorkspaceOn
                        onCheckedChanged: root.dWorkspaceOn = checked
                    }
                }

                ConfigRow {
                    visible: root.dFloat
                    uniform: true
                    ConfigSwitch {
                        text: Translation.tr("At a set size")
                        checked: root.dSizeOn
                        onCheckedChanged: root.dSizeOn = checked
                    }
                    ConfigSwitch {
                        text: Translation.tr("Centered")
                        checked: root.dCenter
                        onCheckedChanged: root.dCenter = checked
                    }
                }

                ConfigRow {
                    visible: root.dFloat && root.dSizeOn
                    ConfigSpinBox {
                        text: Translation.tr("Width")
                        value: root.dSizeW
                        from: 100
                        to: 10000
                        stepSize: 50
                        onValueChanged: root.dSizeW = value
                    }
                    ConfigSpinBox {
                        text: Translation.tr("Height")
                        value: root.dSizeH
                        from: 100
                        to: 10000
                        stepSize: 50
                        onValueChanged: root.dSizeH = value
                    }
                }

                ConfigRow {
                    visible: root.dWorkspaceOn
                    ConfigSpinBox {
                        text: Translation.tr("Workspace")
                        value: root.dWorkspaceNum
                        from: 1
                        to: 10
                        stepSize: 1
                        onValueChanged: root.dWorkspaceNum = value
                    }
                    ConfigSwitch {
                        text: Translation.tr("Without following it there")
                        checked: root.dWorkspaceSilent
                        onCheckedChanged: root.dWorkspaceSilent = checked
                    }
                }

                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        text: Translation.tr("Pin above everything")
                        checked: root.dPin
                        onCheckedChanged: root.dPin = checked
                    }
                    ConfigSwitch {
                        text: Translation.tr("Open fullscreen")
                        checked: root.dFullscreen
                        onCheckedChanged: root.dFullscreen = checked
                    }
                }

                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        text: Translation.tr("Open maximized")
                        checked: root.dMaximize
                        onCheckedChanged: root.dMaximize = checked
                    }
                    Item { Layout.fillWidth: true }
                }

                ContentSubsectionLabel {
                    text: Translation.tr("Appearance")
                }

                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        text: Translation.tr("Set transparency")
                        checked: root.dOpacityOn
                        onCheckedChanged: root.dOpacityOn = checked
                    }
                    ConfigSwitch {
                        text: Translation.tr("No frost behind it")
                        checked: root.dNoBlur
                        onCheckedChanged: root.dNoBlur = checked
                    }
                }

                ConfigSlider {
                    visible: root.dOpacityOn
                    text: Translation.tr("Opacity")
                    from: 0.1
                    to: 1.0
                    value: root.dOpacity
                    onMoved: root.dOpacity = value
                }

                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        text: Translation.tr("No border")
                        checked: root.dNoBorder
                        onCheckedChanged: root.dNoBorder = checked
                    }
                    ConfigSwitch {
                        text: Translation.tr("No shadow")
                        checked: root.dNoShadow
                        onCheckedChanged: root.dNoShadow = checked
                    }
                }

                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        text: Translation.tr("Square corners")
                        checked: root.dNoRounding
                        onCheckedChanged: root.dNoRounding = checked
                    }
                    ConfigSwitch {
                        text: Translation.tr("Never dim it")
                        checked: root.dNoDim
                        onCheckedChanged: root.dNoDim = checked
                    }
                }

                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        text: Translation.tr("Skip open/close animations")
                        checked: root.dNoAnim
                        onCheckedChanged: root.dNoAnim = checked
                    }
                    Item { Layout.fillWidth: true }
                }

                ContentSubsectionLabel {
                    text: Translation.tr("Behavior")
                }

                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        text: Translation.tr("Allow tearing (games)")
                        checked: root.dTearing
                        onCheckedChanged: root.dTearing = checked
                    }
                    ConfigSwitch {
                        text: Translation.tr("Keep aspect ratio")
                        checked: root.dKeepAspect
                        onCheckedChanged: root.dKeepAspect = checked
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    StyledText {
                        text: Translation.tr("Screen sleep")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledComboBox {
                        Layout.preferredWidth: 240
                        textRole: "displayName"
                        model: root.idleInhibitOptions
                        currentIndex: Math.max(0, root.idleInhibitOptions.findIndex(o => o.value === root.dIdleInhibit))
                        onActivated: index => root.dIdleInhibit = root.idleInhibitOptions[index].value
                    }
                    Item { Layout.fillWidth: true }
                }

                ContentSubsectionLabel {
                    text: Translation.tr("Custom effects")
                }

                Repeater {
                    model: root.dCustom.length
                    delegate: RowLayout {
                        id: customRow
                        required property int index
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialTextField {
                            Layout.preferredWidth: 220
                            placeholderText: Translation.tr("Effect (e.g. xray)")
                            text: root.dCustom[customRow.index].field
                            onTextChanged: root.dCustom[customRow.index].field = text
                        }
                        MaterialTextField {
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Value (e.g. true)")
                            text: root.dCustom[customRow.index].value
                            onTextChanged: root.dCustom[customRow.index].value = text
                        }
                        SmallIconButton {
                            glyph: "close"
                            onClicked: {
                                let next = root.dCustom.slice();
                                next.splice(customRow.index, 1);
                                root.dCustom = next;
                            }
                        }
                    }
                }

                RippleButtonWithIcon {
                    materialIcon: "add"
                    mainText: Translation.tr("Add a custom effect")
                    onClicked: root.dCustom = root.dCustom.concat([{ field: "", value: "" }])
                    StyledToolTip { text: Translation.tr("Any effect name Hyprland knows, for the ones the switches above don't cover") }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    GroupButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: root.editIndex = -1
                    }
                    GroupButton {
                        id: saveButton
                        buttonText: Translation.tr("Save rule")
                        enabled: root.draftSaveable
                        toggled: true
                        onClicked: root.saveDraft()
                        // The default contentItem keeps the on-dark text color,
                        // which disappears against the toggled (primary) fill.
                        contentItem: StyledText {
                            text: saveButton.buttonText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: saveButton.enabled ? Appearance.colors.colOnPrimary
                                                      : Appearance.colors.colOnLayer1
                            opacity: saveButton.enabled ? 1 : 0.4
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        visible: !root.editorOpen
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.fillWidth: true
        RippleButtonWithIcon {
            materialIcon: "add"
            mainText: Translation.tr("Add rule")
            onClicked: root.openEditor(root.rules.length)
        }
        Item { Layout.fillWidth: true }
        RippleButtonWithIcon {
            id: removeAllButton
            visible: root.rules.length > 0
            property bool armed: false
            materialIcon: "delete_sweep"
            mainText: removeAllButton.armed
                ? Translation.tr("Click again to remove them all")
                : Translation.tr("Remove all rules")
            onClicked: {
                if (!removeAllButton.armed) {
                    removeAllButton.armed = true;
                    disarmTimer.restart();
                    return;
                }
                removeAllButton.armed = false;
                root.rules = [];
                root.writeRules();
            }
            Timer {
                id: disarmTimer
                interval: 4000
                onTriggered: removeAllButton.armed = false
            }
            StyledToolTip {
                text: Translation.tr("Only the rules made here — anything in your own config files stays")
            }
        }
    }

}
