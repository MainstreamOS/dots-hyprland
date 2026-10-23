pragma ComponentBehavior: Bound

import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item { // Wrapper
    id: root

    readonly property string xdgConfigHome: Directories.config
    readonly property int typingDebounceInterval: 200
    readonly property int typingResultLimit: 15 // Should be enough to cover the whole view

    // Exposed so the panel-level wheelOverlay (Overview.qml) can route wheel
    // events into the result list instead of scrolling the outer Flickable.
    property alias appResults: appResults
    property real maximumResultsHeight: 600
    property bool quietStyle: false
    property real uiScale: 1
    property var contentColors: Appearance.launcherPanelContent
    readonly property real collapsedHeight: searchBar.height + searchBar.verticalPadding * 4 + Appearance.sizes.elevationMargin * root.uiScale * 2
    signal navigationKeyPressed(var event)

    property string searchingText: LauncherSearch.query
    property bool showResults: searchingText != ""
    implicitWidth: searchWidgetContent.implicitWidth + Appearance.sizes.elevationMargin * root.uiScale * 2
    implicitHeight: searchWidgetContent.implicitHeight + searchBar.verticalPadding * 2 + Appearance.sizes.elevationMargin * root.uiScale * 2

    function focusFirstItem() {
        appResults.currentIndex = 0;
    }

    function focusSearchInput() {
        searchBar.forceFocus();
    }

    function disableExpandAnimation() {
        searchBar.animateWidth = false;
    }

    function cancelSearch() {
        searchBar.searchInput.selectAll();
        LauncherSearch.query = "";
        searchBar.animateWidth = true;
    }

    function setSearchingText(text) {
        searchBar.searchInput.text = text;
        LauncherSearch.query = text;
    }

    Keys.onPressed: event => {
        // Prevent Esc and Backspace from registering
        if (event.key === Qt.Key_Escape)
            return;

        // Handle Backspace: focus and delete character if not focused
        if (event.key === Qt.Key_Backspace) {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                if (event.modifiers & Qt.ControlModifier) {
                    // Delete word before cursor
                    let text = searchBar.searchInput.text;
                    let pos = searchBar.searchInput.cursorPosition;
                    if (pos > 0) {
                        // Find the start of the previous word
                        let left = text.slice(0, pos);
                        let match = left.match(/(\s*\S+)\s*$/);
                        let deleteLen = match ? match[0].length : 1;
                        searchBar.searchInput.text = text.slice(0, pos - deleteLen) + text.slice(pos);
                        searchBar.searchInput.cursorPosition = pos - deleteLen;
                    }
                } else {
                    // Delete character before cursor if any
                    if (searchBar.searchInput.cursorPosition > 0) {
                        searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition - 1) + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                        searchBar.searchInput.cursorPosition -= 1;
                    }
                }
                // Always move cursor to end after programmatic edit
                searchBar.searchInput.cursorPosition = searchBar.searchInput.text.length;
                event.accepted = true;
            }
            // If already focused, let TextField handle it
            return;
        }

        // Only handle visible printable characters (ignore control chars, arrows, etc.)
        if (event.text && event.text.length === 1 && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Return && event.key !== Qt.Key_Delete && event.text.charCodeAt(0) >= 0x20) // ignore control chars like Backspace, Tab, etc.
        {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                // Insert the character at the cursor position
                searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition) + event.text + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                searchBar.searchInput.cursorPosition += 1;
                event.accepted = true;
                root.focusFirstItem();
            }
        }
    }

    StyledRectangularShadow {
        target: searchWidgetContent
        blur: 0.9 * Appearance.sizes.elevationMargin * root.uiScale
        offset: Qt.vector2d(0, root.uiScale)
        spread: root.uiScale
        color: Appearance.colors.colLauncherShadow
    }
    LauncherSearchSurface { // Background
        id: searchWidgetContent
        uiScale: root.uiScale
        searchHeight: searchBar.height
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: Appearance.sizes.elevationMargin * root.uiScale
        }
        clip: true
        implicitWidth: root.quietStyle ? searchBar.preferredWidth + 14 * root.uiScale : columnLayout.implicitWidth
        implicitHeight: columnLayout.implicitHeight
        Behavior on implicitHeight {
            id: searchHeightBehavior
            enabled: GlobalStates.overviewOpen && root.showResults
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            id: columnLayout
            width: root.quietStyle ? searchWidgetContent.width : implicitWidth
            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
            }
            spacing: 0

            // clip: true
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: searchWidgetContent.width
                    height: searchWidgetContent.width
                    radius: searchWidgetContent.radius
                }
            }

            SearchBar {
                id: searchBar
                quietStyle: root.quietStyle
                fillSearchWidth: root.quietStyle
                uiScale: root.uiScale
                contentColors: root.contentColors
                property real verticalPadding: 4 * root.uiScale
                Layout.fillWidth: true
                Layout.minimumHeight: root.quietStyle ? 48 * root.uiScale : 0
                Layout.maximumHeight: root.quietStyle ? 48 * root.uiScale : Infinity
                Layout.leftMargin: 10 * root.uiScale
                Layout.rightMargin: 4 * root.uiScale
                Layout.topMargin: verticalPadding
                Layout.bottomMargin: verticalPadding
                Synchronizer on searchingText {
                    property alias source: root.searchingText
                }
                onKeyPressed: event => root.navigationKeyPressed(event)
                onAccepted: {
                    const item = appResults.itemAtIndex(0);
                    if (item) item.clicked();
                }
            }

            Rectangle {
                // Separator
                visible: root.showResults
                Layout.fillWidth: true
                height: root.uiScale
                color: root.contentColors.colOutlineVariant
            }

            ListView { // App results
                id: appResults
                visible: root.showResults
                Layout.fillWidth: true
                implicitHeight: Math.min(root.maximumResultsHeight, appResults.contentHeight + topMargin + bottomMargin)
                clip: true
                topMargin: 10 * root.uiScale
                bottomMargin: 10 * root.uiScale
                spacing: 2 * root.uiScale
                KeyNavigation.up: searchBar
                highlightMoveDuration: 100

                onFocusChanged: {
                    if (focus)
                        appResults.currentIndex = 1;
                }

                Connections {
                    target: root
                    function onSearchingTextChanged() {
                        if (appResults.count > 0)
                            appResults.currentIndex = 0;
                    }
                }

                Timer {
                    id: debounceTimer
                    interval: root.typingDebounceInterval
                    onTriggered: {
                        resultModel.values = LauncherSearch.results ?? [];
                    }
                }

                Connections {
                    target: LauncherSearch
                    function onResultsChanged() {
                        resultModel.values = LauncherSearch.results.slice(0, root.typingResultLimit);
                        root.focusFirstItem();
                        debounceTimer.restart();
                    }
                }

                model: ScriptModel {
                    id: resultModel
                    objectProp: "key"
                }

                delegate: SearchItem {
                    id: searchItem
                    uiScale: root.uiScale
                    contentColors: root.contentColors
                    // The selectable item for each search result
                    required property var modelData
                    anchors.left: parent?.left
                    anchors.right: parent?.right
                    entry: modelData
                    query: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch])

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab) {
                            if (LauncherSearch.results.length === 0)
                                return;
                            const tabbedText = searchItem.modelData.name;
                            LauncherSearch.query = tabbedText;
                            searchBar.searchInput.text = tabbedText;
                            event.accepted = true;
                            root.focusSearchInput();
                        }
                    }
                }
            }
        }
    }
}
