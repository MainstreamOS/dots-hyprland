pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

// File + folder search for the launcher widget.
//
// Backend: `fd` (https://github.com/sharkdp/fd). Walks ~/ live, no
// daily-rebuilt database. The single bash invocation tags each result
// "d:" or "f:" via [ -d ] so the QML side can show the right icon.
// Query is passed as a bash positional argument ($2), never spliced
// into the script body — fully injection-safe.
//
// Cancellation: runId increments per query; the SplitParser ignores
// lines from a runId that no longer matches root.searchId, so stale
// results from a killed-but-still-flushing fd process can't leak into
// the current query's result set.
Singleton {
    id: root

    // Each result: { path: string, isDir: bool, iconName: string }.
    // Held as a JS array (≤ Config.options.search.fileSearch.maxResults
    // entries) — the binding cost is negligible at that size.
    property var results: []
    property string activeQuery: ""
    property string pendingQuery: ""
    property int searchId: 0
    property bool running: false

    function shouldSearch(query) {
        if (!Config.options.search.fileSearch.enable) return false;
        if (!query || query.trim().length < 2) return false;
        return true;
    }

    function reset() {
        if (fdProc.running) fdProc.running = false;
        flushTimer.stop();
        root._pendingLines = [];
        // Empty-to-empty assignment still fires bindings; guard so typing
        // a single-char query (which fails shouldSearch and falls through
        // to reset()) doesn't trigger downstream re-renders for nothing.
        if (root.results.length > 0) root.results = [];
        root.activeQuery = "";
        root.running = false;
    }

    function search(query) {
        const trimmed = String(query || "").trim();
        if (!shouldSearch(trimmed)) { reset(); return; }
        root.pendingQuery = trimmed;
        debounceTimer.restart();
    }

    Timer {
        id: debounceTimer
        // 40ms is below the "feels delayed" threshold but coalesces fast
        // typing into a single fd spawn. fd kill-on-restart in runSearch
        // bounds concurrent processes to 1 regardless.
        interval: 40
        repeat: false
        onTriggered: root.runSearch(root.pendingQuery)
    }

    function runSearch(query) {
        const trimmed = String(query || "").trim();
        if (!shouldSearch(trimmed)) { reset(); return; }
        if (fdProc.running) fdProc.running = false;

        root.searchId += 1;
        root.activeQuery = trimmed;
        root.results = [];

        const maxResults = Config.options.search.fileSearch.maxResults;
        const home = FileUtils.trimFileProtocol(Directories.home);

        // Excludes are hardcoded for v1 — the typical noise dirs (build
        // artefacts, package caches, VCS internals). Make them config-
        // driven once we hit a real case where a user wants different
        // ones; static is simpler now.
        const script =
            'fd --type f --type d --max-results "$1" \\\n' +
            '   --exclude .git --exclude node_modules \\\n' +
            '   --exclude target --exclude build \\\n' +
            '   --exclude .cache --exclude .local \\\n' +
            '   --exclude .npm --exclude .cargo \\\n' +
            '   --exclude .venv --exclude __pycache__ \\\n' +
            '   "$2" "$3" 2>/dev/null \\\n' +
            ' | while IFS= read -r p; do\n' +
            '     if [ -d "$p" ]; then printf "d:%s\\n" "$p"\n' +
            '     else printf "f:%s\\n" "$p"\n' +
            '     fi\n' +
            '   done';

        fdProc.runId = root.searchId;
        fdProc.command = ["bash", "-c", script, "_", String(maxResults), trimmed, home];
        fdProc.running = true;
        root.running = true;
        flushTimer.start();
    }

    // Batch fd output into one results-array update every ~50ms (plus a
    // final flush on Process exit). Without this, each incoming line
    // triggered LauncherSearch.fileResults to remap ALL existing results
    // through resultComp.createObject — for 30 streamed lines that's
    // 1+2+…+30 = 465 createObject calls, which is visible as UI stutter
    // on the keystroke that finished the query.
    property var _pendingLines: []

    function _flush() {
        if (_pendingLines.length === 0) return;
        root.results = root.results.concat(_pendingLines);
        _pendingLines = [];
    }

    Timer {
        id: flushTimer
        interval: 50
        repeat: true
        running: false
        onTriggered: root._flush()
    }

    // ── Icon resolution ─────────────────────────────────────────────────
    //
    // Map file extension → XDG icon name. Resolved by the launcher via
    // Quickshell.iconPath(name, fallback) against the user's active icon
    // theme. Generic category names (image-x-generic, audio-x-generic,
    // etc.) are chosen deliberately because they exist in every well-
    // formed theme; specific MIME icons (text-x-python, application-pdf)
    // are only used where the icon's presence is reasonably universal.
    readonly property var xdgIconByExt: ({
        // Images
        "jpg":  "image-x-generic", "jpeg": "image-x-generic", "png":  "image-x-generic",
        "gif":  "image-x-generic", "webp": "image-x-generic", "svg":  "image-x-generic",
        "bmp":  "image-x-generic", "ico":  "image-x-generic", "heic": "image-x-generic",
        "heif": "image-x-generic", "tiff": "image-x-generic", "tif":  "image-x-generic",
        "avif": "image-x-generic", "raw":  "image-x-generic", "psd":  "image-x-generic",
        // Audio
        "mp3":  "audio-x-generic", "wav":  "audio-x-generic", "flac": "audio-x-generic",
        "ogg":  "audio-x-generic", "m4a":  "audio-x-generic", "opus": "audio-x-generic",
        "aac":  "audio-x-generic", "wma":  "audio-x-generic", "ape":  "audio-x-generic",
        // Video
        "mp4":  "video-x-generic", "mkv":  "video-x-generic", "avi":  "video-x-generic",
        "mov":  "video-x-generic", "webm": "video-x-generic", "flv":  "video-x-generic",
        "wmv":  "video-x-generic", "m4v":  "video-x-generic", "mpg":  "video-x-generic",
        "mpeg": "video-x-generic", "ts":   "video-x-generic", "vob":  "video-x-generic",
        // PDF — application-pdf is in every shipping theme
        "pdf": "application-pdf",
        // Source / scripts
        "sh":  "text-x-script", "bash":"text-x-script", "zsh":  "text-x-script",
        "fish":"text-x-script", "py":  "text-x-script", "rb":   "text-x-script",
        "rs":  "text-x-script", "go":  "text-x-script", "java": "text-x-script",
        "kt":  "text-x-script", "js":  "text-x-script", "tsx":  "text-x-script",
        "jsx": "text-x-script", "lua": "text-x-script", "c":    "text-x-script",
        "cpp": "text-x-script", "cc":  "text-x-script", "h":    "text-x-script",
        "hpp": "text-x-script", "cs":  "text-x-script", "php":  "text-x-script",
        "swift":"text-x-script","pl":  "text-x-script", "r":    "text-x-script",
        "sql": "text-x-script", "qml": "text-x-script",
        // Web
        "html":"text-html", "htm": "text-html",
        "css": "text-css",  "scss":"text-css",  "sass": "text-css",
        // Archives / packages
        "zip": "package-x-generic", "tar": "package-x-generic", "gz":  "package-x-generic",
        "bz2": "package-x-generic", "xz":  "package-x-generic", "7z":  "package-x-generic",
        "rar": "package-x-generic", "zst": "package-x-generic", "lz":  "package-x-generic",
        "deb": "package-x-generic", "rpm": "package-x-generic",
        // Fonts
        "ttf": "font-x-generic", "otf":  "font-x-generic",
        "woff":"font-x-generic", "woff2":"font-x-generic",
        // Executables / launchers
        "appimage":"application-x-executable", "exe":"application-x-executable",
        "desktop": "application-x-executable",
        // Subtitles / data — fall through to text-x-generic
    })

    function iconForPath(path, isDir) {
        if (isDir) return "folder";
        const dot = path.lastIndexOf(".");
        if (dot <= 0 || dot === path.length - 1) return "text-x-generic";
        const ext = path.slice(dot + 1).toLowerCase();
        return root.xdgIconByExt[ext] || "text-x-generic";
    }

    Process {
        id: fdProc
        property int runId: 0

        stdout: SplitParser {
            onRead: line => {
                if (fdProc.runId !== root.searchId) return;
                const raw = String(line || "");
                if (raw.length < 3) return;
                const isDir = raw[0] === "d";
                const path = raw.slice(2).trim();
                if (!path) return;
                // Push into the pending buffer; flushTimer batches the
                // results-array update so the launcher binding chain re-
                // renders at most once per ~50ms instead of per-line.
                root._pendingLines.push({
                    path: path,
                    isDir: isDir,
                    iconName: root.iconForPath(path, isDir),
                });
            }
        }

        onExited: {
            if (fdProc.runId !== root.searchId) return;
            flushTimer.stop();
            root._flush();
            root.running = false;
        }
    }
}
