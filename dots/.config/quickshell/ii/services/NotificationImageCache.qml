pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.functions

// Notification image-provider URLs belong to the running shell. Copy their
// pixels while the notification is alive, so history survives shell reloads.
// A copy is named after its image, so an updated notification reuses it, and
// copies nothing refers to any more are removed by prune().
Singleton {
    id: root
    readonly property string directory: FileUtils.trimFileProtocol(Directories.cache) + "/notifications/images"
    property bool directoryReady: false
    property var pending: []
    property var current: null
    // Names copied this session, so the same image is not copied again.
    property var copied: ({})
    signal stored(notificationId: int, original: string, cached: string)

    function store(notificationId, source, imageKey) {
        if (!source || source.startsWith("file://" + directory + "/")) return;
        // Theme icons already have stable URLs. Do not ask Canvas to decode
        // those providers on its image-reader thread (QIcon is not thread-safe).
        if (!/^(image:\/\/qsimage\/|file:\/\/|\/)/.test(source)) return;
        if (current?.notificationId === notificationId && current.source === source) return;
        if (pending.some(job => job.notificationId === notificationId && job.source === source)) return;
        const name = (/^[0-9a-f]{8,64}$/i.test(imageKey || "") ? imageKey : Qt.md5(source)) + ".png";
        if (copied[name]) {
            Qt.callLater(() => root.stored(notificationId, source, "file://" + directory + "/" + name));
            return;
        }
        pending = pending.filter(job => job.notificationId !== notificationId).concat({notificationId, source, name});
        if (!directoryReady) {
            if (!prepare.running) prepare.running = true;
        } else pump();
    }
    function pump() {
        if (current || !directoryReady || !pending.length) return;
        current = pending[0];
        pending = pending.slice(1);
        deadline.restart();
    }
    function finish(cached) {
        const job = current;
        if (!job) return;
        deadline.stop();
        if (canvas.available) canvas.unloadImage(job.source);
        current = null;
        if (cached) {
            copied = Object.assign({}, copied, {[job.name]: true});
            stored(job.notificationId, job.source, cached);
        }
        Qt.callLater(pump);
    }
    function copyImage() {
        if (!current || !canvas.available || decoder.status !== Image.Ready
            || decoder.source.toString() !== Qt.resolvedUrl(current.source).toString()) return;
        const job = current;
        if (!canvas.isImageLoaded(job.source)) {
            canvas.loadImage(job.source);
            return;
        }
        const ctx = canvas.getContext("2d");
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(job.source, 0, 0, canvas.width, canvas.height);
        const path = directory + "/" + job.name;
        const saved = canvas.save(path);
        finish(saved ? "file://" + path : "");
    }
    Process {
        id: prepare
        command: ["mkdir", "-p", "-m", "700", root.directory]
        onExited: exitCode => {
            root.directoryReady = exitCode === 0;
            if (root.directoryReady) root.pump();
            else root.pending = [];
        }
    }
    Timer { id: deadline; interval: 3000; onTriggered: root.finish("") }

    // Removes copies not among these URLs. A copy younger than a minute may
    // belong to a notification that has not taken it yet, so it stays.
    function prune(urls) {
        const prefix = "file://" + directory + "/";
        const keep = urls.filter(u => typeof u === "string" && u.startsWith(prefix)).map(u => u.slice(prefix.length));
        pruneProc.command = ["sh", "-c", 'dir="$1"; shift; find "$dir" -maxdepth 1 -type f -name "*.png" -mmin +1 -printf "%f\\n" '
            + '| while read -r f; do case " $* " in *" $f "*) ;; *) rm -f -- "$dir/$f";; esac; done', "sh", directory].concat(keep);
        pruneProc.running = true;
        const kept = {};  // QML's JavaScript has no Object.fromEntries
        for (const name of keep) kept[name] = true;
        copied = kept;
    }
    Process { id: pruneProc }
    // Canvas needs a window, but no image is drawn on screen. This one-pixel,
    // input-free surface only exists for the duration of a copy; Canvas.Image
    // reads the decoded pixels on the CPU rather than capturing the desktop.
    PanelWindow {
        visible: !!root.current
        implicitWidth: 1
        implicitHeight: 1
        anchors { top: true; left: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:notificationImageCache"
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}
        Image {
            id: decoder
            visible: false
            source: root.current?.source ?? ""
            asynchronous: true
            sourceSize: Qt.size(512, 512)
            cache: false
            onStatusChanged: {
                if (status === Image.Ready) Qt.callLater(root.copyImage);
                else if (status === Image.Error) root.finish("");
            }
        }
        Canvas {
            id: canvas
            x: -1024
            y: -1024
            readonly property real imageScale: Math.min(1, 512 / Math.max(1, decoder.implicitWidth, decoder.implicitHeight))
            width: Math.max(1, Math.round(decoder.implicitWidth * imageScale))
            height: Math.max(1, Math.round(decoder.implicitHeight * imageScale))
            renderTarget: Canvas.Image
            onAvailableChanged: if (available) Qt.callLater(root.copyImage)
            onImageLoaded: Qt.callLater(root.copyImage)
        }
    }
}
