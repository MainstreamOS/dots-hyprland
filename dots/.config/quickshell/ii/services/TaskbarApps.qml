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
        const appId = toplevel.appId || "";
        if (appId === "") return "";
        if (appId !== "org.quickshell") {
            // Pins store desktop-entry ids while windows report compositor
            // classes, and the two disagree for XWayland capitalization,
            // Electron classes, and launcher/client splits such as
            // spotify-launcher starting a client whose class is "spotify".
            // Group by the resolved desktop identity so one app is one icon.
            return AppSearch.resolveDesktopEntry(appId)?.id ?? appId;
        }
        const title = toplevel.title || "";
        if (title === Translation.tr("Mainstream Settings")) return "settings";
        if (title === Translation.tr("Welcome to Mainstream")) return "welcome-tutorial";
        if (title === Translation.tr("Uninstall Apps")) return "app-remover";
        if (title === Translation.tr("Auto Drive Mount")) return "disk-mounter";
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
        // resolveAppId goes through DesktopEntries.byId, a plain call that
        // registers no dependency, and the entry database fills in lazily
        // after startup. Windows restored at login would otherwise keep the
        // raw-id grouping they were dealt before the scan landed.
        DesktopEntries.applications.values;
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
            // A window can map before its class arrives; keying it under the
            // empty id would flash a ghost icon until the update lands.
            if (!toplevel.appId) continue;
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

        // Entries are reused between runs rather than rebuilt. Everything this
        // binding reads re-runs the whole body, so opening a window recomputed
        // the entire list even though the same apps were still in it. Handing
        // the model a fresh object for every app made it treat each one as a
        // new item, so the dock dropped and re-added every icon, ran its
        // appearance transition, and the animated width slid the whole centred
        // row sideways before it settled. Reordering never showed it because
        // that path turns the transition off while it drags.
        //
        // An app that really did appear or disappear still gets a new or
        // destroyed entry, so those keep animating.
        var values = [];
        const live = new Set();

        for (const [key, value] of map) {
            live.add(key);
            let entry = root._entries[key];
            if (entry) {
                entry.appId = value.originalId;
                entry.toplevels = value.toplevels;
                entry.pinned = value.pinned;
                entry.isFolder = value.isFolder;
            } else {
                entry = appEntryComp.createObject(null, {
                    appId: value.originalId,
                    toplevels: value.toplevels,
                    pinned: value.pinned,
                    isFolder: value.isFolder
                });
                root._entries[key] = entry;
            }
            values.push(entry);
        }

        for (const key in root._entries) {
            if (live.has(key)) continue;
            root._entries[key].destroy();
            delete root._entries[key];
        }

        return values;
    }

    // Keyed by the same key the map above uses. Only ever mutated in place —
    // assigning to it would make the binding above depend on its own output.
    property var _entries: ({})

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
