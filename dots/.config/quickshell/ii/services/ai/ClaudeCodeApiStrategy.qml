import QtQuick
import qs.services
import "strategyhelpers.js" as Helpers

ApiStrategy {
    id: root
    isCliStrategy: true
    supportsAttachments: true

    property var _requestInfo: ({})
    // A denied step otherwise sends the model hunting for workarounds and
    // writing up why each one failed, before the approval card even shows.
    readonly property string askNote: "Actions that change files or run commands need the user's approval, which this session cannot ask for mid-reply: such a tool call is denied, and the user then sees an approval card. When one is denied, stop at once. Do not try another tool or command to get around it. End the reply with one short line naming what needs approval. If the user approves, the next message says so and every step of the task is allowed for that reply, so continue the task from where it stopped."

    // A path that would change what a permission rule matches (a wildcard,
    // a closing paren, a second line) gets no rule.
    function isScopable(value: var): bool {
        return typeof value === "string" && value.length > 0 && !/[\n)*?\[\]\\]/.test(value)
            && !value.endsWith("…[truncated]");
    }

    function pathRule(tool: string, path: var): string {
        return (root.isScopable(path) && path.startsWith("/")) ? `${tool}(/${path})` : "";
    }

    function buildRequest(ctx: var): var {
        const model = ctx.model;
        const mode = ctx.mode ?? "ask";
        const attachment = Helpers.attachmentPath(ctx);
        // A regenerate starts a fresh conversation; its init event replaces the id.
        const sessionId = ctx.regenerate ? "" : root.sessionId;

        const argv = ["claude"];
        if (model.model && model.model !== "claude-code") argv.push("--model", model.model);
        if (sessionId.length > 0) {
            argv.push("--resume", sessionId);
        } else if ((ctx.systemPrompt ?? "").length > 0) {
            argv.push("--system-prompt", ctx.systemPrompt);
        }
        // No positional prompt: -p reads it from stdin.
        argv.push("-p");
        let effort = ctx.thinkingLevel;
        if (effort === "extra") effort = "xhigh";
        else if (effort === "ultracode") effort = "max";
        else if (effort === "minimal") effort = "low";
        if (["low", "medium", "high", "xhigh", "max"].includes(effort)) argv.push("--effort", effort);
        if (Ai.cliPlanState["claude-code"]?.features?.includes("thinking-display")) argv.push("--thinking-display", "summarized");

        // An approval covers the whole next reply, as one approval should
        // carry a task through all of its steps.
        const granted = mode === "auto" || (mode === "ask" && Boolean(ctx.grant));
        // Claude asks before each step that needs approval and waits for the answer.
        const bridged = mode === "ask" && !granted && Boolean(Ai.cliPlanState["claude-code"]?.features?.includes("permission-bridge"));
        root._requestInfo = { mode: mode, modelName: model.name ?? "", bridged: bridged };
        // The file may be outside the working directory, which would raise an
        // approval for every attachment. Variadic, so another flag follows.
        if (attachment.length > 0 && !granted) {
            const rule = root.pathRule("Read", attachment);
            if (rule.length > 0) argv.push("--allowedTools", rule);
        }
        argv.push("--verbose", "--output-format", "stream-json", "--include-partial-messages");
        if (granted) argv.push("--dangerously-skip-permissions");
        else if (mode === "plan") argv.push("--permission-mode", "plan");
        else if (bridged) argv.push("--input-format", "stream-json", "--permission-prompt-tool", "stdio");
        else argv.push("--append-system-prompt", root.askNote);

        const attachedLine = attachment.length > 0 ? Translation.tr("Attached file: %1").arg(attachment) : "";
        const prompt = Helpers.cliPrompt(ctx, m => Ai.historyText(m), Translation.tr("Earlier conversation:"), attachedLine);
        const env = {};
        if (model.requires_key) env.ANTHROPIC_API_KEY = ctx.apiKey ?? Ai.apiKeys?.[model.key_id] ?? "";
        return {
            // Claude Code keys --resume sessions by working directory.
            options: ["--workdir", ctx.dirs.home, "--stdin", "--filter", "claude", "--report-exit"],
            argv: argv,
            stdin: bridged ? JSON.stringify({ type: "user", message: { role: "user", content: prompt } }) + "\n" : prompt,
            keepStdin: bridged,
            env: env
        };
    }

    // Called after buildRequest, so the mode belongs to this request.
    function newState(): var {
        return { input: -1, gotResult: false, mode: root._requestInfo.mode ?? "ask", modelName: root._requestInfo.modelName ?? "", bridged: root._requestInfo.bridged === true };
    }

    function inputTokens(usage: var): int {
        if (usage?.input_tokens === undefined) return -1;
        return usage.input_tokens + (usage.cache_read_input_tokens ?? 0) + (usage.cache_creation_input_tokens ?? 0);
    }

    // What the approval card shows for one tool call.
    function stepCommand(name: string, input: var): string {
        return name === "Bash" ? String(input?.command ?? "") : "";
    }

    function stepTarget(input: var): string {
        return String(input?.file_path ?? input?.notebook_path ?? input?.path ?? input?.url ?? "");
    }

    function raiseDenials(denials: var, sink: var): void {
        const names = [];
        const commands = [];
        const targets = [];
        for (const denial of denials) {
            const name = String(denial?.tool_name ?? "");
            if (name.length === 0) continue;
            if (!names.includes(name)) names.push(name);
            const command = root.stepCommand(name, denial?.tool_input);
            const target = root.stepTarget(denial?.tool_input);
            if (command.length > 0 && !commands.includes(command)) commands.push(command);
            if (target.length > 0 && !targets.includes(target)) targets.push(target);
        }
        if (names.length === 0) return;
        sink.requestConfirmation({
            type: "cli",
            provider: "claude-code",
            action: names.join(", "),
            command: commands.join("\n"),
            target: targets.join("\n"),
            scope: "all",
            grantNote: Translation.tr("Approving lets %1 run commands and edit files without asking for its next reply only.").arg(sink.state.modelName)
        });
    }

    function handleStreamEvent(event: var, sink: var): void {
        const state = sink.state;
        switch (event.type) {
        case "message_start": {
            const input = root.inputTokens(event.message?.usage);
            if (input >= 0) state.input = input;
            break;
        }
        case "content_block_start":
            if (event.content_block?.type === "thinking") sink.think("");
            break;
        case "content_block_delta": {
            const deltaType = event.delta?.type;
            if (deltaType === "text_delta") {
                sink.text(event.delta.text || "");
            } else if (deltaType === "thinking_delta") {
                sink.think(event.delta.thinking || "");
            }
            break;
        }
        case "message_delta":
            if (event.usage) {
                const input = root.inputTokens(event.usage);
                if (input >= 0) state.input = input;
                const output = event.usage.output_tokens ?? -1;
                sink.usage({ input: state.input, output: output, total: Math.max(0, state.input) + Math.max(0, output) });
            }
            break;
        // Every API call inside an agentic run ends with message_stop; only
        // the result event ends the request.
        case "message_stop":
            sink.endThink();
            break;
        }
    }

    function handleControl(json: var, sink: var): void {
        const request = json.request ?? {};
        const id = String(json.request_id ?? "");
        if (request.subtype !== "can_use_tool" || !sink.state.bridged) {
            sink.writeInput(JSON.stringify({ type: "control_response", response: { subtype: "error", request_id: id, error: "unsupported request" } }) + "\n");
            return;
        }
        const name = String(request.tool_name ?? "");
        const target = root.stepTarget(request.input);
        sink.endThink();
        sink.askPermission({
            controlId: id,
            action: String(request.display_name || name),
            command: root.stepCommand(name, request.input),
            target: target.length > 0 ? target : String(request.blocked_path ?? ""),
            scope: "all",
            grantNote: Translation.tr("Approving lets %1 run commands and edit files for the rest of this reply.").arg(sink.state.modelName)
        });
    }

    // Allowing without updatedInput keeps the call as the model wrote it;
    // the stream filter may have shortened the input this side saw.
    function permissionAnswer(controlId: string, allow: bool, message: string): string {
        const response = allow ? { behavior: "allow" } : { behavior: "deny", message: message };
        return JSON.stringify({ type: "control_response", response: { subtype: "success", request_id: controlId, response: response } }) + "\n";
    }

    function handleResult(json: var, sink: var): void {
        const state = sink.state;
        state.gotResult = true;
        // Ends the CLI, which would otherwise wait for another turn.
        if (state.bridged) sink.endInput();
        sink.endThink();
        // A failed run still arrives with subtype "success", and the reason
        // is only in is_error.
        if (json.is_error) {
            // A dead session pins every retry to the same failure.
            sink.setSessionId("");
            sink.error(json.result ?? json.subtype ?? Translation.tr("the request failed"));
        } else if (json.session_id) {
            sink.setSessionId(json.session_id);
        }
        if (json.usage) {
            const input = root.inputTokens(json.usage);
            const output = json.usage.output_tokens ?? -1;
            sink.usage({ input: input, output: output, total: Math.max(0, input) + Math.max(0, output) });
        }
        // Bridged denials are the user's own declines.
        const denials = json.permission_denials ?? [];
        if (state.mode === "ask" && !state.bridged && Array.isArray(denials) && denials.length > 0) {
            root.raiseDenials(denials, sink);
        }
        sink.finished();
    }

    function parseLine(line: string, sink: var): void {
        const cleanData = line.trim();
        if (cleanData.length === 0) return;

        let json;
        try {
            json = JSON.parse(cleanData);
        } catch (e) {
            sink.raw(cleanData);
            return;
        }
        try {
            if (json.type === "result") {
                root.handleResult(json, sink);
            } else if (json.type === "system") {
                if (json.subtype === "init" && json.session_id) sink.setSessionId(json.session_id);
            } else if (json.type === "control_request") {
                root.handleControl(json, sink);
            } else if (json.type === "stream_event") {
                if (json.event?.type) root.handleStreamEvent(json.event, sink);
            } else if (json.type === "error") {
                const detail = typeof json.error === "string" ? json.error
                    : json.error?.message ?? json.message ?? JSON.stringify(json);
                sink.error(detail);
            }
        } catch (e) {
            console.warn("[Ai] Claude Code: unexpected event:", e);
        }
    }

    function finish(sink: var, exitCode: int, stderrTail: string): void {
        if (exitCode === 0 || sink.state.gotResult) return;
        sink.setSessionId("");
        const detail = Helpers.lastErrorLine(stderrTail);
        sink.error(detail.length > 0 ? detail : Translation.tr("%1 stopped with code %2").arg("Claude Code").arg(exitCode));
    }
}
