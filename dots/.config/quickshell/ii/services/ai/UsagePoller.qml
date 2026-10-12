import QtQuick
import Quickshell.Io
import qs.services

/**
 * Polls a subscription usage endpoint for ClaudeUsage and CodexUsage.
 * `command` prints one JSON object: the usage, which `accept` takes in, or
 * {"error": code, "retryAfter": value}. Failures back off from 30 s, doubling,
 * with a Retry-After as the floor and the fetch interval as the cap.
 */
QtObject {
    id: root

    property string name: ""
    property bool active: false
    property int fetchInterval: 60 * 1000
    property list<string> command: []
    // Takes a usage object and returns false when it holds no usage.
    property var accept: data => false

    property bool available: false
    property string lastError: ""

    readonly property var codes: ["no-login", "expired", "auth", "rate-limit", "network", "unexpected"]
    readonly property int minBackoff: 30 * 1000
    property int failures: 0
    // Epoch ms: when the next fetch is due, and the end of a Retry-After wait.
    property double nextAt: 0
    property double holdUntil: 0
    property bool manualUsed: false

    // Retry-After is either seconds or an HTTP date.
    function retryAfterMs(value) {
        const s = String(value ?? "").trim();
        if (/^\d+$/.test(s))
            return Number(s) * 1000;
        const t = Date.parse(s);
        return isNaN(t) ? 0 : Math.max(0, t - Date.now());
    }

    function schedule(delay) {
        root.nextAt = Date.now() + delay;
        if (root.active) {
            pollTimer.interval = delay;
            pollTimer.restart();
        }
    }

    function fail(error, retryAfterMs) {
        root.lastError = root.codes.includes(error) ? error : "unexpected";
        if (root.lastError === "no-login" || root.lastError === "expired" || root.lastError === "auth")
            root.available = false;
        root.failures++;
        let delay = Math.min(root.minBackoff * Math.pow(2, root.failures - 1), root.fetchInterval);
        if (retryAfterMs > 0) {
            const wait = Math.min(retryAfterMs, root.fetchInterval);
            root.holdUntil = Date.now() + wait;
            delay = Math.max(delay, wait);
        }
        root.schedule(delay);
    }

    function succeed(data) {
        if (!root.accept(data)) {
            root.fail("unexpected", 0);
            return;
        }
        root.available = true;
        root.lastError = "";
        root.failures = 0;
        root.holdUntil = 0;
        root.manualUsed = false;
        root.schedule(root.fetchInterval);
    }

    function fetch() {
        if (fetcher.running)
            return;
        // Replaced when the result arrives; covers a fetch that never reports back.
        root.schedule(root.fetchInterval);
        fetcher.running = true;
    }

    // The refresh button. While fetches fail it may skip the wait once per
    // scheduled retry, but never a Retry-After wait.
    function refresh() {
        if (!root.active || fetcher.running || Date.now() < root.holdUntil)
            return;
        if (root.failures > 0) {
            if (root.manualUsed)
                return;
            root.manualUsed = true;
        }
        root.fetch();
    }

    function fetchDue() {
        root.manualUsed = false;
        root.holdUntil = 0;
        root.fetch();
    }

    function resume() {
        const wait = Math.min(root.nextAt - Date.now(), root.fetchInterval);
        if (wait <= 0) {
            root.fetchDue();
        } else {
            pollTimer.interval = wait;
            pollTimer.restart();
        }
    }

    Component.onCompleted: if (root.active) root.resume()
    onActiveChanged: {
        if (root.active)
            root.resume();
        else
            pollTimer.stop();
    }
    // A shorter interval cuts the wait already running.
    onFetchIntervalChanged: if (root.active) root.resume()

    property Process fetcher: Process {
        command: root.command
        stdout: StdioCollector {
            onStreamFinished: {
                let d;
                try {
                    d = JSON.parse(text);
                } catch (e) {
                    console.warn(`[${root.name}] ${e.message}`);
                    root.fail("unexpected", 0);
                    return;
                }
                if (d?.error) {
                    root.fail(d.error, root.retryAfterMs(d.retryAfter));
                    return;
                }
                root.succeed(d);
            }
        }
    }

    property Timer pollTimer: Timer {
        repeat: false
        onTriggered: root.fetchDue()
    }

    // The CLI renews an expired token when it runs, so a finished reply is
    // the moment to look again.
    property Connections replies: Connections {
        target: Ai
        function onResponseFinished() {
            if (root.active && root.lastError === "expired" && Date.now() >= root.holdUntil)
                root.fetch();
        }
    }
}
