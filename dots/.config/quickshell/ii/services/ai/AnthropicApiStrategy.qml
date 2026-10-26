import QtQuick
import qs.services
import "strategyhelpers.js" as Helpers

ApiStrategy {
    id: root
    supportsAttachments: true

    function acceptsAttachment(path: string): bool {
        return Helpers.isImage(path) || Helpers.extension(path) === "pdf";
    }

    // Models that take adaptive thinking and output_config.effort; budget_tokens
    // and sampling parameters are rejected by most of them.
    function isCurrentModel(id: string): bool {
        return /^claude-(opus|fable|sonnet|haiku)-5/.test(id) || /^claude-opus-4-[6-9]/.test(id) || id.startsWith("claude-sonnet-4-6");
    }

    function effortFor(level: string, id: string): string {
        // xhigh arrived with Opus 4.7.
        const noXhigh = id.startsWith("claude-opus-4-6") || id.startsWith("claude-sonnet-4-6");
        switch (level) {
        case "low":
        case "medium":
        case "high": return level;
        case "extra": return noXhigh ? "high" : "xhigh";
        case "max":
        case "ultracode": return "max";
        case "minimal":
        case "none": return "low";
        }
        return "";
    }

    function buildRequest(ctx: var): var {
        const model = ctx.model;
        const messages = (ctx.messages ?? []).map(message => {
            return {
                "role": message.role,
                "content": message.role === "assistant" ? Ai.historyText(message) : message.rawContent
            };
        });
        const files = Helpers.historyFiles(ctx, path => root.acceptsAttachment(path));
        for (const file of files) {
            messages[file.index].content = [
                {
                    "type": Helpers.extension(file.path) === "pdf" ? "document" : "image",
                    "source": { "type": "base64", "media_type": file.mime, "data": file.data }
                },
                { "type": "text", "text": messages[file.index].content }
            ];
        }
        // Empty text blocks are rejected, and a stopped reply can leave one behind.
        const history = messages.filter(message => typeof message.content !== "string" || message.content.length > 0);

        const req = {
            "model": model.model,
            "max_tokens": 8192,
            "messages": history,
            "stream": true,
        };
        if ((ctx.systemPrompt ?? "").length > 0) req.system = ctx.systemPrompt;
        const level = ctx.thinkingLevel;
        if (root.isCurrentModel(model.model)) {
            req.max_tokens = 64000;
            req.thinking = { "type": "adaptive", "display": "summarized" };
            const effort = root.effortFor(level, model.model);
            if (effort.length > 0) req.output_config = { "effort": effort };
        } else if (level && level !== "default" && level !== "off") {
            const budgets = {
                "low": 1024,
                "medium": 2048,
                "high": 4096,
                "extra": 8192,
                "max": 16384,
                "ultracode": 32768
            };
            const budget = budgets[level] || 2048;
            req.thinking = {
                "type": "enabled",
                "budget_tokens": budget
            };
            req.max_tokens = Math.max(8192, budget + 4096);
        } else if (model.sendTemperature) {
            req.temperature = Math.min(ctx.temperature, 1.0);
        }

        const options = ["--report-exit", "--body", "--secret-header", "x-api-key", "", "API_KEY"];
        options.push(...Helpers.fileOptions(files));
        return {
            options: options,
            argv: ["curl", "--no-buffer", "--silent", "--show-error", model.endpoint,
                "-H", "Content-Type: application/json", "-H", "anthropic-version: 2023-06-01",
                "--data-binary", "@-"],
            stdin: JSON.stringify(req),
            env: {}
        };
    }

    function newState(): var {
        return { input: -1, gotAny: false };
    }

    function parseLine(line: string, sink: var): void {
        let cleanData = line.trim();
        if (cleanData.length === 0 || cleanData.startsWith("event:") || cleanData.startsWith(":")) return;
        if (cleanData.startsWith("data:")) {
            cleanData = cleanData.slice(5).trim();
        }
        const state = sink.state;
        state.gotAny = true;

        let json;
        try {
            json = JSON.parse(cleanData);
        } catch (e) {
            sink.raw(cleanData);
            return;
        }
        try {
            switch (json.type) {
            case "error":
                sink.error(json.error?.message ?? JSON.stringify(json.error ?? json));
                sink.finished();
                break;
            case "message_start": {
                const usage = json.message?.usage;
                if (usage?.input_tokens !== undefined) {
                    state.input = usage.input_tokens + (usage.cache_read_input_tokens ?? 0) + (usage.cache_creation_input_tokens ?? 0);
                }
                break;
            }
            case "content_block_start":
                if (json.content_block?.type === "thinking") sink.think("");
                break;
            case "content_block_delta": {
                const deltaType = json.delta?.type;
                if (deltaType === "text_delta") {
                    sink.text(json.delta.text || "");
                } else if (deltaType === "thinking_delta") {
                    sink.think(json.delta.thinking || "");
                }
                break;
            }
            case "message_delta": {
                const usage = json.usage;
                if (usage) {
                    if (usage.input_tokens !== undefined) {
                        state.input = usage.input_tokens + (usage.cache_read_input_tokens ?? 0) + (usage.cache_creation_input_tokens ?? 0);
                    }
                    const output = usage.output_tokens ?? -1;
                    sink.usage({
                        input: state.input,
                        output: output,
                        total: Math.max(0, state.input) + Math.max(0, output)
                    });
                }
                if (json.delta?.stop_reason === "refusal") {
                    sink.error(Translation.tr("The model declined this request."));
                }
                break;
            }
            case "message_stop":
                sink.endThink();
                sink.finished();
                break;
            }
        } catch (e) {
            console.warn("[Ai] Anthropic: unexpected response line:", e);
        }
    }

    function finish(sink: var, exitCode: int, stderrTail: string): void {
        if (exitCode !== 0 && !sink.state.gotAny) {
            const detail = Helpers.lastErrorLine(stderrTail);
            if (detail.length > 0) sink.error(detail);
        }
    }
}
