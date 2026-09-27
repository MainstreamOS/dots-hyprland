pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.models.hyprland
import "monitor-wallpaper-keys.js" as Keys

/**
 * Pictures for single monitors, picked from the desktop menu on any monitor
 * other than the default one. Nothing here runs the wallpaper script or
 * writes the config: the colors, the login screen and the overview backdrop
 * all come from background.wallpaperPath, which the default monitor always
 * shows, so a picture picked here only ever changes the screen it was
 * picked for.
 */
Singleton {
    id: root

    // Key to { path, width, height, connector, description }. The key is "desc:" and the
    // monitor's description (make, model and serial), so a picture follows
    // its monitor to another port or dock; a monitor with no description, or
    // one that shares it with another connected monitor, is keyed by its
    // connector name. The size is taken when the picture is picked, so the
    // background never has to measure it; 0 means it could not be read.
    readonly property var entries: Persistent.states.monitors.wallpapers ?? ({})
    readonly property bool ready: Persistent.ready && root.defaultMonitorKnown

    // Sent as soon as a pick is accepted, so the picker can close before the
    // size comes back.
    signal assigned(string monitorName)

    // Monitors Hyprland has described in full. It can name a monitor in an
    // event a moment before adding it, and that placeholder has no
    // description or position yet: read as it is, it would pass for another
    // monitor, or for the one at 0,0.
    readonly property var monitors: Hyprland.monitors.values.filter(m => Object.keys(m.lastIpcObject ?? {}).length > 0)
    // Quickshell refreshes the monitors it knows when one is added, not when
    // one is removed, and Hyprland can move the rest when it is: the one at
    // 0,0, the default while none is set, would otherwise be read stale.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "monitorremoved") Hyprland.refreshMonitors();
        }
    }

    function knows(name) {
        return root.monitors.some(m => m.name === name);
    }

    // Settings > Display stores its choice as cursor:default_monitor and,
    // while that is unset (it reads "[[EMPTY]]"), treats the monitor at 0,0
    // or else the first one as the default. Resolving in the same order keeps
    // the shell and Settings in agreement.
    HyprlandConfigOption {
        id: defaultMonitorOption
        key: "cursor:default_monitor"
    }
    property bool defaultMonitorKnown: false
    Connections {
        target: defaultMonitorOption
        function onFetchingChanged() {
            if (!defaultMonitorOption.fetching) root.defaultMonitorKnown = true;
        }
    }
    readonly property string defaultMonitorName: Keys.defaultMonitorName(
        defaultMonitorOption.set ? defaultMonitorOption.value : "", root.monitors)

    function isOtherMonitor(name) {
        return root.ready && !!name && root.defaultMonitorName !== ""
            && name !== root.defaultMonitorName && root.knows(name);
    }

    // The picture a screen draws instead of the main wallpaper, or null. The
    // default monitor never gets one: its wallpaper is the one the colors
    // come from.
    function pictureFor(name) {
        if (!root.isOtherMonitor(name)) return null;
        const key = Keys.keysFor(root.entries, root.monitors, name)[0];
        return key ? root.entries[key] : null;
    }
    function hasPicture(name) {
        return root.pictureFor(name) !== null;
    }
    function pathFor(name) {
        return root.pictureFor(name)?.path ?? "";
    }

    // The latest pick per monitor, so a size that comes back after a newer
    // pick or a clear is dropped instead of saved over it.
    property var pendingPicks: ({})

    function setPicture(name, path) {
        const clean = FileUtils.trimFileProtocol(String(path ?? ""));
        if (!Persistent.ready || !root.isOtherMonitor(name) || !Keys.isImagePath(clean))
            return false;
        // The main wallpaper picked again means following it, so the screen
        // changes along with it later rather than keeping this copy.
        if (clean === FileUtils.trimFileProtocol(Config.options.background.wallpaperPath)) {
            root.clearPicture(name);
            root.assigned(name);
            return true;
        }
        root.pendingPicks[name] = clean;
        root.assigned(name);
        sizeProbe.createObject(root, { monitorName: name, path: clean });
        return true;
    }

    function clearPicture(name) {
        delete root.pendingPicks[name];
        if (!Persistent.ready) return;
        const next = Keys.withPicture(root.entries, root.monitors, name, null);
        if (Object.keys(next).length !== Object.keys(root.entries).length)
            Persistent.states.monitors.wallpapers = next;
    }

    // For a monitor that is not coming back, whose picture the menu can no
    // longer reach.
    function forgetKey(key) {
        if (!Persistent.ready || !(key in root.entries)) return;
        const next = Object.assign({}, root.entries);
        delete next[key];
        Persistent.states.monitors.wallpapers = next;
    }

    function save(name, path, width, height) {
        if (root.pendingPicks[name] !== path) return;
        delete root.pendingPicks[name];
        // Unplugged while it was being measured: there is nothing left to
        // key the picture by.
        if (!root.knows(name)) return;
        Persistent.states.monitors.wallpapers = Keys.withPicture(root.entries, root.monitors, name,
            { path: path, width: width, height: height });
    }

    Component {
        id: sizeProbe
        Process {
            id: probe
            required property string monitorName
            required property string path
            // One line per frame for an animated picture; the first is enough.
            // -ping reads the size from the header instead of decoding the
            // whole picture, so the screen changes as soon as it closes.
            command: ["magick", "identify", "-ping", "-format", "%w %h\n", probe.path]
            environment: Images.magickEnvironment
            stdout: StdioCollector {
                id: probeOutput
            }
            Component.onCompleted: probe.running = true
            onExited: exitCode => {
                const size = probeOutput.text.split("\n")[0].split(" ").map(Number);
                const known = exitCode === 0 && size.length === 2 && size[0] > 0 && size[1] > 0;
                root.save(probe.monitorName, probe.path, known ? size[0] : 0, known ? size[1] : 0);
                probe.destroy();
            }
        }
    }

    Process {
        id: systemPicker
        property string monitorName: ""
        stdout: StdioCollector {
            id: systemPickerOutput
        }
        onExited: exitCode => {
            const picked = systemPickerOutput.text.trim();
            if (exitCode === 0 && picked.length > 0) root.setPicture(systemPicker.monitorName, picked);
        }
    }
    // Opens where the wallpaper script's own dialog opens and lists pictures
    // only: a video cannot be drawn per monitor.
    function pickWithSystemDialog(name) {
        if (!root.isOtherMonitor(name) || systemPicker.running) return;
        systemPicker.monitorName = name;
        systemPicker.command = ["bash", "-c",
            'cd "$1/Wallpapers/showcase" 2>/dev/null || cd "$1/Wallpapers" 2>/dev/null || cd "$1" 2>/dev/null || cd; '
            + 'exec zenity --file-selection --filename="$PWD/" --file-filter="$2 | $3" --title="$4"',
            "monitor-wallpaper",
            FileUtils.trimFileProtocol(Directories.pictures),
            Translation.tr("Wallpapers"),
            Keys.imageExtensions.map(ext => `*.${ext} *.${ext.toUpperCase()}`).join(" "),
            // Named apart from the main wallpaper's dialog, since a pick here
            // leaves the colors alone.
            `${Translation.tr("Choose wallpaper")} (${Translation.tr("This screen only")})`];
        systemPicker.running = true;
    }

    // Lets the feature be checked without moving the pointer.
    IpcHandler {
        target: "monitorWallpapers"

        function pick(monitor: string, path: string): string {
            return root.setPicture(monitor, path) ? "ok" : "refused";
        }
        function clear(monitor: string): void {
            root.clearPicture(monitor);
        }
        function forget(key: string): void {
            root.forgetKey(key);
        }
        function list(): string {
            return JSON.stringify(root.entries);
        }
        function defaultMonitor(): string {
            return root.defaultMonitorName;
        }
        function hasPicture(monitor: string): bool {
            return root.hasPicture(monitor);
        }
    }
}
