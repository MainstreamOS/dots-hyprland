import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent
    property bool animeCloset: SidebarLeftTabs.animeCloset
    // Handed over by syncPages rather than bound, so the strip is rebuilt in
    // the same step as the pages and never points at a page that moved.
    property var tabButtonList: []
    property int tabCount: swipeView.count

    // The page on show, by id: turning another tab on or off moves pages
    // around, and this one stays on show wherever it lands.
    property string currentPageId: ""
    property bool syncing: false

    function focusActiveItem() {
        swipeView.currentItem.forceActiveFocus()
    }

    function pageIndex(page) {
        for (let i = 0; i < swipeView.count; i++) {
            if (swipeView.itemAt(i) === page) return i;
        }
        return -1;
    }

    // Puts the pages SidebarLeftTabs asks for into the swipe view, in its
    // order, keeping the ones already there rather than building them again.
    function syncPages() {
        const pages = {};
        for (let i = 0; i < root.pagePool.length; i++)
            pages[root.pagePool[i].pageId] = root.pagePool[i];
        const wanted = SidebarLeftTabs.pageIds.map(id => pages[id]).filter(page => page !== undefined);
        const previousIndex = swipeView.currentIndex;
        root.syncing = true;
        for (let i = swipeView.count - 1; i >= 0; i--) {
            if (wanted.indexOf(swipeView.itemAt(i)) === -1) swipeView.takeItem(i);
        }
        // A tab turned off lets go of its page, and whatever that page held (art,
        // images, a chat), until it is turned on and shown again.
        for (const page of root.pagePool) {
            if (wanted.indexOf(page) === -1) page.built = false;
        }
        for (let i = 0; i < wanted.length; i++) {
            const at = root.pageIndex(wanted[i]);
            if (at === -1) swipeView.insertItem(i, wanted[i]);
            else if (at !== i) swipeView.moveItem(at, i);
        }
        // The swipe view only takes these changes in at its next layout, and
        // doing so shifts its current index, which would carry it off the
        // page picked below to wherever the old one's neighbor ended up.
        swipeView.contentItem.forceLayout();
        // A page that was a tab and is one no longer, such as Anime put in the
        // closet while on show, is not kept on show: it has no tab to leave by.
        const wasTab = root.tabButtonList.some(tab => tab.id === root.currentPageId);
        const isTab = SidebarLeftTabs.tabs.some(tab => tab.id === root.currentPageId);
        root.tabButtonList = SidebarLeftTabs.tabs;
        root.syncing = false;
        const kept = (wasTab && !isTab) ? -1 : wanted.findIndex(page => page.pageId === root.currentPageId);
        // A page that is gone gives way to a tab near it, never to the
        // closeted page, which only a swipe is meant to reach.
        root.showPage(kept !== -1 ? kept : Math.max(0, Math.min(previousIndex, root.tabButtonList.length - 1)));
    }

    function showPage(index) {
        if (index < 0 || index >= swipeView.count) return;
        root.currentPageId = swipeView.itemAt(index).pageId;
        root.syncing = true;
        if (swipeView.currentIndex !== index) swipeView.setCurrentIndex(index);
        if (tabBar.currentIndex !== index) tabBar.setCurrentIndex(index);
        root.syncing = false;
    }

    Component.onCompleted: root.syncPages()
    Connections {
        target: SidebarLeftTabs
        // Both change in one pass over the config; by the time the call
        // comes, each has settled.
        function onPageIdsChanged() { Qt.callLater(root.syncPages) }
        function onTabsChanged() { Qt.callLater(root.syncPages) }
    }

    // A page is built the first time it is on screen and kept from then on,
    // so a tab nobody opens costs nothing and one already open keeps its
    // state across tab switches.
    component PageLoader: Loader {
        id: pageLoader
        required property string pageId
        // Read from the page id rather than the swipe view, whose current
        // item passes through other pages while syncPages moves them.
        readonly property bool onScreen: GlobalStates.sidebarLeftOpen && root.currentPageId === pageLoader.pageId
        property bool built: false
        onOnScreenChanged: if (pageLoader.onScreen) pageLoader.built = true
        active: pageLoader.built || pageLoader.onScreen
        // The swipe view gives focus to the loader of the page it shows. It
        // goes to the page itself each time, not to whatever inside the page
        // last had it, so the page can pass it on to its own text field.
        onLoaded: pageLoader.item.focus = true
        onFocusChanged: if (pageLoader.focus && pageLoader.item) pageLoader.item.focus = true
    }

    // One page for each id SidebarLeftTabs can ask for.
    property list<Item> pagePool: [
        PageLoader {
            pageId: "ai"
            sourceComponent: AiChat {}
        },
        PageLoader {
            pageId: "translator"
            sourceComponent: Translator {}
        },
        PageLoader {
            id: mediaPage
            pageId: "media"
            sourceComponent: SidebarMediaPlayer {
                // The lock screen covers the sidebar without closing it.
                shown: mediaPage.onScreen && !GlobalStates.screenLocked
            }
        },
        PageLoader {
            pageId: "anime"
            sourceComponent: Anime {}
        },
        PageLoader {
            pageId: "placeholder"
            sourceComponent: placeholder
        }
    ]

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                swipeView.incrementCurrentIndex()
                event.accepted = true;
            }
            else if (event.key === Qt.Key_PageUp) {
                swipeView.decrementCurrentIndex()
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors {
            fill: parent
            margins: sidebarPadding
        }
        spacing: sidebarPadding

        Toolbar {
            id: tabToolbar
            visible: tabButtonList.length > 0
            Layout.alignment: Qt.AlignHCenter
            enableShadow: false
            ToolbarTabBar {
                id: tabBar
                Layout.alignment: Qt.AlignHCenter
                tabButtonList: root.tabButtonList
                availableWidth: contentColumn.width - tabToolbar.padding * 2
                onCurrentIndexChanged: if (!root.syncing) root.showPage(tabBar.currentIndex)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitWidth: swipeView.implicitWidth
            implicitHeight: swipeView.implicitHeight
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            SwipeView { // Content pages
                id: swipeView
                anchors.fill: parent
                spacing: 10
                onCurrentIndexChanged: if (!root.syncing) root.showPage(swipeView.currentIndex)

                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.small
                    }
                }
            }
        }

        Component {
            id: placeholder
            Item {
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 40
                    spacing: 4
                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: root.animeCloset ? Translation.tr("Nothing") : Translation.tr("Your sidebar is empty")
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        visible: !root.animeCloset
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: Translation.tr("Add tabs from Settings → Interface → Left Sidebar")
                        color: Appearance.colors.colSubtext
                        opacity: 0.8
                    }
                    Item { width: 1; height: 8 }
                    GroupButton {
                        visible: !root.animeCloset
                        anchors.horizontalCenter: parent.horizontalCenter
                        baseWidth: contentItem.implicitWidth + 30
                        baseHeight: 34
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        onClicked: {
                            Quickshell.execDetached(["sh", "-c", "QS_SETTINGS_PAGE=InterfaceConfig.qml QS_SETTINGS_SECTION=leftSidebarSection quickshell -p '" + StringUtils.shellSingleQuoteEscape(Directories.settingsAppPath) + "'"]);
                            GlobalStates.sidebarLeftOpen = false;
                        }
                        contentItem: StyledText {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: Translation.tr("Open Interface settings")
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }
    }
}
