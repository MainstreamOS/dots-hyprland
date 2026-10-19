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
        if (swipeView.contentItem && "cacheBuffer" in swipeView.contentItem) {
            swipeView.contentItem.cacheBuffer = 10000;
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
        if (SidebarLeftTabs.targetTab) {
            const targetIdx = wanted.findIndex(page => page.pageId === SidebarLeftTabs.targetTab);
            if (targetIdx !== -1) {
                root.showPage(targetIdx);
                SidebarLeftTabs.targetTab = "";
                warmupTimer.restart();
                return;
            }
        }
        const kept = (wasTab && !isTab) ? -1 : wanted.findIndex(page => page.pageId === root.currentPageId);
        // A page that is gone gives way to a tab near it, never to the
        // closeted page, which only a swipe is meant to reach.
        root.showPage(kept !== -1 ? kept : Math.max(0, Math.min(previousIndex, root.tabButtonList.length - 1)));
        warmupTimer.restart();
    }

    Timer {
        id: warmupTimer
        interval: 40
        repeat: true
        onTriggered: {
            for (let i = 0; i < swipeView.count; i++) {
                const page = swipeView.itemAt(i);
                // The closeted page is built when someone swipes to it.
                if (page && !page.built && !(page.pageId === "anime" && SidebarLeftTabs.animeCloset)) {
                    page.built = true;
                    return;
                }
            }
            for (let i = 0; i < swipeView.count; i++) {
                const page = swipeView.itemAt(i);
                if (page && page.built && !page.sgWarmed && page.item && page.width > 0 && page.height > 0 && GlobalStates.sidebarLeftOpen) {
                    page.sgWarmed = true;
                    page.item.grabToImage(() => {}, Qt.size(1, 1));
                    return;
                }
            }
            warmupTimer.stop();
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen) {
                if (SidebarLeftTabs.targetTab && root.showTab(SidebarLeftTabs.targetTab)) SidebarLeftTabs.targetTab = "";
                root.realign();
                warmupTimer.restart();
            }
        }
    }

    Connections {
        target: Phone
        function onConversationsLoadedChanged() {
            if (Phone.conversationsLoaded) {
                for (let i = 0; i < root.pagePool.length; i++) {
                    if (root.pagePool[i].pageId === "phone") {
                        root.pagePool[i].sgWarmed = false;
                    }
                }
                if (GlobalStates.sidebarLeftOpen) warmupTimer.restart();
            }
        }
    }

    // Keeps the current page aligned after a resize or a page change.
    function realign(): void {
        Qt.callLater(root.alignCurrentPage);
    }

    function alignCurrentPage(): void {
        const view = swipeView.contentItem;
        if (!view || swipeView.width <= 0 || swipeView.currentIndex < 0) return;
        // Reparenting a resized detached sidebar changes the page widths before
        // the ListView lays them out. Position against the new page geometry.
        view.cancelFlick();
        view.forceLayout();
        view.positionViewAtIndex(swipeView.currentIndex, ListView.Beginning);
    }

    function showPage(index) {
        if (index < 0 || index >= swipeView.count) return;
        const page = swipeView.itemAt(index);
        const arriving = root.currentPageId !== page.pageId;
        root.currentPageId = page.pageId;
        root.syncing = true;
        if (swipeView.currentIndex !== index) swipeView.setCurrentIndex(index);
        if (tabBar.currentIndex !== index) tabBar.setCurrentIndex(index);
        root.realign();
        root.syncing = false;
        // Focus goes to the page itself each time it comes on show, not to
        // whatever inside it last had it, so the page can pass it on to its
        // own text field.
        if (arriving && page.item) page.item.focus = true;
    }

    // False when the tab is not listed yet; the request then waits in targetTab for syncPages.
    function showTab(tabId) {
        const idx = root.tabButtonList.findIndex(t => t.id === tabId);
        if (idx !== -1) root.showPage(idx);
        return idx !== -1;
    }

    onParentChanged: root.realign()
    Component.onCompleted: root.syncPages()
    Connections {
        target: SidebarLeftTabs
        // Both change in one pass over the config; by the time the call
        // comes, each has settled.
        function onPageIdsChanged() { Qt.callLater(root.syncPages) }
        function onTabsChanged() { Qt.callLater(root.syncPages) }
        function onRequestTab(tabId) {
            if (root.showTab(tabId)) SidebarLeftTabs.targetTab = "";
        }
    }

    // A page is built in the background after startup and kept from then on,
    // so switching tabs never stutters to build a page mid-animation and one
    // already open keeps its state across tab switches.
    component PageLoader: Loader {
        id: pageLoader
        required property string pageId
        // Read from the page id rather than the swipe view, whose current
        // item passes through other pages while syncPages moves them.
        readonly property bool onScreen: GlobalStates.sidebarLeftOpen && root.currentPageId === pageLoader.pageId
        property bool built: false
        property bool sgWarmed: false
        onBuiltChanged: if (!pageLoader.built) pageLoader.sgWarmed = false
        onOnScreenChanged: if (pageLoader.onScreen) {
            pageLoader.built = true;
            pageLoader.sgWarmed = true;
        }
        active: pageLoader.built || pageLoader.onScreen
        // Handed over here and in showPage, never from the loader's own focus:
        // a page passing focus to its field sets the loader's focus again on
        // the way up, which would hand it straight back to the page.
        onLoaded: {
            if (pageLoader.onScreen) pageLoader.item.focus = true;
            else if (GlobalStates.sidebarLeftOpen) warmupTimer.restart();
        }
    }

    // One page for each id SidebarLeftTabs can ask for.
    property list<Item> pagePool: [
        PageLoader {
            id: aiPage
            pageId: "ai"
            sourceComponent: AiChat {
                scopeRoot: root.scopeRoot
                // Any lock screen covers the sidebar without closing it.
                onScreen: aiPage.onScreen && !GlobalStates.sessionLocked
            }
        },
        PageLoader {
            id: phonePage
            pageId: "phone"
            sourceComponent: PhoneTab {
                onScreen: phonePage.onScreen
            }
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

    // Only the chat listens, so only it has Hyprland asked about other lockers.
    Binding {
        target: GlobalStates
        property: "sessionLockWatched"
        value: true
        when: aiPage.onScreen
    }

    // The sidebar's own shortcuts, handled once here for every page.
    Keys.onPressed: (event) => {
        if (event.modifiers !== Qt.ControlModifier)
            return;
        switch (event.key) {
        case Qt.Key_PageDown:
            swipeView.incrementCurrentIndex();
            break;
        case Qt.Key_PageUp:
            swipeView.decrementCurrentIndex();
            break;
        case Qt.Key_D:
            root.scopeRoot.toggleDetach();
            break;
        case Qt.Key_O:
            root.scopeRoot.toggleExtend();
            break;
        case Qt.Key_P:
            root.scopeRoot.togglePin();
            break;
        default:
            return;
        }
        event.accepted = true;
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
                onWidthChanged: {
                    if (width > 0) root.realign();
                }

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
                            Session.openSettings("InterfaceConfig.qml", "leftSidebarSection");
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
