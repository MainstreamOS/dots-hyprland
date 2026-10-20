pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    readonly property var pending: Ai.pendingConfirmation ?? null
    readonly property bool shown: root.pending !== null
    // Holds the last confirmation so the card keeps its content while it collapses.
    property var conf: null

    // Approval runs or grants all of this, so the preview shows every character.
    readonly property string previewSource: [root.conf?.command ?? "", root.conf?.target ?? ""].filter(s => s.length > 0).join("\n")
    readonly property int previewLineCount: root.previewSource.split("\n").length
    // Laid out a few thousand lines, or a stretch of one long line, per frame,
    // so a huge command never stalls the shell. Where the next part starts in
    // previewSource, negative once all of it is in.
    property int previewNext: -1
    // The rest of a spelled-out character a part ended inside of, shown first in the next part.
    property string previewCarry: ""
    // A long line split between parts depends on the width it was split for.
    property bool previewSplitsLines: false
    readonly property bool previewBuilt: root.previewNext < 0
    readonly property string grantNote: root.conf?.grantNote ?? ""

    onPendingChanged: {
        if (root.pending)
            root.conf = root.pending;
    }
    Component.onCompleted: root.conf = root.pending
    onPreviewSourceChanged: root.buildPreview()

    // Controls and invisible or reordering characters are spelled out so nothing hides or disguises a part.
    function hiddenCharacters() {
        return /[\x00-\x08\x0B-\x1F\x7F-\x9F\u061C\u200B-\u200F\u2028-\u202E\u2060-\u2064\u2066-\u2069\uFEFF\u{E0000}-\u{E007F}]/gu;
    }
    function spelling(c) {
        return `<U+${c.codePointAt(0).toString(16).toUpperCase().padStart(4, "0")}>`;
    }
    function spelledOut(text) {
        return text.replace(root.hiddenCharacters(), root.spelling);
    }

    function buildPreview() {
        root.previewNext = 0;
        root.previewCarry = "";
        root.previewSplitsLines = false;
        root.addPreviewChunk(0);
        if (previewChunkModel.count > 1)
            previewChunkModel.remove(1, previewChunkModel.count - 1);
        previewFlickable.contentY = 0;
        previewBuilder.restart();
    }

    // A part runs to a line end, up to 2048 lines or 16 KB. A line over 8 KB
    // gets parts of its own, split where a row starts so the wrapping stays.
    // Sizes count the spelled-out text, which is spelled out only as far as a
    // part reaches, since it can be ten times as long.
    function addPreviewChunk(index) {
        const text = root.previewSource;
        let lineStart = root.previewNext;
        let carry = root.previewCarry;
        let lines = 0;
        let chunk = "";
        root.previewCarry = "";
        while (true) {
            const newline = text.indexOf("\n", lineStart);
            const lineEnd = newline < 0 ? text.length : newline;
            let shown = carry;
            let end = lineStart;
            while (end < lineEnd && shown.length <= 8192) {
                let stop = Math.min(lineEnd, end + 1024);
                const last = text.charCodeAt(stop - 1);
                if (stop < lineEnd && last >= 0xD800 && last < 0xDC00)
                    stop++;
                shown += root.spelledOut(text.slice(end, stop));
                end = stop;
            }
            if (shown.length > 8192) {
                if (lines > 0) {
                    root.previewNext = lineStart;
                } else {
                    chunk = root.wholeRows(shown.substr(0, 8192));
                    root.skipShown(text.slice(lineStart, end), lineStart, carry, chunk.length);
                    root.previewSplitsLines = true;
                }
                break;
            }
            chunk += lines > 0 ? "\n" + shown : shown;
            carry = "";
            lines++;
            if (newline < 0) {
                root.previewNext = -1;
                break;
            }
            lineStart = newline + 1;
            if (lines >= 2048 || chunk.length + 1 >= 16384) {
                root.previewNext = lineStart;
                break;
            }
        }
        if (index < previewChunkModel.count)
            previewChunkModel.set(index, { "chunk": chunk });
        else
            previewChunkModel.append({ "chunk": chunk });
    }

    // Moves the next part's start past count characters of carry plus the
    // spelled-out stretch from start, keeping the rest of a character cut through.
    function skipShown(stretch, start, carry, count) {
        if (count < carry.length) {
            root.previewNext = start;
            root.previewCarry = carry.slice(count);
            return;
        }
        count -= carry.length;
        const hidden = root.hiddenCharacters();
        let at = 0;
        while (true) {
            const match = hidden.exec(stretch);
            if (!match || count <= match.index - at) {
                root.previewNext = start + at + count;
                return;
            }
            count -= match.index - at;
            at = match.index + match[0].length;
            const spelled = root.spelling(match[0]);
            if (count < spelled.length) {
                root.previewNext = start + at;
                root.previewCarry = spelled.slice(count);
                return;
            }
            count -= spelled.length;
        }
    }

    // Drops the last row of a stretch of one line, as the preview would wrap it.
    function wholeRows(part) {
        previewMeasure.text = part;
        const lastRowY = previewMeasure.positionToRectangle(part.length).y;
        let low = 0;
        let high = part.length;
        while (low < high) {
            const mid = (low + high) >> 1;
            if (previewMeasure.positionToRectangle(mid).y < lastRowY - 0.5)
                low = mid + 1;
            else
                high = mid;
        }
        previewMeasure.text = "";
        if (low > 0)
            return part.slice(0, low);
        return /[\uD800-\uDBFF]$/.test(part) ? part.slice(0, -1) : part;
    }

    ListModel {
        id: previewChunkModel
    }

    Timer {
        id: previewBuilder
        interval: 16
        repeat: true
        onTriggered: {
            if (root.previewNext < 0) {
                stop();
                return;
            }
            root.addPreviewChunk(previewChunkModel.count);
        }
    }

    visible: implicitHeight > 0
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    border.width: 1
    border.color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.4)
    implicitHeight: root.shown ? (mainCol.implicitHeight + 20) : 0
    opacity: root.shown ? 1 : 0
    clip: true

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    ColumnLayout {
        id: mainCol
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 10
        }
        spacing: 8

        // Header Row
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: "shield"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colPrimary
            }

            ColumnLayout {
                spacing: 1
                Layout.fillWidth: true

                StyledText {
                    text: Translation.tr("Permission Required")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Translation.tr("%1 requires approval to continue").arg(root.conf?.action || Translation.tr("Action"))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // Command and target preview, capped at six lines
        Rectangle {
            Layout.fillWidth: true
            visible: root.previewSource.length > 0
            radius: Appearance.rounding.small
            color: Appearance.colors.colSurfaceContainerHighest
            implicitHeight: previewFlickable.height + 12
            clip: true

            StyledFlickable {
                id: previewFlickable
                property Text firstChunk: null
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: 8
                }
                height: {
                    const first = previewFlickable.firstChunk;
                    if (!first)
                        return 0;
                    return Math.min(previewColumn.implicitHeight, Math.ceil(first.implicitHeight * 6 / Math.max(1, first.lineCount)));
                }
                contentWidth: width
                contentHeight: previewColumn.implicitHeight
                interactive: contentHeight > height
                clip: true
                onWidthChanged: {
                    if (root.previewSplitsLines)
                        Qt.callLater(root.buildPreview);
                }

                Column {
                    id: previewColumn
                    width: previewFlickable.width

                    Repeater {
                        model: previewChunkModel
                        onItemAdded: (index, item) => {
                            if (index === 0)
                                previewFlickable.firstChunk = item;
                        }
                        onItemRemoved: (index, item) => {
                            if (item === previewFlickable.firstChunk)
                                previewFlickable.firstChunk = null;
                        }

                        delegate: StyledText {
                            id: chunkText
                            required property string chunk
                            width: previewFlickable.width
                            text: chunkText.chunk
                            textFormat: Text.PlainText
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            // Fixed so a part of only digits wraps like previewMeasure.
                            font.variableAxes: Appearance.font.variableAxes.main
                            wrapMode: Text.WrapAnywhere
                            color: Appearance.m3colors.m3onSurface
                        }
                    }
                }
            }

            // Wraps exactly as a preview part does, for finding where its rows start.
            TextEdit {
                id: previewMeasure
                visible: false
                readOnly: true
                width: previewFlickable.width
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.WrapAnywhere
                renderType: Text.NativeRendering
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.hintingPreference: Font.PreferDefaultHinting
                font.variableAxes: Appearance.font.variableAxes.main
            }
        }

        // The preview scrolls, so say how much there is to read
        StyledText {
            Layout.fillWidth: true
            visible: root.previewSource.length > 0 && previewFlickable.interactive
            text: root.previewLineCount > 1
                ? Translation.tr("Scroll to read all %1 lines (%2 characters)").arg(root.previewLineCount).arg(root.previewSource.length)
                : Translation.tr("Scroll to read all %1 characters").arg(root.previewSource.length)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colPrimary
            wrapMode: Text.WordWrap
        }

        // What an approval allows beyond the preview
        StyledText {
            Layout.fillWidth: true
            visible: root.grantNote.length > 0
            text: root.grantNote
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }

        // Action Buttons Row
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item { Layout.fillWidth: true }

            RippleButton {
                id: rejectBtn
                implicitHeight: 32
                buttonRadius: Appearance.rounding.small
                horizontalPadding: 12
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover

                contentItem: RowLayout {
                    spacing: 6
                    anchors.centerIn: parent

                    MaterialSymbol {
                        text: "close"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        text: Translation.tr("Reject")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }

                onClicked: {
                    if (root.shown)
                        Ai.rejectPendingAction(root.conf?.id);
                }
            }

            RippleButton {
                id: approveBtn
                // An approval covers only what the preview has shown.
                enabled: root.previewBuilt
                implicitHeight: 32
                buttonRadius: Appearance.rounding.small
                horizontalPadding: 12
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover

                contentItem: RowLayout {
                    spacing: 6
                    anchors.centerIn: parent

                    MaterialSymbol {
                        text: "check"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnPrimary
                    }

                    StyledText {
                        text: Translation.tr("Approve & Run")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnPrimary
                    }
                }

                onClicked: {
                    if (root.shown && root.previewBuilt)
                        Ai.approvePendingAction(root.conf?.id);
                }
            }
        }
    }
}
