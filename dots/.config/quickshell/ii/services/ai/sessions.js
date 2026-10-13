.pragma library
.import "sink.js" as Sink

// Session files: version 2 writes, and reads of version 2, version 1 and the
// bare message arrays that came before both.

var VERSION = 2;

function str(value) {
    return (typeof value === "string") ? value : (value === undefined || value === null ? "" : String(value));
}

function plainArray(value) {
    if (value === undefined || value === null)
        return [];
    if (Array.isArray(value))
        return value;
    if (typeof value === "object" && typeof value.length === "number")
        return Array.prototype.slice.call(value);
    return [];
}

function serializeMessage(m) {
    return {
        "id": str(m.id),
        "role": str(m.role),
        "content": str(m.content),
        "rawContent": str(m.rawContent),
        "fileMimeType": str(m.fileMimeType),
        "fileUri": str(m.fileUri),
        "localFilePath": str(m.localFilePath),
        "model": str(m.model),
        "annotations": plainArray(m.annotations),
        "annotationSources": plainArray(m.annotationSources),
        "searchQueries": plainArray(m.searchQueries).map(str),
        "functionName": str(m.functionName),
        "functionCall": m.functionCall ?? null,
        "functionArgs": m.functionArgs ?? null,
        "functionThoughtSignature": str(m.functionThoughtSignature),
        "functionCallId": str(m.functionCallId),
        "functionResponse": str(m.functionResponse),
        "visibleToUser": m.visibleToUser !== false,
        "answer": str(m.answer),
        "activities": plainArray(m.activities),
        "thinkBlocks": plainArray(m.thinkBlocks),
    };
}

// messages: AiMessageData objects in display order. Returns the file text.
function serialize(messages, model, cliSessions, savedAt) {
    const list = [];
    for (const m of messages) {
        if (m && m.persist !== false)
            list.push(serializeMessage(m));
    }
    return JSON.stringify({
        "version": VERSION,
        "model": str(model),
        "savedAt": savedAt,
        "cliSessions": cliSessions ?? {},
        "messages": list,
    });
}

// data: the parsed file. Returns {ok, version, model, cliSessions, items}.
function parse(data) {
    if (Array.isArray(data))
        return { ok: true, version: 0, model: "", cliSessions: {}, items: data };
    if (!data || typeof data !== "object")
        return { ok: false };
    const version = Number(data.version);
    return {
        ok: true,
        version: Number.isFinite(version) && version > 0 ? version : 1,
        model: str(data.model),
        cliSessions: (data.cliSessions && typeof data.cliSessions === "object" && !Array.isArray(data.cliSessions)) ? data.cliSessions : {},
        items: Array.isArray(data.messages) ? data.messages : [],
    };
}

function sanitizeThinkBlocks(value) {
    return plainArray(value).map(entry => {
        const e = (entry && typeof entry === "object") ? entry : {};
        const start = Number(e.start);
        const duration = Number(e.duration);
        return {
            start: Number.isFinite(start) && start > 0 ? start : 0,
            duration: Number.isFinite(duration) && duration > 0 ? Math.round(duration) : 0,
            collapsed: typeof e.collapsed === "boolean" ? e.collapsed : null,
        };
    });
}

function activityRecord(kind, verb, target, extra) {
    return Object.assign({
        kind: kind,
        verb: verb,
        target: target,
        path: "",
        lineRange: "",
        added: -1,
        removed: -1,
        copyText: "",
    }, extra ?? {});
}

function matchAntigravityLine(line) {
    let m = /^(Edited|Added) (.+) \+(\d+) -(\d+)$/.exec(line);
    if (m)
        return activityRecord("edit", m[1], m[2], { added: Number(m[3]), removed: Number(m[4]) });
    m = /^Ran web search "(.*)"$/.exec(line);
    if (m) {
        const target = 'web search "' + m[1] + '"';
        return activityRecord("search", "Ran", target, { copyText: target });
    }
    m = /^Analyzed (.+?)(?: (#L\d+-\d+))?$/.exec(line);
    if (m)
        return activityRecord("read", "Analyzed", m[1], { lineRange: m[2] ?? "" });
    m = /^Run (.+)$/.exec(line);
    if (m)
        return activityRecord("command", "Run", m[1], { copyText: m[1] });
    return null;
}

function matchShellLine(line) {
    const m = /^Ran (.+)$/.exec(line);
    return m ? activityRecord("command", "Ran", m[1], { copyText: m[1] }) : null;
}

// [start, end) offsets of the text inside each think segment, found with the
// same sequential rules the message renderer uses.
function thinkSegments(content) {
    const ranges = [];
    let i = 0;
    while (i < content.length) {
        const think = content.indexOf("<think>", i);
        const fence = content.indexOf("```", i);
        if (think === -1)
            break;
        if (fence !== -1 && fence < think) {
            const close = content.indexOf("```", fence + 3);
            if (close === -1)
                break;
            i = close + 3;
            continue;
        }
        const start = think + 7;
        const end = content.indexOf("</think>", start);
        ranges.push([start, end === -1 ? content.length : end]);
        if (end === -1)
            break;
        i = end + 8;
    }
    return ranges;
}

// Turns the activity lines older versions wrote as plain text into records
// and marker lines. Only whole lines inside think segments are considered.
function convertLegacyActivities(content, matcher) {
    const activities = [];
    const ranges = thinkSegments(content);
    if (ranges.length === 0)
        return { content: content, activities: activities };
    let out = "";
    let last = 0;
    for (const [start, end] of ranges) {
        const lines = content.slice(start, end).split("\n");
        // The first and last pieces share a line with a tag.
        for (let j = 1; j < lines.length - 1; j++) {
            const record = matcher(lines[j]);
            if (!record)
                continue;
            lines[j] = Sink.marker(activities.length);
            activities.push(record);
        }
        out += content.slice(last, start) + lines.join("\n");
        last = end;
    }
    out += content.slice(last);
    return { content: out, activities: activities };
}

/**
 * Properties for one restored AiMessageData, or null to skip the entry.
 * opts: {retiredModels, isAntigravityModel(id): bool, newId(): string}
 */
function messageProps(raw, version, opts) {
    if (!raw || typeof raw !== "object")
        return null;
    const content = str(raw.content ?? raw.rawContent ?? "");
    const modelId = str(raw.model);
    const props = Object.assign(serializeMessage(raw), {
        "id": (typeof raw.id === "string" && raw.id.length > 0) ? raw.id : opts.newId(),
        "role": typeof raw.role === "string" && raw.role.length > 0 ? raw.role : "user",
        "content": content,
        "rawContent": raw.rawContent === undefined || raw.rawContent === null ? content : str(raw.rawContent),
        "model": opts.retiredModels[modelId] ?? modelId,
        "thinking": false,
        "done": true,
        "functionPending": false,
        "activities": [],
        "thinkBlocks": [],
    });
    if (version >= 2) {
        props.activities = plainArray(raw.activities).map(r => Sink.normalizeActivity(r, ""));
        props.thinkBlocks = sanitizeThinkBlocks(raw.thinkBlocks);
        return props;
    }
    const thinkDuration = Number(raw.thinkDuration);
    if (Number.isFinite(thinkDuration) && thinkDuration > 0)
        props.thinkBlocks = [{ start: 0, duration: Math.round(thinkDuration), collapsed: null }];
    let matcher = null;
    if (opts.isAntigravityModel(props.model))
        matcher = matchAntigravityLine;
    else if (props.functionName === "run_shell_command")
        matcher = matchShellLine;
    if (matcher && content.indexOf("<think>") !== -1) {
        const converted = convertLegacyActivities(content, matcher);
        if (converted.activities.length > 0) {
            props.content = converted.content;
            props.rawContent = converted.content;
            props.activities = converted.activities;
        }
    }
    return props;
}
