import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../common/functions/markdownblocks.js" as MarkdownBlocks
import "../../../../services/ai/sink.js" as Sink

Rectangle {
    id: root
    property string messageId
    property var messageData: null
    readonly property var modelEntry: {
        const models = Ai.models;
        const id = root.messageData?.model ?? "";
        return (models && Object.prototype.hasOwnProperty.call(models, id)) ? models[id] : null;
    }

    property real messagePadding: 7
    property real contentSpacing: 3

    property bool enableMouseSelection: false
    property bool renderMarkdown: true
    property bool editing: false

    readonly property string role: root.messageData?.role ?? ""
    // Function and command outputs are stored as user messages but belong to a tool.
    readonly property bool isToolOutput: root.role !== "assistant" && (root.messageData?.functionName ?? "").length > 0
    readonly property bool isUserMessage: root.role === "user" && !root.isToolOutput
    readonly property string toolTitle: {
        if (!root.isToolOutput) return "";
        const activities = root.messageData?.activities ?? [];
        const command = activities.find(a => a?.kind === "command" && a?.target);
        return command ? String(command.target).split("\n")[0] : (root.messageData?.functionName ?? "");
    }

    property var splitter: MarkdownBlocks.createSplitter()
    property var blocks: []
    property string openBlockContent: ""

    function refresh(): void {
        const data = root.messageData;
        if (!data) {
            if (root.blocks.length > 0) root.blocks = [];
            root.openBlockContent = "";
            return;
        }
        const next = root.splitter.update(data.content, data.contentRevision, data.done);
        if (next !== root.blocks) root.blocks = next;
        root.openBlockContent = root.splitter.openContent();
    }

    onMessageDataChanged: {
        root.splitter = MarkdownBlocks.createSplitter();
        root.refresh();
    }
    Component.onCompleted: root.refresh()

    Connections {
        target: root.messageData
        function onContentChanged() { root.refresh(); }
        function onDoneChanged() { root.refresh(); }
        function onContentRevisionChanged() { root.refresh(); }
    }

    function blockText(block): string {
        return block.completed ? root.splitter.content(block.key) : root.openBlockContent;
    }

    function copyText(): string {
        const parts = [];
        for (const block of root.blocks) {
            if (block.type === "text") parts.push(root.blockText(block));
            else if (block.type === "code") parts.push(MarkdownBlocks.fence(block.lang, root.blockText(block)));
        }
        return Sink.unescapeThinkTags(parts.join("")).trim();
    }

    function saveMessage(): void {
        if (!root.editing) return;
        const parts = [];
        for (let i = 0; i < blockRepeater.count; i++) {
            const item = blockRepeater.itemAt(i);
            if (item && typeof item.sourceText === "function") parts.push(item.sourceText());
        }
        root.editing = false;
        if (!root.messageData) return;
        Ai.updateMessageContent(root.messageId, parts.join(""));
    }

    anchors.left: parent?.left
    anchors.right: parent?.right
    implicitHeight: columnLayout.implicitHeight + root.messagePadding * 2

    radius: Appearance.rounding.normal
    color: (root.role === 'user') ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
    border.width: (root.role === 'user') ? 1 : 0
    border.color: Appearance.colors.colOutlineVariant

    Keys.onPressed: (event) => {
        if ( // Prevent de-select
            event.key === Qt.Key_Control ||
            event.key == Qt.Key_Shift ||
            event.key == Qt.Key_Alt ||
            event.key == Qt.Key_Meta
        ) {
            event.accepted = true
        }
        // Ctrl + S to save
        if ((event.key === Qt.Key_S) && event.modifiers == Qt.ControlModifier) {
            root.saveMessage();
            event.accepted = true;
        }
    }

    ColumnLayout { // Main layout of the whole thing
        id: columnLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: messagePadding
        spacing: root.contentSpacing

        Rectangle {
            Layout.fillWidth: true
            implicitWidth: headerRowLayout.implicitWidth + 4 * 2
            implicitHeight: headerRowLayout.implicitHeight + 4 * 2
            color: (root.role === 'user') ? Appearance.colors.colLayer1 : Appearance.colors.colSecondaryContainer
            radius: Appearance.rounding.small

            RowLayout { // Header
                id: headerRowLayout
                anchors {
                    fill: parent
                    margins: 4
                }
                spacing: 8

                Item { // Name
                    id: nameWrapper
                    implicitHeight: Math.max(nameRowLayout.implicitHeight + 2 * 2, 26)
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter

                    RowLayout {
                        id: nameRowLayout
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 8

                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillHeight: true
                            implicitWidth: root.role === 'assistant' ? modelIcon.width
                                : root.isUserMessage ? userAvatar.width
                                : roleIcon.implicitWidth
                            implicitHeight: root.role === 'assistant' ? modelIcon.height
                                : root.isUserMessage ? userAvatar.height
                                : roleIcon.implicitHeight

                            CustomIcon {
                                id: modelIcon
                                anchors.centerIn: parent
                                visible: root.role === 'assistant' && !!root.modelEntry?.icon
                                width: Appearance.font.pixelSize.large
                                height: Appearance.font.pixelSize.large
                                source: root.role === 'assistant' ? (root.modelEntry?.icon ?? '') : ''

                                colorize: true
                                color: Appearance.m3colors.m3onSecondaryContainer
                            }

                            ClippingRectangle {
                                id: userAvatar
                                anchors.centerIn: parent
                                visible: root.isUserMessage && userAvatarImage.status === Image.Ready
                                width: Appearance.font.pixelSize.larger
                                height: Appearance.font.pixelSize.larger
                                radius: Appearance.rounding.full
                                color: "transparent"

                                StyledImage {
                                    id: userAvatarImage
                                    anchors.fill: parent
                                    source: (root.isUserMessage && Directories.userAvatarPathAccountsService) ? ("file://" + Directories.userAvatarPathAccountsService) : ""
                                    fallbacks: [
                                        Directories.userAvatarPathRicersAndWeirdSystems ? ("file://" + Directories.userAvatarPathRicersAndWeirdSystems) : "",
                                        Directories.userAvatarPathRicersAndWeirdSystems2 ? ("file://" + Directories.userAvatarPathRicersAndWeirdSystems2) : ""
                                    ]
                                    fillMode: Image.PreserveAspectCrop
                                    antialiasing: true
                                    fadeIn: false
                                }
                            }

                            MaterialSymbol {
                                id: roleIcon
                                anchors.centerIn: parent
                                visible: !modelIcon.visible && !userAvatar.visible
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.m3colors.m3onSecondaryContainer
                                text: root.isToolOutput ? (root.messageData?.functionName === "run_shell_command" ? 'terminal' : 'build') :
                                    root.role == 'user' ? 'person' :
                                    root.role == 'interface' ? 'settings' :
                                    root.role == 'assistant' ? 'neurology' :
                                    'computer'
                            }
                        }

                        StyledText {
                            id: providerName
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.m3colors.m3onSecondaryContainer
                            text: root.role == 'assistant' ? ((root.modelEntry?.name ?? root.messageData?.model ?? "").replace(/^Custom:\s*/i, "")) :
                                root.isToolOutput ? root.toolTitle :
                                root.role == 'user' ? (SystemInfo.username || Translation.tr("User")) :
                                Translation.tr("Interface")
                        }
                    }
                }

                Button { // Not visible to model
                    id: modelVisibilityIndicator
                    visible: root.role == 'interface'
                    implicitWidth: 16
                    implicitHeight: 30
                    Layout.alignment: Qt.AlignVCenter

                    background: Item

                    MaterialSymbol {
                        id: notVisibleToModelText
                        anchors.centerIn: parent
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        text: "visibility_off"
                    }
                    StyledToolTip {
                        text: Translation.tr("Not visible to model")
                    }
                }

                ButtonGroup {
                    spacing: 5

                    AiMessageControlButton {
                        id: regenButton
                        buttonIcon: "refresh"
                        visible: root.role === 'assistant'

                        onClicked: {
                            Ai.regenerate(root.messageId)
                        }

                        StyledToolTip {
                            text: Translation.tr("Regenerate")
                        }
                    }

                    AiMessageControlButton {
                        id: copyButton
                        buttonIcon: activated ? "inventory" : "content_copy"

                        onClicked: {
                            Quickshell.clipboardText = root.copyText()
                            copyButton.activated = true
                            copyIconTimer.restart()
                        }

                        Timer {
                            id: copyIconTimer
                            interval: 1500
                            repeat: false
                            onTriggered: {
                                copyButton.activated = false
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("Copy")
                        }
                    }
                    AiMessageControlButton {
                        id: editButton
                        activated: root.editing
                        enabled: root.messageData?.done ?? false
                        buttonIcon: "edit"
                        onClicked: {
                            if (root.editing) root.saveMessage()
                            else root.editing = true
                        }
                        StyledToolTip {
                            text: root.editing ? Translation.tr("Save") : Translation.tr("Edit")
                        }
                    }
                    AiMessageControlButton {
                        id: toggleMarkdownButton
                        visible: root.role === 'assistant'
                        activated: !root.renderMarkdown
                        buttonIcon: "code"
                        onClicked: {
                            root.renderMarkdown = !root.renderMarkdown
                        }
                        StyledToolTip {
                            text: Translation.tr("View Markdown source")
                        }
                    }
                    AiMessageControlButton {
                        id: deleteButton
                        buttonIcon: "close"
                        onClicked: {
                            Ai.removeMessage(root.messageId)
                        }
                        StyledToolTip {
                            text: Translation.tr("Delete")
                        }
                    }
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            active: (root.messageData?.localFilePath ?? "").length > 0
            sourceComponent: AttachedFileIndicator {
                filePath: root.messageData?.localFilePath ?? ""
                canRemove: false
            }
        }

        ColumnLayout { // Message content
            id: messageContentColumnLayout
            spacing: 0

            Item {
                Layout.fillWidth: true
                implicitHeight: loadingIndicatorLoader.shown ? loadingIndicatorLoader.implicitHeight : 0
                implicitWidth: loadingIndicatorLoader.implicitWidth
                visible: implicitHeight > 0

                Behavior on implicitHeight {
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                FadeLoader {
                    id: loadingIndicatorLoader
                    anchors.centerIn: parent
                    shown: (root.blocks.length < 1) && (!root.messageData?.done)
                    sourceComponent: MaterialLoadingIndicator {
                        loading: true
                    }
                }
            }
            Repeater {
                id: blockRepeater
                model: ScriptModel {
                    values: root.blocks
                    objectProp: "key"
                }
                delegate: DelegateChooser {
                    id: messageDelegate
                    role: "type"

                    DelegateChoice { roleValue: "code"; MessageCodeBlock {
                        editing: root.editing
                        renderMarkdown: root.renderMarkdown
                        enableMouseSelection: root.enableMouseSelection
                        segmentContent: root.blockText(modelData)
                        segmentLang: modelData.lang
                        messageData: root.messageData
                        done: root.messageData?.done ?? false
                        contentRevision: root.messageData?.contentRevision ?? 0
                    } }
                    DelegateChoice { roleValue: "think"; MessageThinkBlock {
                        editing: root.editing
                        renderMarkdown: root.renderMarkdown
                        enableMouseSelection: root.enableMouseSelection
                        segmentContent: root.blockText(modelData)
                        messageData: root.messageData
                        done: root.messageData?.done ?? false
                        completed: modelData.completed
                        thinkIndex: modelData.thinkIndex
                        contentRevision: root.messageData?.contentRevision ?? 0
                    } }
                    DelegateChoice { roleValue: "text"; MessageTextBlock {
                        editing: root.editing
                        renderMarkdown: root.renderMarkdown
                        enableMouseSelection: root.enableMouseSelection
                        segmentContent: root.blockText(modelData)
                        messageData: root.messageData
                        done: root.messageData?.done ?? false
                        completed: modelData.completed
                        contentRevision: root.messageData?.contentRevision ?? 0
                        forceDisableChunkSplitting: modelData.hasFence
                    } }
                }
            }

            // Streaming active indicator
            RowLayout {
                visible: (root.role === 'assistant') && !(root.messageData?.done ?? true) && (root.blocks.length > 0)
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                Layout.leftMargin: 6
                spacing: 6

                Rectangle {
                    id: streamingBar
                    readonly property bool live: !(root.messageData?.done ?? true)
                    property real pulse: 1
                    implicitWidth: 8
                    implicitHeight: 14
                    radius: 2
                    color: Appearance.colors.colPrimary
                    opacity: streamingBar.live ? streamingBar.pulse : 1
                    SequentialAnimation on pulse {
                        loops: Animation.Infinite
                        running: streamingBar.live
                        NumberAnimation { to: 0.2; duration: 450; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0; duration: 450; easing.type: Easing.InOutQuad }
                    }
                }

                StyledText {
                    text: Translation.tr("Generating…")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        Flow { // Annotations
            visible: root.messageData?.annotationSources?.length > 0
            spacing: 5
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.annotationSources || []
                }
                delegate: AnnotationSourceButton {
                    required property var modelData
                    displayText: modelData.text
                    url: modelData.url
                }
            }
        }

        Flow { // Search queries
            visible: root.messageData?.searchQueries?.length > 0
            spacing: 5
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft

            Repeater {
                model: ScriptModel {
                    values: root.messageData?.searchQueries || []
                }
                delegate: SearchQueryButton {
                    required property var modelData
                    query: modelData
                }
            }
        }

    }
}

