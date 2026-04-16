pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Emojis.
 */
Singleton {
    id: root
    property string emojiScriptPath: `${Directories.config}/hypr/hyprland/scripts/fuzzel-emoji.sh`
	property string lineBeforeData: "### DATA ###"
    property list<var> list
    readonly property var preparedEntries: list.map(a => ({
        name: Fuzzy.prepare(`${a}`),
        entry: a
    }))

    // Frequency tracking: { "😀": 5, "🔥": 3, ... }
    property var frequencyMap: ({})
    // Recent usage: ["🔥", "😀", ...] most-recent first, max 8
    property list<string> recentList: []
    property int maxRecent: 8

    // Last 8 recently used emojis as full entry strings
    readonly property list<var> recentEmojis: {
        const recents = root.recentList;
        if (recents.length === 0) return [];
        return recents.map(emoji => {
            return root.list.find(line => line.match(/^\s*(\S+)/)?.[1] === emoji);
        }).filter(Boolean);
    }

    function recordUsage(emoji: string) {
        // Update frequency
        const map = root.frequencyMap;
        map[emoji] = (map[emoji] || 0) + 1;
        root.frequencyMap = map;

        // Update recency — move to front, cap at maxRecent
        let recents = root.recentList.filter(e => e !== emoji);
        recents.unshift(emoji);
        if (recents.length > root.maxRecent)
            recents = recents.slice(0, root.maxRecent);
        root.recentList = recents;

        _save();
    }

    function _save() {
        frequencyFileView.setText(JSON.stringify({
            frequency: root.frequencyMap,
            recent: root.recentList
        }));
    }

    function fuzzyQuery(search: string): var {
        if (root.sloppySearch) {
            const results = entries.slice(0, 100).map(str => ({
                entry: str,
                score: Levendist.computeTextMatchScore(str.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        return Fuzzy.go(search, preparedEntries, {
            all: true,
            key: "name"
        }).map(r => r.obj.entry);
    }

    function load() {
        emojiFileView.reload()
    }

    function updateEmojis(fileContent) {
        const lines = fileContent.split("\n")
        const dataIndex = lines.indexOf(root.lineBeforeData)
        if (dataIndex === -1) {
            console.warn("No data section found in emoji script file.")
            return
        }
        const emojis = lines.slice(dataIndex + 1).filter(line => line.trim() !== "")
        root.list = emojis.map(line => line.trim())
    }

    Component.onCompleted: {
        frequencyFileView.reload()
    }

    FileView {
        id: emojiFileView
        path: Qt.resolvedUrl(root.emojiScriptPath)
        onLoadedChanged: {
            const fileContent = emojiFileView.text()
            root.updateEmojis(fileContent)
        }
    }

    FileView {
        id: frequencyFileView
        path: Qt.resolvedUrl(Directories.emojiFrequencyPath)
        onLoaded: {
            const content = frequencyFileView.text();
            try {
                const data = JSON.parse(content);
                // Support both old format (plain map) and new format ({ frequency, recent })
                if (data && typeof data.frequency === "object") {
                    root.frequencyMap = data.frequency;
                    root.recentList = data.recent || [];
                } else if (data && typeof data === "object") {
                    // Old format: plain frequency map
                    root.frequencyMap = data;
                    root.recentList = [];
                }
            } catch (e) {
                root.frequencyMap = {};
                root.recentList = [];
            }
        }
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                root.frequencyMap = {};
                root.recentList = [];
                root._save();
            }
        }
    }
}
