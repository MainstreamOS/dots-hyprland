pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Gemini subscription usage for Google accounts (free / Google AI Pro / Ultra).
 *
 * Reads the OAuth access token from the system keyring (kept fresh by the
 * Antigravity CLI) and polls https://daily-cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels
 * for model quota and reset times. Polls only while online AI is allowed and an
 * Antigravity model is selected and signed in, and only when
 * Config.options.bar.geminiUsage.enable is true.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options.bar.geminiUsage.enable
    readonly property int fetchInterval: Math.max(1, Config.options.bar.geminiUsage.fetchInterval) * 60 * 1000
    // Not the plan's setup entry, whose model field (what a fetch sends) is
    // its setup id rather than a model the quota endpoint knows.
    readonly property bool active: root.enabled && Config.options.policies.ai === 1
        && Ai.currentModel?.api_format === "antigravity-cli" && Ai.currentModel.model !== Ai.cliPlans["antigravity-cli"].setupId
        && Ai.cliReady("antigravity-cli")
    readonly property bool running: fetcher.running

    property bool available: false
    property string lastError: ""
    property string planType: ""

    // Utilization percentages (0-100); -1 means "not reported"
    property real session: 0
    property real sevenDay: -1

    // Aliases matching ClaudeUsage / CodexUsage conventions
    readonly property real fiveHour: session
    readonly property double fiveHourReset: sessionReset

    // Reset timestamps (epoch ms; 0 if unknown)
    property double sessionReset: 0
    property double sevenDayReset: 0

    readonly property int _minBackoff: 30 * 1000
    readonly property int _maxBackoff: 30 * 60 * 1000
    property int _backoff: _minBackoff
    // Set when signed out or the token cannot be refreshed: retrying cannot help.
    property bool _stopped: false
    property bool _refetch: false
    // Whether the queued fetch may lift a stop, as a manual refresh does.
    property bool _refetchForced: false

    function _pct(v) {
        return (v === null || v === undefined) ? -1 : v;
    }

    function _parseIso(s) {
        if (!s)
            return 0;
        const t = Date.parse(s);
        return isNaN(t) ? 0 : t;
    }

    // Human "2h 5m" until the given epoch-ms. References DateTime.time so it
    // recomputes on the clock tick.
    function timeUntil(epochMs) {
        DateTime.time; // reactivity dependency
        if (!epochMs)
            return "";
        let diff = Math.floor((epochMs - Date.now()) / 1000);
        if (diff <= 0)
            return Translation.tr("now");
        const d = Math.floor(diff / 86400);
        diff %= 86400;
        const h = Math.floor(diff / 3600);
        diff %= 3600;
        const m = Math.floor(diff / 60);
        let out = "";
        if (d > 0)
            out += `${d}d `;
        if (h > 0)
            out += `${h}h `;
        out += `${m}m`;
        return out.trim();
    }

    function _fail(error) {
        root.available = false;
        root.lastError = error;
        if (error === "no-login" || error === "auth") {
            root._stopped = true;
            retryTimer.stop();
            return;
        }
        if (root.active) {
            retryTimer.interval = root._backoff;
            retryTimer.restart();
        }
        root._backoff = Math.min(root._backoff * 2, root._maxBackoff);
    }

    function refine(data) {
        if (!data.session && !data.weekly) {
            root._fail("no quota in response");
            return;
        }
        root.planType = data.planType ?? "";
        if (data.session) {
            root.session = root._pct(data.session.utilization);
            root.sessionReset = root._parseIso(data.session.resets_at);
        } else {
            root.session = 0;
            root.sessionReset = 0;
        }
        if (data.weekly && data.weekly.utilization !== -1) {
            root.sevenDay = root._pct(data.weekly.utilization);
            root.sevenDayReset = root._parseIso(data.weekly.resets_at);
        } else {
            root.sevenDay = -1;
            root.sevenDayReset = root._parseIso(data.weekly?.resets_at);
        }
        root.available = true;
        root.lastError = "";
        root._backoff = root._minBackoff;
    }

    // A manual refresh always runs. One asked for during a fetch follows it,
    // so a model switch mid-fetch still gets that model's quota.
    function getData() {
        if (!root.enabled)
            return;
        if (fetcher.running) {
            root._refetch = true;
            root._refetchForced = true;
            return;
        }
        root._stopped = false;
        root._start();
    }

    // A finished reply moved the quota, but signed out or unrefreshable
    // stays stopped, and a reply during a fetch adds at most the one queued.
    function refreshAfterReply() {
        if (!root.active || root._stopped)
            return;
        if (fetcher.running) {
            root._refetch = true;
            return;
        }
        root._start();
    }

    function _model() {
        return Ai.currentModel?.model ?? "";
    }

    function _start() {
        retryTimer.stop();
        fetcher.command = ["python3", Directories.aiGeminiUsageScriptPath, root._model()];
        fetcher.running = true;
        // The next poll counts from this fetch, whatever started it.
        if (pollTimer.running) pollTimer.restart();
    }

    Component.onCompleted: if (root.active) root.getData()
    onActiveChanged: {
        if (root.active) {
            root._backoff = root._minBackoff;
            root.getData();
        } else {
            retryTimer.stop();
        }
    }

    Process {
        id: fetcher
        onRunningChanged: {
            if (fetcher.running || !root._refetch)
                return;
            const forced = root._refetchForced;
            root._refetch = false;
            root._refetchForced = false;
            if (!root.active)
                return;
            if (forced)
                root.getData();
            else
                root.refreshAfterReply();
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length === 0) {
                    root._fail("empty response");
                    return;
                }
                try {
                    const d = JSON.parse(text);
                    if (d.error) {
                        root._fail(typeof d.error === "string" ? d.error : JSON.stringify(d.error));
                        return;
                    }
                    root.refine(d);
                } catch (e) {
                    root._fail(e.message);
                    console.warn(`[GeminiUsage] ${e.message}`);
                }
            }
        }
    }

    Timer {
        id: pollTimer
        running: root.active && !root._stopped
        repeat: true
        interval: root.fetchInterval
        onTriggered: root.getData()
    }

    Timer {
        id: retryTimer
        repeat: false
        onTriggered: if (root.active && !root._stopped && !root.available) root.getData()
    }

    Connections {
        target: Ai
        // A switch that also made the service active has its fetch running
        // already, for this same model.
        function onCurrentModelIdChanged() {
            if (root.active && !(fetcher.running && fetcher.command[2] === root._model()))
                root.getData();
        }
    }
}
