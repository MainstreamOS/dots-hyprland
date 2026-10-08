import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF

ApiStrategy {
    id: root
    property string sessionId: ""
    property bool _errored: false
    property bool _finished: false
    property bool _streamed: false
    property int _lastStepIndex: -1
    // Handed in translated by Ai.qml, which has the translation service
    // this module does not import.
    property string exitText: "Antigravity stopped with code %1"
    property string lapsedText: "Gemini could not use your Google sign-in. Log in again to keep chatting."
    property string workDir: ""
    // Set when a run fails its sign-in. Ai.qml clears it and checks the plan
    // again, which then offers the sign-in instead of failing every message.
    property bool loginLapsed: false
    isCliStrategy: true

    function buildEndpoint(model: AiModel): string { return "" }
    function buildAuthorizationHeader(apiKeyEnvVarName: string): string { return "" }

    function buildRequestData(model: AiModel, messages, systemPrompt: string, temperature: real, tools: list<var>, filePath: string) {
        return {};
    }

    function quote(text: string): string {
        return `'${CF.StringUtils.shellSingleQuoteEscape(text)}'`;
    }

    function buildScriptRequestContent(model: AiModel, messages, systemPrompt: string, temperature: real): string {
        const lastUserMsg = [...messages].reverse().find(m => m.role === "user");
        const userMessage = lastUserMsg?.rawContent ?? "";

        let script = "export PATH=\"$HOME/.local/bin:$PATH\"\n";
        // The CLI treats the folder it runs in as the workspace the model may
        // read. An empty folder of its own keeps the user's files out of the
        // chat. No system prompt: print mode has no way to carry one.
        script += "dir=\"" + root.workDir + "\"\n";
        script += "mkdir -p \"$dir\" && cd \"$dir\" || exit 1\n";

        // The = form keeps a message or id that starts with a dash from being
        // read as another flag, and a message that starts with a slash stays
        // a message rather than one of the CLI's own commands. A conversation
        // the CLI no longer has only draws a warning and starts a new one.
        const mode = Config.options?.ai?.mode ?? "safe";
        let command = "agy --output-format=stream-json";
        if (mode === "yolo") {
            command += " --disable-slash-commands --dangerously-skip-permissions";
        } else if (mode === "plan") {
            command += " --mode=plan --dangerously-skip-permissions";
        } else {
            command += " --disable-slash-commands";
        }
        if (root.sessionId.length > 0) command += ` --conversation=${root.quote(root.sessionId)}`;
        if (model.model && model.model !== "gemini-plan") {
            command += ` --model=${root.quote(model.model)}`;
            if (model.model.startsWith("gemini-")) {
                let effort = (Ai.thinkingLevel || model.thinkingLevel || "medium").toLowerCase();
                if (effort === "minimal") effort = "low";
                if (!["low", "medium", "high"].includes(effort)) effort = "medium";
                if (model.model.includes("3.1-pro") && effort === "medium") effort = "high";
                command += ` --effort=${root.quote(effort)}`;
            }
        }
        command += ` --print=${root.quote(userMessage)}`;

        // Kept off stdout so the chat reads only the event stream, and shown
        // only when the run fails, since that is when it says why. The trap
        // hands a stopped request on to the CLI, which a plain exec would do
        // but then nothing could report the failure afterwards.
        script += `${command} < /dev/null 2> last-error.log &\n`;
        script += "pid=$!\n";
        script += "trap 'kill \"$pid\" 2>/dev/null; exit 143' TERM INT HUP\n";
        script += "wait \"$pid\"; code=$?\n";
        script += "if [ \"$code\" -ne 0 ]; then\n";
        script += "    jq -cRs --argjson code \"$code\" '{event: \"cli_exit\", code: $code, stderr: .}' < last-error.log\n";
        script += "fi\n";
        return script;
    }

    function append(message: AiMessageData, text: string) {
        message.rawContent += text;
        message.content += text;
    }

    function fail(message: AiMessageData, detail: string) {
        const lapsed = root.isSignInError(detail);
        if (lapsed) root.loginLapsed = true;
        if (root._errored) return;
        root._errored = true;
        root.append(message, `**Error**: ${lapsed ? root.lapsedText : detail}`);
    }

    function isSignInError(text: string): bool {
        return /authenticat|sign in|signed out|log ?in/i.test(text);
    }

    function parseResponseLine(line: string, message: AiMessageData): var {
        const cleanData = line.trim();
        if (cleanData.length === 0) return {};

        let json;
        try {
            json = JSON.parse(cleanData);
        } catch (e) {
            // stdout carries only the event stream, so anything else is
            // unexpected and worth seeing rather than dropping.
            root.append(message, cleanData + "\n");
            return {};
        }

        switch (json.event) {
        case "init": {
            const id = json.init?.conversation_id ?? json.conversation_id;
            if (id) root.sessionId = id;
            return {};
        }
        case "step_update": {
            // The prompt and tool steps stream too; only the reply belongs in
            // the chat.
            const step = json.step_update ?? {};
            if (step.step_type === "agent_response" && step.text_delta) {
                // Only separate distinct agent steps (e.g. before/after tool execution),
                // not partial text deltas streaming within the same step.
                if (root._lastStepIndex !== -1 && step.step_index !== undefined && step.step_index !== root._lastStepIndex) {
                    if (message.content.length > 0 && !message.content.endsWith("\n")) {
                        root.append(message, "\n\n");
                    }
                }
                if (step.step_index !== undefined) {
                    root._lastStepIndex = step.step_index;
                }
                root._streamed = true;
                root.append(message, step.text_delta);
            }
            return {};
        }
        case "result": {
            const result = json.result ?? {};
            root._finished = true;
            if (result.conversation_id) root.sessionId = result.conversation_id;
            if (result.status !== "SUCCESS") {
                const detail = result.error || result.status || JSON.stringify(result);
                root.fail(message, detail);
                return { finished: true };
            }
            // If nothing was streamed yet, use result.response as fallback.
            if (!root._streamed) {
                if (result.response) {
                    root.append(message, result.response);
                } else if (result.denied_actions && result.denied_actions.length > 0) {
                    const denied = result.denied_actions.map(a => a.display_name || a.action).join(", ");
                    root.fail(message, `Action denied (${denied}).`);
                }
            } else if (result.denied_actions && result.denied_actions.length > 0 && !result.response) {
                const denied = result.denied_actions.map(a => a.display_name || a.action).join(", ");
                root.fail(message, `Action denied (${denied}).`);
            }
            const done = { finished: true };
            if (result.usage) {
                done.tokenUsage = {
                    input: result.usage.input_tokens ?? -1,
                    output: result.usage.output_tokens ?? -1,
                    total: result.usage.total_tokens ?? -1
                };
            }
            return done;
        }
        case "cli_exit": {
            // A turn the CLI reported itself already ended the request and
            // said why.
            if (root._finished) return {};
            // The run ended before it could report anything: a crash, or a
            // conversation that cannot be resumed and would fail every retry
            // the same way, so the next request starts a fresh one.
            root.sessionId = "";
            // The CLI ends a failure with an `error:` line of its own, after
            // progress notes and a structured line meant for scripts.
            const lines = (json.stderr ?? "").replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").split("\n")
                .map(l => l.trim()).filter(l => l.length > 0);
            const marked = lines.filter(l => l.startsWith("error:")).map(l => l.slice(6).trim());
            const detail = marked.length > 0 ? marked[marked.length - 1]
                : (lines.length > 0 ? lines[lines.length - 1] : root.exitText.arg(json.code));
            root.fail(message, detail);
            return { finished: true };
        }
        }
        return {};
    }

    function onRequestFinished(message: AiMessageData): var {
        return { finished: true };
    }

    function reset() {
        _errored = false;
        _finished = false;
        _streamed = false;
        _lastStepIndex = -1;
    }
}
