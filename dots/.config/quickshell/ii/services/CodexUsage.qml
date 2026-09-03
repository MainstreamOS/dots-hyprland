pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * ChatGPT subscription usage for the Codex plan models.
 *
 * Reads the OAuth access token from ~/.codex/auth.json (kept fresh by the
 * Codex CLI) and polls the usage endpoint the Codex surfaces read - the same
 * data the CLI's /status command shows. Only active when
 * Config.options.bar.codexUsage.enable is true.
 *
 * Requires `jq` and `curl` (already used elsewhere in the shell).
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options.bar.codexUsage.enable
    readonly property int fetchInterval: Config.options.bar.codexUsage.fetchInterval * 60 * 1000

    property bool available: false
    property string lastError: ""
    property string planType: ""

    // Utilization percentages (0-100)
    property real fiveHour: 0
    property real sevenDay: 0

    // Reset timestamps (epoch ms; 0 if unknown)
    property double fiveHourReset: 0
    property double sevenDayReset: 0

    function _parseWindow(win) {
        if (!win) return null;
        const pct = win.used_percent ?? win.usedPercent ?? win.utilization;
        if (pct === undefined || pct === null) return null;
        // Resets arrive as seconds-until rather than a timestamp; either
        // spelling has appeared in the wild, so both are read.
        const seconds = win.resets_in_seconds ?? win.reset_after_seconds ?? null;
        const at = win.resets_at ? Date.parse(win.resets_at) : NaN;
        let resetMs = 0;
        if (seconds !== null) resetMs = Date.now() + seconds * 1000;
        else if (!isNaN(at)) resetMs = at;
        return { pct: pct, resetMs: resetMs };
    }

    function timeUntil(epochMs) {
        DateTime.time; // reactivity dependency
        if (!epochMs)
            return "—";
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

    function refine(data) {
        const rl = data.rate_limit ?? data.rate_limits ?? data;
        const primary = root._parseWindow(rl.primary_window ?? rl.primary);
        const secondary = root._parseWindow(rl.secondary_window ?? rl.secondary);
        if (!primary && !secondary) {
            root.available = false;
            root.lastError = "no rate limit windows in response";
            retryTimer.restart();
            return;
        }
        if (primary) {
            root.fiveHour = primary.pct;
            root.fiveHourReset = primary.resetMs;
        }
        if (secondary) {
            root.sevenDay = secondary.pct;
            root.sevenDayReset = secondary.resetMs;
        }
        root.planType = data.plan_type ?? data.planType ?? "";
        root.available = true;
        root.lastError = "";
    }

    function getData() {
        if (!root.enabled)
            return;
        fetcher.running = false;
        fetcher.running = true;
    }

    Process {
        id: fetcher
        command: ["bash", "-c", "creds=\"${CODEX_HOME:-$HOME/.codex}/auth.json\"; " + "tok=$(jq -r '.tokens.access_token' \"$creds\" 2>/dev/null); " + "if [ -z \"$tok\" ] || [ \"$tok\" = null ]; then echo '{\"error\":\"no Codex token\"}'; exit 0; fi; " + "curl -s --max-time 10 " + "-H \"Authorization: Bearer $tok\" " + "https://chatgpt.com/backend-api/wham/usage " + "| jq -c ."]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim().length === 0) {
                    root.available = false;
                    root.lastError = "empty response";
                    retryTimer.restart();
                    return;
                }
                try {
                    const d = JSON.parse(text);
                    if (d.error) {
                        root.available = false;
                        root.lastError = typeof d.error === "string" ? d.error : JSON.stringify(d.error);
                        retryTimer.restart();
                        return;
                    }
                    root.refine(d);
                } catch (e) {
                    root.available = false;
                    root.lastError = e.message;
                    retryTimer.restart();
                    console.error(`[CodexUsage] ${e.message}: ${text}`);
                }
            }
        }
    }

    Timer {
        running: root.enabled
        repeat: true
        interval: root.fetchInterval
        triggeredOnStart: true
        onTriggered: root.getData()
    }

    // Quick retry while we don't have data yet (cold start / token mid-refresh /
    // transient network), so a failed first fetch doesn't leave the meters
    // hidden until the next full interval.
    Timer {
        id: retryTimer
        interval: 15000
        repeat: false
        onTriggered: if (root.enabled && !root.available) root.getData()
    }
}
