import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
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

    property real messagePadding: 10
    property real contentSpacing: 6

    property bool enableMouseSelection: false
    property bool renderMarkdown: true
    property bool editing: false

    readonly property string role: root.messageData?.role ?? ""
    // Function and command outputs are stored as user messages but belong to a tool.
    readonly property bool isToolOutput: root.role !== "assistant" && (root.messageData?.functionName ?? "").length > 0
    readonly property bool isUserMessage: root.role === "user" && !root.isToolOutput
    readonly property color headerColor: root.isUserMessage ? Appearance.chatBubble.mineText
        : root.role === "assistant" ? Appearance.chatBubble.theirsText : Appearance.colors.colSubtext
    // The model still gets the answer's text as the user turn.
    readonly property string answer: root.messageData?.answer ?? ""
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

    TextMetrics {
        id: userTextMetrics
        font.family: Appearance.font.family.reading
        font.pixelSize: Appearance.font.pixelSize.small
        text: root.isUserMessage ? (root.messageData?.content ?? "") : ""
    }

    anchors.left: root.isUserMessage ? undefined : parent?.left
    anchors.right: parent?.right
    width: parent ? (root.isUserMessage
        ? Math.min(parent.width * 0.88, Math.max(180, userTextMetrics.boundingRect.width + root.messagePadding * 2 + 16))
        : parent.width) : 0
    implicitHeight: root.answer ? answerLine.implicitHeight + root.messagePadding * 2 : columnLayout.implicitHeight + root.messagePadding * 2

    radius: 14
    color: root.answer ? "transparent" : root.isUserMessage ? Appearance.chatBubble.mine
        : root.role === "assistant" ? Appearance.chatBubble.theirs
        : root.isToolOutput ? Appearance.colors.colLayer2 : "transparent"

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

    RowLayout {
        id: answerLine
        visible: !!root.answer
        anchors.centerIn: parent
        spacing: 6

        MaterialSymbol {
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colSubtext
            text: root.answer === "approved" ? "check" : "close"
        }
        StyledText {
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: root.answer === "approved" ? Translation.tr("Approved") : Translation.tr("Declined")
        }
    }

    ColumnLayout { // Main layout of the whole thing
        id: columnLayout
        visible: !root.answer

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: messagePadding
        spacing: root.contentSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            CustomIcon {
                visible: root.role === "assistant" && !!root.modelEntry?.icon
                implicitWidth: 16
                implicitHeight: 16
                source: root.modelEntry?.icon ?? ""
                colorize: true
                color: root.headerColor
            }

            MaterialSymbol {
                visible: root.role !== "assistant" || !root.modelEntry?.icon
                text: root.isToolOutput ? "terminal" : root.isUserMessage ? "person" : "neurology"
                iconSize: 16
                color: root.headerColor
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Medium
                color: root.headerColor
                text: root.role === "assistant"
                    ? (root.modelEntry?.name ?? root.messageData?.model ?? "").replace(/^Custom:\s*/i, "")
                    : root.isToolOutput ? root.toolTitle : root.isUserMessage ? Translation.tr("You") : Translation.tr("Interface")
            }

            MaterialSymbol {
                visible: root.role === "interface"
                text: "visibility_off"
                iconSize: 16
                color: Appearance.colors.colSubtext
            }

            RippleButton {
                id: copyButton
                property bool activated: false
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: 8
                Accessible.name: Translation.tr("Copy message")
                onClicked: {
                    Quickshell.clipboardText = root.copyText();
                    activated = true;
                    copyIconTimer.restart();
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: copyButton.activated ? "check" : "content_copy"
                    iconSize: 17
                    color: Appearance.colors.colSubtext
                }
                Timer {
                    id: copyIconTimer
                    interval: 1500
                    onTriggered: copyButton.activated = false
                }
                StyledToolTip { text: Translation.tr("Copy") }
            }

            RippleButton {
                id: moreButton
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: 8
                Accessible.name: Translation.tr("Message actions")
                onClicked: {
                    if (messageMenu.visible) messageMenu.close();
                    else messageMenu.openAt(moreButton.width - messageMenu.width, moreButton.height + 4);
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: root.editing ? "edit" : "more_horiz"
                    iconSize: 20
                    color: root.editing ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }
                StyledToolTip {
                    extraVisibleCondition: !messageMenu.visible
                    text: Translation.tr("Message actions")
                }

                ContextMenuPopup {
                    id: messageMenu
                    width: 240
                    implicitHeight: menuColumn.implicitHeight + topPadding + bottomPadding
                    focus: true
                    // Let the trigger close the menu on click instead of
                    // dismissing it on press and immediately opening it again.
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                    contentItem: ColumnLayout {
                        id: menuColumn
                        spacing: 2

                        ContextMenuItem {
                            visible: root.role === "assistant"
                            enabled: root.messageData?.done ?? false
                            iconName: "refresh"
                            label: Translation.tr("Regenerate")
                            Accessible.name: label
                            onClicked: {
                                messageMenu.close();
                                Ai.regenerate(root.messageId);
                            }
                        }
                        ContextMenuItem {
                            enabled: root.messageData?.done ?? false
                            iconName: root.editing ? "save" : "edit"
                            label: root.editing ? Translation.tr("Save changes") : Translation.tr("Edit message")
                            Accessible.name: label
                            onClicked: {
                                messageMenu.close();
                                if (root.editing) root.saveMessage();
                                else root.editing = true;
                            }
                        }
                        ContextMenuItem {
                            visible: root.role === "assistant"
                            iconName: "code"
                            label: root.renderMarkdown ? Translation.tr("View Markdown source") : Translation.tr("Show formatted text")
                            Accessible.name: label
                            onClicked: {
                                messageMenu.close();
                                root.renderMarkdown = !root.renderMarkdown;
                            }
                        }
                        ContextMenuSeparator {}
                        ContextMenuItem {
                            iconName: "delete"
                            label: Translation.tr("Delete message")
                            Accessible.name: label
                            onClicked: {
                                messageMenu.close();
                                Ai.removeMessage(root.messageId);
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: ColorUtils.transparentize(root.isUserMessage
                ? Appearance.chatBubble.mineText : Appearance.chatBubble.theirsText, 0.82)
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
            Layout.fillWidth: true
            spacing: 4

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
                        textColor: root.isUserMessage ? Appearance.chatBubble.mineText : Appearance.chatBubble.theirsText
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

