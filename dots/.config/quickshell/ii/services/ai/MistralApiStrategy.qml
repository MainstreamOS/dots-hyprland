import QtQuick
import qs.services
import "strategyhelpers.js" as Helpers

ApiStrategy {
    id: root
    supportsFunctions: true

    function buildRequest(ctx: var): var {
        const model = ctx.model;
        const unanswered = ctx.unansweredCalls ?? {};
        const history = [];
        // A tool message must answer the call right before it, by that call's id.
        let pendingCallId = "";
        for (const message of (ctx.messages ?? [])) {
            const hasCall = message.functionCall != undefined && message.functionName.length > 0;
            const callId = message.functionCallId ?? "";
            if (hasCall && callId.length > 0 && !unanswered[message.id]) {
                pendingCallId = callId;
                history.push({
                    "role": "assistant",
                    "content": "",
                    "tool_calls": [{
                        "id": callId,
                        "type": "function",
                        "function": {
                            "name": message.functionName,
                            "arguments": JSON.stringify(message.functionArgs ?? {})
                        }
                    }]
                });
                continue;
            }
            if (!hasCall && message.functionName.length > 0 && pendingCallId.length > 0) {
                history.push({
                    "role": "tool",
                    "name": message.functionName,
                    "content": message.functionResponse,
                    "tool_call_id": pendingCallId
                });
                pendingCallId = "";
                continue;
            }
            pendingCallId = "";
            history.push({
                "role": message.role,
                "content": message.role === "assistant" ? Ai.historyText(message) : message.rawContent,
            });
        }
        const baseData = {
            "model": model.model,
            "messages": [
                {role: "system", content: ctx.systemPrompt},
                ...history,
            ],
            "stream": true,
            "temperature": ctx.temperature,
        };
        const tools = ctx.tools ?? [];
        if (tools.length > 0) {
            baseData.tools = tools;
        }
        const body = model.extraParams ? Object.assign({}, baseData, model.extraParams) : baseData;

        const options = ["--report-exit", "--body"];
        if (model.requires_key) options.push("--secret-header", "Authorization", "Bearer ", "API_KEY");
        return {
            options: options,
            argv: ["curl", "--no-buffer", "--silent", "--show-error", model.endpoint,
                "-H", "Content-Type: application/json", "--data-binary", "@-"],
            stdin: JSON.stringify(body),
            env: {}
        };
    }

    function newState(): var {
        return { gotAny: false };
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
            const toolCall = delta?.tool_calls?.[0];
            if (toolCall) {
                const functionName = toolCall.function?.name ?? "";
                const rawArgs = toolCall.function?.arguments;
                let functionArgs = {};
                try {
                    functionArgs = (typeof rawArgs === "string" ? JSON.parse(rawArgs) : rawArgs) || {};
                } catch (e) {
                    sink.error(Translation.tr("Could not read the arguments of %1").arg(functionName));
                    return;
                }
                // The sink skips a call without a name, which still ends the thoughts.
                sink.endThink();
                sink.functionCall({ name: functionName, args: functionArgs, id: toolCall.id ?? "" });
                return;
            }

            const responseContent = delta?.content || dataJson.message?.content;
            const responseReasoning = delta?.reasoning || delta?.reasoning_content;
            if (responseContent && responseContent.length > 0) {
                sink.text(responseContent);
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
            console.warn("[Ai] Mistral: unexpected response line:", e);
        }
    }

    function finish(sink: var, exitCode: int, stderrTail: string): void {
        if (exitCode !== 0 && !sink.state.gotAny) {
            const detail = Helpers.lastErrorLine(stderrTail);
            if (detail.length > 0) sink.error(detail);
        }
    }
}
