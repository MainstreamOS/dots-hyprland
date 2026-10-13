import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell

SheetBase {
    id: root

    readonly property string searchQuery: searchField.text.trim()
    property string selectedTypeFilter: "all" // "all", "images", "docs", "code"
    property bool showHiddenFiles: false
    // Row the user moved to with the keyboard in the active list; -1 when none
    property int keyboardIndex: -1

    readonly property bool isSearching: searchQuery.length > 0
    readonly property bool searchBusy: attachmentSearch.running || attachmentSearch.pending

    readonly property var typeFilterExtensions: ({
        "all": [],
        "images": [".png", ".jpg", ".jpeg", ".webp", ".gif", ".svg", ".bmp", ".avif", ".ico"],
        "docs": [".txt", ".md", ".pdf", ".doc", ".docx", ".json", ".csv", ".log", ".xml", ".yaml", ".yml", ".toml"],
        "code": [".qml", ".js", ".ts", ".py", ".sh", ".bash", ".c", ".cpp", ".h", ".hpp", ".rs", ".go", ".html", ".css", ".scss", ".xml", ".yaml", ".yml", ".toml", ".sql", ".lua", ".zig", ".java", ".kt"]
    })

    readonly property var activeFilters: {
        const list = root.typeFilterExtensions[root.selectedTypeFilter] || [];
        return list.map(ext => "*" + ext);
    }

    // Icon kind of each known file extension
    readonly property var extensionKinds: {
        const kinds = {};
        const add = (kind, extensions) => extensions.forEach(ext => kinds[ext] = kind);
        add("image", root.typeFilterExtensions.images);
        add("pdf", [".pdf"]);
        add("code", root.typeFilterExtensions.code.concat([".json"]));
        add("doc", [".txt", ".md", ".doc", ".docx", ".odt", ".rtf", ".csv", ".tsv", ".epub", ".log"]);
        add("zip", [".zip", ".tar", ".gz", ".xz", ".7z", ".rar", ".bz2", ".tgz"]);
        add("audio", [".mp3", ".wav", ".flac", ".ogg", ".m4a", ".aac", ".opus"]);
        add("video", [".mp4", ".mkv", ".webm", ".avi", ".mov", ".flv", ".wmv"]);
        return kinds;
    }

    function triggerFileSearch(): void {
        root.keyboardIndex = -1;
        const q = root.searchQuery;
        if (q.length >= 2) {
            const extensions = (root.typeFilterExtensions[root.selectedTypeFilter] || []).map(ext => ext.slice(1));
            attachmentSearch.search(q, root.showHiddenFiles, extensions, 100);
        } else {
            attachmentSearch.reset();
        }
    }

    onSearchQueryChanged: triggerFileSearch()
    onShowHiddenFilesChanged: {
        if (root.isSearching) triggerFileSearch();
    }
    onSelectedTypeFilterChanged: {
        if (root.isSearching) triggerFileSearch();
    }

    readonly property var emptyStateInfo: {
        if (!isSearching) {
            if (folderModel.status === FolderListModel.Ready && folderModel.count === 0) {
                return {
                    visible: true,
                    icon: "folder_open",
                    iconColor: Appearance.colors.colSubtext,
                    title: Translation.tr("Folder is empty"),
                    subtitle: Translation.tr("Navigate up or pick another location")
                };
            }
            return { visible: false };
        }
        const qLen = searchQuery.length;
        if (qLen < 2) {
            return {
                visible: true,
                icon: "edit_note",
                iconColor: Appearance.colors.colSubtext,
                title: Translation.tr("Type at least 2 characters"),
                subtitle: Translation.tr("Search across all files in your home folder")
            };
        }
        if (attachmentSearch.results.length === 0) {
            if (root.searchBusy) {
                return {
                    visible: true,
                    icon: "progress_activity",
                    iconColor: Appearance.colors.colPrimary,
                    title: Translation.tr("Searching all files..."),
                    subtitle: ""
                };
            }
            return {
                visible: true,
                icon: "search_off",
                iconColor: Appearance.colors.colSubtext,
                title: Translation.tr("No matching files found"),
                subtitle: Translation.tr("Try searching with different keywords or changing filters")
            };
        }
        return { visible: false };
    }

    function handleItemSelection(path, isDir) {
        if (!path) return;
        if (isDir) {
            goToFolder(path);
            searchField.text = "";
        } else {
            root.fileSelected(FileUtils.fileUrl(path));
            root.close();
        }
    }

    property url currentFolder: Qt.resolvedUrl(Directories.home)
    property var folderHistory: [Qt.resolvedUrl(Directories.home)]
    property int historyIndex: 0

    signal fileSelected(string fileUrl)

    function open(initialFolder): void {
        searchField.text = "";
        root.selectedTypeFilter = "all";
        root.keyboardIndex = -1;
        if (initialFolder)
            goToFolder(initialFolder);
        root.show(searchField.input);
    }

    onClosed: searchField.text = ""

    function setFolder(url): void {
        root.currentFolder = url;
        root.keyboardIndex = -1;
    }

    function goToFolder(urlOrPath) {
        if (!urlOrPath) return;
        let url = urlOrPath;
        if (typeof url === "string") {
            if (!url.startsWith("file://")) {
                url = FileUtils.fileUrl(url);
            } else {
                url = Qt.resolvedUrl(url);
            }
        }
        if (root.currentFolder.toString() === url.toString()) return;

        const history = folderHistory.slice(0, historyIndex + 1);
        history.push(url);
        folderHistory = history;
        historyIndex = history.length - 1;
        setFolder(url);
    }

    function navigateBack() {
        if (historyIndex > 0) {
            historyIndex--;
            setFolder(folderHistory[historyIndex]);
        }
    }

    function navigateForward() {
        if (historyIndex < folderHistory.length - 1) {
            historyIndex++;
            setFolder(folderHistory[historyIndex]);
        }
    }

    function navigateUp() {
        if (canGoUp) {
            goToFolder(folderModel.parentFolder);
        }
    }

    readonly property bool canGoBack: historyIndex > 0
    readonly property bool canGoForward: historyIndex < folderHistory.length - 1
    readonly property bool canGoUp: {
        if (!folderModel.parentFolder) return false;
        const cur = root.currentFolder.toString().replace(/\/+$/, "");
        const par = folderModel.parentFolder.toString().replace(/\/+$/, "");
        return par.length > 0 && par !== cur;
    }

    function isCurrentPath(target) {
        if (!target) return false;
        const t = FileUtils.trimFileProtocol(target.toString()).replace(/\/+$/, "");
        const cur = FileUtils.trimFileProtocol(root.currentFolder.toString()).replace(/\/+$/, "");
        return t === cur;
    }

    function displayPath(folderUrl) {
        if (!folderUrl) return "";
        let p = FileUtils.trimFileProtocol(folderUrl.toString());
        p = decodeURIComponent(p);
        if (p.length > 1 && p.endsWith("/")) p = p.slice(0, -1);
        const home = FileUtils.trimFileProtocol(Directories.home.toString());
        const homeClean = (home.endsWith("/") ? home.slice(0, -1) : home);
        if (p === homeClean) return "~";
        if (p.startsWith(homeClean + "/")) {
            return "~" + p.slice(homeClean.length);
        }
        return p;
    }

    function formatBytes(bytes) {
        if (bytes === undefined || bytes === null || bytes < 0) return "";
        if (bytes === 0) return "0 B";
        const k = 1024;
        const sizes = ["B", "KB", "MB", "GB", "TB"];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        if (i < 0) return bytes + " B";
        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i];
    }

    function fileIconInfo(name, isDir) {
        if (isDir) {
            return { icon: "folder", color: Appearance.colors.colPrimary, isImage: false };
        }
        if (!name) {
            return { icon: "draft", color: Appearance.colors.colSubtext, isImage: false };
        }
        const lower = name.toLowerCase();
        const ext = lower.lastIndexOf(".") !== -1 ? lower.slice(lower.lastIndexOf(".")) : "";

        switch (root.extensionKinds[ext]) {
        case "image":
            return { icon: "image", color: Appearance.colors.colPrimary, isImage: true };
        case "pdf":
            return { icon: "picture_as_pdf", color: Appearance.m3colors.m3error, isImage: false };
        case "code":
            return { icon: "code", color: Appearance.colors.colSecondary, isImage: false };
        case "doc":
            return { icon: "description", color: Appearance.m3colors.m3onSurface, isImage: false };
        case "zip":
            return { icon: "folder_zip", color: Appearance.m3colors.m3tertiary, isImage: false };
        case "audio":
            return { icon: "music_note", color: Appearance.colors.colPrimary, isImage: false };
        case "video":
            return { icon: "movie", color: Appearance.m3colors.m3tertiary, isImage: false };
        default:
            return { icon: "draft", color: Appearance.colors.colSubtext, isImage: false };
        }
    }

    function activeList(): var {
        return root.isSearching ? searchListView : fileListView;
    }

    function selectListRow(index: int): void {
        if (root.isSearching) {
            const item = attachmentSearch.results[index];
            if (item)
                root.handleItemSelection(item.path, item.isDir);
        } else if (index >= 0 && index < folderModel.count) {
            root.handleItemSelection(folderModel.get(index, "filePath"), folderModel.get(index, "fileIsDir"));
        }
    }

    AttachmentSearch {
        id: attachmentSearch
    }

    // Listing (and watching) a folder only while the sheet is on screen
    FolderListModel {
        id: folderModel
        folder: root.visible ? root.currentFolder : ""
        showFiles: true
        showDirs: true
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: root.showHiddenFiles
        caseSensitive: false
        sortField: FolderListModel.Name
        nameFilters: root.activeFilters
    }

    maxCardHeight: 520
    icon: "attach_file"
    title: Translation.tr("Attach File")
    closeToolTip: Translation.tr("Close")
    inputField: searchField.input
    filterField: searchField.input

    headerActions: [
        // Toggle hidden files button
        RippleButton {
            implicitWidth: 32
            implicitHeight: 32
            buttonRadius: Appearance.rounding.full
            colBackground: root.showHiddenFiles ? Appearance.colors.colSecondaryContainer : "transparent"
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: root.showHiddenFiles ? "visibility" : "visibility_off"
                iconSize: Appearance.font.pixelSize.normal
                color: root.showHiddenFiles ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }

            onClicked: root.showHiddenFiles = !root.showHiddenFiles

            StyledToolTip {
                extraVisibleCondition: root.shown
                text: root.showHiddenFiles ? Translation.tr("Hide hidden files") : Translation.tr("Show hidden files")
            }
        }
    ]

    // 2. Navigation & Breadcrumb Path Row (shown when browsing folders)
    RowLayout {
        visible: !root.isSearching
        Layout.fillWidth: true
        spacing: 6

        FileSheetNavButton {
            sheetShown: root.shown
            iconName: "arrow_back"
            tip: Translation.tr("Back")
            enabled: root.canGoBack
            onClicked: root.navigateBack()
        }

        FileSheetNavButton {
            sheetShown: root.shown
            iconName: "arrow_forward"
            tip: Translation.tr("Forward")
            enabled: root.canGoForward
            onClicked: root.navigateForward()
        }

        FileSheetNavButton {
            sheetShown: root.shown
            iconName: "arrow_upward"
            tip: Translation.tr("Parent folder")
            enabled: root.canGoUp
            onClicked: root.navigateUp()
        }

        // Current directory path badge
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 28
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 4

                MaterialSymbol {
                    text: "folder_open"
                    iconSize: 14
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.displayPath(root.currentFolder)
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSurface
                    elide: Text.ElideLeft
                }
            }
        }
    }

    // 3. Quick Jump Bookmarks Row (shown when browsing folders)
    RowLayout {
        visible: !root.isSearching
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: [
                { name: Translation.tr("Home"), icon: "home", path: Directories.home },
                { name: Translation.tr("Pictures"), icon: "image", path: Directories.pictures },
                { name: Translation.tr("Downloads"), icon: "download", path: Directories.downloads },
                { name: Translation.tr("Docs"), icon: "description", path: Directories.documents }
            ]

            delegate: RippleButton {
                id: bookmarkBtn
                required property var modelData
                readonly property bool isCurrent: root.isCurrentPath(modelData.path)
                Layout.fillWidth: true
                implicitHeight: 28
                buttonRadius: Appearance.rounding.small
                colBackground: bookmarkBtn.isCurrent
                    ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colLayer1
                colBackgroundHover: bookmarkBtn.isCurrent
                    ? Appearance.colors.colPrimaryContainerHover
                    : Appearance.colors.colLayer1Hover

                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        text: bookmarkBtn.modelData.icon
                        iconSize: 14
                        color: bookmarkBtn.isCurrent
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colSubtext
                    }

                    StyledText {
                        text: bookmarkBtn.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: bookmarkBtn.isCurrent ? Font.DemiBold : Font.Normal
                        color: bookmarkBtn.isCurrent
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.m3colors.m3onSurface
                    }
                }

                onClicked: root.goToFolder(modelData.path)
            }
        }
    }

    // 3b. Search Status Scope Bar (shown during global file search)
    Rectangle {
        visible: root.isSearching
        Layout.fillWidth: true
        implicitHeight: 28
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6

            MaterialSymbol {
                text: root.searchBusy ? "progress_activity" : "travel_explore"
                iconSize: 14
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    if (root.searchQuery.length < 2) {
                        return Translation.tr("Searching all files in ~");
                    }
                    if (root.searchBusy) {
                        return Translation.tr("Searching all files in ~...");
                    }
                    return Translation.tr("All files in ~ (%1 matches)").arg(attachmentSearch.results.length);
                }
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }
    }

    // 4. Search & Filter Bar
    SheetSearchField {
        id: searchField
        Layout.fillWidth: true
        placeholder: Translation.tr("Search all files...")
        fontPixelSize: Appearance.font.pixelSize.normal
        clearable: true

        onFieldKeyPressed: event => {
            if (event.key === Qt.Key_Down) {
                const targetView = root.activeList();
                targetView.forceActiveFocus();
                if (targetView.count > 0) {
                    if (targetView.currentIndex < 0)
                        targetView.currentIndex = 0;
                    root.keyboardIndex = targetView.currentIndex;
                }
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.keyboardIndex >= 0)
                    root.selectListRow(root.keyboardIndex);
                event.accepted = true;
            }
        }
    }

    // 5. Category Filter Chips Row
    RowLayout {
        Layout.fillWidth: true
        spacing: 4

        Repeater {
            model: [
                { id: "all", name: Translation.tr("All") },
                { id: "images", name: Translation.tr("Images") },
                { id: "docs", name: Translation.tr("Docs") },
                { id: "code", name: Translation.tr("Code") }
            ]

            delegate: RippleButton {
                id: typeChipBtn
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 24
                buttonRadius: Appearance.rounding.small
                colBackground: root.selectedTypeFilter === modelData.id
                    ? Appearance.colors.colSecondaryContainer
                    : "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover

                contentItem: StyledText {
                    anchors.centerIn: parent
                    text: typeChipBtn.modelData.name
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: root.selectedTypeFilter === typeChipBtn.modelData.id ? Font.DemiBold : Font.Normal
                    color: root.selectedTypeFilter === typeChipBtn.modelData.id
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colSubtext
                }

                onClicked: root.selectedTypeFilter = modelData.id
            }
        }
    }

    // 6. File & Directory List / Search Results
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        // Keys the focused list leaves unhandled
        Keys.onPressed: event => {
            const list = root.activeList();
            if (event.key === Qt.Key_Backspace && !root.isSearching) {
                root.navigateUp();
                event.accepted = true;
            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && list.currentIndex >= 0 && list.currentIndex < list.count) {
                root.selectListRow(list.currentIndex);
                event.accepted = true;
            }
        }

        // Folder browse view (when not searching)
        StyledListView {
            id: fileListView
            anchors.fill: parent
            visible: !root.isSearching
            clip: true
            spacing: 4
            model: folderModel

            onCurrentIndexChanged: {
                if (activeFocus)
                    root.keyboardIndex = currentIndex;
            }

            delegate: FileSheetRow {
                required property string fileName
                required property var filePath
                required property bool fileIsDir
                required property var fileSize

                sheet: root
                path: typeof filePath === "string" ? filePath : ""
                name: fileName
                isDir: fileIsDir
                detail: fileIsDir ? Translation.tr("Folder") : root.formatBytes(fileSize)
            }
        }

        // Global search results view (when searching across ~)
        StyledListView {
            id: searchListView
            anchors.fill: parent
            visible: root.isSearching
            clip: true
            spacing: 4

            model: ScriptModel {
                values: attachmentSearch.results
                objectProp: "path"
            }

            onCurrentIndexChanged: {
                if (activeFocus)
                    root.keyboardIndex = currentIndex;
            }

            delegate: FileSheetRow {
                required property var modelData

                sheet: root
                path: modelData?.path ?? ""
                isDir: Boolean(modelData?.isDir)
                name: isDir ? FileUtils.folderNameForPath(path) : FileUtils.fileNameForPath(path)
                detail: root.displayPath(FileUtils.parentDirectory(path))
                detailElide: Text.ElideLeft
            }
        }

        // Contextual empty state
        ColumnLayout {
            anchors.centerIn: parent
            visible: Boolean(root.emptyStateInfo.visible)
            spacing: 8

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: root.emptyStateInfo.icon || ""
                iconSize: Appearance.font.pixelSize.hugeass
                color: root.emptyStateInfo.iconColor || Appearance.colors.colSubtext
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.emptyStateInfo.title || ""
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colSubtext
            }

            StyledText {
                visible: Boolean(root.emptyStateInfo.subtitle)
                Layout.alignment: Qt.AlignHCenter
                text: root.emptyStateInfo.subtitle || ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }
}
