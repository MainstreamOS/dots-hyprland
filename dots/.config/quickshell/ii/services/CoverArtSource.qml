pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Scope {
    id: root
    required property string url
    readonly property string cachePath: `${Directories.coverArt}/${Qt.md5(root.url)}`
    readonly property string localUrl: root.url.startsWith("/") ? FileUtils.fileUrl(root.url)
        : root.url.startsWith("file:/") ? root.url : ""
    readonly property bool remote: /^https?:\/\//i.test(root.url)
    readonly property string source: {
        if (root.localUrl) return root.localUrl;
        if (root.url.startsWith("data:image/")) return root.url;
        return root.remote ? FileUtils.fileUrl(root.cachePath) : "";
    }
    signal cacheReady()

    onUrlChanged: Qt.callLater(root.prepare)
    Component.onCompleted: Qt.callLater(root.prepare)

    function prepare() {
        if (downloader.running) {
            if (downloader.requestedUrl !== root.url) downloader.running = false;
            return;
        }
        if ((!root.remote && !root.localUrl) || (downloader.requestedUrl === root.url
                && (!downloader.failedAt || Date.now() - downloader.failedAt < 15000))) return;
        downloader.requestedUrl = root.url;
        downloader.failedAt = 0;
        downloader.command = ["bash", Quickshell.shellPath("scripts/mpris/fetch-cover-art.sh"),
            root.cachePath, root.localUrl || root.url, root.remote ? "http,https" : "file"];
        downloader.running = true;
    }

    Process {
        id: downloader
        property string requestedUrl: ""
        property double failedAt: 0
        onExited: exitCode => {
            failedAt = exitCode === 0 ? 0 : Date.now();
            if (requestedUrl !== root.url) Qt.callLater(root.prepare);
            else if (exitCode === 0) root.cacheReady();
        }
    }
}
