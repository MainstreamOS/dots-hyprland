pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "textchunks.js" as TextChunks
import "passbudget.js" as PassBudget

ColumnLayout {
    id: root
    // These are needed on the parent loader
    property bool editing: false
    property bool renderMarkdown: true
    property bool enableMouseSelection: false
    property string segmentContent: ""
    property var messageData: null
    property bool done: true
    property bool completed: false
    property int contentRevision: 0
    property bool forceDisableChunkSplitting: false

    readonly property bool finished: root.completed || root.done
    readonly property bool fadeChunkSplitting: !root.forceDisableChunkSplitting && !root._sawPipeLine && Config.options.sidebar.ai.textFadeIn
    readonly property string chunkMode: root.forceDisableChunkSplitting ? "single" : root.fadeChunkSplitting ? "fade" : "blocks"

    property var _chunker: null
    property int _revision: -1
    property bool _sawPipeLine: false
    property int _stable: 0          // chunks already shown in their final form
    property var _sources: []        // source text of each final chunk
    property string _tail: ""
    property bool _tailDirty: false
    property var _latexSpans: []     // per final chunk: [{start, end, hash}]
    property var _latexChunks: ({})  // hash -> indexes of the final chunks showing it
    property bool _latexScanned: false
    // Posted calls can still arrive while the block is being torn down.
    property bool _alive: true
    Component.onDestruction: root._alive = false

    spacing: 0
    Layout.fillWidth: true

    // Source of this block for saving an edit.
    function sourceText(): string {
        return root.editing && editLoader.item ? editLoader.item.text : root.segmentContent;
    }

    function clearChunks(): void {
        root._stable = 0;
        root._sources = [];
        root._tail = "";
        root._tailDirty = false;
        root._latexSpans = [];
        root._latexChunks = {};
        root._latexScanned = false;
        tailTimer.stop();
        chunkModel.clear();
    }

    function resetChunks(): void {
        root._chunker = TextChunks.createChunker(root.chunkMode);
        root._revision = root.contentRevision;
        root.clearChunks();
    }

    function displayText(index: int, source: string): string {
        if (!root.renderMarkdown) return source;
        const spans = root._latexSpans[index];
        if (!spans || spans.length === 0) return source;
        let out = "";
        let last = 0;
        for (const span of spans) {
            const imagePath = LatexRenderer.renderedImagePaths[span.hash];
            if (!imagePath) continue;
            out += source.slice(last, span.start) + `![latex](${imagePath})`;
            last = span.end;
        }
        return out + source.slice(last);
    }

    function setChunk(index: int, text: string): void {
        if (index < chunkModel.count) chunkModel.setProperty(index, "chunk", text);
        else chunkModel.append({ chunk: text });
    }

    function pushTail(): void {
        if (root._chunker === null) return;
        // Chunks before the tail are still being set; the sync that sets the
        // last of them pushes the tail.
        if (root._stable < root._chunker.count() - 1) return;
        root._tailDirty = false;
        const index = root._chunker.count() - 1;
        // A table is laid out again whole on every change, so while it streams
        // it grows a finished row at a time.
        const text = root._chunker.inTable() ? root._tail.slice(0, root._tail.lastIndexOf("\n") + 1) : root._tail;
        root.setChunk(index, text);
    }

    // Pushes the tail now, or soon when this pass has no budget left.
    function pushTailWithin(): void {
        if (!root.done && PassBudget.remaining() <= 0) {
            root._tailDirty = true;
            tailTimer.interval = 16;
            tailTimer.start();
            return;
        }
        root.pushTail();
        PassBudget.done();
        tailTimer.interval = Math.max(50, root._tail.length / 40);
        tailTimer.start();
    }

    function tailTick(): void {
        if (root._alive !== true || !root.messageData || !root._tailDirty) return;
        root.pushTailWithin();
    }

    function sync(): void {
        if (root._alive !== true || !root.messageData || root.editing) return;
        // While the reply streams, chunks wait for the column's width, so their
        // layout happens in the sliced passes below rather than all at once.
        if (!root.done && chunkColumn.width <= 0) return;
        const text = root.segmentContent;
        if (root._revision !== root.contentRevision) root._sawPipeLine = false;
        if (root._chunker === null || root._revision !== root.contentRevision || root._chunker.mode !== root.chunkMode) {
            root.resetChunks();
        }
        let result = root._chunker.update(text, root.finished);
        // The chunker has already started over on the new text.
        if (result.reset) root.clearChunks();
        if (root._chunker.mode === "fade" && root._chunker.sawPipeLine) {
            // Tables never fade in; switching mode rebuilds the chunks once.
            root._sawPipeLine = true;
            root.resetChunks();
            result = root._chunker.update(text, root.finished);
        }

        // Each chunk is laid out when it is set, so while the reply streams a burst
        // of finished chunks is spread over several event loop passes; the tail
        // waits for them.
        const sources = root._sources;
        const sliced = !root.done;
        if (sliced && root._stable < result.stable && PassBudget.remaining() <= 0) {
            syncTimer.restart();
            return;
        }
        let next = root._stable;
        while (next < result.stable) {
            sources[next] = root._chunker.chunk(text, next);
            // A table lays out slowly, so it gets a pass of its own.
            if (sliced && next > root._stable && sources[next].charCodeAt(0) === 124) break;
            root.setChunk(next, root.displayText(next, sources[next]));
            next++;
            if (sliced && PassBudget.remaining() <= 0) break;
        }
        if (sliced) PassBudget.done();
        root._stable = next;
        if (next < result.stable) {
            syncTimer.restart();
            return;
        }

        const count = root._chunker.count();
        if (result.stable < count) {
            root._tail = root._chunker.chunk(text, count - 1);
            if (tailTimer.running) {
                root._tailDirty = true;
            } else {
                root.pushTailWithin();
            }
        } else {
            tailTimer.stop();
            root._tail = "";
            root._tailDirty = false;
            if (chunkModel.count > count) chunkModel.remove(count, chunkModel.count - count);
        }
        if (result.stable === count) root.renderLatex();
    }

    function renderLatex(): void {
        if (!root.messageData || root._latexScanned || !root.finished || root.editing || !root.renderMarkdown) return;
        root._latexScanned = true;
        // $$..$$, \[..\], \(..\), and $..$ that opens and closes next to text and is not a price
        const regex = /\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\\(([\s\S]+?)\\\)|\$(?=[^\s$])([^$\n]*?[^\s$])\$(?!\d)/g;
        const spansByChunk = [];
        const chunksByHash = {};
        let found = false;
        for (let i = 0; i < root._sources.length; i++) {
            const source = root._sources[i];
            const spans = [];
            if (source.indexOf("$") !== -1 || source.indexOf("\\") !== -1) {
                regex.lastIndex = 0;
                let match;
                while ((match = regex.exec(source)) !== null) {
                    const expression = (match[1] ?? match[2] ?? match[3] ?? match[4] ?? "").trim();
                    if (expression.length === 0) continue;
                    // Renders already cached report back at once, before this block
                    // listens; the refresh below shows them instead.
                    const hash = LatexRenderer.requestRender(expression)[0];
                    spans.push({ start: match.index, end: match.index + match[0].length, hash: hash });
                    const chunks = chunksByHash[hash] ?? (chunksByHash[hash] = []);
                    if (chunks[chunks.length - 1] !== i) chunks.push(i);
                    found = true;
                }
            }
            spansByChunk.push(spans);
        }
        if (!found) return;
        root._latexChunks = chunksByHash;
        root._latexSpans = spansByChunk;
        root.refreshDisplay();
    }

    function refreshDisplay(): void {
        for (let i = 0; i < root._stable && i < chunkModel.count; i++) {
            if (root._latexSpans[i]?.length > 0) root.setChunk(i, root.displayText(i, root._sources[i]));
        }
    }

    // Text changes are applied on a later pass than the flush that made them, so
    // laying out text never adds to the cost of creating the blocks around it.
    onSegmentContentChanged: syncTimer.restart()
    onFinishedChanged: syncTimer.restart()
    onContentRevisionChanged: syncTimer.restart()
    onChunkModeChanged: syncTimer.restart()
    onEditingChanged: if (!root.editing) syncTimer.restart()
    onRenderMarkdownChanged: {
        if (!root.messageData) return;
        root.refreshDisplay();
        root.renderLatex();
    }
    Component.onCompleted: root.sync()

    Connections {
        target: LatexRenderer
        enabled: root._latexSpans.length > 0
        function onRenderFinished(hash, imagePath) {
            if (!root.messageData) return;
            for (const i of root._latexChunks[hash] ?? []) root.setChunk(i, root.displayText(i, root._sources[i]));
        }
    }

    Timer {
        id: syncTimer
        interval: 0
        repeat: false
        // Timers fire while a frame is being prepared; posting the work keeps
        // the layout it causes out of that frame.
        onTriggered: Qt.callLater(root.sync)
    }

    Timer {
        id: tailTimer
        // Large tails relayout rarely, so the cost per streamed character stays flat.
        // The interval is set only when (re)armed: changing it restarts a running timer.
        repeat: false
        onTriggered: Qt.callLater(root.tailTick)
    }

    ListModel {
        id: chunkModel
    }

    // A positioner, not a layout: a layout asks each text item for its natural
    // width, which lays the whole chunk out a second time on every change.
    Column {
        id: chunkColumn
        Layout.fillWidth: true
        onWidthChanged: if (!root.done && chunkColumn.width > 0) syncTimer.restart()

        Repeater {
            id: chunkRepeater
            model: chunkModel
            delegate: StyledTextArea {
                id: textArea
                required property int index
                required property string chunk
                readonly property bool tightSeams: root.chunkMode === "blocks"

                // Fade in animation
                visible: !root.editing && opacity > 0
                opacity: (!root.fadeChunkSplitting || root.done || textArea.index < chunkRepeater.count - 1) ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                // Inner seams drop their padding so the chunks lay out like one document.
                // The bottom padding of the last chunk is the spacer below: a padding that
                // changed when the next chunk arrived would lay this chunk out again.
                topPadding: (textArea.tightSeams && textArea.index > 0) ? 0 : padding
                bottomPadding: textArea.tightSeams ? 0 : padding

                width: chunkColumn.width
                readOnly: true
                selectByMouse: root.enableMouseSelection
                renderType: ScreenScale.renderTypeFor(Screen.name)
                font.family: Appearance.font.family.reading
                font.hintingPreference: Font.PreferNoHinting // Prevent weird bold text
                font.pixelSize: Appearance.font.pixelSize.small
                selectedTextColor: Appearance.m3colors.m3onSecondaryContainer
                selectionColor: Appearance.colors.colSecondaryContainer
                wrapMode: TextEdit.Wrap
                color: root.messageData?.thinking ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
                textFormat: root.renderMarkdown ? TextEdit.MarkdownText : TextEdit.PlainText

                // Assigned after creation and once the width is known: a text item
                // created with its text, or before its width, lays the text out twice.
                property bool created: false
                property bool hasText: false
                function applyChunk(): void {
                    if (!textArea.created || chunkColumn.width <= 0) return;
                    textArea.hasText = true;
                    textArea.text = textArea.chunk;
                }
                Component.onCompleted: {
                    textArea.created = true;
                    textArea.applyChunk();
                }
                onChunkChanged: textArea.applyChunk()
                onWidthChanged: if (!textArea.hasText) textArea.applyChunk()

                onLinkActivated: (link) => linkArea.activate(link)

                MessageLinkArea {
                    id: linkArea
                    textItem: textArea
                    selectable: root.enableMouseSelection
                }
            }
        }

        Item {
            width: chunkColumn.width
            height: (root.chunkMode === "blocks" && !root.editing && chunkRepeater.count > 0)
                ? (chunkRepeater.itemAt(chunkRepeater.count - 1)?.padding ?? 0) : 0
        }
    }

    Loader {
        id: editLoader
        Layout.fillWidth: true
        active: root.editing
        visible: active
        sourceComponent: StyledTextArea {
            id: editArea
            readOnly: false
            selectByMouse: true
            font.family: Appearance.font.family.reading
            font.hintingPreference: Font.PreferNoHinting // Prevent weird bold text
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: TextEdit.Wrap
            color: root.messageData?.thinking ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1
            textFormat: TextEdit.PlainText

            Component.onCompleted: editArea.text = root.segmentContent

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton // Only for hover
                cursorShape: Qt.IBeamCursor
            }
        }
    }
}
