import QtQuick

/**
 * The contract every provider strategy implements. A strategy never writes a
 * message: it builds one request and turns each output line into calls on
 * the sink the Ai service hands it (see sink.js for the sink's methods).
 */
QtObject {
    // Whether this strategy can read a function call back out of a reply.
    // Handing function definitions to one that cannot is a dead end: a capable
    // model answers with a call instead of prose, and nothing renders it.
    property bool supportsFunctions: false

    // CLI-based strategies run a local command instead of a curl request.
    property bool isCliStrategy: false

    // Whether any attachment can be sent; acceptsAttachment() decides per file.
    property bool supportsAttachments: false

    // CLI strategies only. Written only through sink.setSessionId.
    property string sessionId: ""

    property bool loginLapsed: false

    // ctx: {requestId, model (AiModel), messages (AiMessageData[] without
    //       interface messages), unansweredCalls (set of message ids whose
    //       function call has no output message), systemPrompt, temperature,
    //       tools, thinkingLevel (resolved), mode (AiModes id),
    //       grant (null | {scope}), attachment (null | {path, mime}),
    //       regenerate (bool), apiKey, scripts: {filter, runRequest},
    //       dirs: {antigravity, codex, home, runtime}}
    // Returns {options: string[], argv: string[], stdin: string, env: object,
    // keepStdin: bool}. stdin carries the request body (API) or the prompt
    // (CLI); argv never carries either. keepStdin leaves it open for
    // writeInput until endInput.
    function buildRequest(ctx: var): var {
        throw new Error("Not implemented");
    }

    function acceptsAttachment(path: string): bool {
        return supportsAttachments;
    }

    // Per-request parse state; the returned object becomes sink.state.
    function newState(): var {
        return ({});
    }

    // Must not throw; shapes it does not know are ignored.
    function parseLine(line: string, sink: var): void {
    }

    function finish(sink: var, exitCode: int, stderrTail: string): void {
    }

    // The line that answers a step raised with sink.askPermission.
    function permissionAnswer(controlId: string, allow: bool, message: string): string {
        return "";
    }
}
