import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
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
    property real iconSize: Appearance.sizes.dockIconSize
    property real countDotWidth: 10
    property real countDotHeight: 4
    property bool appIsActive: appToplevel?.toplevels?.find(t => (t.activated == true)) !== undefined

    // How many windows this button stands for. A delegate goes on answering
    // for a moment after the model has dropped it, so everything that counts
    // windows reads this rather than reaching through what is no longer there.
    readonly property int windowCount: appToplevel?.toplevels?.length ?? 0

    readonly property bool isSeparator: appToplevel?.appId === "SEPARATOR"
    readonly property bool isFolder: appToplevel?.isFolder === true
    // Which of the two ways of showing window count this button is drawing.
    // Both name the styles they want rather than the ones they do not, so a
    // style added later stays off until it is asked for, instead of switching
    // the marks on by not having been excluded.
    readonly property bool showsMarks: !isFolder
        && (Config.options.dock.indicatorStyle === "dashes"
            || Config.options.dock.indicatorStyle === "dots")
    readonly property bool showsBadge: !isFolder
        && Config.options.dock.indicatorStyle === "badge"
        && windowCount >= 2

    // appToplevel.appId is already the canonical resolved id (e.g.
    // "settings", "welcome-tutorial") because TaskbarApps.resolveAppId
    // splits "org.quickshell" toplevels by title at the service layer.
    // We keep this property so callers can still go through one lookup
    // point if the resolution rules ever need to differ between the
    // dock and elsewhere.
    readonly property string lookupAppId: appToplevel?.appId ?? ""

    // Bumped by the retry timer to re-run the lookup below. The timer used to
    // assign straight to desktopEntry, which replaced the binding with whatever
    // that one attempt returned. That was invisible while every delegate was
    // rebuilt each time a window opened — the binding came back with the new
    // delegate. Delegates now live for the whole session, so a lookup that came
    // back null while the database was still filling in stayed null until a
    // reload, and the icon sat on the guessIcon() fallback.
    property int lookupAttempt: 0

    readonly property var desktopEntry: {
        // guessDesktopEntry() resolves through DesktopEntries.byId(), a plain
        // function call that registers no dependency, so read the entry list to
        // make the database itself one: when it finishes populating, every icon
        // re-resolves on its own.
        DesktopEntries.applications.values.length;
        root.lookupAttempt;
        if (root.isFolder) return null;
        return AppSearch.guessDesktopEntry(root.lookupAppId);
    }

    Timer {
        // Safety net for a lookup that fails for a reason the dependency above
        // can't see. It only nudges lookupAttempt — assigning to desktopEntry
        // here is what broke the binding in the first place.
        property int retryCount: 5
        interval: 1000
        running: !root.isSeparator && !root.isFolder && root.desktopEntry === null && retryCount > 0
        repeat: true
        onTriggered: {
            retryCount--;
            root.lookupAttempt++;
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
    readonly property real dragTranslate: {
        if (!appListRoot.dragging) return 0;
        if (isDragged) return appListRoot.dragCursorPos - appListRoot.dragStartCursorPos;
        if (!appToplevel?.pinned || isSeparator) return 0;
        var src = appListRoot.dragSourceIndex;
        var tgt = appListRoot.dragTargetIndex;
        var idx = delegateIndex;
        if (src < tgt && idx > src && idx <= tgt) return -appListRoot.slotSize;
        if (src > tgt && idx >= tgt && idx < src) return appListRoot.slotSize;
        return 0;
    }
    // Idle siblings paint in list order once z ties, so a separator
    // delegate can draw over a neighbor magnifying into its space. Racing
    // it on its own hoverScale isn't enough — falloff-based magnification
    // gives it a nontrivial value of its own even though it never grows —
    // so it's pinned below the baseline instead (icons never go below 1).
    // Regular icons still race each other on hoverScale, so the biggest
    // one paints frontmost.
    // A haloed button has to paint above its neighbours for as long as any of
    // the halo is on screen: it spills past the button's own bounds, and the
    // lift that comes with it is far too slight to say so through scale, which
    // is what orders the rest. Below a dragged one, above every resting one.
    z: isDragged ? 100 : (isSeparator ? -1 : (glowFade > 0 ? 99 : hoverScale))
    scale: isDragged ? 1.05 : 1

    enabled: !isSeparator
    property real hoverScale: 1.0
    // The size to decode an icon at so it stays sharp once hovering has grown
    // it, quantised so a dial being dragged does not mint a raster per step.
    function rasterFor(size) {
        return Math.ceil(size * root.appListRoot.maxScale / 16) * 16;
    }
    // Set by the list, not by a MouseArea here — see pointerIsOver in DockApps.
    property bool pointerOver: false
    // How much of the halo is showing. The button owns this rather than the
    // loader that draws it, because its own stacking has to follow the fade
    // out as well as the fade in.
    property real glowFade: root.pointerOver ? 1 : 0
    Behavior on glowFade {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    property int buttonIndex: 0

    implicitWidth: dockRoot.dockVertical ? dockButtonSize + leftInset + rightInset
        : (isSeparator ? 1 : dockButtonSize)
    implicitHeight: dockRoot.dockVertical ? (isSeparator ? 1 : dockButtonSize)
        : dockButtonSize + topInset + bottomInset

    transform: Translate {
        x: dockRoot.dockVertical ? 0 : root.dragTranslate
        y: dockRoot.dockVertical ? root.dragTranslate : 0
        Behavior on x {
            enabled: !root.isDragged && !appListRoot._suppressTranslateAnim
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on y {
            enabled: !root.isDragged && !appListRoot._suppressTranslateAnim
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    Loader {
        active: isSeparator
        anchors {
            fill: parent
            topMargin: dockRoot.dockVertical ? 0 : dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
            bottomMargin: dockRoot.dockVertical ? 0 : dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
            leftMargin: dockRoot.dockVertical ? dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal : 0
            rightMargin: dockRoot.dockVertical ? dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal : 0
        }
        sourceComponent: DockSeparator {}
    }

    // Drag overlay for pinned non-separator items
    MouseArea {
        id: dragOverlay
        anchors.fill: parent
        z: 10
        enabled: (appToplevel?.pinned ?? false) && !isSeparator
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        property real pressPos: 0
        property bool dragActive: false

        onPressed: (event) => {
            pressPos = dockRoot.dockVertical ? event.y : event.x;
            root.down = true;
            root.startRipple(event.x, event.y);
        }
        onPositionChanged: (event) => {
            if (!pressed) return;
            var dist = Math.abs((dockRoot.dockVertical ? event.y : event.x) - pressPos);
            if (!dragActive && dist > 5) {
                dragActive = true;
                root.cancelRipple();
                root.down = false;
                appListRoot.dragSourceIndex = root.delegateIndex;
                var mapped = mapToItem(appListRoot, event.x, event.y);
                appListRoot.dragStartCursorPos = dockRoot.dockVertical ? mapped.y : mapped.x;
                appListRoot.dragCursorPos = appListRoot.dragStartCursorPos;
                appListRoot.slotSize = (dockRoot.dockVertical ? root.height : root.width) + 2;
                appListRoot.dragging = true;
            }
            if (dragActive) {
                var mapped = mapToItem(appListRoot, event.x, event.y);
                appListRoot.dragCursorPos = dockRoot.dockVertical ? mapped.y : mapped.x;
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
        } else if (root.windowCount > 1) {
            // Multiple windows: toggle the preview so there's something to pick between
            if (appListRoot.clickedButton === root) {
                appListRoot.hidePreview();
            } else {
                appListRoot.showPreview(root);
            }
        } else if (root.windowCount === 1) {
            // Exactly one window: nothing to choose between, so skip the
            // preview and go straight to it — the same thing that happens
            // when you click that window's thumbnail inside a preview.
            appListRoot.focusToplevel(root.appToplevel?.toplevels?.[0]);
        } else {
            // Only here: opening a folder or toggling a window preview is not a
            // launch, and animating those would say something happened that did not.
            launchAnims.play(Config.options.dock.launchAnimation);
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
            appListRoot.mousePosInList = dockRoot.dockVertical
                ? mapped.y + appListRoot.listViewRef.contentY
                : mapped.x + appListRoot.listViewRef.contentX;
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
            transformOrigin: dockRoot.dockEdge === "bottom" ? Item.Bottom
                : dockRoot.dockEdge === "top" ? Item.Top
                : dockRoot.dockEdge === "left" ? Item.Left : Item.Right

            Behavior on scale {
                NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
            }

            // Hover glow. Declared before the icon so it is drawn behind it —
            // the icon stays sharp and only the halo shows around the edges.
            // Carries the launch animation's transform for the same reason the
            // tint overlay does: anchors follow geometry, and scale and rotation
            // do not touch geometry, so without it the halo would sit still
            // while the icon moved inside it.
            Loader {
                // Fills the very item it takes as its source: the halo renders
                // that source into its own bounds, so a box of any other size
                // draws a second icon stretched across it rather than a glow
                // around the one that is there. Both icon loaders take their
                // height from what they hold, which is not the whole button.
                anchors.fill: root.isFolder ? folderIconLoader : iconImageLoader
                // Built only while some of it shows, and not at all when it has
                // no reach to speak of: a blur of no radius is the icon's own
                // silhouette in another colour, fringing whatever it shows
                // through rather than glowing.
                active: root.glowFade > 0 && Appearance.sizes.dockGlowReach > 0
                opacity: root.glowFade
                scale: launchAnims.scale
                rotation: launchAnims.rot
                transformOrigin: Item.Center
                sourceComponent: Glow {
                    source: root.isFolder ? folderIconLoader : iconImageLoader
                    radius: Appearance.sizes.dockGlowReach
                    // Sized for the radius the slider can ask for, so turning
                    // it up never underruns the blur.
                    samples: 57
                    color: Appearance.colors.colDockGlow
                    // Without this the blur is cut off at the item edges, and
                    // since the item is exactly the icon's size the halo ends up
                    // entirely behind the icon with nothing showing.
                    transparentBorder: true
                }
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
                scale: launchAnims.scale
                rotation: launchAnims.rot
                transformOrigin: Item.Center
                sourceComponent: IconImage {
                    id: appIconImage
                    source: Quickshell.iconPath(root.desktopEntry?.icon ?? AppSearch.guessIcon(root.lookupAppId), "image-missing")
                    implicitSize: root.iconSize
                    mipmap: true
                    // Rasterize at the hover peak so the parent Item's
                    // `scale: hoverScale` transform is always a downscale
                    // (crisp) rather than an upscale (fuzzy). IconImage's
                    // default sourceSize tracks actualSize (= iconSize) —
                    // at 100% display scale that's only ~iconSize raster
                    // pixels, which look pixelated when the magnification
                    // animation grows the visual size to iconSize * maxScale.
                    // HiDPI display scales mask the bug because Qt's DPR
                    // already multiplies the raster size.
                    //
                    // mipmap on + downscale from the hover-peak raster
                    // keeps the idle state cleanly anti-aliased without
                    // visibly softening the magnified peak (mip 0 == 1:1
                    // sample at full hover).
                    // Rounded up to a step, so dragging the amount dial asks
                    // for a handful of raster sizes rather than one at every
                    // whole number it passes through.
                    backer.sourceSize.width: root.rasterFor(root.iconSize)
                    backer.sourceSize.height: root.rasterFor(root.iconSize)
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
                                id: folderTileIcon
                                required property var modelData
                                source: Quickshell.iconPath(AppSearch.guessIcon(modelData), "image-missing")
                                implicitSize: root.iconSize * 0.4
                                mipmap: true
                                // Folder tiles live in the same scaled Item
                                // as the main app icon, so they need the
                                // same maxScale-bumped sourceSize to stay
                                // crisp through the hover animation.
                                backer.sourceSize.width: root.rasterFor(root.iconSize * 0.4)
                                backer.sourceSize.height: root.rasterFor(root.iconSize * 0.4)
                            }
                        }
                    }
                }
            }

            Loader {
                active: Config.options.dock.monochromeIcons && !root.isFolder
                anchors.fill: iconImageLoader
                // anchors follow geometry, and scale/rotation are render
                // transforms that leave geometry alone — so this has to repeat
                // them or the tint sits still while the icon underneath moves.
                scale: launchAnims.scale
                rotation: launchAnims.rot
                transformOrigin: Item.Center
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

            // How many windows an app holds, said outright rather than
            // counted off in marks. It only speaks from the second window on:
            // one window is what an open app already looks like.
            // Built only for the style that draws it: the marks are the stock
            // choice, so every icon on a default dock would otherwise carry a
            // circle and a text run that can never be shown.
            Loader {
                id: badgeLoader
                readonly property real diameter: Math.max(14, root.iconSize * 0.3)
                active: root.showsBadge
                // The icon corner furthest from the screen, tucked back over
                // the art. Both corners are measured out from the center by
                // half an icon: the loaders around the art are stretched to
                // the button's cross axis, so their own edges sit outside the
                // art by however much wider the button is, which on a dock
                // narrow enough carries the badge clear off the surface.
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    horizontalCenterOffset: (dockRoot.dockEdge === "right" ? -1 : 1)
                        * (root.iconSize / 2 - badgeLoader.diameter * 0.2)
                    verticalCenter: parent.verticalCenter
                    verticalCenterOffset: (dockRoot.dockEdge === "top" ? 1 : -1)
                        * (root.iconSize / 2 - badgeLoader.diameter * 0.15)
                }
                sourceComponent: Rectangle {
                    implicitWidth: badgeLoader.diameter
                    implicitHeight: badgeLoader.diameter
                    radius: badgeLoader.diameter / 2
                    color: Appearance.colors.colDockBadge
                    StyledText {
                        anchors.centerIn: parent
                        text: root.windowCount > 9 ? "9+" : root.windowCount
                        font.pixelSize: badgeLoader.diameter * 0.62
                        color: Appearance.colors.colDockBadgeText
                    }
                }
            }

            GridLayout {
                columnSpacing: 3
                rowSpacing: 3
                columns: dockRoot.dockVertical ? 1 : -1
                rows: dockRoot.dockVertical ? -1 : 1
                anchors {
                    top: dockRoot.dockEdge === "bottom" ? (root.isFolder ? folderIconLoader.bottom : iconImageLoader.bottom) : undefined
                    bottom: dockRoot.dockEdge === "top" ? (root.isFolder ? folderIconLoader.top : iconImageLoader.top) : undefined
                    // On the cross axis the icon loaders are stretched wider
                    // than the art they draw, so the art's side edge has to be
                    // derived from the center — anchoring to the loader's box
                    // edge puts the dots at the window border, where the
                    // magnify scale shoves them past the surface and clips
                    // them into stretched slivers.
                    left: dockRoot.dockEdge === "right" ? parent.horizontalCenter : undefined
                    right: dockRoot.dockEdge === "left" ? parent.horizontalCenter : undefined
                    topMargin: dockRoot.dockEdge === "bottom" ? 2 : 0
                    bottomMargin: dockRoot.dockEdge === "top" ? 2 : 0
                    leftMargin: dockRoot.dockEdge === "right" ? root.iconSize / 2 + 3 : 0
                    rightMargin: dockRoot.dockEdge === "left" ? root.iconSize / 2 + 3 : 0
                    horizontalCenter: dockRoot.dockVertical ? undefined : parent.horizontalCenter
                    verticalCenter: dockRoot.dockVertical ? parent.verticalCenter : undefined
                }
                visible: root.showsMarks
                Repeater {
                    // Gated on the style as well as the count: `visible` alone
                    // still builds a mark per window and rebuilds them on every
                    // window opened or closed, for a style that draws nothing.
                    model: root.showsMarks ? Math.min(root.windowCount, 3) : 0
                    delegate: Rectangle {
                        required property int index
                        // Dashes stretch along the dock while few and tighten
                        // to dots past three; the dots style stays a dot at
                        // any count.
                        readonly property bool asDash: Config.options.dock.indicatorStyle !== "dots"
                            && root.windowCount <= 3
                        radius: Appearance.rounding.full
                        implicitWidth: dockRoot.dockVertical ? root.countDotHeight
                            : asDash ? root.countDotWidth : root.countDotHeight
                        implicitHeight: !dockRoot.dockVertical ? root.countDotHeight
                            : asDash ? root.countDotWidth : root.countDotHeight
                        color: appIsActive ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                    }
                }
            }
        }
    }

    DockLaunchAnimations {
        id: launchAnims
    }
}
