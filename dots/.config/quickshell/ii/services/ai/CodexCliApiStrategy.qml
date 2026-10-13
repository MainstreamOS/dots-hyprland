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

    function buildRequest(ctx: var): var {
        const model = ctx.model;
        const mode = ctx.mode ?? "ask";
        // exec never asks for approval: Ask runs in the read-only sandbox, where
        // Codex refuses what would change something, and an approval reruns the reply without it.
        const granted = mode === "ask" && ctx.grant?.scope === "all";
        root._requestInfo = { mode: mode, modelName: model.name ?? "", granted: granted };
        const attachment = Helpers.attachmentPath(ctx);
        const image = attachment.length > 0 && Helpers.isImage(attachment);
        // A regenerate starts a fresh thread; its thread.started event replaces the id.
        const sessionId = ctx.regenerate ? "" : root.sessionId;

        // No system prompt: exec mode has no supported way to carry one.
        const argv = ["codex", "exec"];
        if (sessionId.length > 0) argv.push("resume", sessionId);
        argv.push("--json", "--skip-git-repo-check");
        // -c rather than --sandbox, which resume does not take.
        if (mode === "auto" || granted) argv.push("--dangerously-bypass-approvals-and-sandbox");
        else argv.push("-c", 'sandbox_mode="read-only"');
        if (model.model && model.model !== "codex-plan") argv.push("-m", model.model);
        const effort = root.effortFor(ctx.thinkingLevel, Ai.codexEfforts(model.model ?? ""));
        if (effort.length > 0) argv.push("-c", `model_reasoning_effort="${effort}"`);
        if (image) argv.push("-i", attachment);
        // -i takes several files; the lone - after -- reads the prompt from stdin.
        argv.push("--", "-");

        const attachedLine = (attachment.length > 0 && !image) ? Translation.tr("Attached file: %1").arg(attachment) : "";
        return {
            options: ["--workdir", ctx.dirs.codex, "--stdin", "--filter", "codex", "--report-exit"],
            argv: argv,
            stdin: Helpers.cliPrompt(ctx, m => Ai.historyText(m), Translation.tr("Earlier conversation:"), attachedLine),
            env: {}
        };
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
            granted: root._requestInfo.granted === true
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
                    root.emitBlock(sink, `**${Translation.tr("Note")}**: ${item.message}`);
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

    function finish(sink: var, exitCode: int, stderrTail: string): void {
        if (exitCode === 0 || sink.state.finished) return;
        sink.setSessionId("");
        const detail = Helpers.lastErrorLine(stderrTail);
        sink.error(detail.length > 0 ? detail : Translation.tr("%1 stopped with code %2").arg("Codex").arg(exitCode));
    }
}
