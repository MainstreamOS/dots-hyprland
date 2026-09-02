import QtQuick
import qs.modules.common.functions as CF

ApiStrategy {
    id: root
    property string sessionId: ""
    property bool isThinking: false
    property int _inputTokens: -1
    isCliStrategy: true

    function buildEndpoint(model: AiModel): string { return "" }
    function buildAuthorizationHeader(apiKeyEnvVarName: string): string { return "" }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        return {};
    }

    function buildScriptRequestContent(model: AiModel, messages, systemPrompt: string, temperature: real): string {
        const lastUserMsg = [...messages].reverse().find(m => m.role === "user");
        const userMessage = lastUserMsg?.rawContent ?? "";

        let script = "unset CLAUDECODE\n";
        if (model.requires_key) {
            script += "export ANTHROPIC_API_KEY=\"$API_KEY\"\n";
        }
        // The native installer lands in ~/.local/bin, which a non-login shell
        // may not have on PATH. exec so that killing the request reaches the
        // CLI itself rather than the bash wrapping it.
        script += "export PATH=\"$HOME/.local/bin:$PATH\"\n";
        script += "exec claude";
        if (model.model && model.model !== "claude-code") {
            script += ` --model '${CF.StringUtils.shellSingleQuoteEscape(model.model)}'`;
        }
        if (root.sessionId.length > 0) {
            script += ` --resume '${CF.StringUtils.shellSingleQuoteEscape(root.sessionId)}'`;
        } else if (systemPrompt.length > 0) {
            script += ` --system-prompt '${CF.StringUtils.shellSingleQuoteEscape(systemPrompt)}'`;
        }
        script += ` -p '${CF.StringUtils.shellSingleQuoteEscape(userMessage)}'`;
        script += " --verbose";
        script += " --output-format stream-json";
        script += " --include-partial-messages";
        script += " < /dev/null 2>&1";
        script += "\n";
        return script;
    }

    function parseResponseLine(line: string, message: AiMessageData) {
        let cleanData = line.trim();
        if (cleanData.length === 0) return {};

        try {
            const json = JSON.parse(cleanData);

            // Claude Code result event (top-level, not wrapped)
            if (json.type === "result") {
                if (json.session_id) root.sessionId = json.session_id;
                if (isThinking) {
                    isThinking = false;
                    message.rawContent += "\n\n</think>\n\n";
                    message.content += "\n\n</think>\n\n";
                }
                // A failed run still arrives with subtype "success", and the
                // reason is only in is_error. Reading the subtype alone reports
                // an expired login as an empty answer, which reads as the model
                // having nothing to say. Checked after the thinking block is
                // closed so a failure partway through one does not leave it open.
                if (json.is_error) {
                    // A dead session pins every retry to the same failure, so
                    // the next request starts a fresh one.
                    root.sessionId = "";
                    const failure = `**Error**: ${json.result ?? json.subtype ?? "the request failed"}`;
                    message.rawContent += failure;
                    message.content += failure;
                    return { finished: true };
                }
                const result = { finished: true };
                if (json.usage) {
                    result.tokenUsage = {
                        input: json.usage.input_tokens ?? _inputTokens,
                        output: json.usage.output_tokens ?? -1,
                        total: (json.usage.input_tokens ?? 0) + (json.usage.output_tokens ?? 0)
                    };
                }
                return result;
            }

            // Error event
            if (json.type === "error" || json.error) {
                const errDetail = typeof json.error === "string" ? json.error
                    : json.error?.message ?? json.message ?? JSON.stringify(json);
                const errorMsg = `**Error**: ${errDetail}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true };
            }

            // Claude Code system init event
            if (json.type === "system" && json.subtype === "init") {
                if (json.session_id) root.sessionId = json.session_id;
                return {};
            }

            // Wrapped API stream event
            const event = json.type === "stream_event" ? json.event : json;
            if (!event || !event.type) return {};

            if (event.type === "message_start") {
                if (event.message?.usage?.input_tokens) {
                    _inputTokens = event.message.usage.input_tokens;
                }
                return {};
            }

            if (event.type === "content_block_start") {
                const blockType = event.content_block?.type;
                if (blockType === "thinking" && !isThinking) {
                    isThinking = true;
                    message.rawContent += "\n\n<think>\n\n";
                    message.content += "\n\n<think>\n\n";
                }
                return {};
            }

            if (event.type === "content_block_delta") {
                const deltaType = event.delta?.type;
                if (deltaType === "text_delta") {
                    if (isThinking) {
                        isThinking = false;
                        message.rawContent += "\n\n</think>\n\n";
                        message.content += "\n\n</think>\n\n";
                    }
                    const text = event.delta.text || "";
                    message.rawContent += text;
                    message.content += text;
                } else if (deltaType === "thinking_delta") {
                    if (!isThinking) {
                        isThinking = true;
                        message.rawContent += "\n\n<think>\n\n";
                        message.content += "\n\n<think>\n\n";
                    }
                    const thinking = event.delta.thinking || "";
                    message.rawContent += thinking;
                    message.content += thinking;
                }
                return {};
            }

            if (event.type === "content_block_stop") {
                return {};
            }

            if (event.type === "message_delta") {
                const result = {};
                if (event.usage) {
                    result.tokenUsage = {
                        input: event.usage.input_tokens ?? _inputTokens,
                        output: event.usage.output_tokens ?? -1,
                        total: (event.usage.input_tokens ?? _inputTokens ?? 0) + (event.usage.output_tokens ?? 0)
                    };
                }
                return result;
            }

            if (event.type === "message_stop") {
                if (isThinking) {
                    isThinking = false;
                    message.rawContent += "\n\n</think>\n\n";
                    message.content += "\n\n</think>\n\n";
                }
                return { finished: true };
            }

        } catch (e) {
            // Non-JSON line (likely stderr or plain text output) — show to user
            message.rawContent += cleanData + "\n";
            message.content += cleanData + "\n";
        }

        return {};
    }

    function onRequestFinished(message: AiMessageData): var {
        if (isThinking) {
            isThinking = false;
            message.rawContent += "\n\n</think>\n\n";
            message.content += "\n\n</think>\n\n";
        }
        return {};
    }

    function reset() {
        isThinking = false;
        _inputTokens = -1;
    }
}
