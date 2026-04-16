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
        previewLoader.active = true;
        previewShow = true;
        dismissTimer.restart();
    }
    function hidePreview() {
        previewFading = true;
        fadeTimer.restart();
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
    property real dragCursorX: 0
    property real dragStartCursorX: 0
    property real slotWidth: 0
    property int dragTargetIndex: {
        if (!dragging || slotWidth <= 0) return dragSourceIndex;
        var delta = dragCursorX - dragStartCursorX;
        var slots = Math.round(delta / slotWidth);
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
        dragCursorX = 0;
        dragStartCursorX = 0;
        // Allow the ListView to fully process delegate changes before
        // re-enabling transitions, preventing the opacity-flicker on add.
        reorderSettleTimer.restart();
    }

    function cancelDrag() {
        _suppressTranslateAnim = true;
        dragging = false;
        dragSourceIndex = -1;
        dragCursorX = 0;
        dragStartCursorX = 0;
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
    property real mouseXInList: -9999
    property bool listHovered: false
    property real maxScale: 2.2
    property real sigma: 60

    function scaleForX(itemCenterX) {
        if (!listHovered || previewShow) return 1.0;
        const dist = itemCenterX - mouseXInList;
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
            root.mouseXInList = mouse.x + listView.contentX;
        }
        onEntered:  root.listHovered = true
        onExited:   root.listHovered = false
    }

    Layout.fillHeight: true
    Layout.topMargin: Appearance.sizes.hyprlandGapsOut
    implicitWidth: listView.implicitWidth

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
        orientation: ListView.Horizontal
        anchors {
            top: parent.top
            bottom: parent.bottom
        }
        implicitWidth: contentWidth

        Behavior on implicitWidth {
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

            topInset: Appearance.sizes.hyprlandGapsOut + root.buttonPadding
            bottomInset: Appearance.sizes.hyprlandGapsOut + root.buttonPadding
            hoverScale: root.scaleForX(x + width / 2)
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
                gravity: Edges.Top
                edges: Edges.Top
                adjustment: PopupAdjustment.SlideX
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
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Appearance.sizes.elevationMargin
                    anchors.horizontalCenter: parent.horizontalCenter
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
                                padding: 0
                                middleClickAction: () => {
                                    windowButton.modelData?.close();
                                }
                                onClicked: {
                                    root.hidePreview();
                                    windowButton.modelData?.activate();
                                }
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
                                            captureSource: windowButton.modelData
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
                gravity: Edges.Top
                edges: Edges.Top
                adjustment: PopupAdjustment.SlideX
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

                anchors {
                    bottom: parent.bottom
                    horizontalCenter: parent.horizontalCenter
                    bottomMargin: Appearance.sizes.elevationMargin
                }
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
