.pragma library

// The stream sink a strategy writes a reply through, plus the text rules it
// shares with history building and session files. Only the sink creates
// think blocks and activity markers; model text can forge neither.

var MARK = "\u001F";
var ZWSP = "​";
var THINK_OPEN = "\n\n<think>\n\n";
var THINK_CLOSE = "\n\n</think>\n\n";
var ACTIVITY_KINDS = ["edit", "read", "command", "search", "tool"];

function marker(index) {
    return MARK + "activity:" + index + MARK;
}

function escapeThinkTags(text) {
    return text.replace(/<(\/?think>)/g, "<" + ZWSP + "$1");
}

function unescapeThinkTags(text) {
    return text.replace(/<​(\/?think>)/g, "<$1");
}

function stripMarks(text) {
    return text.indexOf(MARK) === -1 ? text : text.replace(/\u001F/g, "");
}

// Length of the tail of text that could still become a think tag. Both tags
// hold a single '<', at their start, so a match can only start at the last one.
function partialTagLength(text) {
    const i = text.lastIndexOf("<");
    if (i === -1 || text.length - i > 7)
        return 0;
    const tail = text.slice(i);
    return ("</think>".startsWith(tail) || (tail.length < 7 && "<think>".startsWith(tail))) ? tail.length : 0;
}

// Model text, safe to append: no marker bytes, tags made inert.
function cleanModelText(text) {
    return escapeThinkTags(stripMarks(String(text ?? "")));
}

// The answer as the model should see it again: think segments and marker
// lines removed, the tag escape undone.
function historyText(content) {
    let text = String(content ?? "");
    if (text.indexOf("<think>") !== -1)
        text = text.replace(/(?:\n\n)?<think>[\s\S]*?(?:<\/think>(?:\n\n)?|$)/g, "\n\n");
    if (text.indexOf(MARK) !== -1)
        text = text.replace(/^\u001Factivity:\d+\u001F$\n?/gm, "");
    return unescapeThinkTags(text).trim();
}

function toInt(value, fallback) {
    const n = Number(value);
    return Number.isFinite(n) ? Math.round(n) : fallback;
}

function normalizeActivity(record, fallbackTarget) {
    const r = (record && typeof record === "object") ? record : {};
    const str = v => (typeof v === "string" ? stripMarks(v) : "");
    const rec = {
        kind: ACTIVITY_KINDS.indexOf(r.kind) !== -1 ? r.kind : "tool",
        verb: str(r.verb),
        target: str(r.target) || fallbackTarget || "Action",
        path: str(r.path),
        lineRange: str(r.lineRange),
        added: toInt(r.added, -1),
        removed: toInt(r.removed, -1),
        copyText: str(r.copyText),
    };
    if (rec.kind === "edit" && rec.added === 0 && rec.removed === 0)
        rec.added = 1;
    return rec;
}

function placeholderThinkBlock() {
    return { start: 0, duration: 0, collapsed: null };
}

function applyThinkPatch(blocks, patch) {
    while (blocks.length < patch.index)
        blocks.push(placeholderThinkBlock());
    const prev = blocks[patch.index] ?? placeholderThinkBlock();
    blocks[patch.index] = {
        start: patch.open ? patch.start : (prev.start ?? 0),
        duration: patch.open ? 0 : patch.duration,
        collapsed: prev.collapsed ?? null,
    };
}

function sameSources(a, b) {
    const x = a ?? [];
    const y = b ?? [];
    if (x.length !== y.length)
        return false;
    if (x.length === 0)
        return true;
    return (x[x.length - 1]?.url ?? "") === (y[y.length - 1]?.url ?? "");
}

/**
 * Creates the sink for one request. host provides:
 *   isActive(req): bool, now(): number, scheduleFlush(req),
 *   setSessionId(req, id), recordFunctionCall(req, call): bool,
 *   uploadedFile(req, uri, mime), askPermission(req, fields),
 *   writeInput(req, line), endInput(req), actionFallback: string
 * The buffers live on req.buf; flush() moves them into the message.
 */
function createSink(req, host) {
    const b = {
        parts: [],
        hold: "",
        inThink: false,
        thinkCount: 0,
        openThinkStart: 0,
        // A model thinks from the moment it last showed anything, and some
        // send their thoughts only once they are done.
        quietSince: req.startTime ?? host.now(),
        patches: [],
        activities: [],
        activityBase: 0,
        usage: null,
        annotations: null,
        sawOutput: false,
        errored: false,
        flushQueued: false,
    };
    req.buf = b;

    const active = () => host.isActive(req);

    function schedule() {
        if (!b.flushQueued) {
            b.flushQueued = true;
            host.scheduleFlush(req);
        }
    }

    function releaseHold() {
        if (b.hold.length > 0) {
            b.parts.push(b.hold);
            b.hold = "";
        }
    }

    function push(text) {
        if (text.length > 0) {
            b.parts.push(text);
            schedule();
        }
    }

    function append(text) {
        const clean = stripMarks(text);
        if (b.hold.length === 0 && clean.indexOf("<") === -1) {
            push(clean);
            return;
        }
        const escaped = escapeThinkTags(b.hold + clean);
        const k = partialTagLength(escaped);
        b.hold = k > 0 ? escaped.slice(escaped.length - k) : "";
        push(k > 0 ? escaped.slice(0, escaped.length - k) : escaped);
    }

    function openThink(start) {
        releaseHold();
        b.inThink = true;
        b.openThinkStart = start;
        b.patches.push({ index: b.thinkCount, open: true, start: start });
        b.thinkCount++;
        push(THINK_OPEN);
    }

    function closeThink() {
        if (!b.inThink)
            return;
        releaseHold();
        b.inThink = false;
        const elapsed = host.now() - b.openThinkStart;
        b.patches.push({
            index: b.thinkCount - 1,
            open: false,
            duration: b.openThinkStart > 0 ? Math.max(1, Math.round(elapsed / 1000)) : 0,
        });
        push(THINK_CLOSE);
    }

    const sink = {
        state: null,
        text(s) {
            if (!active() || s === undefined || s === null)
                return;
            const t = String(s);
            if (t.length === 0)
                return;
            b.sawOutput = true;
            closeThink();
            append(t);
            b.quietSince = host.now();
        },
        think(s) {
            if (!active())
                return;
            b.sawOutput = true;
            if (!b.inThink)
                openThink(b.quietSince);
            if (s !== undefined && s !== null && String(s).length > 0)
                append(String(s));
        },
        thinkWhole(s) {
            if (!active())
                return;
            b.sawOutput = true;
            closeThink();
            openThink(b.quietSince);
            if (s !== undefined && s !== null)
                append(String(s));
            closeThink();
        },
        endThink() {
            if (!active())
                return;
            closeThink();
        },
        activity(record) {
            if (!active())
                return -1;
            b.sawOutput = true;
            if (!b.inThink)
                openThink(b.quietSince);
            const index = b.activityBase + b.activities.length;
            b.activities.push(normalizeActivity(record, host.actionFallback));
            releaseHold();
            push("\n" + marker(index) + "\n");
            return index;
        },
        error(detail, label) {
            if (!active() || b.errored)
                return;
            b.errored = true;
            b.sawOutput = true;
            closeThink();
            append("**" + (label || "Error") + "**: " + String(detail ?? ""));
        },
        raw(line) {
            sink.text(String(line ?? "") + "\n");
        },
        usage(u) {
            if (!active() || !u)
                return;
            b.usage = {
                input: toInt(u.input, -1),
                output: toInt(u.output, -1),
                total: toInt(u.total, -1),
            };
            schedule();
        },
        functionCall(call) {
            if (!active() || !call || !call.name)
                return;
            closeThink();
            const recorded = host.recordFunctionCall(req, {
                name: String(call.name),
                args: call.args ?? {},
                id: call.id ?? "",
                thoughtSignature: call.thoughtSignature ?? "",
            });
            if (recorded) {
                b.sawOutput = true;
                append("\n\n[[ Function: " + call.name + "(" + JSON.stringify(call.args ?? {}, null, 2) + ") ]]\n");
            }
        },
        setSessionId(id) {
            if (active())
                host.setSessionId(req, String(id ?? ""));
        },
        setAnnotations(sources, annotations, queries) {
            if (!active())
                return;
            b.annotations = {
                sources: Array.isArray(sources) ? sources : [],
                annotations: Array.isArray(annotations) ? annotations : [],
                queries: Array.isArray(queries) ? queries.map(String) : [],
            };
            schedule();
        },
        uploadedFile(uri, mime) {
            if (active())
                host.uploadedFile(req, String(uri ?? ""), String(mime ?? ""));
        },
        requestConfirmation(partial) {
            if (active() && partial && typeof partial === "object")
                req.confirmationDraft = partial;
        },
        // A step the CLI holds until the user answers; the request keeps running.
        askPermission(fields) {
            if (active() && fields && typeof fields === "object")
                host.askPermission(req, fields);
        },
        writeInput(line) {
            if (active())
                host.writeInput(req, String(line ?? ""));
        },
        endInput() {
            if (active())
                host.endInput(req);
        },
        loginLapsed() {
            if (active())
                req.loginLapsed = true;
        },
        searchRefused() {
            if (active())
                req.searchRefused = true;
        },
        // The process exit, not this event, ends a request.
        finished() {},
        // Service side: ends an open think block and releases held text.
        close() {
            closeThink();
            releaseHold();
        },
    };
    return sink;
}

/**
 * Moves the buffered stream into the message with at most one write per
 * property, in the order that keeps every marker resolvable. Returns the
 * buffered usage (or null) for the host to publish.
 */
function flush(b, message) {
    b.flushQueued = false;
    if (b.activities.length > 0) {
        message.activities = (message.activities ?? []).concat(b.activities);
        b.activityBase += b.activities.length;
        b.activities = [];
    }
    if (b.patches.length > 0) {
        const blocks = (message.thinkBlocks ?? []).slice();
        for (const patch of b.patches)
            applyThinkPatch(blocks, patch);
        b.patches = [];
        message.thinkBlocks = blocks;
    }
    if (b.parts.length > 0) {
        const added = b.parts.join("");
        b.parts = [];
        if (added.length > 0)
            message.content = message.content + added;
    }
    if (b.sawOutput && message.thinking)
        message.thinking = false;
    if (b.annotations) {
        const a = b.annotations;
        b.annotations = null;
        if (!sameSources(a.sources, message.annotationSources))
            message.annotationSources = a.sources;
        if (!sameSources(a.annotations, message.annotations))
            message.annotations = a.annotations;
        if (a.queries.length !== (message.searchQueries?.length ?? 0))
            message.searchQueries = a.queries;
    }
    const usage = b.usage;
    b.usage = null;
    return usage;
}

// Drops whatever a superseded request still had buffered.
function discard(b) {
    b.flushQueued = false;
    b.parts = [];
    b.hold = "";
    b.patches = [];
    b.activities = [];
    b.usage = null;
    b.annotations = null;
}
