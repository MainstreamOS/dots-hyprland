pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell

/**
 * - Eases fuzzy searching for applications by name
 * - Guesses icon name for window class name
 */
Singleton {
    id: root
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property var substitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
        "footclient": "foot",
    })
    property var regexSubstitutions: [
        {
            "regex": /^steam_app_(\d+)$/,
            "replace": "steam_icon_$1"
        },
        {
            "regex": /Minecraft.*/,
            "replace": "minecraft"
        },
        {
            "regex": /.*polkit.*/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /gcr.prompter/,
            "replace": "system-lock-screen"
        }
    ]

    // What the shell shows about each app, copied out of Quickshell's desktop
    // entries in one pass per scan. Everything outside this file reads these
    // plain records, never an entry's own properties. A rescan rewrites the live
    // entries while notifying whatever observes them, and an app overridden in
    // ~/.local/share/applications is rewritten twice, to the system copy and
    // back, which has crashed the shell in the middle of that notification. A
    // record has nothing to notify: bindings that read one refresh when the
    // records are replaced, once the scan has finished.
    //
    // A record carries the entry fields the shell uses under the same names,
    // plus execute(), so it stands in wherever an entry did. It holds no entry
    // object: execute() looks the entry up by id when called, so a record a
    // model kept from before a rescan still launches the app, not a deleted one.
    property var records: ({}) // id -> record, for every entry looked up so far
    property var list: [] // the apps shown in menus, deduped
    property var preppedNames: []
    property var preppedIcons: []
    property var pendingEntries: []

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.refresh();
        }
    }

    Component.onCompleted: refresh()

    function copyOf(entry) {
        const id = entry.id;
        return {
            id: id,
            name: entry.name,
            genericName: entry.genericName,
            comment: entry.comment,
            icon: entry.icon,
            keywords: Array.from(entry.keywords),
            categories: Array.from(entry.categories),
            noDisplay: entry.noDisplay,
            startupClass: entry.startupClass,
            execString: entry.execString,
            command: Array.from(entry.command),
            runInTerminal: entry.runInTerminal,
            actions: Array.from(entry.actions).map(action => {
                const actionId = action.id;
                return {
                    id: actionId,
                    name: action.name,
                    icon: action.icon,
                    execString: action.execString,
                    command: Array.from(action.command),
                    execute: () => root.executeAction(id, actionId)
                };
            }),
            execute: () => DesktopEntries.byId(id)?.execute()
        };
    }

    function executeAction(entryId, actionId) {
        const entry = DesktopEntries.byId(entryId);
        if (!entry) return;
        Array.from(entry.actions).find(action => action.id === actionId)?.execute();
    }

    function refresh() {
        const records = {};
        const list = [];
        for (const entry of DesktopEntries.applications.values) {
            if (records[entry.id]) continue;
            const record = root.copyOf(entry);
            records[entry.id] = record;
            list.push(record);
        }
        // Entries kept out of menus that something looked up stay copied.
        for (const id of Object.keys(root.records)) {
            if (records[id]) continue;
            const entry = DesktopEntries.byId(id);
            if (entry) records[id] = root.copyOf(entry);
        }
        root.preppedNames = list.map(a => ({
            name: Fuzzy.prepare(`${a.name} `),
            entry: a
        }));
        root.preppedIcons = list.map(a => ({
            name: Fuzzy.prepare(`${a.icon} `),
            entry: a
        }));
        root.records = records;
        root.list = list;
    }

    // The record for a DesktopEntry from DesktopEntries.byId() or
    // heuristicLookup(). One kept out of menus is copied on the next turn of the
    // event loop rather than here: read here, inside whatever binding asked,
    // the entry's properties would be bound to after all. Until then it is null,
    // and the binding asks again once the copy lands. The records are read even
    // when there is no entry: byId() and heuristicLookup() register no
    // dependency, so a lookup made before the first scan would never run again.
    function recordFor(entry) {
        const records = root.records;
        if (!entry) return null;
        const record = records[entry.id];
        if (record) return record;
        root.pendingEntries.push(entry);
        Qt.callLater(root.copyPending);
        return null;
    }

    function copyPending() {
        const entries = root.pendingEntries.splice(0);
        const records = Object.assign({}, root.records);
        let added = false;
        for (const entry of entries) {
            if (!entry || records[entry.id]) continue;
            records[entry.id] = root.copyOf(entry);
            added = true;
        }
        if (added) root.records = records;
    }

    function fuzzyQuery(search: string): var {
        if (root.sloppySearch) {
            const results = list.map(obj => ({
                entry: obj,
                score: Levendist.computeScore(obj.name.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        return Fuzzy.go(search, preppedNames, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }

    function iconExists(iconName) {
        if (!iconName || iconName.length == 0) return false;
        return (Quickshell.iconPath(iconName, "").length > 0)
            && !iconName.includes("image-missing");
    }

    function getReverseDomainNameAppName(str) {
        return str.split('.').slice(-1)[0]
    }

    function getKebabNormalizedAppName(str) {
        return str.toLowerCase().replace(/\s+/g, "-");
    }

    function getUndescoreToKebabAppName(str) {
        return str.toLowerCase().replace(/_/g, "-");
    }

    // Resolve a string (window class, pinned id, or display name) to an app's record.
    // Mirrors guessIcon's fallback chain so pins like "GitHub Desktop" still resolve
    // when the user enters the display name instead of the desktop-entry id.
    function guessDesktopEntry(str) {
        const resolved = root.resolveDesktopEntry(str);
        if (resolved) return root.recordFor(resolved);
        if (!str || str.length == 0) return null;

        const nameMatches = root.fuzzyQuery(str);
        if (nameMatches.length > 0) return nameMatches[0];

        return null;
    }

    // The deterministic part of the chain: the id spellings plus quickshell's
    // class heuristics (StartupWMClass), and nothing fuzzy. Dock grouping of
    // windows with pins rides on this, where a fuzzy guess would merge two
    // unrelated apps into one icon.
    function resolveDesktopEntry(str) {
        if (!str || str.length == 0) return null;

        const direct = DesktopEntries.byId(str);
        if (direct) return direct;

        const lowercased = str.toLowerCase();
        const lowered = DesktopEntries.byId(lowercased);
        if (lowered) return lowered;

        const kebab = getKebabNormalizedAppName(str);
        const kebabEntry = DesktopEntries.byId(kebab);
        if (kebabEntry) return kebabEntry;

        const underscoreKebab = getUndescoreToKebabAppName(str);
        if (underscoreKebab !== kebab) {
            const underscoreEntry = DesktopEntries.byId(underscoreKebab);
            if (underscoreEntry) return underscoreEntry;
        }

        const reverseDomain = getReverseDomainNameAppName(str);
        if (reverseDomain !== str) {
            const reverseEntry = DesktopEntries.byId(reverseDomain)
                ?? DesktopEntries.byId(reverseDomain.toLowerCase());
            if (reverseEntry) return reverseEntry;
        }

        const heuristic = DesktopEntries.heuristicLookup(str);
        if (heuristic) return heuristic;

        return null;
    }

    function guessIcon(str) {
        if (!str || str.length == 0) return "image-missing";

        // Quickshell's desktop entry lookup
        const entry = root.recordFor(DesktopEntries.byId(str));
        if (entry && iconExists(entry.icon)) return entry.icon;

        // Normal substitutions
        if (substitutions[str]) return substitutions[str];
        if (substitutions[str.toLowerCase()]) return substitutions[str.toLowerCase()];

        // Regex substitutions
        for (let i = 0; i < regexSubstitutions.length; i++) {
            const substitution = regexSubstitutions[i];
            const replacedName = str.replace(
                substitution.regex,
                substitution.replace,
            );
            if (replacedName != str) return replacedName;
        }

        // Icon exists -> return as is
        if (iconExists(str)) return str;


        // Simple guesses
        const lowercased = str.toLowerCase();
        if (iconExists(lowercased)) return lowercased;

        const reverseDomainNameAppName = getReverseDomainNameAppName(str);
        if (iconExists(reverseDomainNameAppName)) return reverseDomainNameAppName;

        const lowercasedDomainNameAppName = reverseDomainNameAppName.toLowerCase();
        if (iconExists(lowercasedDomainNameAppName)) return lowercasedDomainNameAppName;

        const kebabNormalizedGuess = getKebabNormalizedAppName(str);
        if (iconExists(kebabNormalizedGuess)) return kebabNormalizedGuess;

        const undescoreToKebabGuess = getUndescoreToKebabAppName(str);
        if (iconExists(undescoreToKebabGuess)) return undescoreToKebabGuess;

        // Search in desktop entries
        const iconSearchResults = Fuzzy.go(str, preppedIcons, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
        if (iconSearchResults.length > 0) {
            const guess = iconSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        const nameSearchResults = root.fuzzyQuery(str);
        if (nameSearchResults.length > 0) {
            const guess = nameSearchResults[0].icon
            if (iconExists(guess)) return guess;
        }

        // Quickshell's desktop entry lookup
        const heuristicEntry = root.recordFor(DesktopEntries.heuristicLookup(str));
        if (heuristicEntry && iconExists(heuristicEntry.icon)) return heuristicEntry.icon;

        // Give up
        return "application-x-executable";
    }
}
