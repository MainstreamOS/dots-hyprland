import QtQuick
import qs.services
import "strategyhelpers.js" as Helpers

ApiStrategy {
    id: root
    isCliStrategy: true
    supportsAttachments: true

    // The words Codex itself reads as a sandbox denial in a failed command's output.
    readonly property var sandboxDenialWords: ["operation not permitted", "permission denied", "read-only file system", "seccomp", "sandbox", "landlock", "failed to write file"]
    property var _requestInfo: ({})
    // Requested access by server request id, echoed back when approved.
    property var _permissionAsks: ({})

    function buildRequest(ctx: var): var {
        const model = ctx.model;
        const mode = ctx.mode ?? "ask";
        // exec never asks for approval: without the app server, Ask runs in the
        // read-only sandbox, where Codex refuses what would change something,
        // and an approval reruns the reply without it.
        const granted = mode === "ask" && ctx.grant?.scope === "all";
        const bridged = mode === "ask" && !granted && Boolean(Ai.cliPlanState["codex-cli"]?.features?.includes("app-server"));
        const attachment = Helpers.attachmentPath(ctx);
        const image = attachment.length > 0 && Helpers.isImage(attachment);
        // A regenerate starts a fresh thread; its thread.started event replaces the id.
        const sessionId = ctx.regenerate ? "" : root.sessionId;
        const effort = root.effortFor(ctx.thinkingLevel, Ai.codexEfforts(model.model ?? ""));
        const attachedLine = (attachment.length > 0 && !image) ? Translation.tr("Attached file: %1").arg(attachment) : "";
        const prompt = Helpers.cliPrompt(ctx, m => Ai.historyText(m), Translation.tr("Earlier conversation:"), attachedLine);
        const options = ["--workdir", ctx.dirs.codex, "--stdin", "--filter", "codex", "--report-exit"];
        root._requestInfo = { mode: mode, modelName: model.name ?? "", granted: granted, bridged: bridged };

        // The app server talks JSON-RPC on stdin: initialize, open the thread,
        // start the turn, each sent when the one before is answered.
        if (bridged) {
            root._permissionAsks = {};
            const input = [{ type: "text", text: prompt }];
            if (image) input.push({ type: "localImage", path: attachment });
            root._requestInfo.turn = {
                threadId: sessionId,
                cwd: ctx.dirs.codex,
                model: (model.model && model.model !== "codex-plan") ? model.model : "",
                effort: effort,
                input: input
            };
            return {
                options: options,
                argv: ["codex", "app-server"],
                stdin: root.rpc(1, "initialize", { clientInfo: { name: "mainstream", version: "1" } }),
                keepStdin: true,
                env: {}
            };
        }

        // No system prompt: exec mode has no supported way to carry one.
        const argv = ["codex", "exec"];
        if (sessionId.length > 0) argv.push("resume", sessionId);
        argv.push("--json", "--skip-git-repo-check");
        // -c rather than --sandbox, which resume does not take.
        if (mode === "auto" || granted) argv.push("--dangerously-bypass-approvals-and-sandbox");
        else argv.push("-c", 'sandbox_mode="read-only"');
        if (model.model && model.model !== "codex-plan") argv.push("-m", model.model);
        if (effort.length > 0) argv.push("-c", `model_reasoning_effort="${effort}"`);
        if (image) argv.push("-i", attachment);
        // -i takes several files; the lone - after -- reads the prompt from stdin.
        argv.push("--", "-");
        return {
            options: options,
            argv: argv,
            stdin: prompt,
            env: {}
        };
    }

    function rpc(id: int, method: string, params: var): string {
        return JSON.stringify({ id: id, method: method, params: params }) + "\n";
    }

    // The Codex effort for one of the tab's levels, or "" to leave it to the
    // CLI. A model the catalog lists takes only the efforts listed for it.
    function effortFor(level: string, supported: var): string {
        let effort = Object.keys(Ai.codexEffortLevels).find(key => Ai.codexEffortLevels[key] === level) ?? "";
        if (effort === "minimal" && !supported.includes("minimal")) effort = "low";
        if (supported.length > 0) return supported.includes(effort) ? effort : "";
        return ["none", "low", "medium", "high", "xhigh", "max", "ultra"].includes(effort) ? effort : "";
    }

    // Called after buildRequest, so the mode belongs to this request.
    function newState(): var {
        return {
            finished: false,
            textOpen: false,
            refused: [],
            mode: root._requestInfo.mode ?? "ask",
            modelName: root._requestInfo.modelName ?? "",
            granted: root._requestInfo.granted === true,
            bridged: root._requestInfo.bridged === true,
            turn: root._requestInfo.turn ?? null,
            // File paths of each file change item, by item id
            files: ({}),
            // Ids of the items whose text arrived in pieces
            streamed: ({}),
            usage: null
        };
    }

    // Messages and notices arrive as whole items; a blank line keeps them apart.
    function emitBlock(sink: var, text: string): void {
        sink.text((sink.state.textOpen ? "\n\n" : "") + text);
        sink.state.textOpen = true;
    }

    function isRefused(item: var): bool {
        if (item.status === "declined") return true;
        if (item.status !== "failed" || item.exit_code === 0) return false;
        const output = String(item.aggregated_output ?? "").toLowerCase();
        return root.sandboxDenialWords.some(word => output.includes(word));
    }

    function raiseRefusals(sink: var): void {
        const state = sink.state;
        if (state.refused.length === 0) return;
        sink.requestConfirmation({
            type: "cli",
            provider: "codex-cli",
            action: Translation.tr("Shell command"),
            command: state.refused.join("\n"),
            target: "",
            scope: "all",
            grantNote: Translation.tr("Approving lets %1 run commands and edit files without asking for its next reply only.").arg(state.modelName)
        });
    }

    function parseLine(line: string, sink: var): void {
        const cleanData = line.trim();
        if (cleanData.length === 0) return;
        // The CLI announces that it noticed a redirected stdin; chat has
        // nothing to learn from that.
        if (cleanData.startsWith("Reading additional input from stdin")) return;

        let json;
        try {
            json = JSON.parse(cleanData);
        } catch (e) {
            sink.raw(cleanData);
            return;
        }
        try {
            const state = sink.state;
            if (state.bridged) {
                root.handleServerLine(json, sink);
                return;
            }
            switch (json.type) {
            case "thread.started":
                if (json.thread_id) sink.setSessionId(json.thread_id);
                break;
            // exec mode delivers whole items, not deltas: the message text
            // and the reasoning summary each arrive once, completed.
            case "item.completed": {
                const item = json.item ?? {};
                if (item.type === "agent_message" && item.text) {
                    root.emitBlock(sink, item.text);
                } else if (item.type === "reasoning" && item.text) {
                    sink.thinkWhole(item.text);
                    state.textOpen = false;
                } else if (item.type === "command_execution") {
                    // Plan runs read-only too, and a refusal there raises no card.
                    const command = String(item.command ?? "");
                    if (state.mode === "ask" && !state.granted && root.isRefused(item) && !state.refused.includes(command))
                        state.refused.push(command);
                } else if (item.type === "error" && item.message) {
                    // A warning that does not stop the turn, such as a thread
                    // resumed with another model than it was recorded with.
                    sink.notice(item.message);
                }
                break;
            }
            case "turn.completed":
                state.finished = true;
                if (json.usage) {
                    // Cached input is a subset of input_tokens.
                    const input = json.usage.input_tokens ?? -1;
                    const output = json.usage.output_tokens ?? -1;
                    sink.usage({ input: input, output: output, total: Math.max(0, input) + Math.max(0, output) });
                }
                root.raiseRefusals(sink);
                sink.finished();
                break;
            case "turn.failed":
            case "error": {
                // A dead session pins every retry to the same failure. One
                // failure arrives as both an error event and a failed turn,
                // and the sink shows only the first error.
                sink.setSessionId("");
                state.finished = true;
                sink.error(json.error?.message ?? json.message ?? JSON.stringify(json));
                break;
            }
            }
        } catch (e) {
            console.warn("[Ai] Codex: unexpected event:", e);
        }
    }

    function handleServerLine(json: var, sink: var): void {
        const state = sink.state;
        const method = String(json.method ?? "");
        if (method.length === 0) {
            root.handleResponse(json, sink);
            return;
        }
        if (json.id !== undefined) {
            root.handleServerRequest(json, sink);
            return;
        }
        const params = json.params ?? {};
        switch (method) {
        case "item/started":
            if (params.item?.type === "fileChange")
                state.files[params.item.id] = (params.item.changes ?? []).map(change => String(change?.path ?? "")).filter(path => path.length > 0);
            break;
        // Text arrives in pieces as it is written; the finished item repeats it.
        case "item/agentMessage/delta": {
            const id = String(params.itemId ?? "");
            if (!state.streamed[id]) {
                state.streamed[id] = true;
                if (state.textOpen) sink.text("\n\n");
                state.textOpen = true;
            }
            sink.text(String(params.delta ?? ""));
            break;
        }
        case "item/reasoning/summaryPartAdded":
            if (state.streamed[String(params.itemId ?? "")]) sink.think("\n\n");
            break;
        case "item/reasoning/summaryTextDelta":
            state.streamed[String(params.itemId ?? "")] = true;
            sink.think(String(params.delta ?? ""));
            break;
        case "item/completed": {
            const item = params.item ?? {};
            const streamed = state.streamed[String(item.id ?? "")] === true;
            if (item.type === "agentMessage" && item.text && !streamed) {
                root.emitBlock(sink, item.text);
            } else if (item.type === "reasoning") {
                const summary = (item.summary ?? []).map(String).join("\n\n");
                if (streamed) {
                    sink.endThink();
                    state.textOpen = false;
                } else if (summary.length > 0) {
                    sink.thinkWhole(summary);
                    state.textOpen = false;
                }
            }
            break;
        }
        case "thread/tokenUsage/updated":
            state.usage = params.tokenUsage?.last ?? null;
            break;
        case "warning":
            sink.notice(params.message);
            break;
        case "configWarning":
        case "deprecationNotice":
            sink.notice(params.summary);
            break;
        case "error":
            if (!params.willRetry) root.fail(sink, params.error?.message ?? JSON.stringify(params));
            break;
        case "turn/completed": {
            const turn = params.turn ?? {};
            if (turn.status === "failed") root.fail(sink, turn.error?.message ?? Translation.tr("the request failed"));
            state.finished = true;
            sink.endInput();
            if (state.usage) {
                // Cached input is a subset of inputTokens.
                const input = state.usage.inputTokens ?? -1;
                const output = state.usage.outputTokens ?? -1;
                sink.usage({ input: input, output: output, total: Math.max(0, input) + Math.max(0, output) });
            }
            sink.finished();
            break;
        }
        }
    }

    function handleResponse(json: var, sink: var): void {
        const turn = sink.state.turn;
        if (json.error) {
            // A thread that cannot be resumed pins every retry to the same failure.
            root.fail(sink, json.error.message ?? JSON.stringify(json.error));
            sink.state.finished = true;
            sink.endInput();
            return;
        }
        if (json.id === 1) {
            const settings = { cwd: turn.cwd, approvalPolicy: "on-request", sandbox: "read-only" };
            if (turn.model.length > 0) settings.model = turn.model;
            sink.writeInput(JSON.stringify({ method: "initialized" }) + "\n" + (turn.threadId.length > 0
                ? root.rpc(2, "thread/resume", Object.assign({ threadId: turn.threadId }, settings))
                : root.rpc(2, "thread/start", settings)));
        } else if (json.id === 2) {
            const threadId = String(json.result?.thread?.id ?? turn.threadId);
            sink.setSessionId(threadId);
            const params = { threadId: threadId, input: turn.input };
            if (turn.effort.length > 0) params.effort = turn.effort;
            if (turn.model.length > 0) params.model = turn.model;
            sink.writeInput(root.rpc(3, "turn/start", params));
        }
    }

    // Approvals wait on the card; anything else the server asks of a client
    // is refused so the turn does not stall.
    function handleServerRequest(json: var, sink: var): void {
        const params = json.params ?? {};
        const id = String(json.id);
        let fields = null;
        if (json.method === "item/commandExecution/requestApproval") {
            const actions = (params.commandActions ?? []).map(action => String(action?.command ?? "")).filter(command => command.length > 0);
            fields = { action: Translation.tr("Shell command"), command: actions.length > 0 ? actions.join("\n") : String(params.command ?? ""), target: "" };
        } else if (json.method === "item/fileChange/requestApproval") {
            const paths = sink.state.files[params.itemId] ?? [];
            fields = { action: Translation.tr("File change"), command: "", target: paths.length > 0 ? paths.join("\n") : String(params.grantRoot ?? params.reason ?? "") };
        } else if (json.method === "item/permissions/requestApproval") {
            root._permissionAsks[id] = params.permissions ?? {};
            fields = { action: Translation.tr("Extra access"), command: String(params.reason ?? ""), target: "" };
        }
        if (!fields) {
            sink.writeInput(JSON.stringify({ id: json.id, error: { code: -32601, message: "unsupported request" } }) + "\n");
            return;
        }
        sink.askPermission(Object.assign(fields, {
            controlId: id,
            scope: "all",
            grantNote: Translation.tr("Approving lets %1 run commands and edit files for the rest of this reply.").arg(sink.state.modelName)
        }));
    }

    function permissionAnswer(controlId: string, allow: bool, message: string): string {
        const asked = root._permissionAsks[controlId];
        delete root._permissionAsks[controlId];
        const result = asked !== undefined
            ? { permissions: allow ? asked : {}, scope: "turn" }
            : { decision: allow ? "accept" : "decline" };
        return JSON.stringify({ id: Number(controlId), result: result }) + "\n";
    }

    function fail(sink: var, detail: string): void {
        sink.setSessionId("");
        sink.error(detail);
    }

    function finish(sink: var, exitCode: int, stderrTail: string): void {
        if (exitCode === 0 || sink.state.finished) return;
        sink.setSessionId("");
        const detail = Helpers.lastErrorLine(stderrTail);
        sink.error(detail.length > 0 ? detail : Translation.tr("%1 stopped with code %2").arg("Codex").arg(exitCode));
    }
}
