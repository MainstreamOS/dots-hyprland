import QtQuick
import qs.services
import "strategyhelpers.js" as Helpers
import "sink.js" as Sink

ApiStrategy {
    id: root
    supportsAttachments: true

    readonly property string openTag: "<think>"
    readonly property string closeTag: "</think>"

    function acceptsAttachment(path: string): bool {
        return Helpers.isImage(path);
    }

    function reasoningEffort(level: string, local: bool): string {
        if (local) return ["low", "medium", "high"].includes(level) ? level : "";
        switch (level) {
        case "none": return "none";
        case "minimal": return "low";
        case "low":
        case "medium":
        case "high": return level;
        case "extra": return "xhigh";
        case "max":
        case "ultracode": return "max";
        }
        return "";
    }

    function buildRequest(ctx: var): var {
        const model = ctx.model;
        const messages = ctx.messages ?? [];
        const history = messages.map(message => {
            return {
                "role": message.role,
                "content": message.role === "assistant" ? Ai.historyText(message) : message.rawContent,
            };
        });
        const attachment = ctx.attachment?.path ?? "";
        const lastUser = Helpers.lastUserIndex(messages);
        const file = Helpers.filePlaceholders();
        if (attachment.length > 0 && lastUser >= 0) {
            // run-request.sh fills in the file's type and contents.
            history[lastUser].content = [
                { type: "text", text: history[lastUser].content },
                { type: "image_url", image_url: { url: "data:" + file.mime + ";base64," + file.data } }
            ];
        }
        const baseData = {
            "model": model.model,
            "messages": [
                {role: "system", content: ctx.systemPrompt},
                ...history,
            ],
            "stream": true,
        };
        const tools = ctx.tools ?? [];
        if (tools.length > 0) {
            baseData.tools = tools;
        }
        if (model.sendTemperature) {
            baseData.temperature = ctx.temperature;
        }
        const effort = root.reasoningEffort(ctx.thinkingLevel, (model.endpoint ?? "").includes("localhost"));
        if (effort.length > 0) baseData.reasoning_effort = effort;
        const body = model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;

        const options = ["--report-exit", "--body"];
        if (model.requires_key) options.push("--secret-header", "Authorization", "Bearer ", "API_KEY");
        if (attachment.length > 0) options.push("--inline-file", attachment, "--file-token", file.token);
        return {
            options: options,
            argv: ["curl", "--no-buffer", "--silent", "--show-error", model.endpoint,
                "-H", "Content-Type: application/json", "--data-binary", "@-"],
            stdin: JSON.stringify(body),
            env: {}
        };
    }

    function newState(): var {
        // inTagThink: the open think block was opened by a tag in the content.
        return { inTagThink: false, hold: "", gotAny: false };
    }

    // Length of the end of `text` that could still become `tag`. The sink's
    // helper allows either tag, so the other one is filtered out here.
    function partialTagLength(text: string, tag: string): int {
        const held = Sink.partialTagLength(text);
        return held > 0 && tag.startsWith(text.slice(text.length - held)) ? held : 0;
    }

    // Models served through this format (every Ollama model) may think inside
    // the answer text, so tags in it become think blocks, even when split
    // across chunks.
    function routeContent(content: string, sink: var): void {
        const state = sink.state;
        if (!state.inTagThink) sink.endThink();
        let rest = state.hold + content;
        state.hold = "";
        while (rest.length > 0) {
            const tag = state.inTagThink ? root.closeTag : root.openTag;
            const index = rest.indexOf(tag);
            let part;
            if (index >= 0) {
                part = rest.slice(0, index);
            } else {
                const held = root.partialTagLength(rest, tag);
                part = rest.slice(0, rest.length - held);
                state.hold = rest.slice(rest.length - held);
            }
            if (state.inTagThink) {
                if (part.length > 0) sink.think(part);
            } else if (part.length > 0) {
                sink.text(part);
            }
            if (index < 0) break;
            rest = rest.slice(index + tag.length);
            if (state.inTagThink) {
                state.inTagThink = false;
                sink.endThink();
            } else {
                state.inTagThink = true;
                sink.think("");
            }
        }
    }

    function parseLine(line: string, sink: var): void {
        // Remove 'data: ' prefix if present and trim whitespace
        let cleanData = line.trim();
        if (cleanData.startsWith("data:")) {
            cleanData = cleanData.slice(5).trim();
        }

        if (!cleanData || cleanData.startsWith(":")) return;
        const state = sink.state;
        state.gotAny = true;
        if (cleanData === "[DONE]") {
            sink.finished();
            return;
        }

        let dataJson;
        try {
            dataJson = JSON.parse(cleanData);
        } catch (e) {
            sink.raw(line);
            return;
        }
        try {
            if (dataJson.error) {
                sink.error(dataJson.error.message || JSON.stringify(dataJson.error));
                sink.finished();
                return;
            }

            const delta = dataJson.choices?.[0]?.delta;
            const responseContent = delta?.content || dataJson.message?.content;
            const responseReasoning = delta?.reasoning || delta?.reasoning_content;

            if (responseContent && responseContent.length > 0) {
                root.routeContent(responseContent, sink);
            } else if (responseReasoning && responseReasoning.length > 0) {
                sink.think(responseReasoning);
            }

            if (dataJson.usage) {
                sink.usage({
                    input: dataJson.usage.prompt_tokens ?? -1,
                    output: dataJson.usage.completion_tokens ?? -1,
                    total: dataJson.usage.total_tokens ?? -1
                });
            }

            if (dataJson.done) {
                sink.finished();
            }
        } catch (e) {
            console.warn("[Ai] OpenAI: unexpected response line:", e);
        }
    }

    function finish(sink: var, exitCode: int, stderrTail: string): void {
        const state = sink.state;
        if (state.hold.length > 0) {
            if (state.inTagThink) sink.think(state.hold);
            else sink.text(state.hold);
            state.hold = "";
        }
        if (exitCode !== 0 && !state.gotAny) {
            const detail = Helpers.lastErrorLine(stderrTail);
            if (detail.length > 0) sink.error(detail);
        }
    }
}
