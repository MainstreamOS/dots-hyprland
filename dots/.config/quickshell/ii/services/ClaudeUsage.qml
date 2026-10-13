pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.services.ai
import qs.modules.common
import QtQuick
import Quickshell

/**
 * Claude subscription usage (Pro / Max).
 *
 * Reads the OAuth access token from ~/.claude/.credentials.json (kept fresh by
 * Claude Code) and polls https://api.anthropic.com/api/oauth/usage — the same
 * data Claude Code's /usage command shows. Polls only while online AI is allowed
 * and a Claude Code model is selected and signed in, and only when
 * Config.options.bar.claudeUsage.enable is true. The credentials are only read:
 * Claude Code renews its own token.
 *
 * Requires `jq` and `curl` (already used elsewhere in the shell).
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options.bar.claudeUsage.enable
    readonly property int fetchInterval: Math.max(1, Config.options.bar.claudeUsage.fetchInterval) * 60 * 1000
    readonly property bool active: root.enabled && Config.options.policies.ai === 1
        && Ai.currentModel?.api_format === "claude-code" && Ai.cliReady("claude-code")

    // A code for the card. "no-login", "expired" and "auth" hide the meters;
    // "rate-limit", "network" and "unexpected" keep the last numbers.
    readonly property bool available: poller.available
    readonly property string lastError: poller.lastError
    readonly property double updatedAt: poller.updatedAt
    property string subscriptionType: "" // "pro" | "max" | ...

    // Utilization percentages (0-100); -1 means "not reported by the API"
    property real fiveHour: 0
    property real sevenDay: 0
    property real sevenDayOpus: -1
    property real sevenDaySonnet: -1

    // Reset timestamps (epoch ms; 0 if unknown)
    property double fiveHourReset: 0
    property double sevenDayReset: 0

    // Pay-as-you-go extra credits
    property bool extraEnabled: false
    property real extraUsedCredits: 0
    property real extraMonthlyLimit: 0
    property string extraCurrency: ""

    property alias _failures: poller.failures
    property alias _nextAt: poller.nextAt
    property alias _holdUntil: poller.holdUntil
    property alias _manualUsed: poller.manualUsed

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
        if (!data || typeof data !== "object" || !("five_hour" in data || "seven_day" in data))
            return false;
        root.subscriptionType = data.subscriptionType ?? "";
        root.fiveHour = data.five_hour?.utilization ?? 0;
        root.sevenDay = data.seven_day?.utilization ?? 0;
        root.sevenDayOpus = root._pct(data.seven_day_opus?.utilization);
        root.sevenDaySonnet = root._pct(data.seven_day_sonnet?.utilization);
        root.fiveHourReset = root._parseIso(data.five_hour?.resets_at);
        root.sevenDayReset = root._parseIso(data.seven_day?.resets_at);
        const ex = data.extra_usage;
        root.extraEnabled = ex?.is_enabled ?? false;
        root.extraUsedCredits = ex?.used_credits ?? 0;
        root.extraMonthlyLimit = ex?.monthly_limit ?? 0;
        root.extraCurrency = ex?.currency ?? "";
        return true;
    }

    function getData() {
        poller.refresh();
    }

    UsagePoller {
        id: poller
        name: "ClaudeUsage"
        active: root.active
        fetchInterval: root.fetchInterval
        accept: data => root.refine(data)
        command: ["bash", "-c", "creds=\"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json\"; "
            + "{ IFS= read -r tok; IFS= read -r exp; IFS= read -r sub; } < <(jq -r '.claudeAiOauth | (.accessToken // \"\"), (.expiresAt // 0 | tostring), (.subscriptionType // \"\")' \"$creds\" 2>/dev/null); "
            + "if [ -z \"$tok\" ]; then echo '{\"error\":\"no-login\"}'; exit 0; fi; "
            + "if [[ $exp =~ ^[0-9]+$ ]] && (( exp > 0 && exp <= ${EPOCHREALTIME//[!0-9]/} / 1000 )); then echo '{\"error\":\"expired\"}'; exit 0; fi; "
            + "out=$(curl -s --max-time 10 -w '\\n%{http_code} %header{retry-after}' "
            + "-H @<(printf 'Authorization: Bearer %s\\n' \"$tok\") "
            + "-H 'anthropic-beta: oauth-2025-04-20' -H 'anthropic-version: 2023-06-01' "
            + "https://api.anthropic.com/api/oauth/usage); "
            + "meta=${out##*$'\\n'}; body=${out%$'\\n'*}; "
            + "case ${meta%% *} in "
            + "200) printf '%s' \"$body\" | jq -ec --arg sub \"$sub\" '. + {subscriptionType: $sub}' 2>/dev/null || echo '{\"error\":\"unexpected\"}' ;; "
            + "401|403) echo '{\"error\":\"auth\"}' ;; "
            + "429) jq -cn --arg ra \"${meta#* }\" '{error: \"rate-limit\", retryAfter: $ra}' ;; "
            + "000|5??) echo '{\"error\":\"network\"}' ;; "
            + "*) echo '{\"error\":\"unexpected\"}' ;; "
            + "esac"]
    }
}
