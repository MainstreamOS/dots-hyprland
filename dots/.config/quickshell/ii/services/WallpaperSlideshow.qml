pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Rotates the wallpaper through a folder on a timer.
 *
 * The settings live in Config under background.slideshow, which means a saved
 * theme carries them in its config.json snapshot and applying a theme installs
 * that theme's rotation — a theme saved with a single wallpaper switches the
 * slideshow off when it takes over, and a Day/Night pair hand their own
 * rotations back and forth at the boundary. Nothing here needs to know the
 * theme system exists; it only has to keep out of its way while an apply is
 * mid-flight.
 *
 * A tick normally runs switchwall.sh --picture-only, which swaps the image and
 * leaves the palette, the terminals and the accent colour alone. Turning
 * `recolor` on gives up that cheapness for a full regeneration each time.
 */
Singleton {
    id: root

    function load() {} // For forcing initialization

    // Only the main shell rotates. settings.qml loads qs.services too, and two
    // processes on the same timer would race switchwall.sh with itself — the
    // same reason ThemeManager gates its scheduler and ReleaseUpdates gates its
    // announcements.
    property bool _rotationEnabled: false

    readonly property var opts: Config.options?.background?.slideshow ?? null

    readonly property string defaultFolder: `${FileUtils.trimFileProtocol(Directories.pictures)}/Wallpapers`

    // A theme exported to another machine has its folder stripped, and a fresh
    // config has never had one, so an unset folder means the stock wallpaper
    // directory rather than nothing to show.
    readonly property string folder: {
        const configured = (root.opts?.folder ?? "").trim()
        if (configured.length > 0) return FileUtils.trimFileProtocol(configured)
        return root.defaultFolder
    }

    // Videos are left out on purpose: each one tears down and respawns
    // mpvpaper on every monitor, which is not something to do on a timer.
    readonly property list<string> extensions: ["jpg", "jpeg", "png", "webp", "bmp", "avif"]

    // Regenerating the palette costs a second of work plus a reload every
    // client feels, so it gets a floor a plain image swap doesn't need.
    readonly property int minimumInterval: (root.opts?.recolor ?? false) ? 15 : 5
    readonly property int intervalMinutes: Math.max(root.minimumInterval, root.opts?.intervalMinutes ?? 30)

    readonly property bool active: root._rotationEnabled
        && Config.ready
        && (root.opts?.enable ?? false)

    // Rotating behind a fullscreen window means decoding an image nobody can
    // see, and with recolor on it would repaint a desktop that isn't visible
    // either. Wait for the next tick instead. A function rather than a bound
    // property so the walk over every toplevel happens once a cycle instead of
    // on every window event.
    function _anythingFullscreen() {
        return Hyprland.workspaces.values.some(ws =>
            ws.active && ws.toplevels.values.some(w => w.wayland?.fullscreen))
    }

    property var _recent: []

    // Started only once everything above is ready, so the first change lands a
    // full interval into the session rather than during startup — config.json
    // must not be written while the shell is still coming up.
    Timer {
        id: rotateTimer
        running: root.active
        repeat: true
        interval: root.intervalMinutes * 60 * 1000
        onTriggered: root.rotate()
    }

    // A theme apply owns config.json for the length of its run and rewrites
    // wallpaperPath itself; stepping in would either lose the theme's wallpaper
    // or be lost by it. The tick is simply skipped — the timer comes back.
    function rotate() {
        if (!root.active) return
        if (Config.themeApplyInProgress) return
        if (root._anythingFullscreen()) return
        listProc.running = false
        listProc.running = true
    }

    // Re-read the folder on every change rather than caching it, so wallpapers
    // added or deleted mid-session are picked up without anything to invalidate.
    Process {
        id: listProc
        property string buf: ""
        // A theme that carried its own pictures keeps them inside its directory,
        // and deleting that theme takes the directory with it. Falling back to
        // the stock folder means the rotation carries on with something to show
        // rather than stopping dead and never saying why.
        command: ["bash", "-c",
            `DIR="$1"; [ -d "$DIR" ] || DIR="$2"\n` +
            `find -L "$DIR" -maxdepth 1 -type f \\( ${root.extensions.map(e => `-iname '*.${e}'`).join(" -o ")} \\) 2>/dev/null | LC_ALL=C sort`,
            "wallpaper-slideshow", root.folder, root.defaultFolder]
        onRunningChanged: if (running) buf = ""
        stdout: SplitParser { onRead: data => listProc.buf += data + "\n" }
        onExited: root._advance((listProc.buf || "").split("\n").filter(l => l.length > 0))
    }

    function _advance(all) {
        if (all.length === 0) return
        const current = FileUtils.trimFileProtocol(Config.options.background.wallpaperPath ?? "")
        let next = ""

        if (root.opts?.shuffle ?? true) {
            // Keep a short memory of what has already been shown so a small
            // folder doesn't repeat itself immediately. When everything has
            // had a turn the memory clears rather than the rotation stalling.
            const memory = Math.min(root._recent.length, Math.max(0, Math.floor(all.length / 2)))
            const recent = root._recent.slice(root._recent.length - memory)
            let pool = all.filter(p => p !== current && recent.indexOf(p) < 0)
            if (pool.length === 0) {
                root._recent = []
                pool = all.filter(p => p !== current)
            }
            if (pool.length === 0) return
            next = pool[Math.floor(Math.random() * pool.length)]
            root._recent = recent.concat([next]).slice(-64)
        } else {
            // An unrecognised current wallpaper (a theme's embedded copy, say,
            // which lives in the theme directory rather than this folder)
            // starts the sequence from the top.
            const index = all.indexOf(current)
            next = all[(index + 1) % all.length]
            if (next === current) return
        }

        root.apply(next)
    }

    function apply(path) {
        if (!path || path.length === 0) return
        // --keep-slideshow is what separates a tick from someone choosing a
        // single wallpaper; without it the script reads this as the user
        // picking one and turns the rotation off mid-run.
        const args = [Directories.wallpaperSwitchScriptPath,
                      "--mode", Appearance.m3colors.darkmode ? "dark" : "light",
                      "--image", path,
                      "--keep-slideshow"]
        if (!(root.opts?.recolor ?? false)) args.push("--picture-only")
        Quickshell.execDetached(args)
    }

    // A theme sets its own wallpaper as it lands, so start the interval over
    // from there — otherwise a theme applied late in a cycle gets its wallpaper
    // replaced moments after arriving.
    Connections {
        target: ThemeManager
        function onApplied(slug) {
            if (!root.active) return
            rotateTimer.restart()
        }
    }

    IpcHandler {
        target: "slideshow"

        function next(): void {
            root.rotate();
        }
    }
}
