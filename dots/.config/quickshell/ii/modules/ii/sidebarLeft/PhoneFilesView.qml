import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import QtMultimedia

// The phone's storage, mounted by KDE Connect over sshfs.
Item {
    id: root

    // The folder on show and the place it was opened from, as local paths.
    property string folder: ""
    property string activeKey: "camera"
    property string viewMode: "list"
    property bool fullscreenVideo: false
    property bool fullscreenImage: false
    property var fullscreenMedia: null
    readonly property bool isMounted: Phone.mounted
    onFullscreenImageChanged: {
        if (fullscreenImage) Phone.requestThumbnails([]);
        else {
            Phone.cancelFilePreview();
            thumbScanTimer.restart();
        }
    }
    onFullscreenVideoChanged: {
        if (fullscreenVideo) Phone.requestThumbnails([]);
        else thumbScanTimer.restart();
    }

    Connections {
        target: Phone
        function onFilePreviewFinished(request, path, error) {
            if (!root.fullscreenImage || request !== root.fullscreenMedia?.request) return;
            root.fullscreenMedia = Object.assign({}, root.fullscreenMedia, {localPath: path, error});
        }
    }

    function isVideoFile(path): bool {
        return /\.(mp4|mkv|mov|webm|3gp)$/i.test(String(path ?? ""));
    }

    function isImageFile(path): bool {
        return /\.(jpe?g|png|gif|webp|heic|bmp)$/i.test(String(path ?? ""));
    }

    function openMedia(filePath, fileName, thumbSource): void {
        const path = String(filePath ?? "");
        const name = String(fileName ?? "");
        const thumb = String(thumbSource ?? "");
        if (root.isVideoFile(path)) {
            root.fullscreenImage = false;
            root.fullscreenMedia = { path: path, name: name, thumb: thumb, isGif: false };
            root.fullscreenVideo = true;
            mediaPlayer.source = FileUtils.mediaUrl(path);
            mediaPlayer.play();
            videoOverlay.forceActiveFocus();
        } else if (root.isImageFile(path)) {
            const isGif = /\.gif($|\?)/i.test(path);
            if (root.fullscreenVideo) {
                mediaPlayer.stop();
                mediaPlayer.source = "";
                root.fullscreenVideo = false;
            }
            root.fullscreenMedia = { path: path, name: name, thumb: thumb, isGif: isGif, localPath: "", error: "" };
            root.fullscreenImage = true;
            const request = Phone.prepareFilePreview(path);
            root.fullscreenMedia = Object.assign({}, root.fullscreenMedia, {request,
                error: request ? "" : Translation.tr("Could not read file from phone")});
            imageOverlay.forceActiveFocus();
        }
    }

    function exitFullscreen(): void {
        if (root.fullscreenVideo) {
            mediaPlayer.stop();
            mediaPlayer.source = "";
            root.fullscreenVideo = false;
        }
        root.fullscreenImage = false;
        root.fullscreenMedia = null;
    }

    property int mediaRevision: 0
    function refreshMediaItems(): void {
        root.mediaRevision++;
        thumbScanTimer.restart();
    }

    readonly property var currentMediaItems: {
        root.mediaRevision;
        if (folderModel.status !== FolderListModel.Ready) return [];
        const list = [];
        const count = folderModel.count;
        for (let i = 0; i < count; i++) {
            const p = folderModel.get(i, "filePath");
            const isDir = folderModel.get(i, "fileIsDir");
            if (!isDir && p && (root.isImageFile(p) || root.isVideoFile(p))) {
                list.push({
                    index: i,
                    path: p,
                    name: folderModel.get(i, "fileName"),
                    size: folderModel.get(i, "fileSize")
                });
            }
        }
        return list;
    }

    readonly property int currentMediaIndex: {
        if (!root.fullscreenMedia?.path) return -1;
        const currentPath = root.fullscreenMedia.path;
        return root.currentMediaItems.findIndex(m => m.path === currentPath);
    }

    readonly property bool hasPrevMedia: root.currentMediaIndex > 0
    readonly property bool hasNextMedia: root.currentMediaIndex >= 0 && root.currentMediaIndex < (root.currentMediaItems.length - 1)

    function prevMedia(): void {
        if (!root.hasPrevMedia) return;
        const target = root.currentMediaItems[root.currentMediaIndex - 1];
        if (target) {
            root.openMedia(target.path, target.name, Phone.thumbnails[target.path] ?? "");
        }
    }

    function nextMedia(): void {
        if (!root.hasNextMedia) return;
        const target = root.currentMediaItems[root.currentMediaIndex + 1];
        if (target) {
            root.openMedia(target.path, target.name, Phone.thumbnails[target.path] ?? "");
        }
    }

    property bool searchOpen: false
    property string searchQuery: ""
    // Filtering re-lists the folder over sshfs, so it waits for typing to pause.
    property string appliedQuery: ""
    onSearchQueryChanged: {
        if (searchQuery.trim().length === 0) {
            searchApply.stop();
            appliedQuery = "";
        } else searchApply.restart();
    }
    Timer {
        id: searchApply
        interval: 250
        onTriggered: root.appliedQuery = root.searchQuery.trim()
    }

    property string sortFieldKey: "date"
    property bool sortReversed: true
    property bool sortMenuOpen: false

    property bool selectionMode: false
    property var selectedFiles: ({})
    readonly property var selectedPathsList: Object.keys(root.selectedFiles)
    readonly property int selectedCount: root.selectedPathsList.length
    readonly property var selectedFilePaths: root.selectedPathsList.filter(p => !root.selectedFiles[p]?.isDir)
    property var selectedSaveRequests: ({})
    readonly property int pendingSelectedSaves: Object.keys(root.selectedSaveRequests).length
    readonly property real selectedTotalBytes: {
        let total = 0;
        for (const p of root.selectedPathsList) {
            total += Number(root.selectedFiles[p]?.size || 0);
        }
        return total;
    }

    function isSelected(filePath): bool {
        return !!root.selectedFiles[filePath];
    }

    function toggleSelect(filePath, size, isDir): void {
        const p = String(filePath || "");
        if (!p) return;
        const copy = Object.assign({}, root.selectedFiles);
        if (copy[p]) {
            delete copy[p];
        } else {
            copy[p] = { size: size || 0, isDir: !!isDir };
        }
        root.selectedFiles = copy;
    }

    function endSelection(): void {
        root.clearSelection();
        root.selectionMode = false;
    }

    function clearSelection(): void {
        root.selectedFiles = ({});
    }

    function downloadSelected(): void {
        if (root.pendingSelectedSaves) return;
        const requests = {};
        for (const path of root.selectedFilePaths) {
            const request = Phone.saveCopy(path, "", false, "files");
            if (request) requests[request] = path;
        }
        root.selectedSaveRequests = requests;
    }

    Connections {
        target: Phone
        function onSaveFinished(request, source, success) {
            if (root.selectedSaveRequests[request] !== source) return;
            const requests = Object.assign({}, root.selectedSaveRequests);
            delete requests[request];
            root.selectedSaveRequests = requests;
            if (success) {
                const selected = Object.assign({}, root.selectedFiles);
                delete selected[source];
                root.selectedFiles = selected;
            }
            // Failed files remain selected so they can be retried.
            if (!root.pendingSelectedSaves && root.selectedCount === 0) root.selectionMode = false;
        }
    }

    Timer {
        id: thumbScanTimer
        interval: 120
        repeat: false
        onTriggered: root.scanThumbnails()
    }

    onFolderChanged: {
        root.exitFullscreen();
        root.searchOpen = false;
        root.searchQuery = "";
        root.sortMenuOpen = false;
        root.endSelection();
        thumbScanTimer.restart();
    }

    function scanThumbnails(): void {
        if (!visible || fullscreenImage || fullscreenVideo || !Phone.mounted || root.folder.length === 0) return;
        const count = folderModel.count;
        const paths = [];
        const view = root.viewMode === "list" ? fileList : fileGrid;
        const start = Math.max(0, view.indexAt(1, view.contentY + 1));
        // The screen in view first, then the next one, so scrolling finds them ready.
        for (let i = start; i < Math.min(count, start + 48); i++) {
            const p = folderModel.get(i, "filePath");
            const isDir = folderModel.get(i, "fileIsDir");
            if (!isDir && p && !(Phone.thumbnails[p] ?? "").length && /\.(jpe?g|png|webp|heic|bmp|mp4|mov|mkv|webm)$/i.test(p)) {
                paths.push(p);
            }
        }
        Phone.requestThumbnails(paths);
    }

    readonly property bool sshfsMissing: Phone.mountError.length > 0 && Phone.sshfsMissing
    readonly property color colCard: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer1, 0.94)

    function placePath(path): string {
        const p = String(path ?? "");
        return p.startsWith(Phone.mountPoint) || Phone.mountPoint.length === 0 ? p : Phone.mountPoint + (p.startsWith("/") ? "" : "/") + p;
    }

    // On current Android the first place, or else /storage/emulated/0, is the storage users see.
    readonly property string storageRoot: {
        const places = Phone.places ?? [];
        if (places.length > 0 && places[0].path) {
            return root.placePath(places[0].path);
        }
        if (Phone.mountPoint && Phone.mountPoint.length > 0) {
            return root.placePath("storage/emulated/0");
        }
        return Phone.mountPoint;
    }

    function resolveQuickPlace(key): string {
        const base = root.storageRoot;
        if (!base || base.length === 0) return "";

        const places = Phone.places ?? [];
        for (const p of places) {
            const name = String(p.name ?? "").toLowerCase();
            const path = String(p.path ?? "").toLowerCase();
            if (key === "camera" && (name.includes("camera") || path.includes("camera") || path.includes("dcim")))
                return root.placePath(p.path);
            if (key === "downloads" && (name.includes("download") || path.includes("download")))
                return root.placePath(p.path);
            if (key === "screenshots" && (name.includes("screenshot") || path.includes("screenshot")))
                return root.placePath(p.path);
        }

        if (key === "camera") {
            return base + "/DCIM/Camera";
        } else if (key === "downloads") {
            return base + "/Download";
        } else if (key === "screenshots") {
            return base + "/DCIM/Screenshots";
        } else {
            return base;
        }
    }

    function updateActiveKeyForFolder(): void {
        const f = root.folder.toLowerCase();
        if (f.endsWith("/camera") || f.includes("/dcim/camera")) root.activeKey = "camera";
        else if (f.endsWith("/download") || f.endsWith("/downloads")) root.activeKey = "downloads";
        else if (f.includes("screenshot")) root.activeKey = "screenshots";
        else root.activeKey = "storage";
    }

    // True once the user opens a folder or goes up; a places refresh then keeps that folder.
    property bool browsed: false
    function openQuickPlace(key): void {
        root.browsed = false;
        root.activeKey = key;
        const target = root.resolveQuickPlace(key);
        root.folder = target;
    }

    readonly property bool canGoUp: root.folder.length > 0 && root.folder !== root.storageRoot

    function up(): void {
        if (!root.canGoUp) return;
        root.browsed = true;
        const lastSlash = root.folder.lastIndexOf("/");
        if (lastSlash > 0) {
            const parentFolder = root.folder.slice(0, lastSlash);
            if (parentFolder.length >= root.storageRoot.length) {
                root.folder = parentFolder;
            } else {
                root.folder = root.storageRoot;
            }
        } else {
            root.folder = root.storageRoot;
        }
        root.updateActiveKeyForFolder();
    }

    readonly property string folderTitle: {
        if (root.folder === root.storageRoot) return Translation.tr("Internal Storage");
        if (root.folder === root.resolveQuickPlace("camera")) return Translation.tr("Camera & Media");
        if (root.folder === root.resolveQuickPlace("downloads")) return Translation.tr("Downloads");
        if (root.folder === root.resolveQuickPlace("screenshots")) return Translation.tr("Screenshots");
        return root.folder.slice(root.folder.lastIndexOf("/") + 1) || Translation.tr("Files");
    }

    readonly property string currentPlaceIcon: {
        if (root.activeKey === "camera") return "photo_camera";
        if (root.activeKey === "downloads") return "download";
        if (root.activeKey === "screenshots") return "screenshot_monitor";
        return "folder_open";
    }

    function sizeText(bytes): string {
        if (bytes < 1024) return Translation.tr("%1 B").arg(bytes);
        if (bytes < 1024 * 1024) return Translation.tr("%1 KB").arg(Math.round(bytes / 1024));
        if (bytes < 1024 * 1024 * 1024) return Translation.tr("%1 MB").arg((bytes / 1048576).toFixed(1));
        return Translation.tr("%1 GB").arg((bytes / 1073741824).toFixed(1));
    }

    onStorageRootChanged: {
        if (root.storageRoot.length > 0 && (root.folder.length === 0 || !root.folder.startsWith(root.storageRoot))) {
            root.openQuickPlace(root.activeKey || "camera");
        }
    }

    Connections {
        target: Phone
        function onMountedChanged() {
            if (!root.isMounted) {
                root.folder = "";
            } else if (root.storageRoot.length > 0) {
                root.openQuickPlace(root.activeKey || "camera");
            }
        }
        function onMountPointChanged() {
            if (Phone.mounted && root.storageRoot.length > 0) {
                root.openQuickPlace(root.activeKey || "camera");
            }
        }
        // A refresh of the same storage keeps a folder the user browsed to; until then the
        // quick place is resolved again, since the first open can come before the places do.
        function onPlacesChanged() {
            if (Phone.mounted && root.storageRoot.length > 0
                && !(root.browsed && root.folder.startsWith(root.storageRoot + "/"))) {
                root.openQuickPlace(root.activeKey || "camera");
            }
        }
        function onDeviceIdChanged() {
            root.folder = "";
            if (Phone.mounted && root.storageRoot.length > 0) {
                root.openQuickPlace(root.activeKey || "camera");
            }
        }
    }

    function autoMountIfReachable(): void {
        if (Phone.reachable && !Phone.mounted && !Phone.mounting && Phone.mountError.length === 0) {
            Phone.mountFiles();
        }
    }

    Component.onCompleted: {
        if (Phone.mounted && root.storageRoot.length > 0) {
            root.openQuickPlace("camera");
        } else {
            root.autoMountIfReachable();
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (!GlobalStates.sidebarLeftOpen) root.exitFullscreen();
        }
    }

    onVisibleChanged: {
        if (visible) {
            if (Phone.mounted && root.storageRoot.length > 0) {
                root.openQuickPlace(root.activeKey || "camera");
            } else {
                root.autoMountIfReachable();
            }
        } else {
            Phone.requestThumbnails([]);
            root.exitFullscreen();
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - 20
        spacing: 14
        visible: !root.isMounted

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 64
            implicitHeight: 64
            radius: 20
            color: root.colCard

            MaterialSymbol {
                anchors.centerIn: parent
                text: "folder_open"
                iconSize: 32
                color: Appearance.colors.colPrimary
            }
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: Phone.mounting ? Translation.tr("Opening your phone's files…")
                : root.sshfsMissing ? Translation.tr("Browsing phone files needs sshfs. Install it, then try again:\nsudo pacman -S sshfs")
                : Phone.mountError.length > 0 ? Translation.tr("Could not open your phone's files: %1").arg(Phone.mountError)
                : Translation.tr("Browse the photos, downloads and other files on your phone.")
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.small
        }
        MaterialLoadingIndicator {
            Layout.alignment: Qt.AlignHCenter
            visible: Phone.mounting
            implicitSize: 36
            loading: visible
        }
        RippleButton {
            Layout.alignment: Qt.AlignHCenter
            visible: !Phone.mounting
            enabled: Phone.reachable
            implicitHeight: 38
            implicitWidth: browseBtnRow.implicitWidth + 24
            buttonRadius: 12
            colBackground: Appearance.colors.colPrimaryContainer
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            colRipple: Appearance.colors.colPrimaryContainerActive
            onClicked: Phone.mountFiles()

            contentItem: RowLayout {
                id: browseBtnRow
                anchors.centerIn: parent
                spacing: 7
                MaterialSymbol {
                    text: "smartphone"
                    iconSize: 17
                    color: Appearance.colors.colOnPrimaryContainer
                }
                StyledText {
                    text: Phone.mountError.length > 0 ? Translation.tr("Try again") : Translation.tr("Browse phone files")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        visible: root.isMounted
        spacing: 8

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 2
            columnSpacing: 2

            Repeater {
                model: [
                    {
                        key: "camera",
                        icon: "photo_camera",
                        title: Translation.tr("Camera & Media"),
                        sub: Translation.tr("DCIM / Camera"),
                        tl: 18, tr: 4, bl: 4, br: 4
                    },
                    {
                        key: "downloads",
                        icon: "download",
                        title: Translation.tr("Downloads"),
                        sub: Translation.tr("Received & Web"),
                        tl: 4, tr: 18, bl: 4, br: 4
                    },
                    {
                        key: "screenshots",
                        icon: "screenshot_monitor",
                        title: Translation.tr("Screenshots"),
                        sub: Translation.tr("Pictures / Captures"),
                        tl: 4, tr: 4, bl: 18, br: 4
                    },
                    {
                        key: "storage",
                        icon: "folder_open",
                        title: Translation.tr("Internal Storage"),
                        sub: Translation.tr("Root filesystem"),
                        tl: 4, tr: 4, bl: 4, br: 18
                    }
                ]

                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    readonly property bool isActive: root.activeKey === tile.modelData.key

                    Layout.fillWidth: true
                    implicitHeight: tileContents.implicitHeight + 20
                    topLeftRadius: tile.modelData.tl
                    topRightRadius: tile.modelData.tr
                    bottomLeftRadius: tile.modelData.bl
                    bottomRightRadius: tile.modelData.br

                    color: {
                        if (tile.isActive) {
                            return tileMouse.pressed
                                ? Appearance.colors.colPrimaryContainerActive
                                : (tileMouse.containsMouse ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer);
                        }
                        return tileMouse.pressed
                            ? Appearance.colors.colLayer2Active
                            : (tileMouse.containsMouse ? Appearance.colors.colLayer2Hover : root.colCard);
                    }

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openQuickPlace(tile.modelData.key)
                    }

                    ColumnLayout {
                        id: tileContents
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true

                            Rectangle {
                                implicitWidth: 28
                                implicitHeight: 28
                                radius: 8
                                color: tile.isActive
                                    ? Appearance.colors.colPrimary
                                    : ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: tile.modelData.icon
                                    iconSize: 16
                                    fill: tile.isActive ? 1 : 0
                                    color: tile.isActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                                }
                            }

                            Item { Layout.fillWidth: true }

                            MaterialSymbol {
                                text: "chevron_right"
                                iconSize: 15
                                color: tile.isActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                            }
                        }

                        ColumnLayout {
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: tile.modelData.title
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: tile.isActive ? Font.DemiBold : Font.Medium
                                color: tile.isActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: tile.modelData.sub
                                font.pixelSize: 10
                                color: tile.isActive
                                    ? ColorUtils.mix(Appearance.colors.colOnPrimaryContainer, Appearance.colors.colPrimaryContainer, 0.25)
                                    : Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 38
            radius: 10
            color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.45)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 10
                spacing: 8

                RippleButton {
                    enabled: root.canGoUp
                    opacity: root.canGoUp ? 1.0 : 0.35
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: 8
                    colBackground: root.canGoUp
                        ? ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer1, 0.88)
                        : "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: root.up()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "arrow_back"
                        iconSize: 16
                        color: root.canGoUp ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                    }
                    StyledToolTip {
                        text: root.canGoUp ? Translation.tr("Go up to parent folder") : Translation.tr("At storage root")
                    }
                }

                MaterialSymbol {
                    text: root.currentPlaceIcon
                    iconSize: 16
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.folderTitle
                    elide: Text.ElideMiddle
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    text: Translation.tr("%1 items").arg(folderModel.count)
                    font.pixelSize: 11
                    color: Appearance.colors.colSubtext
                }

                Rectangle {
                    implicitHeight: 26
                    implicitWidth: toolCapsuleRow.implicitWidth + 6
                    radius: 8
                    color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.6)

                    RowLayout {
                        id: toolCapsuleRow
                        anchors.centerIn: parent
                        spacing: 2

                        RippleButton {
                            implicitWidth: 26
                            implicitHeight: 22
                            buttonRadius: 6
                            padding: 0
                            colBackground: root.searchOpen ? Appearance.colors.colPrimaryContainer : "transparent"
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: {
                                root.searchOpen = !root.searchOpen;
                                if (!root.searchOpen) root.searchQuery = "";
                            }
                            contentItem: Item {
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "search"
                                    iconSize: 14
                                    color: root.searchOpen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                                }
                            }
                            StyledToolTip { text: Translation.tr("Search files…") }
                        }

                        Rectangle {
                            implicitWidth: 2
                            Layout.fillHeight: true
                            Layout.topMargin: 3
                            Layout.bottomMargin: 3
                            color: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer0, 0.8)
                        }

                        RippleButton {
                            implicitHeight: 22
                            implicitWidth: sortBtnRow.implicitWidth + 8
                            buttonRadius: 6
                            padding: 0
                            colBackground: root.sortMenuOpen ? Appearance.colors.colPrimaryContainer : "transparent"
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: root.sortMenuOpen = !root.sortMenuOpen
                            contentItem: RowLayout {
                                id: sortBtnRow
                                anchors.centerIn: parent
                                spacing: 2
                                MaterialSymbol {
                                    text: "sort"
                                    iconSize: 13
                                    color: root.sortMenuOpen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colPrimary
                                }
                                StyledText {
                                    text: {
                                        if (root.sortFieldKey === "date") return Translation.tr("Date");
                                        if (root.sortFieldKey === "size") return Translation.tr("Size");
                                        if (root.sortFieldKey === "type") return Translation.tr("Type");
                                        return Translation.tr("Name");
                                    }
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                    color: root.sortMenuOpen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colPrimary
                                }
                                MaterialSymbol {
                                    text: root.sortReversed ? "arrow_downward" : "arrow_upward"
                                    iconSize: 10
                                    color: root.sortMenuOpen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colPrimary
                                }
                            }
                            StyledToolTip { text: Translation.tr("Sort by:") }
                        }

                        Rectangle {
                            implicitWidth: 2
                            Layout.fillHeight: true
                            Layout.topMargin: 3
                            Layout.bottomMargin: 3
                            color: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer0, 0.8)
                        }

                        RippleButton {
                            implicitHeight: 22
                            implicitWidth: selectBtnRow.implicitWidth + 8
                            buttonRadius: 6
                            padding: 0
                            colBackground: root.selectionMode ? Appearance.colors.colPrimary : "transparent"
                            colBackgroundHover: root.selectionMode ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
                            onClicked: {
                                root.selectionMode = !root.selectionMode;
                                if (!root.selectionMode) root.clearSelection();
                            }
                            contentItem: RowLayout {
                                id: selectBtnRow
                                anchors.centerIn: parent
                                spacing: 2
                                MaterialSymbol {
                                    text: root.selectionMode ? "check_box" : "checklist"
                                    iconSize: 13
                                    color: root.selectionMode ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                                    fill: root.selectionMode ? 1 : 0
                                }
                                StyledText {
                                    text: root.selectionMode ? Translation.tr("Done") : Translation.tr("Select")
                                    font.pixelSize: 10
                                    font.weight: root.selectionMode ? Font.DemiBold : Font.Normal
                                    color: root.selectionMode ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                                }
                            }
                            StyledToolTip { text: root.selectionMode ? Translation.tr("Exit select mode") : Translation.tr("Select multiple files") }
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 26
                    implicitWidth: viewSwitcherRow.implicitWidth + 4
                    radius: 8
                    color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.6)

                    RowLayout {
                        id: viewSwitcherRow
                        anchors.centerIn: parent
                        spacing: 2

                        RippleButton {
                            implicitWidth: 26
                            implicitHeight: 22
                            buttonRadius: 6
                            padding: 0
                            leftPadding: 0
                            rightPadding: 0
                            topPadding: 0
                            bottomPadding: 0
                            colBackground: root.viewMode === "list" ? Appearance.colors.colPrimaryContainer : "transparent"
                            colBackgroundHover: root.viewMode === "list"
                                ? Appearance.colors.colPrimaryContainerHover
                                : ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colLayer0, 0.5)
                            onClicked: root.viewMode = "list"
                            contentItem: Item {
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "view_list"
                                    iconSize: 15
                                    color: root.viewMode === "list" ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                                }
                            }
                            StyledToolTip {
                                text: Translation.tr("List view")
                            }
                        }

                        RippleButton {
                            implicitWidth: 26
                            implicitHeight: 22
                            buttonRadius: 6
                            padding: 0
                            leftPadding: 0
                            rightPadding: 0
                            topPadding: 0
                            bottomPadding: 0
                            colBackground: root.viewMode === "grid" ? Appearance.colors.colPrimaryContainer : "transparent"
                            colBackgroundHover: root.viewMode === "grid"
                                ? Appearance.colors.colPrimaryContainerHover
                                : ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colLayer0, 0.5)
                            onClicked: root.viewMode = "grid"
                            contentItem: Item {
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "grid_view"
                                    iconSize: 15
                                    color: root.viewMode === "grid" ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                                }
                            }
                            StyledToolTip {
                                text: Translation.tr("Grid view")
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 34
            radius: 10
            visible: root.searchOpen || root.searchQuery.length > 0
            color: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.45)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 6

                MaterialSymbol {
                    text: "search"
                    iconSize: 15
                    color: Appearance.colors.colPrimary
                }

                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Search files…")
                    color: Appearance.colors.colOnLayer1
                    placeholderTextColor: Appearance.colors.colSubtext
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    background: null
                    text: root.searchQuery
                    onTextChanged: root.searchQuery = text
                    Keys.onEscapePressed: {
                        if (text.length > 0) text = "";
                        else root.searchOpen = false;
                    }
                }

                Rectangle {
                    visible: root.searchQuery.length > 0
                    implicitHeight: 18
                    implicitWidth: matchCountText.implicitWidth + 10
                    radius: 4
                    color: Appearance.colors.colLayer2

                    StyledText {
                        id: matchCountText
                        anchors.centerIn: parent
                        text: Translation.tr("%1 matches").arg(folderModel.count)
                        font.pixelSize: 10
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButton {
                    implicitWidth: 22
                    implicitHeight: 22
                    buttonRadius: 11
                    onClicked: {
                        searchField.text = "";
                        root.searchOpen = false;
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 14
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: sortCol.implicitHeight + 14
            radius: 10
            visible: root.sortMenuOpen
            color: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer0, 0.94)

            ColumnLayout {
                id: sortCol
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    StyledText {
                        text: Translation.tr("Sort by:")
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                        Layout.leftMargin: 2
                    }

                    Item { Layout.fillWidth: true }

                    RippleButton {
                        implicitHeight: 22
                        implicitWidth: orderRow.implicitWidth + 10
                        buttonRadius: 6
                        colBackground: ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: root.sortReversed = !root.sortReversed
                        contentItem: RowLayout {
                            id: orderRow
                            anchors.centerIn: parent
                            spacing: 3
                            MaterialSymbol {
                                text: root.sortReversed ? "arrow_downward" : "arrow_upward"
                                iconSize: 12
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: root.sortReversed ? Translation.tr("Descending") : Translation.tr("Ascending")
                                font.pixelSize: 9
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: [
                            { key: "date", label: Translation.tr("Date") },
                            { key: "name", label: Translation.tr("Name") },
                            { key: "size", label: Translation.tr("Size") },
                            { key: "type", label: Translation.tr("Type") }
                        ]

                        delegate: RippleButton {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 26
                            buttonRadius: 6
                            colBackground: root.sortFieldKey === modelData.key
                                ? Appearance.colors.colPrimaryContainer
                                : ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: {
                                root.sortFieldKey = modelData.key;
                                root.sortMenuOpen = false;
                            }
                            contentItem: StyledText {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: 10
                                font.weight: root.sortFieldKey === modelData.key ? Font.DemiBold : Font.Normal
                                color: root.sortFieldKey === modelData.key
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            FolderListModel {
                id: folderModel
                folder: (root.folder.length > 0 && root.storageRoot.length > 0 && root.folder.startsWith(root.storageRoot))
                    ? FileUtils.fileUrl(root.folder)
                    : "file:///dev/null"
                showDirsFirst: true
                showHidden: false
                showDotAndDotDot: false
                caseSensitive: false
                nameFilters: root.appliedQuery.length > 0 ? ["*" + root.appliedQuery.replace(/[*?[]/g, "[$&]") + "*"] : []  // typed * ? [ are literal
                sortField: {
                    if (root.sortFieldKey === "date") return FolderListModel.Time;
                    if (root.sortFieldKey === "size") return FolderListModel.Size;
                    if (root.sortFieldKey === "type") return FolderListModel.Type;
                    return FolderListModel.Name;
                }
                // QDir's native Time/Size ordering is already descending.
                sortReversed: (root.sortFieldKey === "date" || root.sortFieldKey === "size")
                    ? !root.sortReversed : root.sortReversed
                onCountChanged: thumbScanTimer.restart()
            }

            Connections {
                target: folderModel
                // get() values are snapshots. Sorting can reset the model
                // without changing its count, so invalidate navigation too.
                function onModelReset() { Qt.callLater(root.refreshMediaItems); }
                function onLayoutChanged() { Qt.callLater(root.refreshMediaItems); }
                function onDataChanged() { Qt.callLater(root.refreshMediaItems); }
                function onRowsInserted() { Qt.callLater(root.refreshMediaItems); }
                function onRowsRemoved() { Qt.callLater(root.refreshMediaItems); }
                function onRowsMoved() { Qt.callLater(root.refreshMediaItems); }
            }

            StyledListView {
                id: fileList
                onMovementEnded: thumbScanTimer.restart()
                onContentYChanged: thumbScanTimer.restart()
                visible: root.viewMode === "list"
                anchors.fill: parent
                clip: true
                spacing: 2
                popin: false
                model: root.viewMode === "list" ? folderModel : null
                delegate: Item {
                    id: entry
                    required property int index
                    required property string fileName
                    required property string filePath
                    required property bool fileIsDir
                    required property var fileSize
                    readonly property bool isFirst: entry.index === 0
                    readonly property bool isLast: entry.index === (folderModel.count - 1)
                    readonly property string thumbSource: Phone.thumbnails[entry.filePath] ?? ""
                    width: fileList.width
                    implicitHeight: 48
                    readonly property bool isOpening: Phone.openingFilePath === entry.filePath

                    Rectangle {
                        anchors.fill: parent
                        topLeftRadius: entry.isFirst ? 16 : 4
                        topRightRadius: entry.isFirst ? 16 : 4
                        bottomLeftRadius: entry.isLast ? 16 : 4
                        bottomRightRadius: entry.isLast ? 16 : 4
                        color: (root.selectionMode && root.isSelected(entry.filePath))
                            ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, root.colCard, 0.35)
                            : (entryMouse.pressed
                                ? Appearance.colors.colLayer2Active
                                : (entryMouse.containsMouse ? Appearance.colors.colLayer2Hover : root.colCard))

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }

                    MouseArea {
                        id: entryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.selectionMode) {
                                root.toggleSelect(entry.filePath, Number(entry.fileSize), entry.fileIsDir);
                                return;
                            }
                            if (entry.fileIsDir) {
                                root.browsed = true;
                                root.folder = entry.filePath;
                                root.updateActiveKeyForFolder();
                            } else if (root.isVideoFile(entry.filePath) || root.isImageFile(entry.filePath)) {
                                root.openMedia(entry.filePath, entry.fileName, entry.thumbSource);
                            } else {
                                Phone.openFile(entry.filePath);
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 10

                        Rectangle {
                            visible: root.selectionMode
                            implicitWidth: 20
                            implicitHeight: 20
                            radius: 6
                            color: root.isSelected(entry.filePath) ? Appearance.colors.colPrimary : "transparent"
                            border.color: root.isSelected(entry.filePath) ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            border.width: root.isSelected(entry.filePath) ? 0 : 1.5

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "check"
                                iconSize: 14
                                color: Appearance.colors.colOnPrimary
                                visible: root.isSelected(entry.filePath)
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: 9
                            clip: true
                            color: entry.fileIsDir
                                ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer1, 0.55)
                                : isOpening
                                    ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer1, 0.55)
                                    : ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)

                            Image {
                                anchors.fill: parent
                                visible: !entry.fileIsDir && !isOpening && entry.thumbSource.length > 0
                                source: entry.thumbSource.length > 0 ? FileUtils.fileUrl(entry.thumbSource) : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                            }

                            MaterialLoadingIndicator {
                                anchors.centerIn: parent
                                visible: isOpening
                                implicitSize: 18
                                loading: isOpening
                            }

                            MaterialSymbol {
                                visible: !isOpening && (entry.fileIsDir || entry.thumbSource.length === 0)
                                anchors.centerIn: parent
                                text: entry.fileIsDir ? "folder" : /\.(jpe?g|png|gif|webp|heic|bmp)$/i.test(entry.fileName) ? "image"
                                    : /\.(mp4|mkv|mov|webm|3gp)$/i.test(entry.fileName) ? "movie"
                                    : /\.(mp3|m4a|ogg|opus|flac|wav)$/i.test(entry.fileName) ? "music_note" : "description"
                                iconSize: 16
                                color: entry.fileIsDir || isOpening ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: entry.fileName
                            elide: Text.ElideMiddle
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: entry.fileIsDir ? Font.Medium : Font.Normal
                            color: Appearance.colors.colOnLayer1
                        }

                        StyledText {
                            visible: !entry.fileIsDir
                            text: isOpening ? Translation.tr("Opening…") : root.sizeText(Number(entry.fileSize))
                            font.pixelSize: 11
                            color: isOpening ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        }

                        RippleButton {
                            visible: !entry.fileIsDir
                            implicitWidth: 30
                            implicitHeight: 30
                            buttonRadius: 9
                            colBackground: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer1, 0.88)
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: Phone.saveCopy(entry.filePath, "", false, "files")
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: "download"
                                iconSize: 16
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledToolTip {
                                text: Translation.tr("Save to Downloads")
                            }
                        }
                    }
                }
            }

            GridView {
                id: fileGrid
                onMovementEnded: thumbScanTimer.restart()
                onContentYChanged: thumbScanTimer.restart()
                visible: root.viewMode === "grid"
                anchors.fill: parent
                clip: true
                cellWidth: Math.floor(fileGrid.width / 2)
                cellHeight: 156
                model: root.viewMode === "grid" ? folderModel : null

                ScrollBar.vertical: StyledScrollBar {}

                delegate: Item {
                    id: gridEntry
                    required property string fileName
                    required property string filePath
                    required property bool fileIsDir
                    required property var fileSize
                    readonly property string thumbSource: Phone.thumbnails[gridEntry.filePath] ?? ""
                    readonly property bool isOpening: Phone.openingFilePath === gridEntry.filePath

                    width: fileGrid.cellWidth
                    height: fileGrid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: 14
                        color: (root.selectionMode && root.isSelected(gridEntry.filePath))
                            ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, root.colCard, 0.35)
                            : (gridMouse.pressed
                                ? Appearance.colors.colLayer2Active
                                : (gridMouse.containsMouse ? Appearance.colors.colLayer2Hover : root.colCard))

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        MouseArea {
                            id: gridMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.selectionMode) {
                                    root.toggleSelect(gridEntry.filePath, Number(gridEntry.fileSize), gridEntry.fileIsDir);
                                    return;
                                }
                                if (gridEntry.fileIsDir) {
                                    root.browsed = true;
                                    root.folder = gridEntry.filePath;
                                    root.updateActiveKeyForFolder();
                                } else if (root.isVideoFile(gridEntry.filePath) || root.isImageFile(gridEntry.filePath)) {
                                    root.openMedia(gridEntry.filePath, gridEntry.fileName, gridEntry.thumbSource);
                                } else {
                                    Phone.openFile(gridEntry.filePath);
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                topLeftRadius: 14
                                topRightRadius: 14
                                bottomLeftRadius: 0
                                bottomRightRadius: 0
                                clip: true
                                color: gridEntry.fileIsDir
                                    ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer1, 0.45)
                                    : ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colLayer1, 0.5)

                                Image {
                                    anchors.fill: parent
                                    visible: !gridEntry.fileIsDir && !gridEntry.isOpening && gridEntry.thumbSource.length > 0
                                    source: gridEntry.thumbSource.length > 0 ? FileUtils.fileUrl(gridEntry.thumbSource) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                }

                                Rectangle {
                                    visible: root.selectionMode
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 6
                                    implicitWidth: 22
                                    implicitHeight: 22
                                    radius: 11
                                    color: root.isSelected(gridEntry.filePath) ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colLayer0, 0.4)
                                    border.color: root.isSelected(gridEntry.filePath) ? Appearance.colors.colPrimary : "white"
                                    border.width: root.isSelected(gridEntry.filePath) ? 0 : 1.5

                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "check"
                                        iconSize: 14
                                        color: Appearance.colors.colOnPrimary
                                        visible: root.isSelected(gridEntry.filePath)
                                    }
                                }

                                Rectangle {
                                    visible: /\.(mp4|mkv|mov|webm|3gp)$/i.test(gridEntry.fileName) && !gridEntry.isOpening
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.margins: 6
                                    implicitWidth: 20
                                    implicitHeight: 20
                                    radius: 6
                                    color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.35)
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "play_arrow"
                                        iconSize: 12
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }

                                MaterialLoadingIndicator {
                                    anchors.centerIn: parent
                                    visible: gridEntry.isOpening
                                    implicitSize: 22
                                    loading: gridEntry.isOpening
                                }

                                MaterialSymbol {
                                    visible: !gridEntry.isOpening && (gridEntry.fileIsDir || gridEntry.thumbSource.length === 0)
                                    anchors.centerIn: parent
                                    text: gridEntry.fileIsDir ? "folder" : /\.(jpe?g|png|gif|webp|heic|bmp)$/i.test(gridEntry.fileName) ? "image"
                                        : /\.(mp4|mkv|mov|webm|3gp)$/i.test(gridEntry.fileName) ? "movie"
                                        : /\.(mp3|m4a|ogg|opus|flac|wav)$/i.test(gridEntry.fileName) ? "music_note" : "description"
                                    iconSize: gridEntry.fileIsDir ? 32 : 24
                                    color: gridEntry.fileIsDir ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 44
                                bottomLeftRadius: 14
                                bottomRightRadius: 14
                                color: "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 6
                                    spacing: 4

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: gridEntry.fileName
                                            elide: Text.ElideMiddle
                                            font.pixelSize: 11
                                            font.weight: gridEntry.fileIsDir ? Font.DemiBold : Font.Normal
                                            color: Appearance.colors.colOnLayer1
                                        }

                                        StyledText {
                                            text: gridEntry.fileIsDir
                                                ? Translation.tr("Folder")
                                                : (gridEntry.isOpening ? Translation.tr("Opening…") : root.sizeText(Number(gridEntry.fileSize)))
                                            font.pixelSize: 10
                                            color: gridEntry.isOpening ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                        }
                                    }

                                    RippleButton {
                                        visible: !gridEntry.fileIsDir
                                        implicitWidth: 26
                                        implicitHeight: 26
                                        buttonRadius: 7
                                        colBackground: ColorUtils.mix(Appearance.colors.colLayer2, Appearance.colors.colOnLayer1, 0.88)
                                        colBackgroundHover: Appearance.colors.colLayer2Hover
                                        onClicked: Phone.saveCopy(gridEntry.filePath, "", false, "files")
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "download"
                                            iconSize: 14
                                            color: Appearance.colors.colOnLayer1
                                        }
                                        StyledToolTip {
                                            text: Translation.tr("Save to Downloads")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                anchors.centerIn: parent
                visible: folderModel.count === 0 && root.folder.length > 0
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "folder_open"
                        iconSize: 28
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Folder is empty")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            implicitHeight: root.selectionMode ? 48 : 0
            visible: root.selectionMode
            radius: 24
            color: Appearance.colors.colLayer2
            border.color: Appearance.colors.colLayer0
            border.width: 1
            clip: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 8
                spacing: 10

                Rectangle {
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 15
                    color: Appearance.colors.colPrimaryContainer

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "check"
                        iconSize: 18
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        text: root.selectedCount === 1
                            ? Translation.tr("1 file selected")
                            : Translation.tr("%1 files selected").arg(root.selectedCount)
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        text: Translation.tr("%1 total").arg(root.sizeText(root.selectedTotalBytes))
                        font.pixelSize: 10
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButton {
                    implicitHeight: 32
                    implicitWidth: dlLayout.implicitWidth + 24
                    buttonRadius: 16
                    colBackground: root.selectedCount > 0 ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer1
                    colBackgroundHover: root.selectedCount > 0 ? Appearance.colors.colPrimary : Appearance.colors.colLayer1Hover
                    enabled: root.selectedFilePaths.length > 0 && root.pendingSelectedSaves === 0
                    opacity: enabled ? 1 : 0.5
                    onClicked: root.downloadSelected()

                    contentItem: RowLayout {
                        id: dlLayout
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "download"
                            iconSize: 16
                            color: root.selectedCount > 0 ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }

                        StyledText {
                            text: root.pendingSelectedSaves > 0
                                ? Translation.tr("Saving (%1)").arg(root.pendingSelectedSaves)
                                : Translation.tr("Download (%1)").arg(root.selectedFilePaths.length)
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: root.selectedCount > 0 ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                    }

                    StyledToolTip {
                        text: Translation.tr("Save selected files to Downloads")
                    }
                }

                RippleButton {
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: 16
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: {
                        root.endSelection();
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 16
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledToolTip {
                        text: Translation.tr("Exit select mode")
                    }
                }
            }
        }

        PhoneSaveCard {
            id: pageSaveCard
            Layout.fillWidth: true
            from: "files"
        }
    }

    MediaPlayer {
        id: mediaPlayer
        videoOutput: fullVideo
        audioOutput: AudioOutput {}
        loops: MediaPlayer.Infinite
        onErrorOccurred: (error, errorString) => {
            console.warn("PhoneFilesView video error:", error, errorString);
            root.exitFullscreen();
        }
        onPlaybackStateChanged: {
            if (mediaPlayer.playbackState === MediaPlayer.StoppedState &&
                mediaPlayer.duration > 0 &&
                mediaPlayer.position >= mediaPlayer.duration - 300) {
                mediaPlayer.setPosition(0);
                mediaPlayer.play();
            }
        }
    }

    Item {
        id: videoOverlay
        readonly property real aspect: fullVideo.videoSink.videoSize.width > 0 && fullVideo.videoSink.videoSize.height > 0
            ? fullVideo.videoSink.videoSize.width / fullVideo.videoSink.videoSize.height : 16 / 9
        readonly property bool playing: mediaPlayer.playbackState === MediaPlayer.PlayingState

        anchors.fill: parent
        z: 50
        visible: opacity > 0
        opacity: root.fullscreenVideo ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Keys.onEscapePressed: root.exitFullscreen()
        Keys.onLeftPressed: if (root.hasPrevMedia) root.prevMedia()
        Keys.onRightPressed: if (root.hasNextMedia) root.nextMedia()
        onVisibleChanged: if (visible) videoOverlay.forceActiveFocus()

        // A click outside closes the viewer; the files behind take no input.
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: ColorUtils.transparentize("black", 0.12)
            MouseArea {
                anchors.fill: parent
                onClicked: root.exitFullscreen()
                onWheel: wheel => wheel.accepted = true
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            scale: root.fullscreenVideo ? 1 : 0.92
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(videoOverlay.height - fullControls.implicitHeight - 48, width / videoOverlay.aspect)

                Image {
                    anchors.fill: parent
                    visible: mediaPlayer.playbackState !== MediaPlayer.PlayingState && (root.fullscreenMedia?.thumb ?? "").length > 0
                    source: (root.fullscreenMedia?.thumb ?? "").length > 0 ? FileUtils.mediaUrl(root.fullscreenMedia.thumb) : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    opacity: 0.6
                }

                VideoOutput {
                    id: fullVideo
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectFit
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (videoOverlay.playing) {
                            mediaPlayer.pause();
                        } else {
                            if (mediaPlayer.duration > 0 && mediaPlayer.position >= mediaPlayer.duration) mediaPlayer.setPosition(0);
                            mediaPlayer.play();
                        }
                    }
                }

                RippleButton {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 8
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize("black", 0.45)
                    colBackgroundHover: ColorUtils.transparentize("black", 0.25)
                    visible: (root.fullscreenMedia?.path ?? "").length > 0
                    onClicked: Phone.openFile(root.fullscreenMedia.path)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "open_in_new"
                        iconSize: Appearance.font.pixelSize.normal
                        color: "white"
                    }
                    StyledToolTip {
                        text: Translation.tr("Open externally")
                    }
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 8
                    implicitHeight: 28
                    implicitWidth: Math.min(parent.width - 96, videoTitleText.implicitWidth + 24)
                    radius: Appearance.rounding.full
                    color: ColorUtils.transparentize("black", 0.45)
                    visible: (root.fullscreenMedia?.name ?? "").length > 0

                    StyledText {
                        id: videoTitleText
                        anchors.centerIn: parent
                        width: parent.width - 18
                        text: (root.fullscreenMedia?.name ?? "") + (root.currentMediaItems.length > 1 && root.currentMediaIndex >= 0 ? "  |  " + (root.currentMediaIndex + 1) + " / " + root.currentMediaItems.length : "")
                        elide: Text.ElideMiddle
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: "white"
                    }
                }

                RowLayout {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 6

                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: ColorUtils.transparentize("black", 0.45)
                        colBackgroundHover: ColorUtils.transparentize("black", 0.25)
                        visible: (root.fullscreenMedia?.path ?? "").length > 0
                        onClicked: Phone.saveCopy(root.fullscreenMedia.path, "", false, "files")
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "download"
                            iconSize: Appearance.font.pixelSize.normal
                            color: "white"
                        }
                        StyledToolTip {
                            text: Translation.tr("Save to Downloads")
                        }
                    }

                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: ColorUtils.transparentize("black", 0.45)
                        colBackgroundHover: ColorUtils.transparentize("black", 0.25)
                        onClicked: root.exitFullscreen()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: Appearance.font.pixelSize.normal
                            color: "white"
                        }
                        StyledToolTip {
                            text: Translation.tr("Close")
                        }
                    }
                }
            }

            RowLayout {
                id: fullControls
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                spacing: 6

                RippleButton {
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize("white", 0.88)
                    colBackgroundHover: ColorUtils.transparentize("white", 0.8)
                    onClicked: {
                        if (videoOverlay.playing) {
                            mediaPlayer.pause();
                        } else {
                            if (mediaPlayer.duration > 0 && mediaPlayer.position >= mediaPlayer.duration) mediaPlayer.setPosition(0);
                            mediaPlayer.play();
                        }
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: videoOverlay.playing ? "pause" : "play_arrow"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.larger
                        color: "white"
                    }
                }

                PhoneMediaSeek {
                    Layout.fillWidth: true
                    player: mediaPlayer
                    current: true
                    contentColor: "white"
                }
            }
        }

        RippleButton {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            z: 60
            implicitWidth: 40
            implicitHeight: 40
            buttonRadius: 20
            visible: root.hasPrevMedia && root.currentMediaItems.length > 1
            colBackground: ColorUtils.transparentize("black", 0.45)
            colBackgroundHover: ColorUtils.transparentize("black", 0.25)
            onClicked: root.prevMedia()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "chevron_left"
                iconSize: 24
                color: "white"
            }

            StyledToolTip {
                text: Translation.tr("Previous video (Left arrow)")
            }
        }

        RippleButton {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            z: 60
            implicitWidth: 40
            implicitHeight: 40
            buttonRadius: 20
            visible: root.hasNextMedia && root.currentMediaItems.length > 1
            colBackground: ColorUtils.transparentize("black", 0.45)
            colBackgroundHover: ColorUtils.transparentize("black", 0.25)
            onClicked: root.nextMedia()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "chevron_right"
                iconSize: 24
                color: "white"
            }

            StyledToolTip {
                text: Translation.tr("Next video (Right arrow)")
            }
        }
    }

    Item {
        id: imageOverlay
        readonly property string currentSource: root.fullscreenMedia?.localPath ?? ""
        readonly property bool imageReady: (isGif ? fullGif.status : fullImg.status) === Image.Ready
        readonly property bool thumbnailReady: !isGif && (root.fullscreenMedia?.thumb ?? "").length > 0
            && fullImgThumb.status === Image.Ready
        readonly property string error: root.fullscreenMedia?.error || (((isGif ? fullGif.status : fullImg.status) === Image.Error)
            ? Translation.tr("Could not display this image") : "")
        readonly property size decodeSize: Qt.size(Math.max(1, Math.ceil(width * Screen.devicePixelRatio)),
            Math.max(1, Math.ceil((height - 48) * Screen.devicePixelRatio)))
        readonly property bool isGif: (root.fullscreenMedia?.isGif ?? false) || /\.gif($|\?)/i.test(imageOverlay.currentSource)
        readonly property real aspect: {
            const w = isGif ? fullGif.implicitWidth : (fullImg.implicitWidth > 0 ? fullImg.implicitWidth : (fullImgThumb.implicitWidth > 0 ? fullImgThumb.implicitWidth : 0));
            const h = isGif ? fullGif.implicitHeight : (fullImg.implicitHeight > 0 ? fullImg.implicitHeight : (fullImgThumb.implicitHeight > 0 ? fullImgThumb.implicitHeight : 0));
            return (w > 0 && h > 0) ? (w / h) : (4 / 3);
        }

        anchors.fill: parent
        z: 50
        visible: opacity > 0
        opacity: root.fullscreenImage ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Keys.onEscapePressed: root.exitFullscreen()
        Keys.onLeftPressed: if (root.hasPrevMedia) root.prevMedia()
        Keys.onRightPressed: if (root.hasNextMedia) root.nextMedia()
        onVisibleChanged: if (visible) imageOverlay.forceActiveFocus()

        // A click outside closes the viewer; the files behind take no input.
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: ColorUtils.transparentize("black", 0.12)
            MouseArea {
                anchors.fill: parent
                onClicked: root.exitFullscreen()
                onWheel: wheel => wheel.accepted = true
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            scale: root.fullscreenImage ? 1 : 0.92
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(imageOverlay.height - 48, width / imageOverlay.aspect)

                Image {
                    id: fullImgThumb
                    anchors.fill: parent
                    visible: !imageOverlay.isGif && fullImg.status !== Image.Ready && (root.fullscreenMedia?.thumb ?? "").length > 0
                    source: (root.fullscreenMedia?.thumb ?? "").length > 0 ? FileUtils.mediaUrl(root.fullscreenMedia.thumb) : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                AnimatedImage {
                    id: fullGif
                    anchors.fill: parent
                    visible: imageOverlay.isGif
                    source: (visible && imageOverlay.currentSource.length > 0) ? FileUtils.mediaUrl(imageOverlay.currentSource) : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize: imageOverlay.decodeSize
                    cache: true
                    playing: imageOverlay.visible && visible
                    paused: false
                }

                Image {
                    id: fullImg
                    anchors.fill: parent
                    visible: !imageOverlay.isGif
                    source: (visible && imageOverlay.currentSource.length > 0) ? FileUtils.mediaUrl(imageOverlay.currentSource) : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize: imageOverlay.decodeSize
                    autoTransform: true
                    cache: true
                }

                MaterialLoadingIndicator {
                    id: imageLoadingIndicator
                    anchors.centerIn: parent
                    visible: root.fullscreenImage && !imageOverlay.error && !imageOverlay.imageReady && !imageOverlay.thumbnailReady
                    implicitSize: 36
                    loading: visible
                }

                StyledText {
                    anchors.centerIn: parent
                    width: parent.width - 32
                    visible: !!imageOverlay.error
                    text: imageOverlay.error
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: "white"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.exitFullscreen()
                }

                RippleButton {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 8
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: Appearance.rounding.full
                    colBackground: ColorUtils.transparentize("black", 0.45)
                    colBackgroundHover: ColorUtils.transparentize("black", 0.25)
                    visible: (root.fullscreenMedia?.path ?? "").length > 0
                    onClicked: Phone.openFile(root.fullscreenMedia.path)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "open_in_new"
                        iconSize: Appearance.font.pixelSize.normal
                        color: "white"
                    }
                    StyledToolTip {
                        text: Translation.tr("Open externally")
                    }
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 8
                    implicitHeight: 28
                    implicitWidth: Math.min(parent.width - 96, imageTitleText.implicitWidth + 24)
                    radius: Appearance.rounding.full
                    color: ColorUtils.transparentize("black", 0.45)
                    visible: (root.fullscreenMedia?.name ?? "").length > 0

                    StyledText {
                        id: imageTitleText
                        anchors.centerIn: parent
                        width: parent.width - 18
                        text: (root.fullscreenMedia?.name ?? "") + (root.currentMediaItems.length > 1 && root.currentMediaIndex >= 0 ? "  |  " + (root.currentMediaIndex + 1) + " / " + root.currentMediaItems.length : "")
                        elide: Text.ElideMiddle
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: "white"
                    }
                }

                RowLayout {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 6

                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: ColorUtils.transparentize("black", 0.45)
                        colBackgroundHover: ColorUtils.transparentize("black", 0.25)
                        visible: (root.fullscreenMedia?.path ?? "").length > 0
                        onClicked: Phone.saveCopy(root.fullscreenMedia.path, "", false, "files")
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "download"
                            iconSize: Appearance.font.pixelSize.normal
                            color: "white"
                        }
                        StyledToolTip {
                            text: Translation.tr("Save to Downloads")
                        }
                    }

                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        colBackground: ColorUtils.transparentize("black", 0.45)
                        colBackgroundHover: ColorUtils.transparentize("black", 0.25)
                        onClicked: root.exitFullscreen()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: Appearance.font.pixelSize.normal
                            color: "white"
                        }
                        StyledToolTip {
                            text: Translation.tr("Close")
                        }
                    }
                }
            }
        }

        RippleButton {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            z: 60
            implicitWidth: 40
            implicitHeight: 40
            buttonRadius: 20
            visible: root.hasPrevMedia && root.currentMediaItems.length > 1
            colBackground: ColorUtils.transparentize("black", 0.45)
            colBackgroundHover: ColorUtils.transparentize("black", 0.25)
            onClicked: root.prevMedia()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "chevron_left"
                iconSize: 24
                color: "white"
            }

            StyledToolTip {
                text: Translation.tr("Previous photo (Left arrow)")
            }
        }

        RippleButton {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            z: 60
            implicitWidth: 40
            implicitHeight: 40
            buttonRadius: 20
            visible: root.hasNextMedia && root.currentMediaItems.length > 1
            colBackground: ColorUtils.transparentize("black", 0.45)
            colBackgroundHover: ColorUtils.transparentize("black", 0.25)
            onClicked: root.nextMedia()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "chevron_right"
                iconSize: 24
                color: "white"
            }

            StyledToolTip {
                text: Translation.tr("Next photo (Right arrow)")
            }
        }
    }

    // The viewers cover the page's save card, so a save made in one shows here,
    // above them and solid so it reads over the picture.
    PhoneSaveCard {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            margins: 12
        }
        z: 70
        from: "files"
        visible: implicitHeight > 0 && (root.fullscreenImage || root.fullscreenVideo)
        color: Appearance.colors.colLayer2Base
        onShownChanged: if (!shown && visible) pageSaveCard.shown = false
    }
}
