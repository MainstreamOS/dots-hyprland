import QtQuick

ApiStrategy {
    id: root
    property bool isThinking: false
    property int _inputTokens: -1

    function buildEndpoint(model: AiModel): string {
        return model.endpoint;
    }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        return {
            "model": model.model,
            "max_tokens": 8192,
            "system": systemPrompt,
            "messages": messages.map(message => {
                return { "role": message.role, "content": message.rawContent };
            }),
            "temperature": Math.min(temperature, 1.0),
            "stream": true,
        };
    }

    function buildAuthorizationHeader(apiKeyEnvVarName: string): string {
        return `-H "x-api-key: \$\{${apiKeyEnvVarName}\}" -H "anthropic-version: 2023-06-01"`;
    }

    function parseResponseLine(line: string, message: AiMessageData) {
        let cleanData = line.trim();
        if (cleanData.length === 0 || cleanData.startsWith("event:") || cleanData.startsWith(":")) return {};
        if (cleanData.startsWith("data:")) {
            cleanData = cleanData.slice(5).trim();
        }

        try {
            const json = JSON.parse(cleanData);

            if (json.type === "error") {
                const errDetail = json.error?.message ?? JSON.stringify(json.error ?? json);
                const errorMsg = `**Error**: ${errDetail}`;
                message.rawContent += errorMsg;
                message.content += errorMsg;
                return { finished: true };
            }

            if (json.type === "message_start") {
                if (json.message?.usage?.input_tokens) {
                    _inputTokens = json.message.usage.input_tokens;
                }
                return {};
            }

            if (json.type === "content_block_start") {
                if (json.content_block?.type === "thinking" && !isThinking) {
                    isThinking = true;
                    message.rawContent += "\n\n<think>\n\n";
                    message.content += "\n\n<think>\n\n";
                }
                return {};
            }

            if (json.type === "content_block_delta") {
                const deltaType = json.delta?.type;
                if (deltaType === "text_delta") {
                    if (isThinking) {
                        isThinking = false;
                        message.rawContent += "\n\n</think>\n\n";
                        message.content += "\n\n</think>\n\n";
                    }
                    const text = json.delta.text || "";
                    message.rawContent += text;
                    message.content += text;
                } else if (deltaType === "thinking_delta") {
                    if (!isThinking) {
                        isThinking = true;
                        message.rawContent += "\n\n<think>\n\n";
                        message.content += "\n\n<think>\n\n";
                    }
                    const thinking = json.delta.thinking || "";
                    message.rawContent += thinking;
                    message.content += thinking;
                }
                return {};
            }

            if (json.type === "message_delta") {
                if (json.usage) {
                    return {
                        tokenUsage: {
                            input: _inputTokens,
                            output: json.usage.output_tokens ?? -1,
                            total: (_inputTokens < 0 ? 0 : _inputTokens) + (json.usage.output_tokens ?? 0)
                        }
                    };
                }
                return {};
            }

            if (json.type === "message_stop") {
                if (isThinking) {
                    isThinking = false;
                    message.rawContent += "\n\n</think>\n\n";
                    message.content += "\n\n</think>\n\n";
                }
                return { finished: true };
            }

        } catch (e) {
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
