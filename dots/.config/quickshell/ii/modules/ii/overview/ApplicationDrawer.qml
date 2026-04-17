import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Item {
    id: root
    property bool expanded: false
    property string searchText: ""
    property string sortMode: "name" // "name", "recent"
    property string filterCategory: "all" // "all", "favorites"

    property real collapsedHeight: 400 // Better initial height
    property real availableHeight: 0
    property real availableWidth: 0
    property real expandedHeight: {
        // Use most of available height when expanded, but leave space for top bar
        if (availableHeight > 0) {
            // Use 85% of available height to ensure it doesn't overlap top bar
            // This leaves ~15% for the bar and some breathing room
            return availableHeight * 0.85;
        }
        return 600;
    }
    property int columns: {
        if (availableWidth > 0) {
            const cellWidth = root.expanded ? 135 : 90;
            return Math.max(6, Math.floor((availableWidth - 60) / cellWidth));
        }
        return Math.max(6, Math.floor((width - 60) / (root.expanded ? 135 : 90)));
    }
    property real iconSize: root.expanded ? 75 : 50
    property real spacing: root.expanded ? 45 : 30

    // Drag-to-workspace signals — Overview.qml listens to these.
    // All positions are in scene (window-root) coordinates.
    signal appDragStarted(var app, real sceneX, real sceneY)
    signal appDragUpdate(real sceneX, real sceneY)
    signal appDropped(var app, real sceneX, real sceneY)
    signal appDragCancelled()

    // True while the user is dragging an app icon
    property bool _isDraggingApp: false

    // Context menu state
    property var contextMenuApp: null
    property bool contextMenuVisible: false
    property point contextMenuPosition: Qt.point(0, 0)
    property bool _contextIsFolder: false
    property bool _contextInFolderPopup: false

    // Folder state
    property int _dragHoverIndex: -1
    property bool folderPopupVisible: false
    property var openFolder: null
    property bool folderNameDialogVisible: false
    property string _pendingFolderApp1Id: ""
    property string _pendingFolderApp2Id: ""
    property string _pendingFolderRenameId: ""
    property bool _folderDragActive: false

    // Position of the folder icon the popup is animating from/to (overlay coords)
    property real _folderSourceX: 0
    property real _folderSourceY: 0

    // Bumped on folder changes to force ScriptModel re-evaluation
    property int _folderRevision: 0

    implicitHeight: root.expanded ? root.expandedHeight : root.collapsedHeight

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Appearance.animation.elementResize.duration
            easing.type: Appearance.animation.elementResize.type
            easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
        }
    }

    Connections {
        target: AppFolderManager
        function onFoldersChanged() {
            root._folderRevision++;
            // Keep the open folder popup in sync
            if (root.folderPopupVisible && root.openFolder) {
                const updated = AppFolderManager.getFolder(root.openFolder.id);
                if (updated) {
                    root.openFolder = {
                        _isFolder: true,
                        id: updated.id,
                        name: updated.name,
                        appIds: updated.appIds.slice()
                    };
                } else {
                    root.folderPopupVisible = false;
                    root.openFolder = null;
                }
            }
        }
    }

    // Handle dock requesting to open a folder
    Connections {
        target: GlobalStates
        function onOpenFolderIdChanged() {
            const raw = GlobalStates.openFolderId;
            if (!raw) return;
            GlobalStates.openFolderId = ""; // consume it

            // "rename:folderId" triggers the rename dialog instead
            if (raw.startsWith("rename:")) {
                const folderId = raw.substring(7);
                root._pendingFolderRenameId = folderId;
                root._pendingFolderApp1Id = "";
                root._pendingFolderApp2Id = "";
                root.folderNameDialogVisible = true;
                root.expanded = true;
                return;
            }

            const folder = AppFolderManager.getFolder(raw);
            if (folder) {
                // No source icon when triggered from dock — animate from center
                root._folderSourceX = root.width / 2;
                root._folderSourceY = root.height / 2;
                root.openFolder = {
                    _isFolder: true,
                    id: folder.id,
                    name: folder.name,
                    appIds: folder.appIds.slice()
                };
                root.folderPopupVisible = true;
                root.expanded = true;
            }
        }
    }

    // Filter and sort apps, mixing in folder items when not searching
    function getFilteredApps() {
        // Reference _folderRevision so QML re-evaluates when folders change
        const rev = root._folderRevision;

        const list = AppSearch.list;
        if (!list || list.length === 0) return [];

        let apps = Array.from(list);

        // Filter by search text
        if (root.searchText.length > 0) {
            const searchLower = root.searchText.toLowerCase();
            apps = apps.filter(app =>
                app.name.toLowerCase().includes(searchLower) ||
                (app.description && app.description.toLowerCase().includes(searchLower))
            );
            // When searching, show ALL apps flat (including ones inside folders)
        } else {
            // Normal view: hide apps that live inside a folder
            const folderedIds = AppFolderManager.allFolderedAppIds();
            apps = apps.filter(app => !folderedIds[app.id]);
        }

        // Sort
        if (root.sortMode === "name") {
            apps.sort((a, b) => a.name.localeCompare(b.name));
        }

        // Prepend folder items when not searching
        if (root.searchText.length === 0) {
            const folders = AppFolderManager.folders || [];
            const folderItems = folders.map(f => ({
                _isFolder: true,
                id: f.id,
                name: f.name,
                appIds: f.appIds.slice()
            }));
            return folderItems.concat(apps);
        }

        return apps;
    }

    // Resolve a desktop-entry ID to its DesktopEntry object
    function getAppById(appId) {
        const list = AppSearch.list;
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === appId) return list[i];
        }
        return null;
    }

    // Scroll the inner app grid by the given normalised delta and factor.
    // Called by Overview's wheelOverlay — all expand/collapse logic lives there.
    function scrollGrid(delta, scrollFactor) {
        const maxY = Math.max(0, appGrid.contentHeight - appGrid.height);
        appGrid.contentY = Math.max(0, Math.min(appGrid.contentY - delta * scrollFactor, maxY));
    }

    // Returns true when the grid is scrolled to its very top.
    function isGridAtTop() {
        return appGrid.contentY <= 0;
    }

    // Returns true when the grid is scrolled to its very bottom.
    function isGridAtBottom() {
        const maxY = Math.max(0, appGrid.contentHeight - appGrid.height);
        return appGrid.contentY >= maxY - 1;
    }

    // Resets the grid scroll position to the top.
    // Called by Overview whenever the drawer is opened or closed.
    function resetScroll() {
        appGrid.contentY = 0;
    }

    StyledRectangularShadow {
        target: drawerBackground
    }

    Rectangle {
        id: drawerBackground
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.expanded ? 20 : 15
            spacing: 10

            // Header with search and controls
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: "apps"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    text: root.expanded ? Translation.tr("All Applications") : Translation.tr("Applications")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0
                }

                Item { Layout.fillWidth: true }

                MaterialSymbol {
                    text: root.expanded ? "expand_less" : "expand_more"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }
            }

            // Search bar (only visible when expanded)
            TextField {
                id: searchField
                Layout.fillWidth: true
                visible: root.expanded
                Layout.maximumHeight: root.expanded ? implicitHeight : 0
                opacity: root.expanded ? 1 : 0
                focus: root.expanded

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                Behavior on Layout.maximumHeight {
                    NumberAnimation {
                        duration: Appearance.animation.elementResize.duration
                        easing.type: Appearance.animation.elementResize.type
                        easing.bezierCurve: Appearance.animation.elementResize.bezierCurve
                    }
                }

                placeholderText: Translation.tr("Search applications...")
                placeholderTextColor: Appearance.m3colors.m3outline
                padding: 10

                font {
                    family: Appearance.font.family.main
                    pixelSize: Appearance.font.pixelSize.small
                }

                color: Appearance.m3colors.m3onSurface
                selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                selectionColor: Appearance.colors.colSecondaryContainer

                background: Rectangle {
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: searchField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

                    Behavior on border.color {
                        ColorAnimation {
                            duration: 150
                        }
                    }
                }

                cursorDelegate: Rectangle {
                    width: 1
                    color: Appearance.colors.colPrimary
                    radius: 1
                    visible: searchField.activeFocus
                }

                onTextChanged: {
                    root.searchText = text;
                }

                // Clear button
                MaterialSymbol {
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "close"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                    visible: searchField.text.length > 0

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            searchField.text = "";
                        }
                    }
                }
            }

            // App Grid — no ScrollView wrapper.
            // The outer Overview wheelOverlay delegates scroll here via
            // scrollGrid(); GridView does not handle its own scroll events.
            Item {
                id: gridContainer
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: root.expanded ? 100 : 40
                clip: true

                // Whether there is content below the current scroll position in collapsed mode.
                // Used to show the "more" indicator and reserve bottom margin for it.
                readonly property bool hasOverflow: !root.expanded
                    && (appGrid.contentHeight > appGrid.height + appGrid.contentY + 1)

                // How many items are below the current visible area (for the indicator label).
                readonly property int itemsBelowFold: {
                    if (!hasOverflow) return 0;
                    const bottomRow = Math.ceil((appGrid.contentY + appGrid.height) / appGrid.cellHeight);
                    return Math.max(0, appGrid.count - bottomRow * root.columns);
                }

                GridView {
                    id: appGrid
                    anchors.fill: parent
                    cellWidth: Math.max(root.expanded ? 120 : 80, (parent.width - (root.columns - 1) * root.spacing - 30) / root.columns)
                    cellHeight: cellWidth * 1.3
                    interactive: false
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar {
                        visible: !root.expanded && gridContainer.hasOverflow
                        policy: ScrollBar.AsNeeded
                        minimumSize: 0.1
                    }

                    model: ScriptModel {
                        values: root.getFilteredApps()
                    }

                    // Show "no results" message
                    Label {
                        anchors.centerIn: parent
                        visible: appGrid.count === 0 && root.searchText.length > 0
                        text: Translation.tr("No applications found")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }

                    delegate: RippleButton {
                        id: appButton
                        required property var modelData
                        required property int index
                        property bool keyboardDown: false
                        property bool isDragTarget: root._dragHoverIndex === index && root._isDraggingApp

                        width: appGrid.cellWidth
                        height: appGrid.cellHeight
                        buttonRadius: Appearance.rounding.normal
                        colBackground: {
                            if (isDragTarget)
                                return ColorUtils.transparentize(Appearance.colors.colPrimary, 0.5);
                            if (appButton.down || appButton.keyboardDown)
                                return Appearance.colors.colSecondaryContainerActive;
                            if (appButton.hovered || appButton.focus)
                                return Appearance.colors.colSecondaryContainer;
                            return ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 1);
                        }
                        colBackgroundHover: Appearance.colors.colSecondaryContainer
                        colRipple: Appearance.colors.colSecondaryContainerActive

                        PointingHandInteraction {}

                        // Click handled by dragOverlay for mouse; keyboard below
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                appButton.keyboardDown = true;
                                if (modelData._isFolder) {
                                    const center = appButton.mapToItem(folderPopupOverlay, appButton.width / 2, appButton.height / 2);
                                    root._folderSourceX = center.x;
                                    root._folderSourceY = center.y;
                                    root.openFolder = modelData;
                                    root.folderPopupVisible = true;
                                } else {
                                    GlobalStates.overviewOpen = false;
                                    modelData.execute();
                                }
                                event.accepted = true;
                            }
                        }

                        Keys.onReleased: (event) => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                appButton.keyboardDown = false
                                event.accepted = true
                            }
                        }

                        // ── Folder visual ──────────────────────────────
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6
                            visible: modelData._isFolder === true

                            Rectangle {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: root.iconSize
                                Layout.preferredHeight: root.iconSize
                                radius: Appearance.rounding.normal
                                color: Appearance.colors.colLayer1
                                border.width: 1
                                border.color: Appearance.colors.colLayer0Border

                                Grid {
                                    anchors.centerIn: parent
                                    columns: 2
                                    spacing: 2

                                    Repeater {
                                        model: modelData._isFolder ? modelData.appIds.slice(0, 4) : []

                                        IconImage {
                                            required property var modelData
                                            source: Quickshell.iconPath(AppSearch.guessIcon(modelData), "image-missing")
                                            implicitSize: root.iconSize * 0.38
                                        }
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer0
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                            }
                        }

                        // ── App visual ─────────────────────────────────
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6
                            visible: !modelData._isFolder

                            IconImage {
                                Layout.alignment: Qt.AlignHCenter
                                source: !modelData._isFolder
                                    ? Quickshell.iconPath(AppSearch.guessIcon(modelData.id || modelData.icon), "application-x-executable")
                                    : ""
                                implicitSize: root.iconSize
                                onStatusChanged: {
                                    if (status === Image.Error)
                                        source = Quickshell.iconPath("application-x-executable", "")
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer0
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                            }
                        }

                        // Drag-target highlight ring
                        Rectangle {
                            anchors.fill: parent
                            radius: Appearance.rounding.normal
                            color: "transparent"
                            border.width: 2
                            border.color: Appearance.colors.colPrimary
                            visible: appButton.isDragTarget
                        }

                        StyledToolTip {
                            text: modelData._isFolder
                                ? (modelData.name + " (" + modelData.appIds.length + " apps)")
                                : (modelData.name + (modelData.description ? "\n" + modelData.description : ""))
                        }
                    }
                }

                // Drag-detection overlay — sits above the grid (z:1) for hit-testing.
                // Handles: click, right-click, drag-to-workspace, drag-to-create-folder,
                // and drag-to-add-to-folder.
                MouseArea {
                    id: dragOverlay
                    anchors.fill: parent
                    z: 1
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true

                    property var _app: null
                    property int _appIndex: -1
                    property real _startX: 0
                    property real _startY: 0
                    property bool _dragging: false
                    readonly property real _threshold: 20

                    onPressed: (mouse) => {
                        _dragging = false
                        _app = null
                        _appIndex = -1
                        _startX = mouse.x
                        _startY = mouse.y
                        root._dragHoverIndex = -1

                        const item = appGrid.itemAt(
                            mouse.x + appGrid.contentX,
                            mouse.y + appGrid.contentY)

                        if (mouse.button === Qt.RightButton) {
                            const data = item ? item.modelData : null
                            if (data) {
                                root._contextIsFolder = (data._isFolder === true)
                                root._contextInFolderPopup = false
                                root.contextMenuApp = data
                                const pos = dragOverlay.mapToItem(root, mouse.x, mouse.y)
                                appContextMenu.x = pos.x
                                appContextMenu.y = pos.y
                                appContextMenu.open()
                            }
                            mouse.accepted = true
                            return
                        }

                        if (item) {
                            _app = item.modelData
                            _appIndex = item.index
                        }
                    }

                    onPositionChanged: (mouse) => {
                        if (!_app) return
                        const dx = mouse.x - _startX
                        const dy = mouse.y - _startY
                        if (!_dragging && (dx * dx + dy * dy) > _threshold * _threshold) {
                            // Don't allow dragging folders themselves
                            if (_app._isFolder) {
                                _app = null
                                return
                            }
                            _dragging = true
                            root._isDraggingApp = true
                            const sp = dragOverlay.mapToItem(null, mouse.x, mouse.y)
                            root.appDragStarted(_app, sp.x, sp.y)
                        }
                        if (_dragging) {
                            const sp = dragOverlay.mapToItem(null, mouse.x, mouse.y)
                            root.appDragUpdate(sp.x, sp.y)

                            // Track which grid cell we're hovering over
                            const hoverItem = appGrid.itemAt(
                                mouse.x + appGrid.contentX,
                                mouse.y + appGrid.contentY)
                            if (hoverItem && hoverItem.index !== _appIndex) {
                                root._dragHoverIndex = hoverItem.index
                            } else {
                                root._dragHoverIndex = -1
                            }
                        }
                    }

                    onReleased: (mouse) => {
                        if (_dragging) {
                            // Check if we're dropping onto another grid item
                            const hoverItem = appGrid.itemAt(
                                mouse.x + appGrid.contentX,
                                mouse.y + appGrid.contentY)

                            if (hoverItem && hoverItem.index !== _appIndex && hoverItem.modelData) {
                                const target = hoverItem.modelData
                                const draggedApp = _app

                                // Cancel the workspace drag ghost FIRST to avoid ghost icons
                                root.appDragCancelled()

                                if (target._isFolder) {
                                    // Drop onto an existing folder → add app
                                    AppFolderManager.addAppToFolder(target.id, draggedApp.id)
                                } else {
                                    // Drop onto another app → prompt for folder name
                                    root._pendingFolderApp1Id = draggedApp.id
                                    root._pendingFolderApp2Id = target.id
                                    root._pendingFolderRenameId = ""
                                    root.folderNameDialogVisible = true
                                }
                            } else {
                                // Not over another item → workspace drop
                                const sp = dragOverlay.mapToItem(null, mouse.x, mouse.y)
                                root.appDropped(_app, sp.x, sp.y)
                            }
                        } else if (_app && mouse.button === Qt.LeftButton) {
                            // Plain click
                            if (_app._isFolder) {
                                const item = appGrid.itemAt(
                                    mouse.x + appGrid.contentX,
                                    mouse.y + appGrid.contentY)
                                if (item) {
                                    const center = item.mapToItem(folderPopupOverlay, item.width / 2, item.height / 2)
                                    root._folderSourceX = center.x
                                    root._folderSourceY = center.y
                                } else {
                                    root._folderSourceX = folderPopupOverlay.width / 2
                                    root._folderSourceY = folderPopupOverlay.height / 2
                                }
                                root.openFolder = _app
                                root.folderPopupVisible = true
                            } else {
                                GlobalStates.overviewOpen = false
                                _app.execute()
                            }
                        }
                        _app = null
                        _appIndex = -1
                        _dragging = false
                        root._isDraggingApp = false
                        root._dragHoverIndex = -1
                    }

                    onCanceled: {
                        if (_dragging) root.appDragCancelled()
                        _app = null
                        _appIndex = -1
                        _dragging = false
                        root._isDraggingApp = false
                        root._dragHoverIndex = -1
                    }
                }
            }
        }
    }

    // ── Context Menu (Popup — matches TaskList.qml style) ──────────
    Popup {
        id: appContextMenu
        padding: 0
        background: Item {
            StyledRectangularShadow { target: menuBg }
            Rectangle {
                id: menuBg
                anchors.fill: parent
                color: Appearance.m3colors.m3surfaceContainer
                radius: Appearance.rounding.normal
            }
        }

        contentItem: ColumnLayout {
            spacing: 0

            // ── App options ─────────────────────────────
            // Pin / Unpin to dock
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 36
                implicitWidth: Math.max(pinRow.implicitWidth + 20, 160)
                visible: !root._contextIsFolder && !root._contextInFolderPopup
                buttonRadius: Appearance.rounding.small
                onClicked: {
                    TaskbarApps.togglePin(root.contextMenuApp.id)
                    appContextMenu.close()
                }
                contentItem: RowLayout {
                    id: pinRow
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 14
                    }
                    spacing: 8
                    MaterialSymbol {
                        text: TaskbarApps.isPinned(root.contextMenuApp?.id ?? "") ? "keep_off" : "keep"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.m3colors.m3onSurface
                        Layout.alignment: Qt.AlignVCenter
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: TaskbarApps.isPinned(root.contextMenuApp?.id ?? "")
                            ? Translation.tr("Unpin from dock")
                            : Translation.tr("Pin to dock")
                        horizontalAlignment: Text.AlignLeft
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        elide: Text.ElideRight
                    }
                }
            }

            // ── Folder options ──────────────────────────
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 36
                implicitWidth: Math.max(renameRow.implicitWidth + 20, 160)
                visible: root._contextIsFolder
                buttonRadius: Appearance.rounding.small
                onClicked: {
                    root._pendingFolderRenameId = root.contextMenuApp.id
                    root._pendingFolderApp1Id = ""
                    root._pendingFolderApp2Id = ""
                    root.folderNameDialogVisible = true
                    appContextMenu.close()
                }
                contentItem: RowLayout {
                    id: renameRow
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 14
                    }
                    spacing: 8
                    MaterialSymbol {
                        text: "edit"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.m3colors.m3onSurface
                        Layout.alignment: Qt.AlignVCenter
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Rename folder")
                        horizontalAlignment: Text.AlignLeft
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        elide: Text.ElideRight
                    }
                }
            }

            // Pin / Unpin folder to dock
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 36
                implicitWidth: Math.max(folderDockPinRow.implicitWidth + 20, 160)
                visible: root._contextIsFolder
                buttonRadius: Appearance.rounding.small
                onClicked: {
                    TaskbarApps.toggleFolderPin(root.contextMenuApp.id)
                    appContextMenu.close()
                }
                contentItem: RowLayout {
                    id: folderDockPinRow
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 14
                    }
                    spacing: 8
                    MaterialSymbol {
                        text: TaskbarApps.isFolderPinned(root.contextMenuApp?.id ?? "") ? "keep_off" : "keep"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.m3colors.m3onSurface
                        Layout.alignment: Qt.AlignVCenter
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: TaskbarApps.isFolderPinned(root.contextMenuApp?.id ?? "")
                            ? Translation.tr("Unpin from dock")
                            : Translation.tr("Pin to dock")
                        horizontalAlignment: Text.AlignLeft
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        elide: Text.ElideRight
                    }
                }
            }

            // Separator
            Item {
                implicitHeight: 9
                Layout.fillWidth: true
                visible: root._contextIsFolder
                Rectangle {
                    anchors {
                        left: parent.left; right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 10; rightMargin: 10
                    }
                    implicitHeight: 1
                    color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
                }
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 36
                implicitWidth: Math.max(deleteRow.implicitWidth + 20, 160)
                visible: root._contextIsFolder
                buttonRadius: Appearance.rounding.small
                onClicked: {
                    AppFolderManager.deleteFolder(root.contextMenuApp.id)
                    appContextMenu.close()
                }
                contentItem: RowLayout {
                    id: deleteRow
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 14
                    }
                    spacing: 8
                    MaterialSymbol {
                        text: "delete"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.m3colors.m3onSurface
                        Layout.alignment: Qt.AlignVCenter
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Delete folder")
                        horizontalAlignment: Text.AlignLeft
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        elide: Text.ElideRight
                    }
                }
            }

            // ── Folder-popup app options ──────────────────
            // Pin / Unpin (inside folder popup)
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 36
                implicitWidth: Math.max(folderPinRow.implicitWidth + 20, 160)
                visible: root._contextInFolderPopup
                buttonRadius: Appearance.rounding.small
                onClicked: {
                    TaskbarApps.togglePin(root.contextMenuApp.id)
                    appContextMenu.close()
                }
                contentItem: RowLayout {
                    id: folderPinRow
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 14
                    }
                    spacing: 8
                    MaterialSymbol {
                        text: TaskbarApps.isPinned(root.contextMenuApp?.id ?? "") ? "keep_off" : "keep"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.m3colors.m3onSurface
                        Layout.alignment: Qt.AlignVCenter
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: TaskbarApps.isPinned(root.contextMenuApp?.id ?? "")
                            ? Translation.tr("Unpin from dock")
                            : Translation.tr("Pin to dock")
                        horizontalAlignment: Text.AlignLeft
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        elide: Text.ElideRight
                    }
                }
            }

            // Separator
            Item {
                implicitHeight: 9
                Layout.fillWidth: true
                visible: root._contextInFolderPopup
                Rectangle {
                    anchors {
                        left: parent.left; right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 10; rightMargin: 10
                    }
                    implicitHeight: 1
                    color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
                }
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 36
                implicitWidth: Math.max(removeRow.implicitWidth + 20, 160)
                visible: root._contextInFolderPopup
                buttonRadius: Appearance.rounding.small
                onClicked: {
                    if (root.openFolder) {
                        AppFolderManager.removeAppFromFolder(
                            root.openFolder.id, root.contextMenuApp.id)
                    }
                    appContextMenu.close()
                }
                contentItem: RowLayout {
                    id: removeRow
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 14
                    }
                    spacing: 8
                    MaterialSymbol {
                        text: "folder_off"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.m3colors.m3onSurface
                        Layout.alignment: Qt.AlignVCenter
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Remove from folder")
                        horizontalAlignment: Text.AlignLeft
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ── Folder Name Dialog (scrim overlay — TodoWidget style) ──────
    Item {
        id: folderNameOverlay
        anchors.fill: parent
        z: 9999

        visible: opacity > 0
        opacity: root.folderNameDialogVisible ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        property bool isRename: root._pendingFolderRenameId !== ""

        function dismiss() {
            root.folderNameDialogVisible = false;
            root._pendingFolderApp1Id = "";
            root._pendingFolderApp2Id = "";
            root._pendingFolderRenameId = "";
        }

        function confirm() {
            const name = folderNameField.text.trim();
            if (name.length === 0) return;
            if (folderNameOverlay.isRename) {
                AppFolderManager.renameFolder(root._pendingFolderRenameId, name);
            } else {
                AppFolderManager.createFolder(name, root._pendingFolderApp1Id, root._pendingFolderApp2Id);
            }
            folderNameOverlay.dismiss();
        }

        // Scrim — blocks all interaction
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colScrim
            MouseArea {
                hoverEnabled: true
                anchors.fill: parent
                preventStealing: true
                propagateComposedEvents: false
            }
        }

        // Dialog card
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 360)
            height: folderNameCol.implicitHeight + 32
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainerHigh
            clip: true

            ColumnLayout {
                id: folderNameCol
                anchors {
                    fill: parent
                    margins: 16
                }
                spacing: 12

                StyledText {
                    text: folderNameOverlay.isRename
                        ? Translation.tr("Rename Folder")
                        : Translation.tr("New Folder")
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                    color: Appearance.m3colors.m3onSurface
                }

                TextField {
                    id: folderNameField
                    Layout.fillWidth: true
                    padding: 10
                    focus: root.folderNameDialogVisible

                    font {
                        family: Appearance.font.family.main
                        pixelSize: Appearance.font.pixelSize.small
                    }

                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                    selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                    selectionColor: Appearance.colors.colSecondaryContainer
                    placeholderText: Translation.tr("Folder name...")
                    placeholderTextColor: Appearance.m3colors.m3outline

                    background: Rectangle {
                        radius: Appearance.rounding.verysmall
                        color: "transparent"
                        border.width: 2
                        border.color: folderNameField.activeFocus
                            ? Appearance.colors.colPrimary
                            : Appearance.m3colors.m3outline
                        Behavior on border.color {
                            ColorAnimation { duration: 150 }
                        }
                    }

                    cursorDelegate: Rectangle {
                        width: 1
                        color: folderNameField.activeFocus ? Appearance.colors.colPrimary : "transparent"
                        radius: 1
                    }

                    Keys.onReturnPressed: folderNameOverlay.confirm()
                    Keys.onEnterPressed: folderNameOverlay.confirm()
                    Keys.onEscapePressed: folderNameOverlay.dismiss()
                }

                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    DialogButton {
                        buttonText: Translation.tr("Cancel")
                        onClicked: folderNameOverlay.dismiss()
                    }
                    DialogButton {
                        buttonText: folderNameOverlay.isRename
                            ? Translation.tr("Rename")
                            : Translation.tr("Create")
                        onClicked: folderNameOverlay.confirm()
                    }
                }
            }
        }

        // Initialise text field when dialog opens
        onOpacityChanged: {
            if (opacity > 0.5 && root.folderNameDialogVisible) {
                if (folderNameOverlay.isRename) {
                    const folder = AppFolderManager.getFolder(root._pendingFolderRenameId);
                    folderNameField.text = folder ? folder.name : "";
                } else {
                    folderNameField.text = Translation.tr("New Folder");
                }
                folderNameField.selectAll();
                folderNameField.forceActiveFocus();
            }
        }
    }

    // ── Folder Popup Overlay (scrim + scale/fade animation + drag-to-workspace) ──
    Item {
        id: folderPopupOverlay
        anchors.fill: parent
        z: 9999

        // Stay alive during drag and during close animation
        visible: opacity > 0 || root._folderDragActive
        onVisibleChanged: {
            if (!visible && !root._folderDragActive) {
                root.openFolder = null;
            }
        }
        opacity: {
            if (root._folderDragActive) return 0;
            return root.folderPopupVisible ? 1 : 0;
        }
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        // Scrim — blocks all interaction underneath
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: Appearance.colors.colScrim
            MouseArea {
                hoverEnabled: true
                anchors.fill: parent
                preventStealing: true
                propagateComposedEvents: false
                onClicked: {
                    if (!root._folderDragActive) {
                        root.folderPopupVisible = false;
                    }
                }
            }
        }

        // Folder card with zoom-from-icon animation
        Rectangle {
            id: folderCard
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.6, 500)
            height: root.expanded
                ? Math.min(parent.height * 0.7, 520)
                : Math.min(parent.height * 0.6, 400)
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainerHigh
            clip: true

            // Scale value animated between 0 (collapsed at icon) and 1 (full size)
            property real _scaleVal: root.folderPopupVisible || root._folderDragActive ? 1 : 0
            Behavior on _scaleVal {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            // Scale transform with origin at the folder icon position (card-local coords)
            transform: Scale {
                origin.x: root._folderSourceX - folderCard.x
                origin.y: root._folderSourceY - folderCard.y
                xScale: folderCard._scaleVal
                yScale: folderCard._scaleVal
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // Folder header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: "folder"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.openFolder ? root.openFolder.name : ""
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Medium
                        color: Appearance.m3colors.m3onSurface
                        elide: Text.ElideRight
                    }

                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        onClicked: {
                            root.folderPopupVisible = false;
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: Appearance.font.pixelSize.normal
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

                // Apps inside the folder (with drag overlay)
                Item {
                    id: folderGridContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // How many columns fit and whether the grid overflows 1 row (collapsed)
                    readonly property int folderColumns: Math.max(1, Math.floor(width / 110))
                    readonly property int folderAppCount: folderGrid.count
                    readonly property bool hasOverflow: !root.expanded && folderAppCount > folderColumns

                    GridView {
                        id: folderGrid
                        anchors.fill: parent
                        // Reserve space for the "show more" bar when overflowing
                        anchors.bottomMargin: parent.hasOverflow ? 40 : 0
                        cellWidth: 110
                        cellHeight: 130
                        interactive: root.expanded
                        boundsBehavior: Flickable.StopAtBounds

                        model: ScriptModel {
                            values: {
                                if (!root.openFolder || !root.openFolder.appIds) return [];
                                const apps = [];
                                for (let i = 0; i < root.openFolder.appIds.length; i++) {
                                    const app = root.getAppById(root.openFolder.appIds[i]);
                                    if (app) apps.push(app);
                                }
                                return apps;
                            }
                        }

                        delegate: RippleButton {
                            id: folderAppBtn
                            required property var modelData
                            required property int index

                            width: folderGrid.cellWidth
                            height: folderGrid.cellHeight
                            buttonRadius: Appearance.rounding.normal
                            colBackground: folderAppBtn.down
                                ? Appearance.colors.colSecondaryContainerActive
                                : (folderAppBtn.hovered
                                    ? Appearance.colors.colSecondaryContainer
                                    : ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 1))
                            colBackgroundHover: Appearance.colors.colSecondaryContainer
                            colRipple: Appearance.colors.colSecondaryContainerActive

                            PointingHandInteraction {}

                            // Click/drag handled by folderDragOverlay

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 56
                                    Layout.preferredHeight: 56

                                    IconImage {
                                        anchors.fill: parent
                                        source: Quickshell.iconPath(
                                            AppSearch.guessIcon(folderAppBtn.modelData.id || folderAppBtn.modelData.icon),
                                            "image-missing")
                                        implicitSize: 56
                                    }

                                    // Remove-from-folder badge
                                    Rectangle {
                                        anchors {
                                            top: parent.top
                                            right: parent.right
                                            topMargin: -4
                                            rightMargin: -4
                                        }
                                        width: 18
                                        height: 18
                                        radius: width / 2
                                        color: Appearance.m3colors.m3error
                                        visible: folderAppBtn.hovered
                                        z: 2

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "close"
                                            iconSize: 12
                                            color: Appearance.m3colors.m3onError
                                        }

                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignHCenter
                                    text: folderAppBtn.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.m3colors.m3onSurface
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                }
                            }

                            StyledToolTip {
                                text: folderAppBtn.modelData.name
                                    + (folderAppBtn.modelData.description
                                        ? "\n" + folderAppBtn.modelData.description
                                        : "")
                            }
                        }
                    }

                    // Drag overlay for folder grid — same pattern as main grid
                    MouseArea {
                        id: folderDragOverlay
                        anchors.fill: parent
                        z: 1
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        preventStealing: true

                        property var _app: null
                        property real _startX: 0
                        property real _startY: 0
                        property bool _dragging: false
                        readonly property real _threshold: 20

                        onPressed: (mouse) => {
                            _dragging = false
                            _app = null
                            _startX = mouse.x
                            _startY = mouse.y

                            const item = folderGrid.itemAt(
                                mouse.x + folderGrid.contentX,
                                mouse.y + folderGrid.contentY)

                            if (mouse.button === Qt.RightButton) {
                                const data = item ? item.modelData : null
                                if (data) {
                                    root._contextIsFolder = false
                                    root._contextInFolderPopup = true
                                    root.contextMenuApp = data
                                    const pos = folderDragOverlay.mapToItem(root, mouse.x, mouse.y)
                                    appContextMenu.x = pos.x
                                    appContextMenu.y = pos.y
                                    appContextMenu.open()
                                }
                                mouse.accepted = true
                                return
                            }

                            _app = item ? item.modelData : null
                        }

                        onPositionChanged: (mouse) => {
                            if (!_app) return
                            const dx = mouse.x - _startX
                            const dy = mouse.y - _startY
                            if (!_dragging && (dx * dx + dy * dy) > _threshold * _threshold) {
                                _dragging = true
                                root._isDraggingApp = true
                                root._folderDragActive = true
                                const sp = folderDragOverlay.mapToItem(null, mouse.x, mouse.y)
                                root.appDragStarted(_app, sp.x, sp.y)
                            }
                            if (_dragging) {
                                const sp = folderDragOverlay.mapToItem(null, mouse.x, mouse.y)
                                root.appDragUpdate(sp.x, sp.y)
                            }
                        }

                        onReleased: (mouse) => {
                            if (_dragging) {
                                const sp = folderDragOverlay.mapToItem(null, mouse.x, mouse.y)
                                root.appDropped(_app, sp.x, sp.y)
                            } else if (_app && mouse.button === Qt.LeftButton) {
                                // Check if click is on the remove badge (top-right of icon)
                                const item = folderGrid.itemAt(
                                    mouse.x + folderGrid.contentX,
                                    mouse.y + folderGrid.contentY)
                                if (item) {
                                    const localPos = folderDragOverlay.mapToItem(item, mouse.x, mouse.y)
                                    // Badge is centered at roughly (cell.width-32, 13); use a generous hit area
                                    if (localPos.x > item.width - 54 && localPos.y < 36) {
                                        if (root.openFolder) {
                                            AppFolderManager.removeAppFromFolder(
                                                root.openFolder.id, _app.id)
                                        }
                                        _app = null
                                        _dragging = false
                                        root._isDraggingApp = false
                                        return
                                    }
                                }
                                root.folderPopupVisible = false
                                root.openFolder = null
                                GlobalStates.overviewOpen = false
                                _app.execute()
                            }
                            _app = null
                            _dragging = false
                            root._isDraggingApp = false
                            if (root._folderDragActive) {
                                root._folderDragActive = false
                                root.folderPopupVisible = false
                                root.openFolder = null
                            }
                        }

                        onCanceled: {
                            if (_dragging) root.appDragCancelled()
                            _app = null
                            _dragging = false
                            root._isDraggingApp = false
                            if (root._folderDragActive) {
                                root._folderDragActive = false
                                root.folderPopupVisible = false
                                root.openFolder = null
                            }
                        }
                    }

                    // "Show more" indicator — visible when collapsed and folder has > 2 rows
                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: 36
                        visible: folderGridContainer.hasOverflow
                        color: "transparent"

                        // Fade gradient over the bottom of the grid
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 0.4; color: Appearance.m3colors.m3surfaceContainerHigh }
                            }
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 4

                            StyledText {
                                text: (folderGridContainer.folderAppCount - folderGridContainer.folderColumns)
                                    + " more"
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colPrimary
                            }

                            MaterialSymbol {
                                text: "expand_more"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colPrimary
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            z: 10
                            onClicked: {
                                // Expand the drawer and keep the folder open
                                const folder = root.openFolder
                                root.expanded = true
                                root.openFolder = folder
                                root.folderPopupVisible = true
                            }
                        }
                    }
                }
            }
        }
    }

}
