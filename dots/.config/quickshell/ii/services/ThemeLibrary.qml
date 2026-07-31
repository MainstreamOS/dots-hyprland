pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The saved-theme library, held for as long as the Settings process runs
 * rather than for as long as the Themes page is on screen.
 *
 * Settings puts every page through one Loader whose source is swapped on
 * navigation, and swaps it again on every theme apply (reloadCurrentPage in
 * settings.qml), so the Themes page is torn down and rebuilt constantly.
 * Owning the index here means a rebuilt page has its grid populated on the
 * first frame instead of after two subprocesses return.
 *
 * This used to hold a decoded copy of every preview alive as well, because a
 * preview.png was a monitor-resolution screenshot and re-decoding five of them
 * on each rebuild was worth going to some trouble to avoid. They are written
 * downscaled now (see previewMaxDimension, applied at capture in
 * ThemesConfig), which is cheap enough to decode that holding them was more
 * machinery than the problem justified.
 *
 * Only Settings reaches for this. QML singletons are created on first use, so
 * the main shell never instantiates it.
 */
Singleton {
    id: root

    function load() {} // For forcing initialization

    readonly property string themesDir: `${FileUtils.trimFileProtocol(Directories.home)}/.config/mainstream/themes`
    readonly property string themesIndex: `${root.themesDir}/index.json`
    readonly property string lastAppliedPath: `${root.themesDir}/last-applied.txt`

    property var themes: []
    property string lastAppliedSlug: ""
    property string _indexRaw: ""

    // What a preview.png is capped at on disk, applied by the capture in
    // ThemesConfig. Stated here next to the size they are drawn at, because the
    // pair only makes sense together: this has to stay comfortably above
    // previewSourceSize or the previews are upscaled.
    //
    // Applied only when a theme is saved or updated. Themes captured before
    // this keep their full-size preview and stay slow to decode until their
    // next save — there is no migration pass over the library.
    readonly property int previewMaxDimension: 1024

    // Qt keys its pixmap cache on the requested size and the fill mode as well
    // as the URL, so every preview on the page has to ask for all three
    // identically or they decode separate copies. A fixed size rather than the
    // drawn width is what makes the key settle during component creation
    // instead of after the layout pass, so a still-cached preview is simply
    // there instead of fading in; 400 covers the ~408px grid card at the
    // default window size.
    readonly property size previewSourceSize: Qt.size(400, 225)
    readonly property int previewFillMode: Image.PreserveAspectCrop

    // `created` is restamped at millisecond resolution every time preview.png
    // is written, so a replaced screenshot always arrives under a URL nothing
    // has decoded yet. That is what makes these safe to cache.
    function previewUrl(theme) {
        if (!theme || !theme.slug) return ""
        return `file://${root.themesDir}/${theme.slug}/preview.png?v=${theme.created || 0}`
    }

    function refresh() {
        loadIndexProc.running = false
        loadIndexProc.running = true
    }

    // Reassigning `themes` resets the pins and every card on the page, so an
    // index that came back unchanged is left alone — a single save reaches
    // here twice, once from the page and once from the watcher, and only one
    // of them has news. An empty or unparseable read means the file was caught
    // mid-rewrite; the last good list stays up rather than the grid emptying
    // for a frame.
    function adoptIndex(raw) {
        const trimmed = (raw || "").trim()
        if (trimmed.length === 0) return
        if (trimmed === root._indexRaw) return
        let parsed = null
        try {
            parsed = JSON.parse(trimmed)
        } catch (e) {
            return
        }
        if (!Array.isArray(parsed)) return
        root._indexRaw = trimmed
        root.themes = parsed
    }

    Component.onCompleted: ensureDirsProc.running = true

    Process {
        id: ensureDirsProc
        command: ["bash", "-c",
            `mkdir -p '${root.themesDir}' && ` +
            `if [ ! -f '${root.themesIndex}' ]; then echo '[]' > '${root.themesIndex}'; fi`
        ]
        onExited: loadIndexProc.running = true
    }

    Process {
        id: loadIndexProc
        property string buf: ""
        command: ["cat", root.themesIndex]
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => loadIndexProc.buf += data }
        onExited: {
            root.adoptIndex(loadIndexProc.buf)
            loadLastAppliedProc.running = false
            loadLastAppliedProc.running = true
        }
    }

    Process {
        id: loadLastAppliedProc
        property string buf: ""
        command: ["bash", "-c", `[ -f '${root.lastAppliedPath}' ] && cat '${root.lastAppliedPath}' || true`]
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => loadLastAppliedProc.buf += data }
        onExited: root.lastAppliedSlug = (loadLastAppliedProc.buf || "").trim()
    }

    // Live-track last-applied.txt so the Themes page updates the "active"
    // highlight the moment any apply happens — including ones the main shell's
    // ThemeManager fires on its own (clock-minute crossings, Hyprsunset
    // schedule transitions).
    FileView {
        path: root.lastAppliedPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.lastAppliedSlug = (text() || "").trim()
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) root.lastAppliedSlug = ""
        }
    }

    // The Themes page no longer re-reads the index by being rebuilt, so watch
    // the file for writers this process can't see — a second Settings window,
    // a restore, a future CLI. index.json is rewritten in place rather than
    // renamed, so the watch survives it.
    FileView {
        path: root.themesIndex
        watchChanges: true
        onFileChanged: root.refresh()
    }

}
