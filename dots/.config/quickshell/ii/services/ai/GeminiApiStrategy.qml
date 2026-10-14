import QtQuick
import qs.services
import "strategyhelpers.js" as Helpers

ApiStrategy {
    id: root
    supportsFunctions: true
    supportsAttachments: true

    property bool _usedSearch: false

    function buildRequest(ctx: var): var {
        const model = ctx.model;
        const tools = ctx.tools ?? [];
        const usingSearch = tools[0]?.google_search !== undefined;
        // 2.5 searches on the free tier, so only a Gemini 3 or 4 refusal is about billing.
        root._usedSearch = usingSearch && (model.model.startsWith("gemini-3") || model.model.startsWith("gemini-4") || model.model.endsWith("-latest"));
        const unanswered = ctx.unansweredCalls ?? {};
        // Gemini 3 answers a functionResponse only when it carries its call's id.
        let lastCallId = "";
        const contents = (ctx.messages ?? []).map(message => {
            const geminiApiRoleName = (message.role === "assistant") ? "model" : message.role;
            const hasCall = message.functionCall != undefined && message.functionName.length > 0;
            if (!usingSearch && hasCall && !unanswered[message.id]) {
                lastCallId = message.functionCallId ?? "";
                const callPart = {
                    functionCall: {
                        "name": message.functionName,
                        "args": message.functionArgs ?? {}
                    }
                };
                if (lastCallId.length > 0) callPart.functionCall.id = lastCallId;
                if (message.functionThoughtSignature && message.functionThoughtSignature.length > 0) {
                    callPart.thoughtSignature = message.functionThoughtSignature;
                }
                return {
                    "role": geminiApiRoleName,
                    "parts": [callPart]
                };
            }
            if (!usingSearch && !hasCall && message.functionName.length > 0) {
                const responsePart = {
                    "name": message.functionName,
                    "response": { "content": message.functionResponse }
                };
                if (lastCallId.length > 0) responsePart.id = lastCallId;
                return {
                    "role": geminiApiRoleName,
                    "parts": [{ functionResponse: responsePart }]
                };
            }
            return {
                "role": geminiApiRoleName,
                "parts": [
                    { text: message.role === "assistant" ? Ai.historyText(message) : message.rawContent },
                    ...(message.fileUri && message.fileUri.length > 0 ? [{
                        "file_data": {
                            "mime_type": message.fileMimeType,
                            "file_uri": message.fileUri
                        }
                    }] : [])
                ]
            };
        });
        const attachment = ctx.attachment?.path ?? "";
        const file = Helpers.filePlaceholders();
        if (attachment.length > 0 && contents.length > 0) {
            // run-request.sh uploads the file and fills these in.
            contents[contents.length - 1].parts.unshift({
                file_data: {
                    mime_type: file.mime,
                    file_uri: file.uri
                }
            });
        }
        // Gemini 3 series deprecates sampling parameters (temperature, top_p, top_k)
        // and thinking_budget in favor of thinking_level ("minimal", "low", "medium", "high").
        let generationConfig = {};
        const chosenThinkingLevel = ctx.thinkingLevel;
        if (Ai.thinkingLevels.includes(chosenThinkingLevel)) {
            let geminiLevel = chosenThinkingLevel;
            if (geminiLevel === "extra" || geminiLevel === "max" || geminiLevel === "ultracode") {
                geminiLevel = "high";
            } else if (geminiLevel === "none") {
                geminiLevel = "minimal";
            }
            // Models like Pro, Argon, and latest series support low, medium, high. Clamp minimal to low.
            if (geminiLevel === "minimal" && (model.model.includes("pro") || model.model.includes("3.8") || model.model.includes("argon") || model.model.endsWith("-latest"))) {
                geminiLevel = "low";
            }
            if (["minimal", "low", "medium", "high"].includes(geminiLevel)) {
                generationConfig.thinkingConfig = {
                    thinkingLevel: geminiLevel,
                    includeThoughts: true
                };
            } else {
                generationConfig.thinkingConfig = {
                    includeThoughts: true
                };
            }
        } else {
            generationConfig.thinkingConfig = {
                includeThoughts: true
            };
        }

        // Sanitize any extraParams so deprecated parameters are never passed
        const budgetKeys = ["thinking_budget", "thinkingBudget"];
        const retiredKeys = ["temperature", "top_p", "top_k"].concat(budgetKeys);
        const without = (obj, keys) => {
            const copy = Object.assign({}, obj);
            for (const key of keys) delete copy[key];
            return copy;
        };
        const extra = without(model.extraParams ?? {}, retiredKeys);
        if (extra.generationConfig) {
            const extraGen = without(extra.generationConfig, retiredKeys);
            if (extraGen.thinkingConfig) {
                extraGen.thinkingConfig = without(extraGen.thinkingConfig, budgetKeys);
                extraGen.thinkingConfig.includeThoughts = true;
            }
            generationConfig = Object.assign(generationConfig, extraGen);
            delete extra.generationConfig;
        }

        const baseData = {
            "contents": contents,
            "tools": tools,
            "system_instruction": {
                "parts": [{ text: ctx.systemPrompt }]
            },
            "generationConfig": generationConfig
        };
        const body = Object.assign({}, baseData, extra);

        const options = ["--report-exit", "--body", "--secret-header", "x-goog-api-key", "", "API_KEY"];
        if (attachment.length > 0) options.push("--upload-gemini", attachment, "--file-token", file.token);
        return {
            options: options,
            argv: ["curl", "--no-buffer", "--silent", "--show-error", model.endpoint,
                "-H", "Content-Type: application/json", "--data-binary", "@-"],
            stdin: JSON.stringify(body),
            env: {}
        };
    }

    // Called after buildRequest, so the search flag belongs to this request.
    function newState(): var {
        return { buffer: "", usedSearch: root._usedSearch, gotAny: false };
    }

    function parseLine(line: string, sink: var): void {
        const state = sink.state;
        if (line.startsWith("[")) {
            state.buffer += line.slice(1).trim();
        } else if (line === "]") {
            root.parseBuffer(sink);
        } else if (line.startsWith(",")) {
            root.parseBuffer(sink);
        } else {
            state.buffer += line.trim();
        }
    }

    function parseBuffer(sink: var): void {
        const state = sink.state;
        const buffer = state.buffer;
        state.buffer = "";
        if (buffer.length === 0) return;
        let dataJson;
        try {
            dataJson = JSON.parse(buffer);
        } catch (e) {
            state.gotAny = true;
            sink.raw(buffer);
            return;
        }
        try {
            root.handleChunk(dataJson, sink);
        } catch (e) {
            console.warn("[Ai] Gemini: unexpected response chunk:", e);
        }
    }

    function handleChunk(dataJson: var, sink: var): void {
        const state = sink.state;
        state.gotAny = true;

        if (dataJson.uploadedFile) {
            sink.uploadedFile(dataJson.uploadedFile.uri, dataJson.uploadedFile.mimeType);
            return;
        }

        if (dataJson.error) {
            if (dataJson.error.code === 429 && state.usedSearch) sink.searchRefused();
            sink.error(dataJson.error.message ?? JSON.stringify(dataJson.error), "Error " + dataJson.error.code);
            sink.finished();
            return;
        }

        const candidate = dataJson.candidates?.[0];
        if (candidate) {
            const parts = candidate.content?.parts ?? [];
            for (const part of parts) {
                if (part.functionCall) {
                    // The sink skips a call without a name, which still ends the thoughts.
                    sink.endThink();
                    const functionCall = part.functionCall;
                    sink.functionCall({
                        name: functionCall.name,
                        args: functionCall.args ?? {},
                        id: functionCall.id ?? "",
                        thoughtSignature: part.thoughtSignature ?? functionCall.thoughtSignature ?? ""
                    });
                    break;
                }
                if (part.thought) {
                    const thoughtText = typeof part.thought === "string" ? part.thought : (part.text || "");
                    sink.think(thoughtText);
                } else if (part.text) {
                    sink.text(part.text);
                }
            }

            const grounding = candidate.groundingMetadata;
            if (grounding) {
                const annotationSources = grounding.groundingChunks?.map(chunk => {
                    return {
                        "type": "url_citation",
                        "text": chunk?.web?.title,
                        "url": chunk?.web?.uri,
                    };
                }) ?? [];
                const annotations = grounding.groundingSupports?.map(citation => {
                    return {
                        "type": "url_citation",
                        "start_index": citation.segment?.startIndex,
                        "end_index": citation.segment?.endIndex,
                        "text": citation?.segment?.text,
                        "url": annotationSources[citation.groundingChunkIndices?.[0]]?.url,
                        "sources": citation.groundingChunkIndices
                    };
                }) ?? [];
                sink.setAnnotations(annotationSources, annotations, grounding.webSearchQueries ?? []);
            }
        }

        if (dataJson.usageMetadata) {
            sink.usage({
                input: dataJson.usageMetadata.promptTokenCount ?? -1,
                output: dataJson.usageMetadata.candidatesTokenCount ?? -1,
                total: dataJson.usageMetadata.totalTokenCount ?? -1
            });
        }

        if (candidate?.finishReason) {
            sink.endThink();
            sink.finished();
        }
    }

    function finish(sink: var, exitCode: int, stderrTail: string): void {
        root.parseBuffer(sink);
        if (exitCode !== 0 && !sink.state.gotAny) {
            const detail = Helpers.lastErrorLine(stderrTail);
            if (detail.length > 0) sink.error(detail);
        }
    }
}
