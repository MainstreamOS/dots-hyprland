pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.aiChat
import qs.services

Item {
    id: root

    signal emojiChosen(string emoji)
    signal closed()

    property string query: ""
    readonly property int columns: Math.max(1, Math.floor(emojiGrid.width / 40))
    readonly property var entries: Emojis.list.map(entry => root.parseEntry(entry))
    readonly property var results: root.query.trim().length > 0
        ? Emojis.fuzzyQuery(root.query.trim()).map(entry => root.parseEntry(entry)) : root.entries
    readonly property var frequent: {
        const counts = Emojis.frequencyMap;
        return root.entries.filter(entry => (counts[entry.emoji] || 0) > 0)
            .sort((a, b) => (counts[b.emoji] - counts[a.emoji])
                || Emojis.recentList.indexOf(a.emoji) - Emojis.recentList.indexOf(b.emoji))
            .slice(0, 16);
    }

    function parseEntry(entry): var {
        const text = String(entry);
        return {emoji: text.match(/^\s*(\S+)/)?.[1] || "", description: text.replace(/^\s*\S+\s*/, "")};
    }

    function choose(emoji: string): void {
        Emojis.recordUsage(emoji);
        root.emojiChosen(emoji);
    }

    Component.onCompleted: if (Emojis.list.length === 0) Emojis.load()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        SheetSearchField {
            id: search
            Layout.fillWidth: true
            implicitHeight: 34
            placeholder: Translation.tr("Search emojis...")
            clearable: true
            onTextChanged: searchDebounce.restart()
            onFieldKeyPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.closed();
                    event.accepted = true;
                }
            }
        }
        Timer {
            id: searchDebounce
            interval: 100
            onTriggered: {
                root.query = search.text;
                emojiGrid.positionViewAtBeginning();
            }
        }

        StyledText {
            visible: root.query.trim().length === 0 && root.frequent.length > 0
            text: Translation.tr("Frequently used")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
        Grid {
            Layout.fillWidth: true
            visible: root.query.trim().length === 0 && root.frequent.length > 0
            columns: root.columns
            Repeater {
                model: root.frequent
                delegate: PhoneEmojiButton {
                    width: emojiGrid.cellWidth
                    height: emojiGrid.cellHeight
                    onChosen: emoji => root.choose(emoji)
                }
            }
        }

        GridView {
            id: emojiGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: width / root.columns
            cellHeight: 40
            model: root.results
            ScrollBar.vertical: StyledScrollBar {}
            delegate: PhoneEmojiButton {
                width: emojiGrid.cellWidth
                height: emojiGrid.cellHeight
                onChosen: emoji => root.choose(emoji)
            }

            StyledText {
                anchors.centerIn: parent
                visible: root.query.trim().length > 0 && root.results.length === 0
                text: Translation.tr("No emojis found")
                color: Appearance.colors.colSubtext
            }
        }
    }
}
