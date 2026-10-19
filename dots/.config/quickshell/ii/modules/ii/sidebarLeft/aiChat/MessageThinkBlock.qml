pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "thinkrows.js" as ThinkRows
import "../../../../services/ai/sink.js" as Sink

Item {
    id: root
    // These are needed on the parent loader
    property bool editing: false
    property bool renderMarkdown: true
    property bool enableMouseSelection: false
    property string segmentContent: ""
    property var messageData: null
    property bool done: true
    property bool completed: false
    property int thinkIndex: 0
    property int contentRevision: 0

    property var collapseAnimation: Appearance.animation.elementMoveFast
    readonly property color headerBackgroundColor: ColorUtils.mix(
        Appearance.colors.colLayer2Hover, Appearance.colors.colSecondaryContainer, 0.65)

    readonly property bool live: !root.completed && !root.done
    readonly property var blockState: root.messageData?.thinkBlocks?.[root.thinkIndex] ?? null
    // Never toggled (null) shows collapsed.
    readonly property bool collapsed: root.blockState?.collapsed ?? true
    property bool animatingToggle: false
    property int elapsedSeconds: 0
    readonly property int shownSeconds: root.live ? root.elapsedSeconds : ((root.blockState?.duration ?? 0) || root.elapsedSeconds)
    property bool changedFilesDropdownOpen: false

    function formatDuration(seconds) {
        if (!seconds || seconds <= 0) return "";
        if (seconds >= 60) {
            const m = Math.floor(seconds / 60);
            const s = seconds % 60;
            return s > 0 ? `${m}m ${s}s` : `${m}m`;
        }
        return `${seconds}s`;
    }

    function themeColor(name) {
        switch (name) {
            case "subtext": return Appearance.colors.colSubtext;
            case "onSurface": return Appearance.m3colors.m3onSurface;
            case "primary": return Appearance.colors.colPrimary;
            case "error": return Appearance.m3colors.m3error;
            default: return name;
        }
    }

    // Source of this block for saving an edit.
    function sourceText(): string {
        const thought = root.segmentContent.replace(/^\n+/, "").replace(/\n+$/, "");
        return Sink.THINK_OPEN + thought + Sink.THINK_CLOSE;
    }

    function toggleCollapsed(): void {
        if (!root.messageData) return;
        root.animatingToggle = true;
        toggleSettleTimer.restart();
        root.messageData.setThinkCollapsed(root.thinkIndex, !root.collapsed);
        Ai.scheduleSave();
    }

    function updateElapsed(): void {
        const start = root.blockState?.start ?? 0;
        if (start > 0) root.elapsedSeconds = Math.max(1, Math.round((Date.now() - start) / 1000));
    }

    function openPath(path: string): void {
        if (!root.messageData || !path.startsWith("/")) return;
        existsCheck.createObject(root, { path: path, command: ["test", "-e", path], running: true });
    }

    function review(paths): void {
        if (!root.messageData || paths.length === 0) return;
        root.changedFilesDropdownOpen = true;
        const term = Config.options.apps?.terminal || "kitty";
        const scriptPath = FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/review-diff.sh`);
        Quickshell.execDetached(["bash", "-c", `${term} -e bash "$@"`, "_", scriptPath, ...paths]);
    }

    Component {
        id: existsCheck
        Process {
            id: check
            property string path
            onExited: (exitCode, exitStatus) => {
                if (exitCode === 0) Qt.openUrlExternally(FileUtils.fileUrl(check.path));
                check.destroy();
            }
        }
    }

    Timer {
        id: thinkTimer
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.live && !!root.messageData
        onTriggered: {
            if (!root.messageData) return;
            root.updateElapsed();
        }
    }

    // Lets the height animate for a toggle only, never for streamed growth.
    Timer {
        id: toggleSettleTimer
        interval: root.collapseAnimation.duration + 100
        onTriggered: if (!collapseHeightAnimation.running) root.animatingToggle = false
    }

    Layout.fillWidth: true
    implicitHeight: columnLayout.implicitHeight

    ColumnLayout {
        id: columnLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        // Header bar
        Item {
            id: header
            Layout.fillWidth: true
            implicitHeight: 34

            Rectangle {
                id: headerHoverBg
                anchors.fill: parent
                radius: 8
                color: headerMouseArea.containsMouse
                    ? ColorUtils.mix(root.headerBackgroundColor, Appearance.colors.colOnSecondaryContainer, 0.86)
                    : root.headerBackgroundColor
            }

            MouseArea {
                id: headerMouseArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: root.toggleCollapsed()
            }

            RowLayout {
                id: headerRow
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                MaterialSymbol {
                    id: thinkIcon
                    property real pulse: 1
                    Layout.alignment: Qt.AlignVCenter
                    text: "auto_awesome"
                    iconSize: Appearance.font.pixelSize.normal
                    color: root.live ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    opacity: root.live ? thinkIcon.pulse : 1

                    SequentialAnimation on pulse {
                        running: root.live
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 750; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0; duration: 750; easing.type: Easing.InOutQuad }
                    }
                }

                StyledText {
                    id: thinkTitle
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: root.live ? Appearance.colors.colPrimary : Appearance.colors.colOnSecondaryContainer
                    elide: Text.ElideRight
                    text: {
                        const dur = root.formatDuration(root.shownSeconds);
                        if (root.live) {
                            return dur.length > 0
                                ? Translation.tr("Thinking Process (%1)...").arg(dur)
                                : Translation.tr("Thinking Process...");
                        } else {
                            return dur.length > 0
                                ? Translation.tr("Thought for %1").arg(dur)
                                : Translation.tr("Thought Process");
                        }
                    }
                }

                MaterialSymbol {
                    id: chevron
                    Layout.alignment: Qt.AlignVCenter
                    text: "keyboard_arrow_down"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                    rotation: root.collapsed ? -90 : 0

                    Behavior on rotation {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                }
            }
        }

        // Divider line between header and content when expanded
        Rectangle {
            id: divider
            Layout.fillWidth: true
            Layout.leftMargin: 3
            height: 1
            visible: !root.collapsed
            color: Appearance.colors.colOutlineVariant
            opacity: 0.35
        }

        // Thought content container
        Item {
            id: contentArea
            Layout.fillWidth: true
            clip: true
            implicitHeight: root.collapsed ? 0 : (contentPlaceholder.visible ? (contentPlaceholder.implicitHeight + 16) : ((rowsLoader.item?.implicitHeight ?? 0) + 16))
            visible: implicitHeight > 0

            Behavior on implicitHeight {
                enabled: root.animatingToggle && !root.editing
                NumberAnimation {
                    id: collapseHeightAnimation
                    duration: root.collapseAnimation.duration
                    easing.type: root.collapseAnimation.type
                    easing.bezierCurve: root.collapseAnimation.bezierCurve
                    onRunningChanged: if (!running && !toggleSettleTimer.running) root.animatingToggle = false
                }
            }

            StyledText {
                id: contentPlaceholder
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: 12
                anchors.topMargin: 8
                visible: ((rowsLoader.item?.rowCount ?? 0) === 0) && root.live
                text: Translation.tr("Reasoning...")
                font.pixelSize: Appearance.font.pixelSize.small
                font.italic: true
                color: Appearance.colors.colSubtext
            }

            // Rows exist only while the block is open (or animating closed).
            Loader {
                id: rowsLoader
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                active: !root.collapsed || root.animatingToggle
                visible: !contentPlaceholder.visible
                sourceComponent: thinkRowsComponent
            }
        }
    }

    Component {
        id: thinkRowsComponent

        ColumnLayout {
            id: rowsColumn
            property var parser: ThinkRows.createParser()
            readonly property int rowCount: rowModel.count
            property int totalAddedLines: 0
            property int totalRemovedLines: 0
            property var reviewPaths: []
            // Posted calls can still arrive while the rows are being torn down.
            property bool _alive: true
            Component.onDestruction: rowsColumn._alive = false
            spacing: 6

            function sync(): void {
                if (rowsColumn._alive !== true || !root.messageData || root.collapsed) return;
                const parser = rowsColumn.parser;
                const result = parser.feed(root.segmentContent, !root.live, root.messageData.activities, root.contentRevision);
                if (result.reset) {
                    rowModel.clear();
                    fileModel.clear();
                }
                const rows = parser.rows;
                for (let i = result.rowsFrom; i < rows.length; i++) {
                    if (i < rowModel.count) rowModel.setProperty(i, "text", rows[i].text);
                    else rowModel.append(rows[i]);
                }
                for (const i of result.files) {
                    if (i < fileModel.count) fileModel.set(i, parser.files[i]);
                    else fileModel.append(parser.files[i]);
                }
                rowsColumn.totalAddedLines = parser.totalAdded;
                rowsColumn.totalRemovedLines = parser.totalRemoved;
                if (result.reset || result.files.length > 0) {
                    rowsColumn.reviewPaths = parser.files.filter(f => f.path.startsWith("/")).map(f => f.path);
                }
            }

            Component.onCompleted: rowsColumn.sync()

            // Inputs that change together in one flush are parsed once, after it.
            Connections {
                target: root
                function onSegmentContentChanged() { rowsSyncTimer.restart(); }
                function onLiveChanged() { rowsSyncTimer.restart(); }
                function onCollapsedChanged() { rowsSyncTimer.restart(); }
                function onContentRevisionChanged() { rowsSyncTimer.restart(); }
            }

            Timer {
                id: rowsSyncTimer
                interval: 0
                repeat: false
                onTriggered: Qt.callLater(rowsColumn.sync)
            }

            ListModel {
                id: rowModel
            }

            ListModel {
                id: fileModel
            }

            Repeater {
                model: rowModel
                delegate: DelegateChooser {
                    role: "type"

                    DelegateChoice {
                        roleValue: "action"
                        ThinkActivityRow {
                            colorFor: root.themeColor
                            onOpenRequested: path => root.openPath(path)
                        }
                    }
                    DelegateChoice {
                        roleValue: "paragraph"
                        ThinkParagraph {
                            renderMarkdown: root.renderMarkdown
                            enableMouseSelection: root.enableMouseSelection
                        }
                    }
                }
            }

            // Bottom summary bar and changed files dropdown
            ColumnLayout {
                id: bottomSummaryContainer
                visible: fileModel.count > 0
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 0

                Rectangle {
                    id: bottomSummaryBar
                    Layout.fillWidth: true
                    implicitHeight: 28
                    topLeftRadius: Appearance.rounding.verysmall
                    topRightRadius: Appearance.rounding.verysmall
                    bottomLeftRadius: root.changedFilesDropdownOpen ? 0 : Appearance.rounding.verysmall
                    bottomRightRadius: root.changedFilesDropdownOpen ? 0 : Appearance.rounding.verysmall
                    color: bottomSummaryMouseArea.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant

                    MouseArea {
                        id: bottomSummaryMouseArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
                            root.changedFilesDropdownOpen = !root.changedFilesDropdownOpen;
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8

                        StyledText {
                            text: fileModel.count === 1
                                ? Translation.tr("%1 file changed").arg(fileModel.count)
                                : Translation.tr("%1 files changed").arg(fileModel.count)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.m3colors.m3onSurface
                        }

                        StyledText {
                            visible: rowsColumn.totalAddedLines > 0
                            text: `+${rowsColumn.totalAddedLines}`
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: "#4ade80"
                        }

                        StyledText {
                            visible: rowsColumn.totalRemovedLines > 0
                            text: `-${rowsColumn.totalRemovedLines}`
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: "#f87171"
                        }

                        MaterialSymbol {
                            id: dropdownChevron
                            text: "keyboard_arrow_down"
                            iconSize: 14
                            color: Appearance.colors.colSubtext
                            rotation: root.changedFilesDropdownOpen ? 0 : -90

                            Behavior on rotation {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            id: reviewBtn
                            implicitWidth: reviewRow.implicitWidth + 14
                            implicitHeight: 22
                            radius: Appearance.rounding.verysmall
                            color: reviewMouseArea.containsMouse ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                            border.width: 1
                            border.color: Appearance.colors.colOutlineVariant

                            MouseArea {
                                id: reviewMouseArea
                                anchors.fill: parent
                                enabled: rowsColumn.reviewPaths.length > 0
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: root.review(rowsColumn.reviewPaths)
                            }

                            RowLayout {
                                id: reviewRow
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    text: "rate_review"
                                    iconSize: 13
                                    color: Appearance.colors.colOnSecondaryContainer
                                }

                                StyledText {
                                    text: Translation.tr("Review")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                            }
                        }
                    }
                }

                // Dropdown panel for changed files
                Rectangle {
                    id: changedFilesDropdown
                    visible: root.changedFilesDropdownOpen
                    Layout.fillWidth: true
                    implicitHeight: changedFilesColumn.implicitHeight + 12
                    color: Appearance.colors.colLayer2
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    bottomLeftRadius: Appearance.rounding.verysmall
                    bottomRightRadius: Appearance.rounding.verysmall
                    clip: true

                    ColumnLayout {
                        id: changedFilesColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 6
                        spacing: 4

                        Repeater {
                            model: fileModel

                            delegate: Rectangle {
                                id: fileItemDelegate
                                required property string name
                                required property string path
                                required property int added
                                required property int removed
                                required property string typeIcon
                                required property string typeColor
                                readonly property bool canOpen: fileItemDelegate.path.startsWith("/")

                                Layout.fillWidth: true
                                implicitHeight: 26
                                radius: Appearance.rounding.verysmall
                                color: fileItemMouseArea.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

                                MouseArea {
                                    id: fileItemMouseArea
                                    anchors.fill: parent
                                    cursorShape: fileItemDelegate.canOpen ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    hoverEnabled: true
                                    onClicked: root.openPath(fileItemDelegate.path)
                                }

                                Loader {
                                    anchors.fill: parent
                                    active: fileItemMouseArea.containsMouse && fileItemDelegate.canOpen
                                    sourceComponent: Item {
                                        StyledToolTip {
                                            delay: 400
                                            text: Translation.tr("Click to open %1").arg(fileItemDelegate.path)
                                        }
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    MaterialSymbol {
                                        text: fileItemDelegate.typeIcon
                                        iconSize: 14
                                        color: root.themeColor(fileItemDelegate.typeColor)
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    StyledText {
                                        text: fileItemDelegate.name
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.m3colors.m3onSurface
                                        elide: Text.ElideMiddle
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    StyledText {
                                        visible: fileItemDelegate.added > 0
                                        text: `+${fileItemDelegate.added}`
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: "#4ade80"
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    StyledText {
                                        visible: fileItemDelegate.removed > 0
                                        text: `-${fileItemDelegate.removed}`
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.DemiBold
                                        color: "#f87171"
                                        Layout.alignment: Qt.AlignVCenter
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
