import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    Layout.fillWidth: true
    implicitHeight: mainColumn.implicitHeight

    readonly property var sectionIds: ["left", "center", "right"]
    readonly property var moduleCatalog: [
        { id: "sidebarButton", name: Translation.tr("Sidebar button"),    icon: "left_panel_open" },
        { id: "activeWindow",  name: Translation.tr("Window title"),      icon: "select_window" },
        { id: "resources",     name: Translation.tr("System resources"),  icon: "monitor_heart" },
        { id: "media",         name: Translation.tr("Media"),             icon: "music_note" },
        { id: "workspaces",    name: Translation.tr("Workspaces"),        icon: "workspaces" },
        { id: "clock",         name: Translation.tr("Clock & date"),      icon: "schedule" },
        { id: "utilButtons",   name: Translation.tr("Utility buttons"),   icon: "widgets" },
        { id: "battery",       name: Translation.tr("Battery"),           icon: "battery_full" },
        { id: "indicators",    name: Translation.tr("Status indicators"), icon: "notifications" },
        { id: "volume",        name: Translation.tr("Volume icon"),       icon: "volume_up" },
        { id: "tray",          name: Translation.tr("System tray"),       icon: "shelf_auto_hide" },
        { id: "timers",        name: Translation.tr("Timers"),            icon: "timer" },
        { id: "weather",       name: Translation.tr("Weather"),           icon: "cloud" },
        { id: "releaseUpdates", name: Translation.tr("Update available"), icon: "system_update_alt" },
    ]

    readonly property real tokenHeight: 35

    // Ids retired from the bar entirely, taken from where the load-time scrub
    // reads them so the editor and that migration cannot come to disagree. The
    // bar renders an unknown id as nothing, so only what was deliberately
    // retired is dropped — unknown ids pass through, though every entry
    // written back is normalized to id + enabled.
    readonly property var retiredModules: Config.retiredBarModules
    // Arranged by the bar rather than the user: the editor hides these
    // while they are placed, preserves their entries in the layout it
    // writes back, and offers the widget again if a layout arrives
    // without it.
    readonly property var barManagedModules: ["sidebarButton"]

    // Widgets with no vertical rendering — hidden from the editor while the bar is vertical.
    readonly property var verticalUnsupported: ["activeWindow", "utilButtons", "weather", "timers", "releaseUpdates"]

    property var dragInfo: null   // { section, gi, wi, id }
    property var dragMeta: null
    property bool dragging: false
    property var dropSlots: []
    property var hoveredSlot: null
    property string mode: Config.options.bar.layoutEditorMode

    // The three sections keep the same names in the config whichever way the
    // bar is turned, but on a bar down the side of the screen they are the top,
    // the middle and the bottom — calling them left and right there tells the
    // user the opposite of where their widgets will end up.
    function sectionLabel(s) {
        if (Config.options.bar.vertical)
            return s === "left" ? Translation.tr("Top") : s === "center" ? Translation.tr("Middle") : Translation.tr("Bottom");
        return s === "left" ? Translation.tr("Left") : s === "center" ? Translation.tr("Center") : Translation.tr("Right");
    }
    function meta(id) {
        for (let i = 0; i < root.moduleCatalog.length; i++)
            if (root.moduleCatalog[i].id === id)
                return root.moduleCatalog[i];
        return { id: id, name: id, icon: "widgets" };
    }
    function widgetsOf(g) {
        return ObjectUtils.layoutGroupWidgets(g)
            .map(w => ({ id: w.id, enabled: w.enabled !== false }))
            .filter(w => root.retiredModules.indexOf(w.id) === -1);
    }
    function widgetHiddenHere(id) {
        if (root.barManagedModules.indexOf(id) !== -1)
            return root.findWidget(id) !== null;
        return Config.options.bar.vertical && root.verticalUnsupported.indexOf(id) !== -1;
    }
    function shownWidgetsOf(g) {
        const ws = root.widgetsOf(g);
        let out = [];
        for (let i = 0; i < ws.length; i++) {
            if (root.widgetHiddenHere(ws[i].id)) continue;
            out.push({ id: ws[i].id, enabled: ws[i].enabled, wi: i, first: false, last: false });
        }
        for (let k = 0; k < out.length; k++) {
            out[k].first = (k === 0);
            out[k].last = (k === out.length - 1);
        }
        return out;
    }
    function groupsOf(s) {
        const a = Config.options.bar.layout[s];
        if (!a) return [];
        return Array.prototype.slice.call(a).map(g => ({ widgets: root.widgetsOf(g) }));
    }
    function commit(s, groups) {
        // Bar-managed entries float to the front of their group: drops index
        // around hidden entries, and without a canonical spot the bar could
        // render one somewhere the editor cannot show.
        for (const g of groups) {
            g.widgets = g.widgets.filter(w => root.barManagedModules.indexOf(w.id) !== -1)
                .concat(g.widgets.filter(w => root.barManagedModules.indexOf(w.id) === -1));
        }
        const cleaned = groups.filter(g => g.widgets.length > 0);
        Config.options.bar.layout[s] = cleaned;
    }
    function findWidget(id) {
        for (let si = 0; si < root.sectionIds.length; si++) {
            const s = root.sectionIds[si];
            const gs = root.groupsOf(s);
            for (let gi = 0; gi < gs.length; gi++) {
                const ws = gs[gi].widgets;
                for (let wi = 0; wi < ws.length; wi++)
                    if (ws[wi].id === id) return { section: s, gi: gi, wi: wi, enabled: ws[wi].enabled };
            }
        }
        return null;
    }
    function isWidgetEnabled(id) {
        const f = root.findWidget(id);
        return f ? f.enabled : false;
    }
    function toggleWidget(id) {
        const f = root.findWidget(id);
        if (f) root.setEnabled(f.section, f.gi, f.wi, !f.enabled);
        else root.addWidget(id);
    }
    function simpleWidgets() {
        return root.moduleCatalog.filter(m => !root.widgetHiddenHere(m.id));
    }
    function setEnabled(s, gi, wi, on) {
        let g = root.groupsOf(s);
        if (!g[gi] || !g[gi].widgets[wi]) return;
        g[gi].widgets[wi].enabled = on;
        root.commit(s, g);
    }
    function placedIds() {
        let ids = [];
        root.sectionIds.forEach(s => root.groupsOf(s).forEach(g => root.widgetsOf(g).forEach(w => ids.push(w.id))));
        return ids;
    }
    function unplaced() {
        const placed = root.placedIds();
        return root.moduleCatalog.filter(m => placed.indexOf(m.id) === -1 && !root.widgetHiddenHere(m.id));
    }
    function addWidget(id) {
        let g = root.groupsOf("center");
        g.push({ widgets: [{ id: id, enabled: true }] });
        root.commit("center", g);
    }
    function resetDefaults() {
        root.sectionIds.forEach(s => root.commit(s, JSON.parse(JSON.stringify(Config.defaultBarLayout[s]))));
    }
    function applyDropTo(target) {
        if (!root.dragInfo || !target) return;
        const from = root.dragInfo;
        let fromGroups = root.groupsOf(from.section);
        if (!fromGroups[from.gi] || !fromGroups[from.gi].widgets[from.wi]) return;
        const entry = fromGroups[from.gi].widgets.splice(from.wi, 1)[0];
        const same = (target.section === from.section);
        let toGroups = same ? fromGroups : root.groupsOf(target.section);
        if (target.newGroup) {
            toGroups.splice(target.newGroupPos, 0, { widgets: [entry] });
        } else {
            let tgi = target.gi;
            let twi = target.wi;
            if (same && target.gi === from.gi && target.wi > from.wi) twi -= 1;
            if (!toGroups[tgi]) toGroups.push({ widgets: [entry] });
            else toGroups[tgi].widgets.splice(twi, 0, entry);
        }
        if (same) root.commit(from.section, fromGroups);
        else { root.commit(from.section, fromGroups); root.commit(target.section, toGroups); }
    }

    // ---- drag driven by geometry hit-test (point-to-rect distance) ----
    function nearestSlot(px, py) {
        let best = null;
        let bestD = Infinity;
        for (let i = 0; i < root.dropSlots.length; i++) {
            const s = root.dropSlots[i];
            if (!s || !s.visible) continue;
            const tl = s.mapToItem(root, 0, 0);
            const dx = Math.max(tl.x - px, 0, px - (tl.x + s.width));
            const dy = Math.max(tl.y - py, 0, py - (tl.y + s.height));
            const d = Math.sqrt(dx * dx + dy * dy);
            if (d < bestD) { bestD = d; best = s; }
        }
        return bestD <= 60 ? best : null;
    }
    function startDrag(section, gi, wi, entry, px, py) {
        root.dragInfo = { section: section, gi: gi, wi: wi, id: entry.id };
        root.dragMeta = root.meta(entry.id);
        root.dragging = true;
        root.moveDrag(px, py);
    }
    function moveDrag(px, py) {
        dragProxy.x = px + 12;
        dragProxy.y = py - dragProxy.height / 2;
        root.hoveredSlot = root.nearestSlot(px, py);
    }
    function dropDrag(px, py) {
        const s = root.nearestSlot(px, py);
        if (s && s.target) root.applyDropTo(s.target);
        root.endDrag();
    }
    function endDrag() {
        root.dragging = false;
        root.dragInfo = null;
        root.dragMeta = null;
        root.hoveredSlot = null;
    }

    // ---- drop indicator (vertical between tokens in a pill, horizontal between pills) ----
    component DropLine: Item {
        id: slot
        property bool newGroup: false
        property bool vertical: false
        property bool edge: false
        property var target
        Layout.fillWidth: !vertical
        Layout.fillHeight: vertical
        implicitWidth: vertical ? (edge ? 0 : 6) : 0
        // The vertical ones sit in a Flow, which has no fillHeight to give
        // them, so they carry a token's height of their own.
        implicitHeight: vertical ? root.tokenHeight : (newGroup ? 12 : 8)
        Component.onCompleted: root.dropSlots.push(slot)
        Component.onDestruction: {
            const i = root.dropSlots.indexOf(slot);
            if (i >= 0) root.dropSlots.splice(i, 1);
        }
        Rectangle {
            anchors.centerIn: parent
            width: slot.vertical ? 3 : parent.width
            height: slot.vertical ? parent.height * 0.7 : (slot.newGroup ? 3 : 2)
            radius: 2
            color: Appearance.colors.colPrimary
            opacity: (root.hoveredSlot === slot) ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 80 } }
        }
    }

    // ---- one widget: compact token; click toggles, drag moves ----
    component WidgetToken: Rectangle {
        id: tok
        required property var entry
        required property string section
        required property int gi
        required property int wi
        readonly property var m: root.meta(entry.id)
        readonly property bool isDragSource: root.dragInfo && root.dragInfo.section === section && root.dragInfo.gi === gi && root.dragInfo.wi === wi
        required property bool roundLeft
        required property bool roundRight
        // Set when the group had to break across rows: the tokens stop being
        // segments of one stadium and become chips sharing a container, so
        // they round on every corner instead of only at the ends.
        property bool wrapped: false
        readonly property real endRadius: implicitHeight / 2
        property real leftRadius: tok.wrapped ? Appearance.rounding.small : (tok.roundLeft ? endRadius : Appearance.rounding.unsharpenmore)
        property real rightRadius: tok.wrapped ? Appearance.rounding.small : (tok.roundRight ? endRadius : Appearance.rounding.unsharpenmore)
        Behavior on leftRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on rightRadius { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        implicitWidth: tokRow.implicitWidth + 24
        implicitHeight: root.tokenHeight
        height: implicitHeight
        topLeftRadius: tok.leftRadius
        bottomLeftRadius: tok.leftRadius
        topRightRadius: tok.rightRadius
        bottomRightRadius: tok.rightRadius
        color: entry.enabled
                ? (dragArea.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary)
                : (dragArea.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer)
        opacity: tok.isDragSource ? 0.3 : 1.0
        Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

        property point pressStart: Qt.point(0, 0)
        property bool didDrag: false

        MouseArea {
            id: dragArea
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            onPressed: mouse => {
                tok.pressStart = mapToItem(root, mouse.x, mouse.y);
                tok.didDrag = false;
            }
            onPositionChanged: mouse => {
                if (!pressed) return;
                const p = mapToItem(root, mouse.x, mouse.y);
                if (!tok.didDrag) {
                    if (Math.hypot(p.x - tok.pressStart.x, p.y - tok.pressStart.y) < 6) return;
                    tok.didDrag = true;
                    root.startDrag(tok.section, tok.gi, tok.wi, tok.entry, p.x, p.y);
                }
                root.moveDrag(p.x, p.y);
            }
            onReleased: mouse => {
                if (tok.didDrag) {
                    const p = mapToItem(root, mouse.x, mouse.y);
                    root.dropDrag(p.x, p.y);
                } else {
                    root.setEnabled(tok.section, tok.gi, tok.wi, !tok.entry.enabled);
                }
            }
            onCanceled: { if (tok.didDrag) root.endDrag(); }
        }

        RowLayout {
            id: tokRow
            anchors.centerIn: parent
            spacing: 4
            MaterialSymbol {
                text: tok.m.icon
                iconSize: Appearance.font.pixelSize.larger
                color: tok.entry.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                text: tok.m.name
                font.pixelSize: Appearance.font.pixelSize.small
                color: tok.entry.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
            }
        }
    }

    ColumnLayout {
        id: mainColumn
        width: parent.width
        spacing: 8

        ConfigSelectionArray {
            Layout.fillWidth: false
            currentValue: root.mode
            onSelected: (newValue) => { Config.options.bar.layoutEditorMode = newValue; }
            options: [
                { "displayName": Translation.tr("Simple"), "icon": "tune", "value": "simple" },
                { "displayName": Translation.tr("Custom"), "icon": "dashboard_customize", "value": "custom" },
            ]
        }

        StyledText {
            visible: root.mode === "custom"
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.bottomMargin: 2
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: Config.options.bar.vertical
                ? Translation.tr("Drag widgets to reorder them or move them between the top, middle, and bottom sections. Drop one against another to group them into a pill. Tap a widget to hide it.")
                : Translation.tr("Drag widgets to reorder them or move them between the left, center, and right sections. Drop one against another to group them into a pill. Tap a widget to hide it.")
        }

        Flow {
            visible: root.mode === "simple"
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 6
            Repeater {
                model: root.simpleWidgets()
                delegate: SelectionGroupButton {
                    required property var modelData
                    leftmost: true
                    rightmost: true
                    buttonIcon: modelData.icon
                    buttonText: modelData.name
                    toggled: {
                        Config.options.bar.layout.left;
                        Config.options.bar.layout.center;
                        Config.options.bar.layout.right;
                        return root.isWidgetEnabled(modelData.id);
                    }
                    onClicked: root.toggleWidget(modelData.id)
                }
            }
        }

        ColumnLayout {
            id: customView
            visible: root.mode === "custom"
            Layout.fillWidth: true
            spacing: 8

        Repeater {
            model: root.sectionIds
            delegate: ColumnLayout {
                id: secCol
                required property string modelData
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    text: root.sectionLabel(secCol.modelData)
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colSubtext
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: groupsCol.implicitHeight + 10
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        id: groupsCol
                        x: 6
                        y: 5
                        width: parent.width - 12
                        spacing: 2

                        StyledText {
                            visible: groupRep.count === 0
                            text: Translation.tr("Empty — drag a widget here")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            Layout.margins: 4
                        }

                        DropLine { newGroup: true; target: ({ section: secCol.modelData, newGroup: true, newGroupPos: 0 }) }

                        Repeater {
                            id: groupRep
                            model: Config.options.bar.layout[secCol.modelData]
                            delegate: ColumnLayout {
                                id: gBox
                                required property var modelData
                                required property int index
                                visible: root.shownWidgetsOf(gBox.modelData).length > 0
                                Layout.fillWidth: true
                                spacing: 2

                                Item { // wrapper holds the raised pill + its shadow behind it
                                    id: pillWrapper
                                    Layout.preferredWidth: pillContainer.implicitWidth
                                    Layout.preferredHeight: pillContainer.implicitHeight

                                    StyledRectangularShadow { target: pillContainer }

                                    Rectangle {
                                        id: pillContainer // one group = one raised pill
                                        // A group can hold more widgets than the section box is
                                        // wide, so the row breaks rather than running off the
                                        // end. Adding up what the tokens asked for tells us
                                        // whether it will, without asking the Flow — whose own
                                        // width is what decides the answer.
                                        readonly property real maxWidth: gBox.width
                                        readonly property real rawWidth: {
                                            let w = 0;
                                            for (let i = 0; i < pillFlow.children.length; i++) {
                                                const c = pillFlow.children[i];
                                                if (c && c.visible && c.implicitWidth)
                                                    w += c.implicitWidth;
                                            }
                                            return w;
                                        }
                                        readonly property bool wrapped: rawWidth > maxWidth
                                        readonly property real inset: wrapped ? 4 : 0
                                        implicitWidth: (wrapped ? maxWidth : rawWidth)
                                        implicitHeight: pillFlow.implicitHeight + inset * 2
                                        radius: wrapped ? Appearance.rounding.large : Appearance.rounding.full
                                        color: Appearance.colors.colLayer3

                                        Flow {
                                            id: pillFlow
                                            x: pillContainer.inset
                                            y: pillContainer.inset
                                            width: parent.width - pillContainer.inset * 2
                                            spacing: pillContainer.wrapped ? 4 : 0

                                            DropLine { vertical: true; edge: true; target: ({ section: secCol.modelData, gi: gBox.index, wi: 0, newGroup: false }) }

                                            Repeater {
                                                model: root.shownWidgetsOf(gBox.modelData)
                                                // A layout rather than a Row: the drop line that
                                                // marks the end of a group is deliberately zero
                                                // wide, and a positioner leaves anything that
                                                // narrow sitting at the origin — which would put
                                                // the target for "add to the end of this group"
                                                // on top of the target for its start.
                                                delegate: RowLayout {
                                                    id: tokWrap
                                                    required property var modelData
                                                    required property int index
                                                    spacing: 0
                                                    WidgetToken {
                                                        section: secCol.modelData
                                                        gi: gBox.index
                                                        wi: tokWrap.modelData.wi
                                                        roundLeft: tokWrap.modelData.first
                                                        roundRight: tokWrap.modelData.last
                                                        wrapped: pillContainer.wrapped
                                                        entry: tokWrap.modelData
                                                    }
                                                    DropLine { vertical: true; edge: tokWrap.modelData.last; target: ({ section: secCol.modelData, gi: gBox.index, wi: tokWrap.modelData.wi + 1, newGroup: false }) }
                                                }
                                            }
                                        }
                                    }
                                }

                                DropLine { newGroup: true; target: ({ section: secCol.modelData, newGroup: true, newGroupPos: gBox.index + 1 }) }
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 3
            visible: root.unplaced().length > 0

            StyledText {
                text: Translation.tr("Add a widget")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: Appearance.colors.colSubtext
            }
            Flow {
                Layout.fillWidth: true
                spacing: 5
                Repeater {
                    model: root.unplaced()
                    delegate: RippleButton {
                        id: addChip
                        required property var modelData
                        implicitHeight: 30
                        implicitWidth: addRow.implicitWidth + 18
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: root.addWidget(addChip.modelData.id)
                        contentItem: RowLayout {
                            id: addRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol { text: "add"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                            MaterialSymbol { text: addChip.modelData.icon; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnLayer1 }
                            StyledText { text: addChip.modelData.name; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer1 }
                        }
                    }
                }
            }
        }
        }

        RippleButton {
            Layout.topMargin: 2
            implicitHeight: 30
            implicitWidth: resetRow.implicitWidth + 18
            buttonRadius: Appearance.rounding.small
            colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: root.resetDefaults()
            contentItem: RowLayout {
                id: resetRow
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol { text: "restart_alt"; iconSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
                StyledText { text: Translation.tr("Reset to default layout"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colSubtext }
            }
        }
    }

    // ---- floating drag proxy ----
    Item {
        anchors.fill: parent
        z: 9999

        Rectangle {
            id: dragProxy
            visible: root.dragging
            width: proxyRow.implicitWidth + 18
            height: 28
            radius: Appearance.rounding.small
            color: Appearance.colors.colSecondaryContainer
            border.width: 1
            border.color: Appearance.colors.colPrimary

            RowLayout {
                id: proxyRow
                anchors.centerIn: parent
                spacing: 4
                MaterialSymbol {
                    text: root.dragMeta ? root.dragMeta.icon : ""
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
                StyledText {
                    text: root.dragMeta ? root.dragMeta.name : ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }
    }
}
