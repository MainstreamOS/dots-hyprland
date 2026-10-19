pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * LinkPreviewService - resolves and caches rich embed previews for URLs in messages
 * (YouTube, TikTok, Instagram, Facebook, Twitter/X, Spotify, Reddit, and general websites).
 */
Singleton {
    id: root

    property var previews: ({})
    property var inFlight: ({})
    property var pendingBatch: []

    readonly property string cacheDir: `${Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache"}/quickshell/link_previews`
    readonly property string indexPath: `${root.cacheDir}/index.json`

    FileView {
        id: indexFileView
        path: FileUtils.trimFileProtocol(root.indexPath)
        onLoaded: {
            try {
                const text = indexFileView.text().trim();
                if (text.length > 0) {
                    const data = JSON.parse(text);
                    const merged = Object.assign({}, root.previews, data);
                    root.previews = merged;
                }
            } catch (e) {
                // A partial index is ignored; batch results still merge from the helper's output.
            }
        }
    }

    Component.onCompleted: {
        indexFileView.reload();
    }

    // Where a matched link ends: sentence punctuation after it is dropped, but a ")"
    // that closes a "(" inside the link (Wikipedia-style) stays.
    function urlEnd(u: string): int {
        let end = u.length;
        while (end > 0 && /[.,!?;:'")]/.test(u[end - 1])) {
            if (u[end - 1] === ")") {
                const head = u.slice(0, end);
                if ((head.match(/\(/g) || []).length >= (head.match(/\)/g) || []).length) break;
            }
            end--;
        }
        return end;
    }

    /**
     * Extracts all valid web URLs from a string.
     * @param {string} text
     * @returns {string[]}
     */
    function extractUrls(text: string): var {
        if (!text || typeof text !== "string") return [];
        const pattern = /(?:https?:\/\/|www\.)[^\s<>"'{}|\\^`\[\]]+/gi;
        const urls = [];
        let match;
        while ((match = pattern.exec(text)) !== null) {
            let u = match[0].slice(0, root.urlEnd(match[0]));
            if (u.toLowerCase().startsWith("www.")) {
                u = "https://" + u;
            }
            if (u.length > 7 && !urls.includes(u)) {
                urls.push(u);
            }
        }
        return urls;
    }

    /**
     * Removes extracted URLs (up to maxCount, default 2) from the text so raw links
     * are not duplicated when rich embedded link previews are displayed.
     * @param {string} text
     * @param {number} maxCount
     * @returns {string}
     */
    function stripUrls(text: string, maxCount: int): string {
        if (!text || typeof text !== "string") return "";
        const limit = (maxCount !== undefined && maxCount > 0) ? maxCount : 2;
        const pattern = /(?:https?:\/\/|www\.)[^\s<>"'{}|\\^`\[\]]+/gi;
        const seen = [];
        let result = "";
        let lastIndex = 0;
        let match;
        while ((match = pattern.exec(text)) !== null) {
            const end = root.urlEnd(match[0]);
            let raw = match[0].slice(0, end);
            const trailing = match[0].slice(end);
            let normalized = raw;
            if (normalized.toLowerCase().startsWith("www.")) {
                normalized = "https://" + normalized;
            }
            if (normalized.length > 7) {
                if (!seen.includes(normalized) && seen.length < limit) {
                    seen.push(normalized);
                }
                if (seen.includes(normalized)) {
                    result += text.slice(lastIndex, match.index);
                    lastIndex = match.index + match[0].length - trailing.length;
                    continue;
                }
            }
        }
        if (seen.length === 0) return text;
        result += text.slice(lastIndex);
        const cleaned = result
            .replace(/\s+([.,!?;:])/g, "$1")
            .replace(/[ \t]{2,}/g, " ")
            .replace(/[ \t]+\n/g, "\n")
            .replace(/\n[ \t]+/g, "\n")
            .replace(/\n{3,}/g, "\n\n")
            .trim();
        if (!/[^\s.,!?;:'"\])}(\[{]/.test(cleaned)) {
            return "";
        }
        return cleaned;
    }

    /**
     * Returns a cached preview object if available, or schedules a background fetch.
     * @param {string} url
     * @returns {var|null}
     */
    function getPreview(url: string): var {
        if (!url || !Config.options.sidebar.phone.linkPreviews) return null;
        const cached = root.previews[url];
        if (!root.settled(cached)) root.queueFetch(url);
        return cached ?? null;
    }

    // A preview counts as final unless it is a failed fetch past its retry time.
    function settled(preview): bool {
        // Refresh Facebook entries produced by the old generic page resolver.
        if (preview && /^https?:\/\/(?:[\w-]+\.)*(?:facebook\.com|fb\.watch)(?:[/?#]|$)/i.test(preview.url ?? "")
                && preview.resolver !== "facebook") return false;
        return !!preview && !(preview.retryAfter && preview.retryAfter * 1000 <= Date.now());
    }

    // Cache read only, for text that is not on screen (quoted replies).
    function peekPreview(url: string): var {
        return url && Config.options.sidebar.phone.linkPreviews ? (root.previews[url] ?? null) : null;
    }

    // Links a batch returned nothing for, and when to ask again.
    property var unresolved: ({})

    function queueFetch(url: string): void {
        if (!url || root.inFlight[url] || root.settled(root.previews[url]) || (root.unresolved[url] ?? 0) > Date.now()) return;
        if (root.pendingBatch.length >= 256) return;
        if (!root.pendingBatch.includes(url)) {
            root.pendingBatch.push(url);
        }
        batchTimer.restart();
    }

    Timer {
        id: batchTimer
        interval: 80
        repeat: false
        onTriggered: root.processPendingBatch()
    }

    property int activeBatches: 0
    function processPendingBatch(): void {
        if (root.pendingBatch.length === 0 || root.activeBatches >= 2) return;
        const urlsToFetch = root.pendingBatch.filter(u => !root.inFlight[u] && !root.settled(root.previews[u])).slice(0, 16);
        root.pendingBatch = root.pendingBatch.filter(u => !urlsToFetch.includes(u));
        if (urlsToFetch.length === 0) return;

        const updatedInFlight = Object.assign({}, root.inFlight);
        for (const u of urlsToFetch) {
            updatedInFlight[u] = true;
        }
        root.inFlight = updatedInFlight;

        const script = FileUtils.trimFileProtocol(`${Directories.scriptPath}/phone/link-preview.py`);
        const proc = batchProcComponent.createObject(root, {
            command: ["python3", "-I", script, "batch"].concat(urlsToFetch),
            targetUrls: urlsToFetch
        });
        if (proc) {
            root.activeBatches++;
            proc.running = true;
        }
    }

    Component {
        id: batchProcComponent
        Process {
            id: procItem
            property var targetUrls: []
            property bool didStart: false
            property bool completed: false
            onStarted: didStart = true
            // Failed starts close no output stream and emit no exit signal.
            onRunningChanged: if (!running && !didStart) Qt.callLater(procItem.complete)
            stdout: StdioCollector {
                id: collector
                onStreamFinished: procItem.complete()
            }
            function complete(): void {
                if (completed) return;
                completed = true;
                try {
                    const out = collector.text.trim();
                    const res = out.length > 0 ? JSON.parse(out) : {};
                    for (const u of procItem.targetUrls) {
                        if (!res[u]) root.unresolved[u] = Date.now() + 600000;
                    }
                    if (Object.keys(res).length > 0) root.previews = Object.assign({}, root.previews, res);
                } catch (e) {
                    for (const u of procItem.targetUrls) root.unresolved[u] = Date.now() + 600000;
                    console.warn("[LinkPreviewService] Failed parsing batch preview output:", e);
                } finally {
                    const inFlightCopy = Object.assign({}, root.inFlight);
                    for (const u of procItem.targetUrls) {
                        delete inFlightCopy[u];
                    }
                    root.inFlight = inFlightCopy;
                    root.activeBatches--;
                    Qt.callLater(root.processPendingBatch);
                    Qt.callLater(procItem.destroy);
                }
            }
        }
    }

    /**
     * Resolves direct video streaming URL (via yt-dlp) for inline playback.
     */
    function fetchStream(url: string, callback): void {
        if (!url || typeof callback !== "function") return;
        const script = FileUtils.trimFileProtocol(`${Directories.scriptPath}/phone/link-preview.py`);
        const proc = streamProcComponent.createObject(root, {
            command: ["python3", "-I", script, "stream", url],
            targetUrl: url,
            cb: callback
        });
        if (proc) proc.running = true;
    }

    Component {
        id: streamProcComponent
        Process {
            id: streamProcItem
            property string targetUrl: ""
            property var cb: null
            property bool didStart: false
            property bool completed: false
            onStarted: didStart = true
            // Failed starts close no output stream and emit no exit signal.
            onRunningChanged: if (!running && !didStart) Qt.callLater(streamProcItem.complete)
            stdout: StdioCollector {
                id: streamCollector
                onStreamFinished: streamProcItem.complete()
            }
            function complete(): void {
                if (completed) return;
                completed = true;
                let streamUrl = "";
                try {
                    const out = streamCollector.text.trim();
                    if (out.length > 0) {
                        const res = JSON.parse(out);
                        if (res.status === "ok" && res.stream_url) {
                            streamUrl = res.stream_url;
                        }
                    }
                } catch (e) {
                    console.warn("[LinkPreviewService] Failed stream resolution:", e);
                } finally {
                    try {
                        if (streamProcItem.cb) streamProcItem.cb(streamUrl);
                    } finally {
                        Qt.callLater(streamProcItem.destroy);
                    }
                }
            }
        }
    }
}
