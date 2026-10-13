pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

// Home folder search for the attachment sheet. Each search runs fd directly in
// its own Process, so stopping a superseded search signals fd itself.
Item {
    id: root
    visible: false

    // Each result: { path: string, isDir: bool }
    readonly property var results: root._results
    readonly property bool running: root._live !== null
    // True while a requested search waits out the debounce
    readonly property bool pending: debounceTimer.running

    readonly property list<string> excludes: [".git", "node_modules", "target", "build", ".cache", ".local", ".npm", ".cargo", ".venv", "__pycache__"]

    property var _results: []
    property var _buffer: []
    property var _request: null
    property var _live: null
    property int _searchId: 0

    function search(query: string, hidden: bool, extensions: var, limit: int): void {
        root._request = {
            query: query,
            hidden: hidden,
            extensions: extensions ?? [],
            limit: limit
        };
        debounceTimer.restart();
    }

    function reset(): void {
        debounceTimer.stop();
        root._request = null;
        root._stopLive();
        if (root._results.length > 0)
            root._results = [];
    }

    function _stopLive(): void {
        root._searchId += 1;
        flushTimer.stop();
        root._buffer = [];
        if (root._live) {
            root._live.running = false;
            root._live = null;
        }
    }

    function _buildCommand(request: var): var {
        const query = String(request.query);
        const extensions = request.extensions.map(e => String(e).replace(/^\./, "")).filter(e => e.length > 0);
        const args = ["fd", "--color=never", "--max-results", String(request.limit)];
        if (request.hidden)
            args.push("--hidden");
        args.push("--type", "f");
        if (extensions.length === 0)
            args.push("--type", "d");
        for (const ext of extensions)
            args.push("--extension", ext);
        for (const dir of root.excludes)
            args.push("--exclude", dir);
        args.push(/[*?]/.test(query) ? "--glob" : "--fixed-strings", "--", query, FileUtils.trimFileProtocol(Directories.home));
        return args;
    }

    function _start(): void {
        const request = root._request;
        if (!request)
            return;
        root._stopLive();
        root._results = [];
        const proc = processComponent.createObject(root, {
            searchId: root._searchId,
            command: root._buildCommand(request)
        });
        root._live = proc;
        proc.running = true;
        flushTimer.start();
    }

    function _onLine(proc: var, line: string): void {
        if (proc.searchId !== root._searchId)
            return;
        let path = line;
        const isDir = path.endsWith("/");
        if (isDir)
            path = path.slice(0, -1);
        if (path.length === 0)
            return;
        root._buffer.push({
            path: path,
            isDir: isDir
        });
    }

    function _flush(): void {
        if (root._buffer.length === 0)
            return;
        root._results = root._results.concat(root._buffer);
        root._buffer = [];
    }

    // Every ending, a failed start included, arrives as runningChanged.
    function _finish(proc: var): void {
        if (proc.searchId === root._searchId) {
            root._flush();
            flushTimer.stop();
            root._live = null;
        }
        proc.destroy();
    }

    Timer {
        id: debounceTimer
        interval: 150
        onTriggered: root._start()
    }

    Timer {
        id: flushTimer
        interval: 50
        repeat: true
        onTriggered: root._flush()
    }

    Component {
        id: processComponent

        Process {
            id: proc
            required property int searchId

            stdout: SplitParser {
                onRead: line => root._onLine(proc, line)
            }
            onRunningChanged: {
                if (!proc.running)
                    root._finish(proc);
            }
        }
    }
}
