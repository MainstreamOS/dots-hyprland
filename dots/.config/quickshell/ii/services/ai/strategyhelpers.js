.pragma library

const transcriptLimit = 32000;
const imageExtensions = ["png", "jpg", "jpeg", "webp", "gif"];

function extension(path) {
    const name = String(path ?? "").split("/").pop();
    const dot = name.lastIndexOf(".");
    return dot > 0 ? name.slice(dot + 1).toLowerCase() : "";
}

function isImage(path) {
    return imageExtensions.includes(extension(path));
}

function lastUserIndex(messages) {
    for (let i = messages.length - 1; i >= 0; i--) {
        if (messages[i]?.role === "user") return i;
    }
    return -1;
}

// A regenerate reuses the stored user message, which still names its file.
function attachmentPath(ctx) {
    if (ctx?.attachment?.path) return ctx.attachment.path;
    if (!ctx?.regenerate) return "";
    const messages = ctx.messages ?? [];
    const last = lastUserIndex(messages);
    return last >= 0 ? (messages[last].localFilePath ?? "") : "";
}

// The prompt a CLI receives on stdin. A regenerate starts a fresh CLI
// conversation, since a CLI cannot drop a turn from its own history, so the
// earlier turns travel with it as a compact transcript.
function cliPrompt(ctx, historyText, earlierLabel, attachedLine) {
    const messages = ctx?.messages ?? [];
    const last = lastUserIndex(messages);
    let prompt = last >= 0 ? (messages[last].rawContent ?? "") : "";
    if (attachedLine.length > 0)
        prompt += (prompt.length > 0 ? "\n\n" : "") + attachedLine;
    if (!ctx?.regenerate || last <= 0)
        return prompt;

    const turns = [];
    let size = 0;
    for (let i = last - 1; i >= 0 && size < transcriptLimit; i--) {
        const message = messages[i];
        if (!message || message.visibleToUser === false) continue;
        const assistant = message.role === "assistant";
        const text = String(assistant ? historyText(message) : (message.rawContent ?? "")).trim();
        if (text.length === 0) continue;
        const turn = (assistant ? "Assistant: " : "User: ") + text;
        turns.push(turn);
        size += turn.length + 2;
    }
    let transcript = turns.reverse().join("\n\n");
    if (transcript.length > transcriptLimit)
        transcript = transcript.slice(transcript.length - transcriptLimit);
    if (transcript.length === 0)
        return prompt;
    return earlierLabel + "\n\n" + transcript + "\n\n" + prompt;
}

// The last line a failed run wrote to stderr, preferring the CLI's own
// `error:` line over progress notes and lines meant for scripts.
function lastErrorLine(stderr) {
    const lines = String(stderr ?? "").replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").split("\n")
        .map(line => line.trim()).filter(line => line.length > 0);
    const marked = lines.filter(line => line.startsWith("error:")).map(line => line.slice(6).trim());
    if (marked.length > 0) return marked[marked.length - 1];
    return lines.length > 0 ? lines[lines.length - 1] : "";
}

// Placeholders that run-request.sh replaces with an attached file's type,
// contents and URI. The token is new for every request, so no chat text matches it.
function filePlaceholders() {
    let token = "__MS_FILE_";
    for (let i = 0; i < 4; i++)
        token += Math.floor(Math.random() * 0x100000000).toString(16).padStart(8, "0");
    return { token: token, mime: token + "_MIME__", data: token + "_B64__", uri: token + "_URI__" };
}

// API requests resend each user turn's file, including on follow-up and regenerate.
function historyFiles(ctx, acceptsAttachment) {
    const messages = ctx.messages ?? [];
    const attachment = ctx.attachment?.path ?? "";
    const lastUser = lastUserIndex(messages);
    const files = [];
    messages.forEach((message, index) => {
        const current = index === lastUser && attachment.length > 0;
        const path = current ? attachment : (message.role === "user" ? (message.localFilePath ?? "") : "");
        if (path.length === 0 || (!current && !acceptsAttachment(path))) return;
        files.push(Object.assign(filePlaceholders(), { index: index, path: path, current: current }));
    });
    return files;
}

function fileOptions(files) {
    const options = [];
    for (const file of files) {
        if (file.current) options.push("--inline-file", file.path, "--file-token", file.token);
        else options.push("--earlier-file", file.path, file.token);
    }
    return options;
}

function basename(path) {
    return String(path ?? "").split("/").pop() || String(path ?? "");
}

function cleanPath(path) {
    let p = typeof path === "string" ? path.trim() : "";
    if (p.startsWith("file://")) p = p.slice(7);
    return p.replace(/^["' ]+|["' ]+$/g, "");
}
