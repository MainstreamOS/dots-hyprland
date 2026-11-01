import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions

// The parts of the wallpaper in front of the clock, stacked above it so the clock sits
// behind them. Fills the wallpaper the owner places it over, and draws only around the clock.
Item {
    id: root

    required property string picture
    // The clock, in shares of the picture.
    required property rect region
    property bool wanted: false
    property bool allowed: true
    // How far the clock can slide against the picture with parallax, in shares of it.
    property real drift: 0

    // A smaller share of the clock covered isn't an effect, and a larger one hides the time.
    readonly property real minCover: 0.01
    readonly property real maxCover: 0.6

    readonly property string script: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/images/wallpaper-depth.py`
    readonly property string readyMark: `${FileUtils.trimFileProtocol(Directories.cache)}/user/generated/wallpaper-depth/.ready`
    property var result: null
    property string resultPicture: ""
    property string failedPicture: ""
    property bool notifiedFailure: false
    readonly property string job: root.wanted && root.picture !== root.failedPicture ? root.picture : ""
    property string runningJob: ""
    // Turned off and on during a setup: whatever that setup ends with, it starts again after.
    property bool retryAfterRun: false

    onWantedChanged: {
        root.failedPicture = "";
        root.notifiedFailure = false;
        root.retryAfterRun = runner.running;
    }

    function cover(layer) {
        const columns = root.result.columns;
        const rows = root.result.rows;
        const x0 = Math.max(0, Math.floor(root.region.x * columns));
        const y0 = Math.max(0, Math.floor(root.region.y * rows));
        const x1 = Math.min(columns, Math.ceil((root.region.x + root.region.width) * columns));
        const y1 = Math.min(rows, Math.ceil((root.region.y + root.region.height) * rows));
        if (x1 <= x0 || y1 <= y0)
            return 0;
        let sum = 0;
        for (let y = y0; y < y1; y++)
            for (let x = x0; x < x1; x++)
                sum += layer.cover[y * columns + x];
        return sum / ((x1 - x0) * (y1 - y0));
    }

    // The farthest plane that leaves the clock readable, so it goes behind as much as it can.
    readonly property string layerPath: {
        if (!root.wanted || root.resultPicture !== root.picture || !root.result)
            return "";
        for (const layer of root.result.layers) {
            const covered = root.cover(layer);
            if (covered <= root.maxCover)
                return covered >= root.minCover ? layer.path : "";
        }
        return "";
    }

    // The part of the picture to load, moved only once the clock leaves it, so a drag
    // reloads now and then instead of every step.
    readonly property real cropSlack: 0.05
    property rect crop: Qt.rect(0, 0, 0, 0)
    readonly property real cropMargin: root.drift + root.cropSlack
    function updateCrop() {
        const r = root.region;
        const inside = r.x >= root.crop.x && r.y >= root.crop.y
            && r.x + r.width <= root.crop.x + root.crop.width && r.y + r.height <= root.crop.y + root.crop.height
            && root.crop.width > 0;
        if (inside || r.width <= 0)
            return;
        const m = root.cropMargin + root.cropSlack;
        const x = Math.max(0, r.x - m);
        const y = Math.max(0, r.y - m);
        root.crop = Qt.rect(x, y, Math.min(1, r.x + r.width + m) - x, Math.min(1, r.y + r.height + m) - y);
    }
    onRegionChanged: root.updateCrop()
    onCropMarginChanged: {
        root.crop = Qt.rect(0, 0, 0, 0);
        root.updateCrop();
    }
    // In the cutout's own pixels, which also keeps it lined up with the wallpaper.
    readonly property int pictureWidth: root.result?.width ?? 0
    readonly property int pictureHeight: root.result?.height ?? 0
    readonly property rect cropPixels: {
        const left = Math.floor(root.crop.x * root.pictureWidth);
        const top = Math.floor(root.crop.y * root.pictureHeight);
        return Qt.rect(left, top, Math.ceil((root.crop.x + root.crop.width) * root.pictureWidth) - left,
            Math.ceil((root.crop.y + root.crop.height) * root.pictureHeight) - top);
    }

    property string loadedLayer: ""
    visible: image.opacity > 0

    Image {
        id: image
        readonly property bool hasCrop: root.cropPixels.width > 0 && root.cropPixels.height > 0
        x: root.pictureWidth > 0 ? root.cropPixels.x / root.pictureWidth * root.width : 0
        y: root.pictureHeight > 0 ? root.cropPixels.y / root.pictureHeight * root.height : 0
        width: root.pictureWidth > 0 ? root.cropPixels.width / root.pictureWidth * root.width : 0
        height: root.pictureHeight > 0 ? root.cropPixels.height / root.pictureHeight * root.height : 0
        source: root.layerPath.length > 0 && hasCrop ? `file://${root.layerPath}` : ""
        sourceClipRect: root.cropPixels
        opacity: root.allowed && root.layerPath.length > 0 && root.loadedLayer === root.layerPath ? 1 : 0
        asynchronous: true
        cache: false
        retainWhileLoading: true
        smooth: true
        onStatusChanged: {
            if (status === Image.Ready)
                root.loadedLayer = root.layerPath;
        }

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    onJobChanged: root.run()
    Component.onCompleted: root.run()

    function run() {
        if (runner.running || root.job.length === 0)
            return;
        root.runningJob = root.job;
        runner.exec(["sh", "-c",
            '[ -e "$1" ] || notify-send -a Shell "$2" "$3"; '
            // A setup that stalls ends on its own, so a retry or another wallpaper can follow it.
            + 'systemd-run --user --scope --quiet -p MemoryMax=3G -p MemorySwapMax=0 -- '
            + 'timeout 1200 nice -n 10 "$4" "$5" || exit; touch "$1"',
            "sh", root.readyMark,
            Translation.tr("Setting up the clock depth effect"),
            Translation.tr("This downloads about 75 MB the first time"),
            root.script, root.picture]);
    }

    Process {
        id: runner
        stdout: StdioCollector {
            id: output
        }
        stderr: StdioCollector {
            id: errors
        }
        onExited: (exitCode, exitStatus) => {
            const finished = root.runningJob;
            const retry = root.retryAfterRun;
            root.runningJob = "";
            root.retryAfterRun = false;
            if (retry) {
                // Asked for again while running, so this outcome is not the last word.
            } else if (exitCode !== 0) {
                root.failedPicture = finished;
                console.warn("[ClockDepthCutout] failed:", errors.text.trim());
                // Only once: a missing package or connection fails every wallpaper the same way.
                if (!root.notifiedFailure)
                    Quickshell.execDetached(["notify-send", "-a", "Shell", Translation.tr("The clock depth effect could not be set up"),
                        Translation.tr("Turn it off and on again in Settings to try again")]);
                root.notifiedFailure = true;
            } else if (finished === root.job) {
                root.result = JSON.parse(output.text.trim().split("\n").pop());
                root.resultPicture = finished;
            }
            if (retry || root.job !== finished)
                root.run();
        }
    }
}
