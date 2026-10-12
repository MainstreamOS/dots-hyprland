pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import org.kde.syntaxhighlighting
import "passbudget.js" as PassBudget
import "../../../common/functions/markdownblocks.js" as MarkdownBlocks
import "../../../../services/ai/sink.js" as Sink

ColumnLayout {
    id: root
    // These are needed on the parent loader
    property bool editing: false
    property bool renderMarkdown: true
    property bool enableMouseSelection: false
    property string segmentContent: ""
    property var segmentLang: "txt"
    property var messageData: null
    property bool done: true
    property int contentRevision: 0
    property bool isCommandRequest: segmentLang === "command"
    property var displayLang: (isCommandRequest ? "bash" : segmentLang)

    property int _shownLength: 0
    property int _shownRevision: -1
    property int _lineCount: 1
    property bool _ready: false
    // Posted calls can still arrive while the block is being torn down.
    property bool _alive: true
    Component.onDestruction: root._alive = false
    property string _shownTail: ""
    readonly property int _appendSlice: 2000

    // Source of this block for saving an edit, fenced again.
    function sourceText(): string {
        return MarkdownBlocks.fence(root.segmentLang, root.editing ? codeTextArea.text : root.segmentContent);
    }

    // The stream escapes think tags in model text; copies and saves get the original.
    function plainCode(): string {
        return Sink.unescapeThinkTags(root.segmentContent);
    }

    function countNewlines(text: string): int {
        let count = 0;
        for (let i = text.indexOf("\n"); i !== -1; i = text.indexOf("\n", i + 1)) count++;
        return count;
    }

    function lineNumbers(from: int, to: int): string {
        const parts = [];
        for (let n = from; n <= to; n++) parts.push(n);
        return parts.join("\n");
    }

    function setLineNumbers(count: int): void {
        lineNumberModel.clear();
        root._lineCount = 0;
        root.appendLineNumbers(count);
    }

    // Line numbers live in rows of 100 so an append relays out only the last row.
    function appendLineNumbers(added: int): void {
        const last = root._lineCount + added;
        let n = root._lineCount + 1;
        while (n <= last) {
            const row = Math.floor((n - 1) / 100);
            const rowEnd = Math.min(last, (row + 1) * 100);
            const numbers = root.lineNumbers(n, rowEnd);
            if (row < lineNumberModel.count) {
                lineNumberModel.setProperty(row, "numbers", lineNumberModel.get(row).numbers + "\n" + numbers);
            } else {
                lineNumberModel.append({ numbers: numbers });
            }
            n = rowEnd + 1;
        }
        root._lineCount = last;
    }

    function setFullText(): void {
        appendTimer.stop();
        const text = root.segmentContent;
        codeTextArea.text = text;
        root._shownLength = text.length;
        root._shownTail = text.slice(-8);
        root._shownRevision = root.contentRevision;
        root.setLineNumbers(root.countNewlines(text) + 1);
    }

    // True when the text only grew past what is shown; the open block may have
    // shown backticks that turned out to be the closing fence.
    function extendsShown(text: string): bool {
        if (root._shownRevision !== root.contentRevision || text.length < root._shownLength) return false;
        return text.slice(root._shownLength - root._shownTail.length, root._shownLength) === root._shownTail;
    }

    function syncCode(): void {
        if (root._alive !== true || !root._ready || !root.messageData || root.editing) return;
        const text = root.segmentContent;
        if (!root.extendsShown(text)) {
            root.setFullText();
            return;
        }
        if (text.length === root._shownLength) return;
        // Streamed code goes in a slice per event loop pass: laying out and
        // highlighting a long block at once would hold the shell for too long.
        if (PassBudget.remaining() <= 0) {
            appendTimer.restart();
            return;
        }
        let end = Math.min(text.length, root._shownLength + root._appendSlice);
        const last = text.charCodeAt(end - 1);
        if (end < text.length && last >= 0xD800 && last <= 0xDBFF) end--;
        const delta = text.slice(root._shownLength, end);
        codeTextArea.insert(codeTextArea.length, delta);
        root._shownLength = end;
        root._shownTail = text.slice(Math.max(0, end - 8), end);
        const added = root.countNewlines(delta);
        if (added > 0) root.appendLineNumbers(added);
        PassBudget.done();
        if (end < text.length) appendTimer.restart();
    }

    onSegmentContentChanged: root.syncCode()
    onContentRevisionChanged: root.syncCode()
    onEditingChanged: if (!root.editing && root._ready) root.setFullText()
    // Nothing is shown before this point, so a block that arrives while the reply
    // streams starts empty and fills in slices instead of all at once.
    Component.onCompleted: {
        root._ready = true;
        if (root.done) {
            root.setFullText();
        } else {
            root._shownRevision = root.contentRevision;
            root.setLineNumbers(1);
            // A delegate made during a flush sees the previous open block's text
            // until the flush is done, so the first slice waits for a later pass.
            appendTimer.restart();
        }
    }

    Timer {
        id: appendTimer
        interval: 0
        repeat: false
        onTriggered: Qt.callLater(root.syncCode)
    }

    Component {
        id: saveFileComponent
        FileView {
            id: saveFile
            property string displayPath
            atomicWrites: true
            blockWrites: false
            preload: false
            watchChanges: false
            printErrors: false
            onSaved: {
                Quickshell.execDetached(["notify-send",
                    Translation.tr("Code saved to file"),
                    Translation.tr("Saved to %1").arg(saveFile.displayPath),
                    "-a", "Shell"
                ])
                saveFile.destroy()
            }
            onSaveFailed: {
                Quickshell.execDetached(["notify-send",
                    Translation.tr("Could not save the code to %1").arg(saveFile.displayPath),
                    "-a", "Shell"
                ])
                saveFile.destroy()
            }
        }
    }

    function saveToDownloads(): void {
        const lang = /^[A-Za-z0-9_+-]{1,16}$/.test(root.segmentLang ?? "") ? root.segmentLang : "txt";
        const path = `${FileUtils.trimFileProtocol(Directories.downloads)}/code.${lang}`;
        const file = saveFileComponent.createObject(root, { path: path, displayPath: path });
        file.setText(root.plainCode());
    }

    property real codeBlockBackgroundRounding: Appearance.rounding.small
    property real codeBlockHeaderPadding: 3
    property real codeBlockComponentSpacing: 2

    spacing: codeBlockComponentSpacing

    Rectangle { // Code background
        Layout.fillWidth: true
        topLeftRadius: codeBlockBackgroundRounding
        topRightRadius: codeBlockBackgroundRounding
        bottomLeftRadius: Appearance.rounding.unsharpen
        bottomRightRadius: Appearance.rounding.unsharpen
        color: Appearance.colors.colSurfaceContainerHighest
        implicitHeight: codeBlockTitleBarRowLayout.implicitHeight + codeBlockHeaderPadding * 2

        RowLayout { // Language and buttons
            id: codeBlockTitleBarRowLayout
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: codeBlockHeaderPadding
            anchors.rightMargin: codeBlockHeaderPadding
            spacing: 5

            StyledText {
                id: codeBlockLanguage
                Layout.alignment: Qt.AlignLeft
                Layout.fillWidth: false
                Layout.topMargin: 7
                Layout.bottomMargin: 7
                Layout.leftMargin: 10
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                text: root.displayLang ? Repository.definitionForName(root.displayLang).name : "plain"
            }

            Item { Layout.fillWidth: true }

            ButtonGroup {
                AiMessageControlButton {
                    id: copyCodeButton
                    buttonIcon: activated ? "inventory" : "content_copy"

                    onClicked: {
                        Quickshell.clipboardText = root.plainCode()
                        copyCodeButton.activated = true
                        copyIconTimer.restart()
                    }

                    Timer {
                        id: copyIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: {
                            copyCodeButton.activated = false
                        }
                    }
                    StyledToolTip {
                        text: Translation.tr("Copy code")
                    }
                }
                AiMessageControlButton {
                    id: saveCodeButton
                    buttonIcon: activated ? "check" : "save"

                    onClicked: {
                        root.saveToDownloads()
                        saveCodeButton.activated = true
                        saveIconTimer.restart()
                    }

                    Timer {
                        id: saveIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: {
                            saveCodeButton.activated = false
                        }
                    }
                    StyledToolTip {
                        text: Translation.tr("Save to Downloads")
                    }
                }
            }
        }
    }

    RowLayout { // Line numbers and code
        spacing: codeBlockComponentSpacing

        Rectangle { // Line numbers
            implicitWidth: 40
            implicitHeight: lineNumberColumnLayout.implicitHeight
            Layout.fillHeight: true
            Layout.fillWidth: false
            topLeftRadius: Appearance.rounding.unsharpen
            bottomLeftRadius: codeBlockBackgroundRounding
            topRightRadius: Appearance.rounding.unsharpen
            bottomRightRadius: Appearance.rounding.unsharpen
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: lineNumberColumnLayout
                anchors {
                    left: parent.left
                    right: parent.right
                    rightMargin: 5
                    top: parent.top
                    topMargin: 6
                }
                spacing: 0

                Repeater {
                    model: ListModel {
                        id: lineNumberModel
                    }
                    Text {
                        required property string numbers
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        horizontalAlignment: Text.AlignRight
                        text: numbers
                    }
                }
            }
        }

        Rectangle { // Code background
            Layout.fillWidth: true
            topLeftRadius: Appearance.rounding.unsharpen
            bottomLeftRadius: Appearance.rounding.unsharpen
            topRightRadius: Appearance.rounding.unsharpen
            bottomRightRadius: codeBlockBackgroundRounding
            color: Appearance.colors.colLayer2
            implicitHeight: codeColumnLayout.implicitHeight

            // Sideways wheel/touchpad scrolling for long lines. Lives outside
            // the ScrollView, whose wheelEnabled: false blocks its children.
            WheelHandler {
                orientation: Qt.Horizontal
                // A touchpad swipe is rarely straight, so its vertical part still has to reach the chat.
                blocking: false
                onWheel: (event) => {
                    const flick = codeScrollView.contentItem
                    const maxX = Math.max(0, flick.contentWidth - flick.width)
                    const delta = event.pixelDelta.x !== 0 ? event.pixelDelta.x : event.angleDelta.x / 2
                    flick.contentX = Math.max(0, Math.min(maxX, flick.contentX - delta))
                }
            }

            ColumnLayout {
                id: codeColumnLayout
                anchors.fill: parent
                spacing: 0
                ScrollView {
                    id: codeScrollView
                    Layout.fillWidth: true
                    // Layout.fillHeight: true
                    implicitWidth: parent.width
                    implicitHeight: codeTextArea.implicitHeight + 1
                    contentWidth: codeTextArea.width - 1
                    // contentHeight: codeTextArea.contentHeight
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AlwaysOff

                    // ScrollView enables wheelEnabled by default, which accepts
                    // every wheel event, so the chat stopped scrolling with the
                    // cursor over code. Turn it off so vertical wheel events
                    // reach the chat. Horizontal scrolling is handled by the
                    // WheelHandler on the code background above.
                    wheelEnabled: false

                    ScrollBar.horizontal: ScrollBar {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        padding: 5
                        policy: ScrollBar.AsNeeded
                        opacity: visualSize == 1 ? 0 : 1
                        visible: opacity > 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                        
                        contentItem: Rectangle {
                            implicitHeight: 6
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2Active
                        }
                    }

                    StyledTextArea { // Code
                        id: codeTextArea
                        Layout.fillWidth: true
                        readOnly: !editing
                        selectByMouse: enableMouseSelection || editing
                        renderType: ScreenScale.renderTypeFor(Screen.name)
                        font.family: Appearance.font.family.monospace
                        font.hintingPreference: Font.PreferNoHinting // Prevent weird bold text
                        font.pixelSize: Appearance.font.pixelSize.small
                        selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        // wrapMode: TextEdit.Wrap
                        color: root.messageData?.thinking ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1

                        onTextChanged: {
                            if (!root.editing) return
                            const lines = root.countNewlines(codeTextArea.text) + 1
                            if (lines !== root._lineCount) root.setLineNumbers(lines)
                        }

                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_Tab) {
                                // Insert 4 spaces at cursor
                                const cursor = codeTextArea.cursorPosition;
                                codeTextArea.insert(cursor, "    ");
                                codeTextArea.cursorPosition = cursor + 4;
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_C) && event.modifiers == Qt.ControlModifier) {
                                codeTextArea.copy();
                                event.accepted = true;
                            }
                        }

                        SyntaxHighlighter {
                            id: highlighter
                            textEdit: codeTextArea
                            repository: Repository
                            definition: Repository.definitionForName(root.displayLang || "plaintext")
                            theme: Appearance.syntaxHighlightingTheme
                        }
                    }
                }
                Loader {
                    active: root.isCommandRequest && (root.messageData?.functionPending ?? false) && Ai.pendingConfirmation?.messageId === root.messageData?.id
                    visible: active
                    Layout.fillWidth: true
                    Layout.margins: 6
                    Layout.topMargin: 0
                    sourceComponent: RowLayout {
                        Item { Layout.fillWidth: true }
                        ButtonGroup {
                            GroupButton {
                                contentItem: StyledText {
                                    text: Translation.tr("Reject")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer2
                                }
                                onClicked: {
                                    if (Ai.pendingConfirmation) Ai.rejectPendingAction(Ai.pendingConfirmation.id)
                                }
                            }
                            GroupButton {
                                toggled: true
                                contentItem: StyledText {
                                    text: Translation.tr("Approve")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnPrimary
                                }
                                onClicked: {
                                    if (Ai.pendingConfirmation) Ai.approvePendingAction(Ai.pendingConfirmation.id)
                                }
                            }
                        }
                    }
                }
            }

            // MouseArea to block scrolling
            // MouseArea {
            //     id: codeBlockMouseArea
            //     anchors.fill: parent
            //     acceptedButtons: editing ? Qt.NoButton : Qt.LeftButton
            //     cursorShape: (enableMouseSelection || editing) ? Qt.IBeamCursor : Qt.ArrowCursor
            //     onWheel: (event) => {
            //         event.accepted = false
            //     }
            // }
        }
    }
}