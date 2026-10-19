pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.overview

Item {
    id: root
    property alias searchInput: searchBar.searchInput
    property bool active: true
    property bool searchRequested: false
    readonly property bool busy: searchRequested
    readonly property bool needsKeyboardFocus: busy
    readonly property var entries: active ? LauncherSearch.results.filter(entry => entry.shown && !entry.isSeparator
        && (searchInput.text.length > 0 || entry.id)) : []
    readonly property string cleanQuery: StringUtils.cleanOnePrefix(searchInput.text, [Config.options.search.prefix.action,
        Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis,
        Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch])
    signal dismissed()
    implicitHeight: searchBar.implicitHeight + 8 + Math.min(208, Math.max(40, results.contentHeight + 8))

    function updateQuery(): void {
        if (active) LauncherSearch.query = searchInput.text || Config.options.search.prefix.app;
    }

    function focusSearch(): void {
        if (active) searchInput.forceActiveFocus();
    }

    function selectResult(delta): void {
        if (!results.count) return;
        results.currentIndex = Math.max(0, Math.min(results.count - 1, results.currentIndex + delta));
        results.positionViewAtIndex(results.currentIndex, ListView.Contain);
    }

    onActiveChanged: if (active) updateQuery()
    function resetSelection(): void {
        results.currentIndex = entries.length ? 0 : -1;
        results.positionViewAtBeginning();
    }

    onEntriesChanged: Qt.callLater(root.resetSelection)
    Component.onCompleted: {
        updateQuery();
        if (searchRequested) Qt.callLater(root.focusSearch);
    }

    Keys.onEscapePressed: event => {
        root.dismissed();
        event.accepted = true;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        SearchBar {
            id: searchBar
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 48
            Layout.leftMargin: 10
            Layout.rightMargin: 4
            searchingText: root.searchInput.text
            inputFocused: root.searchRequested
            fillSearchWidth: true
            synchronizeQuery: false
            completeFirstResult: false
            dismiss: () => root.dismissed()
            onAccepted: {
                const item = results.itemAtIndex(results.currentIndex);
                if (item) item.clicked();
            }
            onKeyPressed: event => {
                if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                    root.selectResult(event.key === Qt.Key_Down ? 1 : -1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab && results.currentIndex >= 0) {
                    root.searchInput.text = root.entries[results.currentIndex].name;
                    root.searchInput.cursorPosition = root.searchInput.text.length;
                    event.accepted = true;
                }
            }
            Connections {
                target: root.searchInput
                function onTextChanged() { root.updateQuery(); }
            }
        }

        ListView {
            id: results
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            topMargin: 4
            bottomMargin: 4
            spacing: 2
            model: ScriptModel { values: root.entries }
            boundsBehavior: Flickable.StopAtBounds
            delegate: SearchItem {
                required property var modelData
                required property int index
                width: results.width
                horizontalMargin: 0
                entry: modelData
                query: root.cleanQuery
                keyboardSelected: ListView.isCurrentItem
                dismiss: () => root.dismissed()
            }

            StyledText {
                anchors.centerIn: parent
                visible: !results.count
                text: Translation.tr("No results")
                color: Appearance.colors.colSubtext
            }
        }
    }
}
