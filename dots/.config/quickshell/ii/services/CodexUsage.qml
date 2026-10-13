pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.services.ai
import qs.modules.common
import QtQuick
import Quickshell

/**
 * ChatGPT subscription usage for the Codex plan models.
 *
 * Reads the OAuth access token from ~/.codex/auth.json (kept fresh by the
 * Codex CLI) and polls the usage endpoint the Codex surfaces read - the same
 * data the CLI's /status command shows. Polls only while online AI is allowed
 * and a Codex plan model is selected and signed in, and only when
 * Config.options.bar.codexUsage.enable is true. The credentials are only read:
 * the Codex CLI renews its own token.
 *
 * Requires `jq` and `curl` (already used elsewhere in the shell).
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options.bar.codexUsage.enable
    readonly property int fetchInterval: Math.max(1, Config.options.bar.codexUsage.fetchInterval) * 60 * 1000
    readonly property bool active: root.enabled && Config.options.policies.ai === 1
        && Ai.currentModel?.api_format === "codex-cli" && Ai.currentModel.model !== Ai.cliPlans["codex-cli"].setupId
        && Ai.cliReady("codex-cli")

    // A code for the card. "no-login", "expired" and "auth" hide the meters;
    // "rate-limit", "network" and "unexpected" keep the last numbers.
    readonly property bool available: poller.available
    readonly property string lastError: poller.lastError
    readonly property double updatedAt: poller.updatedAt
    property string planType: ""

    // Utilization percentages (0-100)
    property real fiveHour: 0
    property real sevenDay: 0

    // Reset timestamps (epoch ms; 0 if unknown)
    property double fiveHourReset: 0
    property double sevenDayReset: 0

    property alias _failures: poller.failures
    property alias _nextAt: poller.nextAt
    property alias _holdUntil: poller.holdUntil
    property alias _manualUsed: poller.manualUsed

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
        if (!data || typeof data !== "object")
            return false;
        const rl = data.rate_limit ?? data.rate_limits ?? data;
        const primary = root._parseWindow(rl.primary_window ?? rl.primary);
        const secondary = root._parseWindow(rl.secondary_window ?? rl.secondary);
        if (!primary && !secondary)
            return false;
        if (primary) {
            root.fiveHour = primary.pct;
            root.fiveHourReset = primary.resetMs;
        }
        if (secondary) {
            root.sevenDay = secondary.pct;
            root.sevenDayReset = secondary.resetMs;
        }
        root.planType = data.plan_type ?? data.planType ?? "";
        return true;
    }

    function getData() {
        poller.refresh();
    }

    UsagePoller {
        id: poller
        name: "CodexUsage"
        active: root.active
        fetchInterval: root.fetchInterval
        accept: data => root.refine(data)
        // The access token is a JWT; its exp claim tells an expired token from a rejected one.
        command: ["bash", "-c", "creds=\"${CODEX_HOME:-$HOME/.codex}/auth.json\"; "
            + "{ IFS= read -r tok; IFS= read -r exp; } < <(jq -r '(.tokens.access_token // \"\"), "
            + "(try (.tokens.access_token | split(\".\")[1] | gsub(\"-\"; \"+\") | gsub(\"_\"; \"/\") | @base64d | fromjson | .exp // 0) catch 0 | tostring)' \"$creds\" 2>/dev/null); "
            + "if [ -z \"$tok\" ]; then echo '{\"error\":\"no-login\"}'; exit 0; fi; "
            + "if [[ $exp =~ ^[0-9]+$ ]] && (( exp > 0 && exp <= EPOCHSECONDS )); then echo '{\"error\":\"expired\"}'; exit 0; fi; "
            + "out=$(curl -s --max-time 10 -w '\\n%{http_code} %header{retry-after}' "
            + "-H @<(printf 'Authorization: Bearer %s\\n' \"$tok\") "
            + "https://chatgpt.com/backend-api/wham/usage); "
            + "meta=${out##*$'\\n'}; body=${out%$'\\n'*}; "
            + "case ${meta%% *} in "
            + "200) if j=$(printf '%s' \"$body\" | jq -ec objects 2>/dev/null); then printf '%s\\n' \"$j\"; else echo '{\"error\":\"unexpected\"}'; fi ;; "
            + "401|403) echo '{\"error\":\"auth\"}' ;; "
            + "429) jq -cn --arg ra \"${meta#* }\" '{error: \"rate-limit\", retryAfter: $ra}' ;; "
            + "000|5??) echo '{\"error\":\"network\"}' ;; "
            + "*) echo '{\"error\":\"unexpected\"}' ;; "
            + "esac"]
    }
}
