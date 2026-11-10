pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.storage

ContentPage {
    id: root
    forceWidth: true
    baseWidth: Math.max(0, Math.min(600 * Appearance.font.roomGrowth, width - 40))

    readonly property string script: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/storage/storage.py`
    readonly property string homePath: FileUtils.trimFileProtocol(Directories.home)
    // Below this share free, the page says so at the top.
    readonly property real lowSpaceShare: 0.1
    readonly property real smallestCleanup: 1024 * 1024
    readonly property int shownEntries: 15

    property var disks: []
    property var efi: null
    property var usage: ({})
    property var cleanups: ({})
    property bool rescanWanted: false
    property string cleaningId: ""
    property string cleanError: ""
    property string browsePath: root.homePath
    property var browseResult: null
    property var largeFiles: []
    property string entryError: ""

    // What each part of the disk is called, in the order a tie falls. Flatpak's two places read as one.
    readonly property var usageParts: [
        { key: "apps", ids: ["apps"], icon: "apps", name: Translation.tr("Apps") },
        { key: "flatpak", ids: ["flatpak", "flatpakSystem"], icon: "package_2", name: Translation.tr("Flatpak apps") },
        { key: "appimages", ids: ["appimages"], icon: "install_desktop", name: Translation.tr("AppImages") },
        { key: "games", ids: ["games"], icon: "sports_esports", name: Translation.tr("Games") },
        { key: "documents", ids: ["documents"], icon: "description", name: Translation.tr("Documents") },
        { key: "downloads", ids: ["downloads"], icon: "download", name: Translation.tr("Downloads") },
        { key: "pictures", ids: ["pictures"], icon: "image", name: Translation.tr("Pictures") },
        { key: "videos", ids: ["videos"], icon: "movie", name: Translation.tr("Videos") },
        { key: "music", ids: ["music"], icon: "music_note", name: Translation.tr("Music") },
        { key: "cache", ids: ["cache"], icon: "cached", name: Translation.tr("App caches") },
        { key: "trash", ids: ["trash"], icon: "delete", name: Translation.tr("Trash") },
        { key: "otherHome", ids: ["otherHome"], icon: "folder", name: Translation.tr("Other files in Home") }
    ]

    readonly property var cleanupRows: [
        {
            id: "trash", icon: "delete", name: Translation.tr("Trash"), action: Translation.tr("Empty"),
            detail: Translation.tr("Files you already deleted."),
            warning: Translation.tr("Empty the Trash? These files can't be brought back.")
        },
        {
            id: "toolCaches", icon: "deployed_code", name: Translation.tr("Build and download caches"), action: Translation.tr("Clean"),
            detail: Translation.tr("Kept by yay, uv, npm and similar tools. They download again when needed."),
            warning: Translation.tr("Clear these caches? The next build may take longer.")
        },
        {
            id: "packages", icon: "inventory_2", name: Translation.tr("Old package versions"), action: Translation.tr("Clean"), admin: true,
            detail: Translation.tr("Older copies of updates. The newest copy of each stays."),
            warning: Translation.tr("Remove the older copies? You won't be able to roll back to them without downloading them again.")
        },
        {
            id: "coredumps", icon: "bug_report", name: Translation.tr("Crash reports"), action: Translation.tr("Clean"), admin: true,
            detail: Translation.tr("Memory saved when an app crashes. Only useful for debugging."),
            warning: Translation.tr("Delete the crash reports? Saved crashes can no longer be investigated.")
        },
        {
            id: "orphans", icon: "extension_off", name: Translation.tr("Unused packages"), action: Translation.tr("Remove"), admin: true,
            detail: Translation.tr("Installed for something that no longer needs them."),
            warning: Translation.tr("Remove these packages? Anything you installed by hand and still use can be installed again.")
        },
        {
            id: "logs", icon: "receipt_long", name: Translation.tr("System logs"), action: Translation.tr("Clean"), admin: true,
            detail: Translation.tr("Older log entries. The newest 200 MB stay."),
            warning: Translation.tr("Delete the older log entries?")
        },
        {
            id: "thumbnails", icon: "photo_library", name: Translation.tr("Thumbnails"), action: Translation.tr("Clean"),
            detail: Translation.tr("Small previews of your files. They are made again when needed."),
            warning: Translation.tr("Clear the thumbnails? Folders may take a moment to fill in next time.")
        },
        {
            id: "flatpaks", icon: "package_2", name: Translation.tr("Unused Flatpak runtimes"), action: Translation.tr("Remove"),
            detail: Translation.tr("Shared parts no installed Flatpak app needs."),
            warning: Translation.tr("Remove these runtimes?")
        }
    ]

    readonly property var shownCleanups: root.cleanupRows
        .filter(row => {
            const found = root.cleanups[row.id];
            return found && (found.size >= root.smallestCleanup || (found.size === 0 && found.items.length > 0));
        })
        .sort((a, b) => root.cleanups[b.id].size - root.cleanups[a.id].size)
    readonly property real cleanupTotal: root.shownCleanups.reduce((sum, row) => sum + root.cleanups[row.id].size, 0)

    function formatSize(bytes) {
        if (bytes < 1024 * 1024)
            return Translation.tr("%1 KB").arg(Math.round(bytes / 1024));
        if (bytes < 1024 * 1024 * 1024)
            return Translation.tr("%1 MB").arg(Math.round(bytes / 1048576));
        const gigabytes = bytes / 1073741824;
        return Translation.tr("%1 GB").arg(gigabytes < 100 ? gigabytes.toFixed(1) : Math.round(gigabytes));
    }

    // One themed hue per part, so the bar stays readable with a dozen of them.
    function partColor(index) {
        const primary = Appearance.colors.colPrimary;
        const hue = (primary.hslHue + index * 0.13) % 1;
        return Qt.hsla(hue, Math.max(0.45, primary.hslSaturation), Math.min(0.72, Math.max(0.52, primary.hslLightness)), 1);
    }

    // A disk's parts by size, then whatever nothing was measured for, which includes recovery snapshots.
    function partsOf(disk) {
        const parts = [];
        let measured = 0;
        for (const part of root.usageParts) {
            let size = 0;
            let path = "";
            for (const id of part.ids) {
                const found = root.usage[id];
                if (found && found.device === disk.device) {
                    size += found.size;
                    path = path || found.path;
                }
            }
            measured += size;
            if (size > 0)
                parts.push({ name: part.name, icon: part.icon, size: size, path: path, key: part.key });
        }
        if (parts.length === 0)
            return parts;
        parts.sort((a, b) => b.size - a.size);
        parts.forEach((part, index) => part.color = root.partColor(index));
        if (disk.used > measured)
            parts.push({ name: Translation.tr("System and other"), icon: "settings_applications", size: disk.used - measured,
                path: "", key: "system", color: Appearance.colors.colOutline });
        return parts;
    }

    function rescan() {
        if (scanner.running) {
            root.rescanWanted = true;
            scanner.running = false;
        } else {
            scanner.running = true;
        }
    }

    function browse(path) {
        root.browsePath = path;
        root.browseResult = null;
        root.entryError = "";
        browser.command = [root.script, "list", path];
        browser.running = false;
        browser.running = true;
    }

    function refreshFiles() {
        root.browse(root.browsePath);
        largeFinder.running = false;
        largeFinder.running = true;
    }

    function clean(id) {
        root.cleaningId = id;
        root.cleanError = "";
        cleaner.command = [root.script, "clean", id];
        cleaner.running = true;
    }

    function moveToTrash(path) {
        root.entryError = "";
        trasher.command = [root.script, "trash", path];
        trasher.running = true;
    }

    Component.onCompleted: {
        scanner.running = true;
        root.refreshFiles();
    }

    Process {
        id: scanner
        command: ["nice", "-n", "10", "ionice", "-c", "3", root.script, "scan"]
        property var freshDisks: []
        stdout: SplitParser {
            onRead: data => {
                let entry;
                try { entry = JSON.parse(data); } catch (e) { return; }
                if (entry.kind === "disk") {
                    scanner.freshDisks = scanner.freshDisks.concat([entry]);
                    root.disks = scanner.freshDisks;
                } else if (entry.kind === "efi") {
                    root.efi = entry;
                } else if (entry.kind === "usage") {
                    root.usage = Object.assign({}, root.usage, { [entry.id]: entry });
                } else if (entry.kind === "clean") {
                    root.cleanups = Object.assign({}, root.cleanups, { [entry.id]: entry });
                }
            }
        }
        onRunningChanged: {
            if (running)
                scanner.freshDisks = [];
        }
        onExited: {
            if (root.rescanWanted) {
                root.rescanWanted = false;
                scanner.running = true;
            }
        }
    }

    Process {
        id: browser
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.browseResult = JSON.parse(text);
                } catch (e) {
                    root.browseResult = { path: root.browsePath, size: 0, entries: [] };
                }
            }
        }
    }

    Process {
        id: largeFinder
        command: ["nice", "-n", "10", "ionice", "-c", "3", root.script, "large"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.largeFiles = JSON.parse(text).entries; } catch (e) { root.largeFiles = []; }
            }
        }
    }

    Process {
        id: cleaner
        stderr: StdioCollector {
            id: cleanerErrors
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                root.cleanError = HelperUtils.failureMessage(exitCode, HelperUtils.helperReason(cleanerErrors.text, "storage"));
            root.cleaningId = "";
            root.rescan();
            root.refreshFiles();
        }
    }

    Process {
        id: trasher
        stderr: StdioCollector {
            id: trasherErrors
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                root.entryError = trasherErrors.text.trim().split("\n").pop() || Translation.tr("The change could not be applied.");
            root.rescan();
            root.refreshFiles();
        }
    }

    component DiskUsageLabel: StyledText {
        id: label
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.alignment: Qt.AlignBottom
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        elide: Text.ElideMiddle
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext

        HoverHandler { id: hover }
        StyledToolTip {
            text: label.text
            extraVisibleCondition: label.truncated && hover.hovered
        }
    }

    component RowIconButton: RippleButton {
        id: iconButton
        property string iconName
        property string tip
        buttonRadius: Appearance.rounding.full
        implicitWidth: 34
        implicitHeight: 34
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: iconButton.iconName
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colSubtext
        }
        StyledToolTip {
            text: iconButton.tip
        }
    }

    // A warning and the two ways out, shown in a row once its action is pressed.
    component ConfirmStrip: ColumnLayout {
        id: strip
        property string warning
        property string action
        property string list: ""
        signal confirmed
        signal canceled
        Layout.fillWidth: true
        Layout.leftMargin: 14
        Layout.rightMargin: 14
        Layout.bottomMargin: 10
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            text: strip.warning
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            Layout.fillWidth: true
            visible: strip.list.length > 0
            text: strip.list
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            RippleButton {
                implicitWidth: 90
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                onClicked: strip.canceled()
                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Cancel")
                    color: Appearance.colors.colOnLayer1
                }
            }
            RippleButton {
                implicitWidth: Math.max(90, confirmLabel.implicitWidth + 28)
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colError
                colBackgroundHover: Appearance.colors.colErrorHover
                colRipple: Appearance.colors.colErrorActive
                onClicked: strip.confirmed()
                contentItem: StyledText {
                    id: confirmLabel
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: strip.action
                    color: Appearance.colors.colOnError
                }
            }
        }
    }

    // A file or folder with its size, and a bar of its share of the biggest one listed.
    component EntryRow: Rectangle {
        id: entryRow
        required property var entry
        required property real largest
        property bool confirming: false

        Layout.fillWidth: true
        implicitHeight: entryColumn.implicitHeight
        radius: Appearance.rounding.small
        color: entryMouse.containsMouse && !confirming ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1

        MouseArea {
            id: entryMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (entryRow.entry.folder)
                    root.browse(entryRow.entry.path);
                else
                    Qt.openUrlExternally(FileUtils.fileUrl(entryRow.entry.path));
            }
        }

        ColumnLayout {
            id: entryColumn
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                Layout.leftMargin: 14
                Layout.rightMargin: 6
                spacing: 12

                MaterialSymbol {
                    text: entryRow.entry.folder ? "folder" : "draft"
                    iconSize: Appearance.font.pixelSize.hugeass
                    color: Appearance.colors.colOnLayer1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        StyledText {
                            Layout.fillWidth: true
                            text: entryRow.entry.name
                            elide: Text.ElideMiddle
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            text: root.formatSize(entryRow.entry.size)
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 4
                        radius: 2
                        color: Appearance.surfaces.row
                        Rectangle {
                            width: parent.width * Math.min(1, entryRow.entry.size / Math.max(1, entryRow.largest))
                            height: parent.height
                            radius: 2
                            color: Appearance.colors.colPrimary
                        }
                    }
                }

                RowIconButton {
                    iconName: "folder_open"
                    tip: Translation.tr("Show in Files")
                    onClicked: Qt.openUrlExternally(FileUtils.fileUrl(entryRow.entry.folder ? entryRow.entry.path : FileUtils.parentDirectory(entryRow.entry.path)))
                }
                RowIconButton {
                    iconName: "delete"
                    enabled: !entryRow.entry.protected
                    opacity: enabled ? 1 : 0.4
                    tip: Translation.tr("Move to Trash")
                    onClicked: entryRow.confirming = true
                }
            }

            ConfirmStrip {
                visible: entryRow.confirming
                warning: Translation.tr("Move %1 to the Trash? Its space comes back once the Trash is emptied.").arg(entryRow.entry.name)
                action: Translation.tr("Move to Trash")
                onCanceled: entryRow.confirming = false
                onConfirmed: {
                    entryRow.confirming = false;
                    root.moveToTrash(entryRow.entry.path);
                }
            }
        }
    }

    ContentSection {
        icon: "hard_drive"
        title: Translation.tr("Disks")

        headerExtra: [
            RowIconButton {
                iconName: "refresh"
                tip: Translation.tr("Measure again")
                onClicked: root.rescan()
            }
        ]

        NoticeBox {
            Layout.fillWidth: true
            visible: root.disks.some(disk => disk.free / disk.total < root.lowSpaceShare)
            materialIcon: "warning"
            text: Translation.tr("A disk is almost full. Updates can fail and apps can misbehave when it runs out, so free up some space below.")
        }

        Repeater {
            model: root.disks
            ColumnLayout {
                id: diskCard
                required property var modelData
                readonly property var parts: root.partsOf(modelData)
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StyledText {
                        text: Translation.tr("%1 free").arg(root.formatSize(diskCard.modelData.free))
                        font.pixelSize: Appearance.font.pixelSize.title
                        color: Appearance.colors.colOnLayer1
                    }
                    DiskUsageLabel {
                        text: Translation.tr("%1 of %2 used on %3").arg(root.formatSize(diskCard.modelData.used))
                            .arg(root.formatSize(diskCard.modelData.total)).arg(diskCard.modelData.mount)
                    }
                }

                // The whole disk, with what is free left as the track.
                Item {
                    id: diskBar
                    Layout.fillWidth: true
                    implicitHeight: 22
                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: Appearance.surfaces.row
                    }
                    Row {
                        anchors.fill: parent
                        spacing: 2
                        Repeater {
                            model: diskCard.parts.length > 0 ? diskCard.parts
                                : [{ size: diskCard.modelData.used, color: Appearance.colors.colPrimary }]
                            Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool first: index === 0
                                readonly property bool last: index === (diskCard.parts.length || 1) - 1
                                // Measured sizes are before compression, so they can add up past what is used.
                                readonly property real measuredTotal: diskCard.parts.reduce((sum, part) => sum + part.size, 0)
                                readonly property real share: modelData.size / Math.max(measuredTotal || modelData.size, diskCard.modelData.used)
                                    * diskCard.modelData.used / diskCard.modelData.total
                                width: Math.max(0, diskBar.width * share - 2)
                                visible: width > 1
                                height: parent.height
                                topLeftRadius: first ? 8 : 2
                                bottomLeftRadius: first ? 8 : 2
                                topRightRadius: last ? 8 : 2
                                bottomRightRadius: last ? 8 : 2
                                color: modelData.color
                            }
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    visible: diskCard.parts.length > 0
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 2
                    Repeater {
                        model: diskCard.parts
                        RippleButton {
                            id: legendRow
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.small
                            colBackground: "transparent"
                            onClicked: {
                                if (modelData.path.length === 0)
                                    return;
                                root.browse(modelData.path);
                                root.scrollToSection("browse");
                            }
                            contentItem: RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8
                                Rectangle {
                                    implicitWidth: 10
                                    implicitHeight: 10
                                    radius: 3
                                    color: legendRow.modelData.color
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: legendRow.modelData.name
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    text: root.formatSize(legendRow.modelData.size)
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            StyledToolTip {
                                extraVisibleCondition: legendRow.modelData.key === "system"
                                text: Translation.tr("Includes recovery snapshots, which can't be measured quickly. Manage them from Recovery.")
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: scanner.running
            spacing: 4
            StyledIndeterminateProgressBar {
                Layout.fillWidth: true
            }
            StyledText {
                text: Object.keys(root.usage).length > 0 ? Translation.tr("Updating these numbers. Your disk is measured in the background.")
                    : Translation.tr("Measuring your disk. This can take a minute the first time.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    ContentSection {
        icon: "cleaning_services"
        title: Translation.tr("Free up space")

        titleExtra: [
            StyledText {
                visible: root.cleanupTotal > 0
                text: Translation.tr("Up to %1").arg(root.formatSize(root.cleanupTotal))
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        ]

        StyledText {
            Layout.fillWidth: true
            visible: !scanner.running && root.shownCleanups.length === 0
            text: Translation.tr("Nothing to clean up right now.")
            color: Appearance.colors.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.cleanError.length > 0
            wrapMode: Text.Wrap
            text: root.cleanError
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.m3colors.m3error
        }

        Repeater {
            model: root.shownCleanups
            Rectangle {
                id: cleanRow
                required property var modelData
                readonly property var found: root.cleanups[modelData.id] ?? { size: 0, items: [] }
                readonly property bool cleaning: root.cleaningId === modelData.id
                property bool confirming: false
                Layout.fillWidth: true
                implicitHeight: cleanColumn.implicitHeight
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1

                ColumnLayout {
                    id: cleanColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 60
                        Layout.leftMargin: 14
                        Layout.rightMargin: 10
                        spacing: 12

                        MaterialSymbol {
                            text: cleanRow.modelData.icon
                            iconSize: Appearance.font.pixelSize.hugeass
                            color: Appearance.colors.colOnLayer1
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            RowLayout {
                                spacing: 4
                                StyledText {
                                    text: cleanRow.modelData.name
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                }
                                MaterialSymbol {
                                    visible: cleanRow.modelData.admin ?? false
                                    text: "lock"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: cleanRow.modelData.detail
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }

                        StyledText {
                            text: cleanRow.found.size > 0 ? root.formatSize(cleanRow.found.size)
                                : Translation.tr("%1 items").arg(cleanRow.found.items.length)
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }

                        RippleButton {
                            implicitWidth: Math.max(72, actionLabel.implicitWidth + 24)
                            implicitHeight: Math.max(32, actionLabel.implicitHeight + 12)
                            buttonRadius: Appearance.rounding.full
                            enabled: root.cleaningId.length === 0 && !cleanRow.confirming
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            colRipple: Appearance.colors.colSecondaryContainerActive
                            onClicked: cleanRow.confirming = true
                            contentItem: StyledText {
                                id: actionLabel
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: cleanRow.cleaning ? Translation.tr("Working") : cleanRow.modelData.action
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }

                    ConfirmStrip {
                        visible: cleanRow.confirming
                        warning: cleanRow.modelData.warning
                        action: cleanRow.modelData.action
                        list: cleanRow.found.items.join(", ")
                        onCanceled: cleanRow.confirming = false
                        onConfirmed: {
                            cleanRow.confirming = false;
                            root.clean(cleanRow.modelData.id);
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        objectName: "browse"
        icon: "folder_managed"
        title: Translation.tr("Browse Home")

        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            RowIconButton {
                iconName: "arrow_upward"
                tip: Translation.tr("Go up to parent folder")
                enabled: root.browsePath !== root.homePath
                onClicked: root.browse(FileUtils.parentDirectory(root.browsePath))
            }
            StyledText {
                Layout.fillWidth: true
                text: root.browsePath.replace(root.homePath, "~")
                elide: Text.ElideMiddle
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                visible: !!root.browseResult
                text: root.formatSize(root.browseResult?.size ?? 0)
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }

        StyledIndeterminateProgressBar {
            Layout.fillWidth: true
            visible: !root.browseResult
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.entryError.length > 0
            wrapMode: Text.Wrap
            text: root.entryError
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.m3colors.m3error
        }

        StyledText {
            Layout.fillWidth: true
            visible: !!root.browseResult && root.browseResult.entries.length === 0
            text: Translation.tr("This folder is empty.")
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: (root.browseResult?.entries ?? []).slice(0, root.shownEntries)
            EntryRow {
                required property var modelData
                entry: modelData
                largest: root.browseResult?.entries[0]?.size ?? 1
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: (root.browseResult?.entries.length ?? 0) > root.shownEntries
            text: Translation.tr("Showing the largest %1.").arg(root.shownEntries)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    ContentSection {
        icon: "description"
        title: Translation.tr("Largest files")
        visible: root.largeFiles.length > 0

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("The biggest files in Home, leaving out the hidden folders apps keep their data in.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        Repeater {
            model: root.largeFiles
            EntryRow {
                required property var modelData
                entry: modelData
                largest: root.largeFiles[0]?.size ?? 1
            }
        }
    }

    // ── EFI Boot Partition ──────────────────────────────────────────────────
    ContentSection {
        id: efiSection
        objectName: "efiBootSection"
        visible: root.efi !== null
        icon: "developer_board"
        title: Translation.tr("EFI Boot Partition")

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Holds bootloader binaries, Unified Kernel Images (UKIs), and system recovery files.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                StyledText {
                    text: Translation.tr("%1 free").arg(root.formatSize(root.efi ? root.efi.free : 0))
                    font.pixelSize: Appearance.font.pixelSize.title
                    color: Appearance.colors.colOnLayer1
                }
                DiskUsageLabel {
                    text: Translation.tr("%1 of %2 used on %3").arg(root.formatSize(root.efi ? root.efi.used : 0))
                        .arg(root.formatSize(root.efi ? (root.efi.part_bytes ?? root.efi.total) : 0)).arg(root.efi ? root.efi.mount : "/boot/efi")
                }
            }

            // Storage bar
            Item {
                id: efiBar
                Layout.fillWidth: true
                implicitHeight: 22

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: Appearance.surfaces.row
                }

                Rectangle {
                    readonly property real usedRatio: root.efi && root.efi.total > 0 ? (root.efi.used / root.efi.total) : 0
                    width: Math.max(14, efiBar.width * usedRatio)
                    height: parent.height
                    radius: 8
                    color: (root.efi && root.efi.free < 150 * 1024 * 1024) ? Appearance.colors.colWarning : Appearance.colors.colPrimary
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: `${root.efi ? root.efi.device : ""} • FAT32 (ESP)`
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                Item { Layout.fillWidth: true }

                RippleButtonWithIcon {
                    visible: root.efi?.planner_available !== false
                    Layout.alignment: Qt.AlignVCenter
                    materialIcon: "aspect_ratio"
                    mainText: Translation.tr("Expand size...")
                    onClicked: efiResizeDialog.open()
                }
            }

            // Low space warning if free space < 150 MB
            NoticeBox {
                Layout.fillWidth: true
                visible: root.efi && (root.efi.free < 150 * 1024 * 1024)
                materialIcon: "warning"
                text: Translation.tr("Low space on EFI partition. Kernel updates and Unified Kernel Images (UKIs) may fail if this runs out.")
            }
        }
    }

    EfiResizeDialog {
        id: efiResizeDialog
        targetArea: root
        efiData: root.efi
        onResizeCompleted: root.rescan()
    }
}
