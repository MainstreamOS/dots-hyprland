pragma ComponentBehavior: Bound
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: root
    property real maxWindowPreviewHeight: 200
    property real maxWindowPreviewWidth: 300
    property real windowControlsHeight: 30
    property real buttonPadding: 5

    property Item clickedButton: null
    property bool previewShow: false
    property bool previewFading: false
    property bool folderPopupShow: false
    property var folderPopupData: null  // {id, name, appIds}
    property bool requestDockShow: previewShow || folderPopupShow || contextMenu.isOpen

    function showPreview(button) {
        hideFolderPopup(); // tear down folder popup first
        clickedButton = button;
        previewFading = false;
        // A fade still in flight belongs to a preview that is gone; left
        // running, its timer would reap the one this click just asked for.
        fadeTimer.stop();
        previewLoader.active = true;
        previewShow = true;
        dismissTimer.restart();
    }
    function hidePreview() {
        // Nothing shown means nothing to fade, and a timer armed for a
        // preview that never existed would reap the next one instead.
        if (!previewLoader.active) return;
        previewFading = true;
        fadeTimer.restart();
    }

    // Focuses a single window — mirrors what clicking its tile in the
    // preview popup does, including tearing down any preview or folder
    // popup that's currently open, so switching straight to a window never
    // leaves a stale popup anchored to a different button. Shared by the
    // preview's per-window buttons and by DockAppButton's single-window
    // fast path (see its onClicked for why 1 window skips the preview).
    function focusToplevel(tl) {
        // Handing focus to a window is a deliberate exit from whatever the
        // shared grab was holding open. Left armed, the grab's whitelist
        // collapses with the sidebar's focus and it spends the user's next
        // click on the bar clearing itself.
        GlobalFocusGrab.dismiss();
        hideFolderPopup();
        hidePreview();
        const addr = tl?.HyprlandToplevel?.address;
        if (!addr) {
            tl?.activate();
            return;
        }
        // Address-targeted dispatch avoids Wayland activate() aliasing
        // across multiple instances of the same app.
        const fullAddr = `0x${addr}`;
        const win = HyprlandData.windowByAddress[fullAddr];
        const wsName = win?.workspace?.name ?? "";
        const wsId = win?.workspace?.id ?? 0;
        const isSpecial = wsName.startsWith("special") || wsId < 0;
        if (!isSpecial) {
            Hyprland.dispatch(
                `hl.dsp.focus({window = "address:${fullAddr}"})`
            );
            if (win?.floating) raiseToplevel(fullAddr);
            return;
        }
        // Pull off special, mirroring the hyprbars title-bar special-toggle.
        Hyprland.dispatch(
            `(function() ` +
                `local m = hl.get_active_monitor(); ` +
                `local t = m and m.active_workspace; ` +
                `if t then ` +
                    `return hl.dsp.window.move({workspace = tostring(t.id), follow = true, window = "address:${fullAddr}"}) ` +
                `end ` +
            `end)()`
        );
        // Scratchpad windows are floating by convention, but check rather
        // than assume — win was read before the move, and floating state
        // isn't something a workspace move changes.
        if (win?.floating) raiseToplevel(fullAddr);
    }

    // focus only moves keyboard/input focus — it doesn't restack a floating
    // window above its floating siblings the way a direct mouse click does,
    // so a covered floating window stays covered until it's explicitly
    // raised to the top of the floating z-order. Callers gate this on
    // win.floating themselves since tiled windows have no z-order to alter.
    function raiseToplevel(fullAddr) {
        Hyprland.dispatch(
            `hl.dsp.window.alter_zorder({mode = "top", window = "address:${fullAddr}"})`
        );
    }

    property bool folderPopupStartRenaming: false

    function showFolderPopup(button, folderData, startRenaming) {
        // Tear down preview first — two PopupWindows crash Quickshell
        dismissTimer.stop();
        fadeTimer.stop();
        previewShow = false;
        previewFading = false;
        previewLoader.active = false;

        clickedButton = button;
        folderPopupData = folderData;
        folderPopupStartRenaming = startRenaming || false;
        folderPopupLoader.active = true;
        folderPopupShow = true;
    }
    function hideFolderPopup() {
        folderPopupShow = false;
        folderPopupLoader.active = false;
        folderPopupData = null;
    }

    // Drag-to-reorder state
    property bool dragging: false
    property bool _reordering: false
    property bool _suppressTranslateAnim: false
    property int dragSourceIndex: -1
    // Main-axis scalars: X on a horizontal dock, Y on a vertical one.
    property real dragCursorPos: 0
    property real dragStartCursorPos: 0
    property real slotSize: 0
    property int dragTargetIndex: {
        if (!dragging || slotSize <= 0) return dragSourceIndex;
        var delta = dragCursorPos - dragStartCursorPos;
        var slots = Math.round(delta / slotSize);
        var pinnedCount = Config.options.dock.pinnedApps.length;
        return Math.max(0, Math.min(dragSourceIndex + slots, pinnedCount - 1));
    }

    // Timer to re-enable animations after the model has fully settled.
    // Qt.callLater can race with deferred model updates, causing transitions
    // to fire on items that are still being added/removed (the flicker).
    Timer {
        id: reorderSettleTimer
        interval: 50
        onTriggered: {
            root._reordering = false;
            root._suppressTranslateAnim = false;
        }
    }

    function finishDrag() {
        _suppressTranslateAnim = true;
        if (dragging && dragSourceIndex !== dragTargetIndex) {
            _reordering = true;
            TaskbarApps.reorderPinned(dragSourceIndex, dragTargetIndex);
            // Process the model change synchronously while transitions are disabled
            listViewRef.forceLayout();
        }
        dragging = false;
        dragSourceIndex = -1;
        dragCursorPos = 0;
        dragStartCursorPos = 0;
        // Allow the ListView to fully process delegate changes before
        // re-enabling transitions, preventing the opacity-flicker on add.
        reorderSettleTimer.restart();
    }

    function cancelDrag() {
        _suppressTranslateAnim = true;
        dragging = false;
        dragSourceIndex = -1;
        dragCursorPos = 0;
        dragStartCursorPos = 0;
        Qt.callLater(function() { _suppressTranslateAnim = false; });
    }

    function openContextMenu(button, appToplevelData) {
        // Immediately tear down any popup — two PopupWindows crash Quickshell.
        dismissTimer.stop();
        fadeTimer.stop();
        previewShow = false;
        previewFading = false;
        previewLoader.active = false;
        hideFolderPopup();
        clickedButton = null;
        contextMenu.open(button, appToplevelData);
    }

    property alias listViewRef: listView
    property real mousePosInList: -9999
    property bool listHovered: false
    property real maxScale: Appearance.sizes.dockMaxScale
    property real sigma: 60

    // Which button the pointer is actually over. Asked of the same mouse
    // position magnification uses, because the per-button hover areas never
    // fire: listHoverArea below fills the whole list and sits above every
    // delegate, so it takes the hover first. Position and size are along the
    // dock's own axis, the same line mousePosInList runs on.
    function pointerIsOver(itemPos, itemSize) {
        if (!listHovered || previewShow) return false;
        return mousePosInList >= itemPos && mousePosInList < itemPos + itemSize;
    }

    // One dispatch for what hovering does to a button's size, so the three
    // effects read as one decision. The effect is asked first: a mode that
    // grows nothing never reads the mouse, and its bindings stay cold.
    function hoverScaleFor(itemPos, itemSize, isSeparator) {
        const effect = Config.options.dock.hoverEffect;
        if (effect === "off" || !listHovered || previewShow) return 1.0;
        if (effect === "glow")
            return !isSeparator && pointerIsOver(itemPos, itemSize) ? maxScale : 1.0;
        const itemCenter = itemPos + itemSize / 2;
        const dist = itemCenter - mousePosInList;
        return 1.0 + (maxScale - 1.0) * Math.exp(-(dist * dist) / (2 * sigma * sigma));
    }

    // Hover-only overlay — acceptedButtons: Qt.NoButton means it never steals clicks
    // but still receives hover position changes independently of dragEater
    MouseArea {
        id: listHoverArea
        anchors.fill: listView
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        z: 1
        onPositionChanged: mouse => {
            root.mousePosInList = dockRoot.dockVertical ? mouse.y + listView.contentY : mouse.x + listView.contentX;
        }
        onEntered:  root.listHovered = true
        onExited:   root.listHovered = false
    }

    Layout.fillHeight: !dockRoot.dockVertical
    Layout.fillWidth: dockRoot.dockVertical
    Layout.topMargin: dockRoot.dockEdge === "bottom" ? Appearance.sizes.hyprlandGapsOut : 0
    Layout.bottomMargin: dockRoot.dockEdge === "top" ? Appearance.sizes.hyprlandGapsOut : 0
    Layout.leftMargin: dockRoot.dockEdge === "right" ? Appearance.sizes.hyprlandGapsOut : 0
    Layout.rightMargin: dockRoot.dockEdge === "left" ? Appearance.sizes.hyprlandGapsOut : 0
    implicitWidth: dockRoot.dockVertical ? 0 : listView.implicitWidth
    implicitHeight: dockRoot.dockVertical ? listView.implicitHeight : 0

    Timer {
        id: dismissTimer
        interval: 3000
        onTriggered: {
            root.hidePreview();
        }
    }

    Timer {
        id: fadeTimer
        interval: Appearance.animation.elementMoveFast.duration
        onTriggered: {
            root.previewShow = false;
            root.previewFading = false;
            previewLoader.active = false;
            root.clickedButton = null;
        }
    }

    StyledListView {
        id: listView
        spacing: 2
        clip: false
        interactive: false
        animateAppearance: !root._reordering
        orientation: dockRoot.dockVertical ? ListView.Vertical : ListView.Horizontal
        anchors {
            top: dockRoot.dockVertical ? undefined : parent.top
            bottom: dockRoot.dockVertical ? undefined : parent.bottom
            left: dockRoot.dockVertical ? parent.left : undefined
            right: dockRoot.dockVertical ? parent.right : undefined
        }
        implicitWidth: dockRoot.dockVertical ? 0 : contentWidth
        implicitHeight: dockRoot.dockVertical ? contentHeight : 0

        Behavior on implicitWidth {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        model: ScriptModel {
            objectProp: "appId"
            values: TaskbarApps.apps
        }
        delegate: DockAppButton {
            id: delegateButton
            required property var modelData
            required property int index
            appToplevel: modelData
            appListRoot: root
            delegateIndex: {
                // Index within pinnedApps only (not the full list)
                var pinnedApps = Config.options?.dock.pinnedApps ?? [];
                return pinnedApps.findIndex(id => id.toLowerCase() === modelData.appId.toLowerCase());
            }
            buttonIndex: index

            topInset: dockRoot.dockVertical ? 0 : Appearance.sizes.hyprlandGapsOut + root.buttonPadding
            bottomInset: dockRoot.dockVertical ? 0 : Appearance.sizes.hyprlandGapsOut + root.buttonPadding
            leftInset: dockRoot.dockVertical ? Appearance.sizes.hyprlandGapsOut + root.buttonPadding : 0
            rightInset: dockRoot.dockVertical ? Appearance.sizes.hyprlandGapsOut + root.buttonPadding : 0
            hoverScale: root.hoverScaleFor(dockRoot.dockVertical ? y : x,
                dockRoot.dockVertical ? height : width, isSeparator)
            // Gated on the mode first, so the halo's only consumer is also the
            // only one paying the per-motion arithmetic behind it.
            pointerOver: Config.options.dock.hoverEffect === "glow"
                && root.pointerIsOver(dockRoot.dockVertical ? y : x, dockRoot.dockVertical ? height : width)
        }
    }

    Loader {
        id: previewLoader
        active: false
        sourceComponent: PopupWindow {
            id: previewPopup
            visible: true

            anchor {
                item: root.clickedButton
                gravity: dockRoot.awayEdges
                edges: dockRoot.awayEdges
                // The popup content grows along X whatever the edge, so a
                // vertical dock needs SlideX on top of its cross-axis SlideY
                // or a wide popup runs off the far side of the screen.
                adjustment: dockRoot.dockVertical ? (PopupAdjustment.SlideX | PopupAdjustment.SlideY) : PopupAdjustment.SlideX
            }
            color: "transparent"
            implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

            MouseArea {
                id: popupMouseArea
                anchors.fill: parent
                hoverEnabled: true

                StyledRectangularShadow {
                    target: popupBackground
                    opacity: (root.previewShow && !root.previewFading) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
                Rectangle {
                    id: popupBackground
                    property real padding: 5
                    opacity: (root.previewShow && !root.previewFading) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    clip: true
                    color: Appearance.m3colors.m3surfaceContainer
                    radius: Appearance.rounding.normal
                    // The window is the background plus a shadow margin on
                    // every side, so centering insets it evenly and the
                    // breathing room sits between popup and dock.
                    anchors.centerIn: parent
                    implicitHeight: previewRowLayout.implicitHeight + padding * 2
                    implicitWidth: previewRowLayout.implicitWidth + padding * 2

                    RowLayout {
                        id: previewRowLayout
                        anchors.centerIn: parent
                        Repeater {
                            model: ScriptModel {
                                values: root.clickedButton?.appToplevel?.toplevels ?? []
                            }
                            RippleButton {
                                id: windowButton
                                required property var modelData
                                property bool captureSuppressed: false
                                padding: 0
                                middleClickAction: () => {
                                    windowButton.captureSuppressed = true;
                                    windowButton.modelData?.close();
                                }
                                onClicked: root.focusToplevel(windowButton.modelData)
                                contentItem: ColumnLayout {
                                    implicitWidth: screencopyView.implicitWidth
                                    implicitHeight: screencopyView.implicitHeight

                                    ButtonGroup {
                                        contentWidth: parent.width - anchors.margins * 2
                                        StyledText {
                                            Layout.margins: 5
                                            Layout.fillWidth: true
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            text: windowButton.modelData?.title
                                            elide: Text.ElideRight
                                            color: Appearance.m3colors.m3onSurface
                                        }
                                        GroupButton {
                                            id: closeButton
                                            colBackground: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer)
                                            baseWidth: windowControlsHeight
                                            baseHeight: windowControlsHeight
                                            buttonRadius: Appearance.rounding.full
                                            contentItem: MaterialSymbol {
                                                anchors.centerIn: parent
                                                horizontalAlignment: Text.AlignHCenter
                                                text: "close"
                                                iconSize: Appearance.font.pixelSize.normal
                                                color: Appearance.m3colors.m3onSurface
                                            }
                                            onClicked: {
                                                windowButton.captureSuppressed = true;
                                                root.hidePreview();
                                                windowButton.modelData?.close();
                                            }
                                        }
                                    }
                                    Item {
                                        implicitWidth: screencopyView.implicitWidth
                                        implicitHeight: screencopyView.implicitHeight
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: Rectangle {
                                                width: screencopyView.implicitWidth
                                                height: screencopyView.implicitHeight
                                                radius: Appearance.rounding.small
                                            }
                                        }

                                        ScreencopyView {
                                            id: screencopyView
                                            anchors.fill: parent
                                            captureSource: windowButton.captureSuppressed ? null : windowButton.modelData
                                            live: true
                                            paintCursor: true
                                            constraintSize: Qt.size(root.maxWindowPreviewWidth, root.maxWindowPreviewHeight)
                                            // PQ-to-sRGB tone-mapping when HDR Always On
                                            layer.enabled: GlobalStates.hdrActive
                                            layer.effect: ShaderEffect {
                                                property real sdrPaperWhite: 203.0
                                                fragmentShader: "file://" + Quickshell.env("HOME") + "/.config/quickshell/ii/shaders/pq_to_srgb.frag.qsb"
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

    // ── Folder popup (PopupWindow above clicked folder icon) ──
    Loader {
        id: folderPopupLoader
        active: false
        sourceComponent: PopupWindow {
            id: folderPopup
            visible: true

            anchor {
                item: root.clickedButton
                gravity: dockRoot.awayEdges
                edges: dockRoot.awayEdges
                // The popup content grows along X whatever the edge, so a
                // vertical dock needs SlideX on top of its cross-axis SlideY
                // or a wide popup runs off the far side of the screen.
                adjustment: dockRoot.dockVertical ? (PopupAdjustment.SlideX | PopupAdjustment.SlideY) : PopupAdjustment.SlideX
            }

            HyprlandFocusGrab {
                active: true
                windows: [folderPopup]
                onCleared: root.hideFolderPopup()
            }

            color: "transparent"
            implicitWidth: folderBg.implicitWidth + Appearance.sizes.elevationMargin * 2
            implicitHeight: folderBg.implicitHeight + Appearance.sizes.elevationMargin * 2

            StyledRectangularShadow {
                target: folderBg
                opacity: root.folderPopupShow ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            Rectangle {
                id: folderBg
                property real padding: 12

                opacity: root.folderPopupShow ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                // The window is the background plus a shadow margin on every
                // side, so centering insets it evenly and the breathing room
                // sits between popup and dock.
                anchors.centerIn: parent
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.normal
                implicitWidth: folderColumn.implicitWidth + padding * 2
                implicitHeight: folderColumn.implicitHeight + padding * 2

                ColumnLayout {
                    id: folderColumn
                    anchors {
                        fill: parent
                        margins: parent.padding
                    }
                    spacing: 8

                    // Folder header
                    property bool renaming: root.folderPopupStartRenaming

                    Component.onCompleted: {
                        if (folderColumn.renaming) {
                            folderRenameField.text = root.folderPopupData ? root.folderPopupData.name : "";
                            folderRenameField.forceActiveFocus();
                            folderRenameField.selectAll();
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: "folder"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colPrimary
                        }

                        // Static name
                        StyledText {
                            Layout.fillWidth: true
                            visible: !folderColumn.renaming
                            text: root.folderPopupData ? root.folderPopupData.name : ""
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.m3colors.m3onSurface
                            elide: Text.ElideRight
                        }

                        // Editable name (shown when renaming)
                        TextField {
                            id: folderRenameField
                            Layout.fillWidth: true
                            visible: folderColumn.renaming
                            padding: 4
                            font {
                                family: Appearance.font.family.main
                                pixelSize: Appearance.font.pixelSize.normal
                                weight: Font.Medium
                            }
                            color: Appearance.m3colors.m3onSurface
                            selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                            selectionColor: Appearance.colors.colSecondaryContainer
                            background: Rectangle {
                                radius: Appearance.rounding.verysmall
                                color: "transparent"
                                border.width: 2
                                border.color: folderRenameField.activeFocus
                                    ? Appearance.colors.colPrimary
                                    : Appearance.m3colors.m3outline
                                Behavior on border.color {
                                    ColorAnimation { duration: 150 }
                                }
                            }
                            cursorDelegate: Rectangle {
                                width: 1
                                color: Appearance.colors.colPrimary
                                radius: 1
                            }
                            Keys.onReturnPressed: {
                                const name = folderRenameField.text.trim();
                                if (name.length > 0 && root.folderPopupData) {
                                    AppFolderManager.renameFolder(root.folderPopupData.id, name);
                                    root.folderPopupData = Object.assign({}, root.folderPopupData, { name: name });
                                }
                                folderColumn.renaming = false;
                            }
                            Keys.onEscapePressed: folderColumn.renaming = false
                        }

                        // Confirm button (only visible when renaming)
                        RippleButton {
                            visible: folderColumn.renaming
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: Appearance.rounding.full
                            onClicked: {
                                const name = folderRenameField.text.trim();
                                if (name.length > 0 && root.folderPopupData) {
                                    AppFolderManager.renameFolder(root.folderPopupData.id, name);
                                    root.folderPopupData = Object.assign({}, root.folderPopupData, { name: name });
                                }
                                folderColumn.renaming = false;
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "check"
                                iconSize: Appearance.font.pixelSize.small
                                color: Appearance.m3colors.m3onSurface
                            }
                        }
                    }

                    // Separator
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
                    }

                    // App grid
                    GridLayout {
                        id: folderAppsGrid
                        columns: Math.min(4, folderAppsRepeater.count)
                        columnSpacing: 4
                        rowSpacing: 4

                        Repeater {
                            id: folderAppsRepeater
                            model: {
                                if (!root.folderPopupData || !root.folderPopupData.appIds) return [];
                                const apps = [];
                                for (let i = 0; i < root.folderPopupData.appIds.length; i++) {
                                    const appId = root.folderPopupData.appIds[i];
                                    const entry = DesktopEntries.heuristicLookup(appId);
                                    if (entry) {
                                        apps.push({ id: appId, entry: entry });
                                    }
                                }
                                return apps;
                            }

                            RippleButton {
                                id: folderAppBtn
                                required property var modelData
                                required property int index

                                implicitWidth: 80
                                implicitHeight: 90
                                buttonRadius: Appearance.rounding.small

                                PointingHandInteraction {}

                                onClicked: {
                                    root.hideFolderPopup();
                                    folderAppBtn.modelData.entry.execute();
                                }

                                contentItem: ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 4

                                    IconImage {
                                        Layout.alignment: Qt.AlignHCenter
                                        source: Quickshell.iconPath(
                                            folderAppBtn.modelData.entry.icon ?? AppSearch.guessIcon(folderAppBtn.modelData.id),
                                            "image-missing")
                                        implicitSize: 40
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignHCenter
                                        text: folderAppBtn.modelData.entry.name
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.m3colors.m3onSurface
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                    }
                                }

                                StyledToolTip {
                                    text: folderAppBtn.modelData.entry.name
                                        + (folderAppBtn.modelData.entry.description
                                            ? "\n" + folderAppBtn.modelData.entry.description
                                            : "")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    DockContextMenu {
        id: contextMenu
    }
}
