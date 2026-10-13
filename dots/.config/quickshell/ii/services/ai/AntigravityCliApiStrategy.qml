import QtQuick
import qs.services
import "strategyhelpers.js" as Helpers

ApiStrategy {
    id: root
    isCliStrategy: true
    supportsAttachments: true

    readonly property var writeTools: ["replace_file_content", "write_to_file", "multi_replace_file_content", "sed_file"]
    // A denied action names its permission category, not the tool that asked.
    readonly property var editActions: ["write_file"]
    property var _requestInfo: ({})

    // stream-json input takes one NDJSON message per turn; the print flag
    // still has to be present, with an empty value.
    function stdinMessage(prompt: string): string {
        return JSON.stringify({ event: "user", message: { role: "user", content: [{ type: "text", text: prompt }] } }) + "\n";
    }

    function buildRequest(ctx: var): var {
        const model = ctx.model;
        const mode = ctx.mode ?? "ask";
        const attachment = Helpers.attachmentPath(ctx);
        // A regenerate starts a fresh conversation; its init event replaces the id.
        const sessionId = ctx.regenerate ? "" : root.sessionId;
        root._requestInfo = { mode: mode, modelName: model.name ?? "" };

        // The = form keeps a value that starts with a dash or a slash from
        // being read as a flag. A conversation the CLI no longer has only
        // draws a warning and starts a new one.
        const argv = ["agy", "--output-format=stream-json", "--input-format=stream-json"];
        if (mode === "plan") {
            // agy ignores Plan mode while slash commands are off.
            argv.push("--mode=plan");
        } else {
            argv.push("--disable-slash-commands");
            // agy has no narrower grant that holds outside its own folder.
            if (mode === "auto" || ctx.grant) argv.push("--dangerously-skip-permissions");
        }
        if (sessionId.length > 0) argv.push("--conversation=" + sessionId);
        if (model.model && model.model !== "gemini-plan") {
            argv.push("--model=" + model.model);
            if (model.model.startsWith("gemini-")) {
                let effort = ctx.thinkingLevel || "medium";
                if (effort === "extra") effort = "xhigh";
                else if (effort === "ultracode") effort = "max";
                else if (effort === "minimal" || effort === "none") effort = "low";
                if (!["low", "medium", "high", "xhigh", "max"].includes(effort)) effort = "medium";
                if (model.model.includes("3.1-pro") && effort === "medium") effort = "high";
                argv.push("--effort=" + effort);
            }
        }
        argv.push("--print=");

        const attachedLine = attachment.length > 0 ? Translation.tr("Attached file: %1").arg(attachment) : "";
        const prompt = Helpers.cliPrompt(ctx, m => Ai.historyText(m), Translation.tr("Earlier conversation:"), attachedLine);
        return {
            // The CLI treats the folder it runs in as the workspace the model
            // may read; an empty folder of its own keeps the user's files out.
            options: ["--workdir", ctx.dirs.antigravity, "--stdin", "--filter", "agy", "--diff", "--report-exit"],
            argv: argv,
            stdin: root.stdinMessage(prompt),
            env: {}
        };
    }

    // Called after buildRequest, so the mode belongs to this request.
    function newState(): var {
        return {
            gotResult: false,
            streamed: false,
            lastStepIndex: -1,
            textOpenLine: false,
            toolSteps: [],
            mode: root._requestInfo.mode ?? "ask",
            modelName: root._requestInfo.modelName ?? ""
        };
    }

    function isSignInError(text: string): bool {
        return /authenticat|sign in|signed out|log ?in/i.test(text);
    }

    function fail(sink: var, detail: string): void {
        if (root.isSignInError(detail)) {
            sink.loginLapsed();
            sink.error(Translation.tr("Gemini could not use your Google sign-in. Log in again to keep chatting."));
        } else {
            sink.error(detail);
        }
    }

    function emitText(sink: var, text: string): void {
        const state = sink.state;
        state.streamed = true;
        sink.text(text);
        state.textOpenLine = !text.endsWith("\n");
    }

    function activity(sink: var, record: var): void {
        const state = sink.state;
        state.streamed = true;
        state.textOpenLine = false;
        sink.activity(record);
    }

    function filePathOf(params: var): string {
        return Helpers.cleanPath(params.TargetFile || params.targetFile || params.AbsolutePath || params.absolutePath || params.path || params.file || "");
    }

    function rememberStep(state: var, step: var, toolName: string, params: var, path: string): void {
        const entry = {
            index: step.step_index,
            toolName: toolName,
            command: typeof params.CommandLine === "string" ? params.CommandLine : "",
            target: path,
            state: step.state ?? ""
        };
        const steps = state.toolSteps;
        const last = steps[steps.length - 1];
        if (last && entry.index !== undefined && last.index === entry.index) steps[steps.length - 1] = entry;
        else steps.push(entry);
    }

    function handleToolStep(step: var, sink: var): void {
        const state = sink.state;
        const toolInfo = step.tool_info || {};
        const params = toolInfo.parameters || step.parameters || {};
        const toolName = step.tool_name || toolInfo.name || "Action";
        const fp = root.filePathOf(params);
        root.rememberStep(state, step, toolName, params, fp);

        const absolute = fp.startsWith("/") ? fp : "";
        if (root.writeTools.includes(toolName)) {
            // The stream filter marks a write that changed nothing, such as a refused one.
            if (step.state !== "DONE" || toolInfo.skipped) return;
            const diff = toolInfo.diff ?? {};
            root.activity(sink, { kind: "edit", verb: toolInfo.verb || "Edited", target: Helpers.basename(fp) || "Action", path: absolute, added: diff.added ?? -1, removed: diff.deleted ?? -1 });
            return;
        }

        if (step.state !== "ACTIVE") return;
        if (toolName === "view_file") {
            const range = (params.StartLine && params.EndLine) ? `#L${params.StartLine}-${params.EndLine}` : "";
            root.activity(sink, { kind: "read", verb: "Analyzed", target: Helpers.basename(fp) || "Action", path: absolute, lineRange: range });
        } else if (toolName === "run_command" && params.CommandLine) {
            root.activity(sink, { kind: "command", verb: "Run", target: params.CommandLine, copyText: params.CommandLine });
        } else if (toolName === "search_web" && params.query) {
            const target = `web search "${params.query}"`;
            root.activity(sink, { kind: "search", verb: "Ran", target: target, copyText: target });
        } else {
            const action = params.toolAction || params.toolSummary || toolName;
            const command = typeof params.CommandLine === "string" ? params.CommandLine : "";
            const target = fp.length > 0 ? Helpers.basename(fp) : command;
            root.activity(sink, { kind: "tool", verb: "Run", target: `${action}${target ? " " + target : ""}`, path: absolute, copyText: command });
        }
    }

    function isEditDenial(denied: var): bool {
        return root.writeTools.includes(denied.tool_name) || root.writeTools.includes(denied.action)
            || root.editActions.includes(denied.action);
    }

    // The tool step a denied action refers to: by step index, then by tool
    // name, then the last step of the same kind (a denied step still ends as
    // DONE), then the last step that never finished.
    function stepForDenial(denied: var, steps: var): var {
        if (denied.step_index !== undefined) {
            const byIndex = steps.find(s => s.index === denied.step_index);
            if (byIndex) return byIndex;
        }
        const name = denied.tool_name || denied.action || "";
        for (let i = steps.length - 1; i >= 0; i--) {
            if (steps[i].toolName === name) return steps[i];
        }
        const edit = root.isEditDenial(denied);
        for (let i = steps.length - 1; i >= 0; i--) {
            if (edit ? root.writeTools.includes(steps[i].toolName) : steps[i].command.length > 0) return steps[i];
        }
        for (let i = steps.length - 1; i >= 0; i--) {
            if (steps[i].state !== "DONE") return steps[i];
        }
        return null;
    }

    function handleDenials(deniedActions: var, sink: var): void {
        const state = sink.state;
        if (state.mode === "auto") return;
        const names = [];
        const commands = [];
        const targets = [];
        for (const denied of deniedActions) {
            const name = String(denied?.display_name || denied?.action || denied?.tool_name || "");
            if (name.length > 0 && !names.includes(name)) names.push(name);
            const step = root.stepForDenial(denied ?? {}, state.toolSteps);
            if (step?.command && !commands.includes(step.command)) commands.push(step.command);
            if (step?.target && !targets.includes(step.target)) targets.push(step.target);
        }
        const action = names.join(", ");
        if (state.mode === "plan") {
            root.emitText(sink, "\n\n" + Translation.tr("Plan mode is on, so this was not run: %1").arg(action));
            return;
        }
        const command = commands.join("\n");
        const target = targets.join("\n");
        const shown = command || target;
        root.emitText(sink, `\n\n**Awaiting confirmation**: ${action}${shown ? ` \`${shown}\`` : ""}`);
        sink.requestConfirmation({
            type: "cli",
            provider: "antigravity-cli",
            action: action,
            command: command,
            target: target,
            scope: "all",
            grantNote: Translation.tr("Approving lets %1 run commands and edit files without asking for its next reply only.").arg(state.modelName)
        });
    }

    function handleResult(result: var, sink: var): void {
        const state = sink.state;
        state.gotResult = true;
        sink.endThink();
        if (result.conversation_id) sink.setSessionId(result.conversation_id);
        if (result.status !== "SUCCESS") {
            root.fail(sink, String(result.error || result.status || JSON.stringify(result)));
        } else {
            if (!state.streamed && result.response) root.emitText(sink, result.response);
            const denied = result.denied_actions ?? [];
            if (Array.isArray(denied) && denied.length > 0) root.handleDenials(denied, sink);
        }
        if (result.usage) {
            sink.usage({
                input: result.usage.input_tokens ?? -1,
                output: result.usage.output_tokens ?? -1,
                total: result.usage.total_tokens ?? -1
            });
        }
        GeminiUsage.refreshAfterReply();
        sink.finished();
    }

    function parseLine(line: string, sink: var): void {
        const cleanData = line.trim();
        if (cleanData.length === 0) return;

        let json;
        try {
            json = JSON.parse(cleanData);
        } catch (e) {
            // stdout carries only the event stream, so anything else is
            // unexpected and worth seeing rather than dropping.
            sink.raw(cleanData);
            return;
        }
        try {
            const state = sink.state;
            switch (json.event) {
            case "init": {
                const id = json.init?.conversation_id ?? json.conversation_id;
                if (id) sink.setSessionId(id);
                break;
            }
            case "step_update": {
                const step = json.step_update ?? {};
                const thought = step.thinking_delta || (step.step_type === "thought" ? (step.text_delta || step.thought) : "");
                if (typeof thought === "string" && thought.length > 0) {
                    state.streamed = true;
                    state.textOpenLine = false;
                    sink.think(thought);
                } else if (step.step_type === "tool") {
                    root.handleToolStep(step, sink);
                } else if (step.step_type === "agent_response" && typeof step.text_delta === "string" && step.text_delta.length > 0) {
                    // Separate distinct agent steps (before and after tool
                    // runs), not deltas streaming within one step.
                    if (state.lastStepIndex !== -1 && step.step_index !== undefined
                            && step.step_index !== state.lastStepIndex && state.textOpenLine) {
                        root.emitText(sink, "\n\n");
                    }
                    if (step.step_index !== undefined) state.lastStepIndex = step.step_index;
                    root.emitText(sink, step.text_delta);
                }
                break;
            }
            case "result":
                root.handleResult(json.result ?? {}, sink);
                break;
            }
        } catch (e) {
            console.warn("[Ai] Antigravity: unexpected event:", e);
        }
    }

    function finish(sink: var, exitCode: int, stderrTail: string): void {
        if (sink.state.gotResult) return;
        // The run ended before it could report anything: a crash, or a
        // conversation that cannot be resumed and would fail every retry.
        sink.setSessionId("");
        if (exitCode === 0 && sink.state.streamed) return;
        const detail = Helpers.lastErrorLine(stderrTail);
        root.fail(sink, detail.length > 0 ? detail : Translation.tr("%1 stopped with code %2").arg("Antigravity").arg(exitCode));
    }
}
