import QtQuick

QtObject {
    // Whether this strategy can read a function call back out of a reply.
    // Handing function definitions to one that cannot is a dead end: a capable
    // model answers with a call instead of prose, and nothing renders it.
    property bool supportsFunctions: false

    // CLI-based strategies run a local command instead of a curl request.
    // Ai.qml routes on this flag, which is what lets a subscription-backed
    // model sit alongside the key-backed ones rather than replacing them.
    property bool isCliStrategy: false

    function buildEndpoint(model: AiModel): string { throw new Error("Not implemented") }
    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) { throw new Error("Not implemented") }
    function buildAuthorizationHeader(apiKeyEnvVarName: string): string { throw new Error("Not implemented") }
    function parseResponseLine(line: string, message: AiMessageData) { throw new Error("Not implemented") }
    function onRequestFinished(message: AiMessageData): var { return {} } // Default: no special handling
    function reset() { } // Reset any internal state if needed
    function buildScriptFileSetup(filePath) { return "" } // Default: no setup
    function buildScriptRequestContent(model: AiModel, messages, systemPrompt: string, temperature: real): string { return "" } // Override to replace the default curl command
    function finalizeScriptContent(scriptContent: string): string { return scriptContent } // Optionally modify/finalize script
}
