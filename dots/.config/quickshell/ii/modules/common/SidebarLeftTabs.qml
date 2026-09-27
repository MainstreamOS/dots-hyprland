pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services

// The left sidebar's tabs, in the order its tab strip shows them. The
// sidebar, its bar button and the bar's slot for that button all read this,
// so they cannot disagree about whether there is anything to open. A new tab
// is an entry here and a page for its id in SidebarLeftContent.
Singleton {
    id: root

    readonly property var definitions: [
        { id: "ai", icon: "neurology", name: Translation.tr("Intelligence"), enabled: Config.options.policies.ai !== 0 },
        { id: "media", icon: "music_note", name: Translation.tr("Media"), enabled: Config.options.sidebar.media.enable },
        { id: "translator", icon: "translate", name: Translation.tr("Translator"), enabled: Config.options.sidebar.translator.enable },
        { id: "anime", icon: "bookmark_heart", name: Translation.tr("Anime"), enabled: Config.options.policies.weeb !== 0 }
    ]

    // Kept in the closet, the anime page is there to be swiped to but has no
    // button of its own.
    readonly property bool animeCloset: Config.options.policies.weeb === 2

    readonly property var tabs: root.definitions.filter(tab => tab.enabled && !(tab.id === "anime" && root.animeCloset))

    // Pages in swipe order: one per tab, a placeholder when there are no
    // tabs at all, and last the closeted anime page.
    readonly property list<string> pageIds: [
        ...root.tabs.map(tab => tab.id),
        ...(root.tabs.length === 0 ? ["placeholder"] : []),
        ...(root.animeCloset ? ["anime"] : [])
    ]

    readonly property bool hasPages: root.definitions.some(tab => tab.enabled)

    // The bar button's stock icon is the logo of the AI model picked in the
    // sidebar, so with AI off it has nothing to show and stays off the bar. A
    // distro or custom icon still shows whenever there is a page to open.
    readonly property bool buttonShown: root.hasPages
        && (Config.options.bar.topLeftIcon !== "spark" || root.tabs.some(tab => tab.id === "ai"))
}
