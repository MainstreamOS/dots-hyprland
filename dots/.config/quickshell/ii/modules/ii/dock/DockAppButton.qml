import qs.services
import qs.modules.common
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

DockButton {
    id: root
    property var appToplevel
    property var appListRoot
    property int delegateIndex: -1
    property real iconSize: 35
    property real countDotWidth: 10
    property real countDotHeight: 4
    property bool appIsActive: appToplevel.toplevels.find(t => (t.activated == true)) !== undefined

    readonly property bool isSeparator: appToplevel.appId === "SEPARATOR"
    readonly property bool isFolder: appToplevel.isFolder === true
    property var desktopEntry: isFolder ? null : DesktopEntries.heuristicLookup(appToplevel.appId)

    Timer {
        // Retry looking up the desktop entry if it failed (e.g. database not loaded yet)
        property int retryCount: 5
        interval: 1000
        running: !root.isSeparator && !root.isFolder && root.desktopEntry === null && retryCount > 0
        repeat: true
        onTriggered: {
            retryCount--;
            root.desktopEntry = DesktopEntries.heuristicLookup(root.appToplevel.appId);
        }
    }

    // Folder icon data — resolved imperatively to avoid reactive dependency
    // on AppFolderManager.folders which would rebuild the entire dock model.
    property var folderAppIds: []

    function refreshFolderData() {
        if (!root.isFolder) return;
        const folderId = appToplevel.appId.substring(TaskbarApps.folderPrefix.length);
        const folder = AppFolderManager.getFolder(folderId);
        root.folderAppIds = folder ? folder.appIds.slice(0, 4) : [];
    }

    Component.onCompleted: refreshFolderData()

    Connections {
        target: AppFolderManager
        enabled: root.isFolder
        function onFoldersChanged() { root.refreshFolderData(); }
    }

    // Drag-to-reorder
    readonly property bool isDragged: appListRoot.dragging && delegateIndex === appListRoot.dragSourceIndex
    readonly property real dragTranslateX: {
        if (!appListRoot.dragging) return 0;
        if (isDragged) return appListRoot.dragCursorX - appListRoot.dragStartCursorX;
        if (!appToplevel.pinned || isSeparator) return 0;
        var src = appListRoot.dragSourceIndex;
        var tgt = appListRoot.dragTargetIndex;
        var idx = delegateIndex;
        if (src < tgt && idx > src && idx <= tgt) return -appListRoot.slotWidth;
        if (src > tgt && idx >= tgt && idx < src) return appListRoot.slotWidth;
        return 0;
    }
    z: isDragged ? 100 : 0
    scale: isDragged ? 1.05 : 1

    enabled: !isSeparator
    property real hoverScale: 1.0
    property int buttonIndex: 0

    implicitWidth: isSeparator ? 1 : (implicitHeight - topInset - bottomInset)

    transform: Translate {
        x: root.dragTranslateX
        Behavior on x {
            enabled: !root.isDragged && !appListRoot._suppressTranslateAnim
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    Loader {
        active: isSeparator
        anchors {
            fill: parent
            topMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
            bottomMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
        }
        sourceComponent: DockSeparator {}
    }

    // Drag overlay for pinned non-separator items
    MouseArea {
        id: dragOverlay
        anchors.fill: parent
        z: 10
        enabled: appToplevel.pinned && !isSeparator
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        property real pressX: 0
        property bool dragActive: false

        onPressed: (event) => {
            pressX = event.x;
            root.down = true;
            root.startRipple(event.x, event.y);
        }
        onPositionChanged: (event) => {
            if (!pressed) return;
            var dist = Math.abs(event.x - pressX);
            if (!dragActive && dist > 5) {
                dragActive = true;
                root.cancelRipple();
                root.down = false;
                appListRoot.dragSourceIndex = root.delegateIndex;
                var mapped = mapToItem(appListRoot, event.x, event.y);
                appListRoot.dragStartCursorX = mapped.x;
                appListRoot.dragCursorX = mapped.x;
                appListRoot.slotWidth = root.width + 2;
                appListRoot.dragging = true;
            }
            if (dragActive) {
                var mapped = mapToItem(appListRoot, event.x, event.y);
                appListRoot.dragCursorX = mapped.x;
            }
        }
        onReleased: (event) => {
            if (dragActive) {
                dragActive = false;
                appListRoot.finishDrag();
            } else {
                root.down = false;
                root.cancelRipple();
                root.click();
            }
        }
        onCanceled: {
            if (dragActive) {
                dragActive = false;
                appListRoot.cancelDrag();
            }
            root.down = false;
            root.cancelRipple();
        }
    }

    onClicked: {
        if (root.isFolder) {
            // Toggle folder popup directly above this icon
            if (appListRoot.folderPopupShow && appListRoot.clickedButton === root) {
                appListRoot.hideFolderPopup();
            } else {
                const folderId = appToplevel.appId.substring(TaskbarApps.folderPrefix.length);
                const folder = AppFolderManager.getFolder(folderId);
                if (folder) appListRoot.showFolderPopup(root, folder);
            }
        } else if (appToplevel.toplevels.length > 0) {
            // Toggle preview
            if (appListRoot.clickedButton === root) {
                appListRoot.hidePreview();
            } else {
                appListRoot.showPreview(root);
            }
        } else {
            root.desktopEntry?.execute();
        }
    }

    // Hover tracker — magnification only
    MouseArea {
        id: hoverTracker
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        z: 1
        onPositionChanged: mouse => {
            appListRoot.listHovered = true;
            const mapped = mapToItem(appListRoot.listViewRef, mouse.x, mouse.y);
            appListRoot.mouseXInList = mapped.x + appListRoot.listViewRef.contentX;
        }
        onEntered: appListRoot.listHovered = true
        onExited: Qt.callLater(() => { appListRoot.listHovered = false; })
    }

    middleClickAction: () => {
        if (!root.isFolder) root.desktopEntry?.execute();
    }

    altAction: () => {
        appListRoot.openContextMenu(root, appToplevel);
    }

    contentItem: Loader {
        active: !isSeparator
        sourceComponent: Item {
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize
            scale: root.hoverScale
            transformOrigin: Item.Bottom

            Behavior on scale {
                NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
            }

            // Regular app icon
            Loader {
                id: iconImageLoader
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                active: !root.isSeparator && !root.isFolder
                sourceComponent: IconImage {
                    source: Quickshell.iconPath(root.desktopEntry?.icon ?? AppSearch.guessIcon(appToplevel.appId), "image-missing")
                    implicitSize: root.iconSize
                }
            }

            // Folder icon — 2x2 mini-icon grid
            Loader {
                id: folderIconLoader
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                active: root.isFolder
                sourceComponent: Rectangle {
                    implicitWidth: root.iconSize
                    implicitHeight: root.iconSize
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border

                    Grid {
                        anchors.centerIn: parent
                        columns: 2
                        spacing: 1

                        Repeater {
                            model: root.folderAppIds

                            IconImage {
                                required property var modelData
                                source: Quickshell.iconPath(AppSearch.guessIcon(modelData), "image-missing")
                                implicitSize: root.iconSize * 0.4
                            }
                        }
                    }
                }
            }

            Loader {
                active: Config.options.dock.monochromeIcons && !root.isFolder
                anchors.fill: iconImageLoader
                sourceComponent: Item {
                    Desaturate {
                        id: desaturatedIcon
                        visible: false
                        anchors.fill: parent
                        source: iconImageLoader
                        desaturation: 0.8
                    }
                    ColorOverlay {
                        anchors.fill: desaturatedIcon
                        source: desaturatedIcon
                        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                    }
                }
            }

            RowLayout {
                spacing: 3
                anchors {
                    top: root.isFolder ? folderIconLoader.bottom : iconImageLoader.bottom
                    topMargin: 2
                    horizontalCenter: parent.horizontalCenter
                }
                visible: !root.isFolder
                Repeater {
                    model: Math.min(appToplevel.toplevels.length, 3)
                    delegate: Rectangle {
                        required property int index
                        radius: Appearance.rounding.full
                        implicitWidth: (appToplevel.toplevels.length <= 3) ?
                            root.countDotWidth : root.countDotHeight
                        implicitHeight: root.countDotHeight
                        color: appIsActive ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                    }
                }
            }
        }
    }
}
