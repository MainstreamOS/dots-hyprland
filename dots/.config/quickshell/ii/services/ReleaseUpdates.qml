pragma Singleton

import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * Mainstream OS releases, as opposed to services/Updates.qml which counts
 * pending pacman packages. Reads the release manifest published alongside the
 * website, compares it against the tag updatems last applied, and works out
 * how urgently the user should be told.
 */
Singleton {
    id: root

    // A release picks up urgency as it ages, so someone who ignores a small
    // patch for a month still ends up being told clearly.
    readonly property int staleYellowDays: 7
    readonly property int staleRedDays: 21

    property string installedVersion: ""
    property var pending: []
    property bool checking: false

    readonly property bool updateAvailable: root.pending.length > 0
    readonly property var latest: root.pending.length > 0 ? root.pending[0] : null
    readonly property string severity: root.severityOf(root.pending)

    // Anything unrecognised reads as "both" — including the "off" that older
    // settings files carry. Off would hide the widget, and the widget is the
    // only way back to this choice, so there'd be no way to undo it.
    readonly property string notifyMode: {
        const mode = Config.options.updates.release.notify;
        return (mode === "tray" || mode === "notification") ? mode : "both";
    }
    readonly property bool wantTray: root.notifyMode === "both" || root.notifyMode === "tray"
    readonly property bool wantNotification: root.notifyMode === "both" || root.notifyMode === "notification"

    // Said in the notification and again in the hover popup; one wording, so
    // translators see it once.
    function availableLine(version) {
        return Translation.tr("Mainstream OS %1 is available").arg(version);
    }

    // Settings reads installedVersion and latest to show which release it is
    // on, which instantiates this singleton in that process too. Only the main
    // shell announces, or opening Settings could raise a second notification
    // for a release the user has already been told about.
    property bool _announceEnabled: false

    function load() {}

    function refresh() {
        if (root.checking) return;
        root.checking = true;
        installedFetcher.running = true;
    }

    // ---- version handling ------------------------------------------------

    // The same 1-2 digit major cap updatems uses, so the retired date tags
    // (2026.05.11) can't sort above a real release.
    readonly property var semver: /^(\d{1,2})\.(\d+)\.(\d+)$/

    function parseVersion(text) {
        const match = root.semver.exec(String(text ?? "").trim());
        return match ? [parseInt(match[1]), parseInt(match[2]), parseInt(match[3])] : null;
    }

    function newer(a, b) {
        for (let i = 0; i < 3; i++) {
            if (a[i] !== b[i]) return a[i] > b[i];
        }
        return false;
    }

    // ---- severity --------------------------------------------------------

    function daysBehind(releases) {
        // Measured from the oldest pending release, not the newest: being
        // three releases behind is judged on when you fell behind.
        let oldest = null;
        for (const entry of releases) {
            const when = Date.parse(entry.date + "T00:00:00Z");
            if (!isNaN(when) && (oldest === null || when < oldest)) oldest = when;
        }
        if (oldest === null) return 0;
        return Math.max(0, Math.floor((Date.now() - oldest) / 86400000));
    }

    function severityOf(releases) {
        if (releases.length === 0) return "";
        const kinds = releases.map(entry => String(entry.kind ?? "patch").toLowerCase());
        const age = root.daysBehind(releases);
        if (kinds.includes("security") || age >= root.staleRedDays) return "red";
        if (age >= root.staleYellowDays) return "yellow";
        if (kinds.includes("feature")) return "blue";
        return "white";
    }

    // ---- the check -------------------------------------------------------

    function settle(manifest) {
        const current = root.parseVersion(root.installedVersion);
        let found = [];
        // With no readable version to compare against we say nothing rather
        // than guess — claiming someone is six releases behind because a
        // marker file was unreadable would be alarming and possibly wrong.
        if (current && manifest && Array.isArray(manifest.releases)) {
            for (const entry of manifest.releases) {
                // The manifest can carry a version that is written up but not
                // cut yet, so the website can show what is coming. It has no
                // tag behind it, so offering it would send updatems after a
                // release that cannot be fetched.
                if (entry?.unreleased) continue;
                const version = root.parseVersion(entry?.version);
                if (version && root.newer(version, current)) found.push({ version: version, entry: entry });
            }
            // The manifest keeps only the newest few, so someone long out of
            // date can be behind a release no longer listed; "latest" names it.
            const latestVersion = root.parseVersion(manifest.latest);
            if (latestVersion && root.newer(latestVersion, current)
                && !found.some(f => String(f.entry.version) === String(manifest.latest))) {
                found.push({ version: latestVersion, entry: { version: manifest.latest, kind: "patch" } });
            }
            found.sort((a, b) => root.newer(a.version, b.version) ? -1 : 1);
        }

        const releases = found.map(f => f.entry);
        root.pending = releases;
        if (root._announceEnabled && root.updateAvailable && root.wantNotification) root.maybeNotify();
    }

    // ---- notification ----------------------------------------------------

    // Announcing a release the machine cannot install yet is worse than saying
    // nothing: the [mainstream] repo is still being put in place through the
    // first boot, and an update started against it fails on packages that are
    // not there. Updates watches for the repo to answer, so hold the news until
    // it does and take it up again on the next check. Nothing is lost by
    // waiting, since lastNotified is only written once the notice goes out.
    Timer {
        id: repoWait
        interval: 5000
        repeat: false
        onTriggered: if (root._announceEnabled && root.updateAvailable && root.wantNotification) root.maybeNotify()
    }

    function maybeNotify() {
        if (!Updates.repoReady) {
            repoWait.restart();
            return;
        }
        const version = String(root.latest.version);
        if (notifyState.lastNotified === version) return;
        notifyState.lastNotified = version;
        notifyStateFile.writeAdapter();

        // Only summary and changes are read here. The manifest also carries the
        // release's raw commit range for the website's technical view; merging
        // any of that into changes would put commit subjects in a desktop
        // notification on every installed machine.
        const summary = String(root.latest.summary ?? "");
        const changes = (root.latest.changes ?? []).slice(0, 3);
        let body = summary;
        if (changes.length > 0) body += (body.length > 0 ? "\n" : "") + changes.map(c => "• " + c).join("\n");
        if (root.pending.length > 1) body += `\n\n${root.pending.length} releases since yours.`;

        notifier.command = ["notify-send", "-a", "Mainstream updates",
            "-i", "mainstream-update",
            "-u", root.severity === "red" ? "critical" : "normal",
            "-A", `open=${Translation.tr("Open updates")}`,
            "-A", `changelog=${Translation.tr("What's new")}`,
            root.availableLine(version), body];
        notifier.running = true;
    }

    function openUpdatesPage() {
        Quickshell.execDetached({
            command: ["qs", "-p", Directories.settingsAppPath],
            environment: ({ "QS_SETTINGS_PAGE": "UpdateConfig.qml" })
        });
    }

    function openChangelog() {
        Quickshell.execDetached(["xdg-open", "https://mainstreamos.org/#changelog"]);
    }

    // notify-send prints the chosen action's name and only exits once the
    // notification is answered or dismissed, so this is also the callback.
    Process {
        id: notifier
        stdout: StdioCollector {
            onStreamFinished: {
                const action = text.trim();
                if (action === "open") root.openUpdatesPage();
                else if (action === "changelog") root.openChangelog();
            }
        }
    }

    // ---- inputs ----------------------------------------------------------

    // An install that has never run updatems has no tag in the clone and reads
    // the one baked into the image instead, so this is a fallback chain rather
    // than a single read — which is the one thing a shell line does neatly.
    Process {
        id: installedFetcher
        command: ["sh", "-c", `cat '${Directories.appliedTagPath}' 2>/dev/null || cat /etc/mainstream-dotfiles-tag 2>/dev/null || true`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.installedVersion = text.trim();
                manifestFetcher.running = true;
            }
        }
    }

    Process {
        id: manifestFetcher
        command: ["curl", "-sfL", "--compressed", "--max-time", "15", Config.options.updates.release.manifestUrl]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0) {
                    try {
                        const manifest = JSON.parse(text);
                        if (text !== manifestCache.text()) manifestCache.setText(text);
                        root.settle(manifest);
                        root.checking = false;
                        return;
                    } catch (e) {
                        console.log(`[ReleaseUpdates] manifest did not parse: ${e.message}`);
                    }
                }
                // Offline, or the server returned nothing usable. The last
                // good copy still says which release was waiting.
                root.settle(manifestCache.parsed());
                root.checking = false;
            }
        }
    }

    // Re-check when updatems installs something, so the indicator clears
    // rather than advertising a release the user already has.
    FileView {
        path: Directories.appliedTagPath
        watchChanges: true
        onFileChanged: root.refresh()
    }

    FileView {
        id: manifestCache
        path: Directories.releaseManifestPath
        function parsed() {
            try {
                return JSON.parse(manifestCache.text());
            } catch (e) {
                return null;
            }
        }
    }

    // Remembers which release was announced, so a shell reload doesn't
    // re-announce one the user has already been told about.
    FileView {
        id: notifyStateFile
        path: Directories.releaseNotifyStatePath
        watchChanges: false
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) writeAdapter();
        }
        JsonAdapter {
            id: notifyState
            property string lastNotified: ""
        }
    }

    Timer {
        interval: Math.max(1, Config.options.updates.release.checkIntervalHours) * 3600 * 1000
        repeat: true
        running: Config.ready
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
