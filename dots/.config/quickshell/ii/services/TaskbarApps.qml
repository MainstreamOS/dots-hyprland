pragma Singleton

import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Wayland

Singleton {
    id: root

    // ── App-id resolution ─────────────────────────────────────────
    // Every Quickshell ApplicationWindow reports the same wayland
    // app_id ("org.quickshell") because Qt's setDesktopFileName is
    // global with no per-window override. Use the window title to map
    // those toplevels to canonical ids so each qs app gets its own
    // dock entry and its own icon — otherwise they all merge into one
    // "org.quickshell" group and the icon flips to whichever toplevel
    // happens to be at index 0. Translation.tr() is used on both
    // sides so non-English locales keep matching.
    function resolveAppId(toplevel) {
        if (toplevel.appId !== "org.quickshell") return toplevel.appId;
        const title = toplevel.title || "";
        if (title === Translation.tr("Mainstream Settings")) return "settings";
        if (title === Translation.tr("Welcome to Mainstream")) return "welcome-tutorial";
        return toplevel.appId;
    }

    // One-time migration: previous shell versions stored Quickshell
    // pins as "org.quickshell" (the literal wayland app_id at pin
    // time) which can't distinguish between qs apps. Convert any
    // such pin to "settings" — the only qs app in the default
    // pinnedApps list. Users who pinned other qs apps under the old
    // behavior can re-pin them to store them under their canonical
    // resolved ids.
    Component.onCompleted: {
        const apps = Config.options?.dock.pinnedApps ?? [];
        if (apps.indexOf("org.quickshell") !== -1) {
            Config.options.dock.pinnedApps = apps.map(id => id === "org.quickshell" ? "settings" : id);
        }
    }

    // ── Pin helpers ───────────────────────────────────────────────
    readonly property string folderPrefix: "folder:"

    function isPinned(appId) {
        return Config.options.dock.pinnedApps.some(id => id.toLowerCase() === appId.toLowerCase());
    }

    function isFolderPinned(folderId) {
        const key = root.folderPrefix + folderId;
        return Config.options.dock.pinnedApps.some(id => id === key);
    }

    function togglePin(appId) {
        if (root.isPinned(appId)) {
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.filter(id => id.toLowerCase() !== appId.toLowerCase())
        } else {
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.concat([appId])
        }
    }

    function toggleFolderPin(folderId) {
        const key = root.folderPrefix + folderId;
        if (root.isFolderPinned(folderId)) {
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.filter(id => id !== key)
        } else {
            Config.options.dock.pinnedApps = Config.options.dock.pinnedApps.concat([key])
        }
    }

    function reorderPinned(from, to) {
        var arr = Config.options.dock.pinnedApps.slice();
        var item = arr.splice(from, 1)[0];
        arr.splice(to, 0, item);
        Config.options.dock.pinnedApps = arr;
    }

    // ── Apps list ─────────────────────────────────────────────────
    // NOTE: Do NOT access AppFolderManager.folders or getFolder() here.
    // Doing so creates a reactive dependency that re-evaluates the entire
    // dock model on every folder change, causing animation glitches.
    // Folder data is resolved lazily by DockAppButton via AppFolderManager.
    property list<var> apps: {
        var map = new Map();

        // Pinned apps and folders
        const pinnedApps = Config.options?.dock.pinnedApps ?? [];
        for (const appId of pinnedApps) {
            if (appId.startsWith(root.folderPrefix)) {
                // Folder entry — don't look up folder data here
                if (!map.has(appId)) {
                    map.set(appId, {
                        pinned: true,
                        toplevels: [],
                        originalId: appId,
                        isFolder: true
                    });
                }
            } else {
                // Regular app entry
                if (!map.has(appId.toLowerCase())) map.set(appId.toLowerCase(), ({
                    pinned: true,
                    toplevels: [],
                    originalId: appId,
                    isFolder: false
                }));
            }
        }

        // Separator
        if (pinnedApps.length > 0) {
            map.set("SEPARATOR", { pinned: false, toplevels: [], originalId: "SEPARATOR", isFolder: false });
        }

        // Ignored apps
        const ignoredRegexStrings = Config.options?.dock.ignoredAppRegexes ?? [];
        const ignoredRegexes = ignoredRegexStrings.map(pattern => new RegExp(pattern, "i"));
        // Open windows. Resolve each toplevel's effective app_id via
        // resolveAppId() so org.quickshell windows split into separate
        // entries by title instead of merging into one group.
        for (const toplevel of ToplevelManager.toplevels.values) {
            if (ignoredRegexes.some(re => re.test(toplevel.appId))) continue;
            const resolvedAppId = root.resolveAppId(toplevel);
            if (!map.has(resolvedAppId.toLowerCase())) map.set(resolvedAppId.toLowerCase(), ({
                pinned: false,
                toplevels: [],
                originalId: resolvedAppId,
                isFolder: false
            }));
            map.get(resolvedAppId.toLowerCase()).toplevels.push(toplevel);
        }

        var values = [];

        for (const [key, value] of map) {
            values.push(appEntryComp.createObject(null, {
                appId: value.originalId,
                toplevels: value.toplevels,
                pinned: value.pinned,
                isFolder: value.isFolder
            }));
        }

        return values;
    }

    component TaskbarAppEntry: QtObject {
        id: wrapper
        required property string appId
        required property list<var> toplevels
        required property bool pinned
        required property bool isFolder
    }
    Component {
        id: appEntryComp
        TaskbarAppEntry {}
    }
}
