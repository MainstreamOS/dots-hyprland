pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions

// Synced lyrics from LRCLIB for whatever the active player is playing. The
// song's title and artist leave the machine only while a lyrics view is on
// screen: each Lyrics view counts itself in through addViewer while it is
// shown, and with nobody counted in nothing is looked up at all.
Singleton {
    id: root

    readonly property MprisPlayer activePlayer: MprisController.activePlayer

    property var lyricsLines: []
    property int activeIndex: -1
    // idle, loading, ok, not_found, no_info, offline or rate_limited
    property string status: "idle"
    property var slots: ["", "", "", "", "", "", ""]

    readonly property int before: 3
    readonly property int after:  3
    readonly property int total:  7

    property int viewers: 0
    readonly property bool shown: root.viewers > 0
    function addViewer() {
        root.viewers += 1;
    }
    function removeViewer() {
        root.viewers = Math.max(0, root.viewers - 1);
    }

    readonly property string trackTitle: root.activePlayer?.trackTitle ?? ""
    readonly property string trackArtist: root.activePlayer?.trackArtist ?? ""
    // Zero when the player does not know it: Quickshell hands out the
    // position in its place, which would be sent as the song's length.
    readonly property real trackLength: (root.activePlayer?.lengthSupported ?? false) ? root.activePlayer.length : 0
    // Which song the lyrics belong to, and what answers are filed under. A
    // player change and a track change both come down to this changing. The
    // length is left out: some players only learn it once the song is under
    // way, and live streams report one that keeps growing, so it would count
    // as a new song every time, and be asked about again on every return.
    readonly property string trackKey: JSON.stringify([root.trackArtist, root.trackTitle])

    // Which song the lyrics on show belong to, or are being looked up for.
    property string loadedKey: ""

    // Answers already had, "not found" included, so a song that comes around
    // again is not asked about again. Newest last; only the most recent are
    // kept, and only for this session.
    readonly property int cacheSize: 200
    property var cache: new Map()
    function remember(key, entry) {
        root.cache.delete(key);
        root.cache.set(key, entry);
        while (root.cache.size > root.cacheSize)
            root.cache.delete(root.cache.keys().next().value);
    }

    // Set when LRCLIB answers 429: no request at all goes out before this.
    property real retryAt: 0

    function buildSlots(idx) {
        let result = []
        for (let i = 0; i < root.total; i++) {
            let lineIdx = idx - root.before + i
            if (lineIdx >= 0 && lineIdx < root.lyricsLines.length)
                result.push(root.lyricsLines[lineIdx].text || "♪")
            else
                result.push("")
        }
        return result
    }

    function show(key, status, lines) {
        root.loadedKey = key;
        root.lyricsLines = lines;
        root.activeIndex = -1;
        root.slots = root.buildSlots(-1);
        root.status = status;
        if (status === "ok")
            root.syncToPosition();
    }

    function syncToPosition() {
        const pos = root.activePlayer?.position ?? 0
        let idx = -1
        for (let i = 0; i < root.lyricsLines.length; i++) {
            if (root.lyricsLines[i].time <= pos) idx = i
            else break
        }
        if (idx !== root.activeIndex) {
            root.activeIndex = idx
            root.slots = root.buildSlots(idx)
        }
    }

    // An answer already had, or a pause LRCLIB asked for, settles a song
    // without a request.
    function answerFromMemory(key) {
        const known = root.cache.get(key);
        if (known) {
            root.remember(key, known);
            root.show(key, known.status, known.lines);
            return true;
        }
        if (root.retryAt > Date.now()) {
            root.show(key, "rate_limited", []);
            root.retryWhenAllowed();
            return true;
        }
        return false;
    }

    function lookUp() {
        if (!root.shown)
            return;
        const key = root.trackKey;
        // Already on show or on its way. A failed attempt is not an answer.
        if (key === root.loadedKey && root.status !== "offline" && root.status !== "rate_limited") {
            if (root.status === "ok")
                root.syncToPosition();
            return;
        }
        if (!root.trackTitle || !root.trackArtist) {
            root.show(key, "no_info", []);
            return;
        }
        if (root.answerFromMemory(key))
            return;
        root.show(key, "loading", []);
        root.request(key, [
            "python3",
            `${FileUtils.trimFileProtocol(Directories.scriptPath)}/lyrics/lyrics.py`,
            StringUtils.cleanMusicTitle(root.trackTitle) || root.trackTitle,
            root.trackArtist,
            String(Math.round(root.trackLength))
        ]);
    }

    // Asks again for the song on show after LRCLIB could not be reached.
    function retry() {
        if (root.status === "offline")
            root.lookUp();
    }

    function retryWhenAllowed() {
        retryTimer.interval = Math.max(1000, root.retryAt - Date.now());
        retryTimer.restart();
    }

    onTrackKeyChanged: {
        if (root.trackKey === root.loadedKey)
            return;
        // What is on show belongs to another song now. Metadata tends to
        // arrive a field at a time, so the lookup waits for it to settle.
        root.show("", root.shown ? "loading" : "idle", []);
        settleTimer.restart();
    }

    // Metadata still arriving is left to the settle timer, so it gets one lookup.
    onShownChanged: if (!settleTimer.running) root.lookUp()

    Timer {
        id: settleTimer
        interval: 400
        onTriggered: root.lookUp()
    }

    Timer {
        id: retryTimer
        onTriggered: if (!settleTimer.running) root.lookUp()
    }

    Timer {
        id: syncTimer
        interval: 300
        repeat: true
        running: root.shown && root.status === "ok" && root.lyricsLines.length > 0
            && (root.activePlayer?.isPlaying ?? false)
        onTriggered: root.syncToPosition()
    }

    // A seek while paused moves the lyrics too.
    Connections {
        target: root.activePlayer
        function onPositionChanged() {
            if (root.shown && root.status === "ok")
                root.syncToPosition();
        }
    }

    // One lookup at a time, and one that has started is left to finish:
    // stopping it here would not stop LRCLIB answering it, so the next song
    // would be asked about alongside it, and the answer it brings is kept for
    // when that song comes around again. Only the newest song waits its turn.
    property var queued: null
    function request(key, command) {
        // Back on a song whose lookup is still under way: its answer is the
        // one wanted, so it is left to finish rather than asked for twice.
        if (lyricsProc.running && !lyricsProc.stopping && lyricsProc.requestKey === key) {
            root.queued = null;
            return;
        }
        root.queued = { key: key, command: command };
        if (!lyricsProc.running)
            root.startQueued();
    }
    function stopLookup() {
        lyricsProc.stopping = true;
        lyricsProc.running = false;
    }
    function startQueued() {
        const next = root.queued;
        root.queued = null;
        if (!next || next.key !== root.trackKey)
            return;
        // It may have waited behind a slow lookup, so what allowed it then
        // has to still hold now.
        if (!root.shown) {
            // Left for the next view to ask for, rather than kept loading.
            root.show("", "idle", []);
            return;
        }
        if (root.answerFromMemory(next.key))
            return;
        lyricsProc.requestKey = next.key;
        lyricsProc.answered = false;
        lyricsProc.stopping = false;
        lyricsProc.command = next.command;
        lyricsProc.running = true;
        watchdog.restart();
    }

    function handleOutput(key, line) {
        const trimmed = line.trim();
        // A pause LRCLIB asks for holds whichever song it was asked about.
        if (trimmed.startsWith("rate_limited")) {
            const seconds = parseInt(trimmed.split("§")[1]);
            root.retryAt = Date.now() + (isNaN(seconds) ? 60 : Math.max(1, seconds)) * 1000;
            if (key === root.loadedKey) {
                root.show(key, "rate_limited", []);
                root.retryWhenAllowed();
            }
            return;
        }
        const current = key === root.trackKey && key === root.loadedKey;
        if (trimmed === "no_info" || trimmed === "offline") {
            if (current)
                root.show(key, trimmed, []);
            return;
        }

        let lines = []
        if (trimmed !== "not_found") {
            const parts = trimmed.split("§")
            if (parts.length < 3) return
            if (parts[parts.length - 1].trim() !== "ok") return

            for (let i = 0; i < parts.length - 1; i += 2) {
                const t = parseFloat(parts[i])
                const txt = parts[i + 1] || ""
                if (!isNaN(t)) lines.push({ time: t, text: txt })
            }
        }

        // Kept even when the song has moved on since it was asked about, so
        // coming back to it does not ask again.
        const status = lines.length > 0 ? "ok" : "not_found";
        root.remember(key, { status: status, lines: lines });
        if (current)
            root.show(key, status, lines);
    }

    Process {
        id: lyricsProc
        property string requestKey: ""
        property bool answered: false
        // Asked to stop but not gone yet, so no longer the lookup to wait on.
        property bool stopping: false
        stdout: SplitParser {
            onRead: data => {
                lyricsProc.answered = true;
                root.handleOutput(lyricsProc.requestKey, data);
            }
        }
        onExited: {
            watchdog.stop();
            // Stopped, or gone without a word: either way no answer came,
            // unless the same song is already waiting to be asked about again.
            if (!lyricsProc.answered && lyricsProc.requestKey === root.loadedKey && root.status === "loading"
                    && root.queued?.key !== lyricsProc.requestKey)
                root.show(root.loadedKey, "offline", []);
            if (root.queued)
                root.startQueued();
        }
    }

    // Name lookups are not covered by the script's own timeouts.
    Timer {
        id: watchdog
        interval: 45000
        onTriggered: root.stopLookup()
    }
}
