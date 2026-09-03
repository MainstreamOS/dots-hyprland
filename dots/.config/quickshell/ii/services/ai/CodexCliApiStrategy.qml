import QtQuick
import qs.modules.common.functions as CF

ApiStrategy {
    id: root
    property string sessionId: ""
    property int _inputTokens: -1
    property bool _errored: false
    isCliStrategy: true

    function buildEndpoint(model: AiModel): string { return "" }
    function buildAuthorizationHeader(apiKeyEnvVarName: string): string { return "" }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        return {};
    }

    function buildScriptRequestContent(model: AiModel, messages, systemPrompt: string, temperature: real): string {
        const lastUserMsg = [...messages].reverse().find(m => m.role === "user");
        const userMessage = lastUserMsg?.rawContent ?? "";

        // The native installer lands in ~/.local/bin, which a non-login shell
        // may not have on PATH. exec so that killing the request reaches the
        // CLI itself rather than the bash wrapping it. The sandbox stays
        // read-only and the git check off: this is a chat window, not a
        // working tree. No system prompt: exec mode has no supported way to
        // carry one, and the chat reads fine without it.
        let script = "export PATH=\"$HOME/.local/bin:$PATH\"\n";
        script += "exec codex exec";
        if (root.sessionId.length > 0) {
            script += ` resume '${CF.StringUtils.shellSingleQuoteEscape(root.sessionId)}'`;
        }
        script += " --json --sandbox read-only --skip-git-repo-check";
        if (model.model && model.model !== "codex-plan") {
            script += ` -m '${CF.StringUtils.shellSingleQuoteEscape(model.model)}'`;
        }
        script += ` '${CF.StringUtils.shellSingleQuoteEscape(userMessage)}'`;
        script += " < /dev/null 2>&1";
        script += "\n";
        return script;
    }

    function parseResponseLine(line: string, message: AiMessageData) {
        let cleanData = line.trim();
        if (cleanData.length === 0) return {};
        // The CLI announces that it noticed a redirected stdin; chat has
        // nothing to learn from that.
        if (cleanData.startsWith("Reading additional input from stdin")) return {};

        try {
            const json = JSON.parse(cleanData);

            if (json.type === "thread.started") {
                if (json.thread_id) root.sessionId = json.thread_id;
                return {};
            }

            // exec mode delivers whole items, not deltas: the message text
            // and the reasoning summary each arrive once, completed.
            if (json.type === "item.completed") {
                const item = json.item ?? {};
                if (item.type === "agent_message" && item.text) {
                    message.rawContent += item.text;
                    message.content += item.text;
                } else if (item.type === "reasoning" && item.text) {
                    const thought = `\n\n<think>\n\n${item.text}\n\n</think>\n\n`;
                    message.rawContent += thought;
                    message.content += thought;
                }
                return {};
            }

            if (json.type === "turn.completed") {
                const result = { finished: true };
                if (json.usage) {
                    const input = (json.usage.input_tokens ?? 0) + (json.usage.cached_input_tokens ?? 0);
                    result.tokenUsage = {
                        input: input,
                        output: json.usage.output_tokens ?? -1,
                        total: input + (json.usage.output_tokens ?? 0)
                    };
                }
                return result;
            }

            if (json.type === "turn.failed" || json.type === "error") {
                // A dead session pins every retry to the same failure, so
                // the next request starts a fresh one. One failure arrives as
                // both an error event and a failed turn; the reason is only
                // worth reading once.
                root.sessionId = "";
                if (root._errored) return { finished: true };
                root._errored = true;
                const detail = json.error?.message ?? json.message ?? JSON.stringify(json);
                const failure = `**Error**: ${detail}`;
                message.rawContent += failure;
                message.content += failure;
                return { finished: true };
            }

        } catch (e) {
            // Non-JSON line (CLI logging or an error before the stream
            // starts): show it rather than losing it.
            message.rawContent += cleanData + "\n";
            message.content += cleanData + "\n";
        }

        return {};
    }

    function onRequestFinished(message: AiMessageData): var {
        return {};
    }

    function reset() {
        _inputTokens = -1;
        _errored = false;
    }
}
