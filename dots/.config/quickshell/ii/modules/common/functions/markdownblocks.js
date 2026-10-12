.pragma library

const THINK_OPEN = "<think>";
const THINK_CLOSE = "</think>";
const FENCE = "```";
// Longest run of \w after a fence that is still waited on for its newline.
const MAX_LANG_WAIT = 32;
const LANG_LINE = /^(\w*)\n/;
const WORD_RUN = /^\w*$/;
const NON_SPACE = /\S/;

function Splitter() {
    this._reset(0);
}

Splitter.prototype._reset = function (revision) {
    this._revision = revision;
    this._length = 0;
    this._completed = [];          // cached descriptors of completed blocks
    this._contents = Object.create(null); // key -> text of a completed block
    this._mode = "text";           // "text" | "think" | "code"
    this._openStart = 0;           // offset where the open block's text starts
    this._pos = 0;                 // scan cursor
    this._lang = "";
    this._thinkCount = 0;
    this._openThinkIndex = -1;
    this._pending = false;
    this._openHasFence = false;
    this._openHasText = false;     // the open block has a non-space character
    this._wsCursor = 0;            // scanned for non-space up to here
    this._openDescriptor = null;
    this._openContent = "";
    this._result = [];
};

Splitter.prototype._emitCompleted = function (type, text, lang, thinkIndex, hasFence) {
    if (!NON_SPACE.test(text)) return;
    const key = this._completed.length + ":" + type;
    const descriptor = {
        key: key,
        type: type,
        lang: lang,
        completed: true,
        thinkIndex: thinkIndex,
        hasFence: hasFence
    };
    this._completed.push(descriptor);
    this._contents[key] = text;
};

Splitter.prototype._openBlock = function (mode, start) {
    this._mode = mode;
    this._openStart = start;
    this._pos = start;
    this._wsCursor = start;
    this._openHasText = false;
    this._openHasFence = false;
};

// Returns false when scanning must wait for more text.
Splitter.prototype._scanText = function (content, done) {
    const len = content.length;
    const think = content.indexOf(THINK_OPEN, this._pos);
    let fence = content.indexOf(FENCE, this._pos);
    while (fence !== -1 && (think === -1 || fence < think)) {
        const rest = content.slice(fence + 3, fence + 3 + MAX_LANG_WAIT + 1);
        const langLine = LANG_LINE.exec(rest);
        if (langLine) {
            this._emitCompleted("text", content.slice(this._openStart, fence), "", -1, this._openHasFence);
            this._lang = langLine[1];
            this._openBlock("code", fence + 3 + langLine[0].length);
            return true;
        }
        if (!done && fence + 3 + rest.length >= len && rest.length <= MAX_LANG_WAIT && WORD_RUN.test(rest)) {
            this._pos = fence;
            this._pending = true;
            return false;
        }
        this._openHasFence = true;
        fence = content.indexOf(FENCE, fence + 3);
    }
    if (think !== -1) {
        this._emitCompleted("text", content.slice(this._openStart, think), "", -1, this._openHasFence);
        this._openThinkIndex = this._thinkCount++;
        this._openBlock("think", think + THINK_OPEN.length);
        return true;
    }
    // Keep enough of the tail to find a tag or fence split across updates.
    this._pos = Math.max(this._pos, len - (THINK_OPEN.length - 1));
    return false;
};

Splitter.prototype._scanThink = function (content) {
    const close = content.indexOf(THINK_CLOSE, this._pos);
    if (close === -1) {
        this._pos = Math.max(this._pos, content.length - (THINK_CLOSE.length - 1));
        return false;
    }
    this._emitCompleted("think", content.slice(this._openStart, close), "", this._openThinkIndex, false);
    this._openThinkIndex = -1;
    this._openBlock("text", close + THINK_CLOSE.length);
    return true;
};

Splitter.prototype._scanCode = function (content) {
    const close = content.indexOf(FENCE, this._pos);
    if (close === -1) {
        this._pos = Math.max(this._pos, content.length - (FENCE.length - 1));
        return false;
    }
    this._emitCompleted("code", content.slice(this._openStart, close), this._lang, -1, false);
    this._lang = "";
    this._openBlock("text", close + FENCE.length);
    return true;
};

Splitter.prototype.update = function (content, revision, done) {
    content = content ?? "";
    revision = revision ?? 0;
    if (revision !== this._revision || content.length < this._length) this._reset(revision);
    this._length = content.length;

    const completedBefore = this._completed.length;
    this._pending = false;
    let more = true;
    while (more) {
        if (this._mode === "text") more = this._scanText(content, done);
        else if (this._mode === "think") more = this._scanThink(content);
        else more = this._scanCode(content);
    }

    const len = content.length;
    // A fence still waiting for its newline is not part of the open text.
    const openEnd = (this._mode === "text" && this._pending) ? this._pos : len;
    if (!this._openHasText && this._wsCursor < openEnd) {
        // Trailing backticks may still become a fence, so they are checked again next time.
        let end = openEnd;
        while (end > this._wsCursor && content.charCodeAt(end - 1) === 96) end--;
        this._openHasText = NON_SPACE.test(content.slice(this._wsCursor, end));
        this._wsCursor = end;
    }

    let open = null;
    let openShown = false;
    if (this._mode === "think") openShown = !done || this._openHasText;
    else openShown = this._openHasText;
    if (openShown) {
        const key = this._completed.length + ":" + this._mode;
        const lang = this._mode === "code" ? this._lang : "";
        const thinkIndex = this._mode === "think" ? this._openThinkIndex : -1;
        const hasFence = this._mode === "text" ? this._openHasFence : false;
        const prev = this._openDescriptor;
        if (prev && prev.key === key && prev.lang === lang && prev.thinkIndex === thinkIndex && prev.hasFence === hasFence) {
            open = prev;
        } else {
            open = {
                key: key,
                type: this._mode,
                lang: lang,
                completed: false,
                thinkIndex: thinkIndex,
                hasFence: hasFence
            };
        }
    }
    this._openContent = openShown ? content.slice(this._openStart, openEnd) : "";

    const prevResult = this._result;
    const sameShape = completedBefore === this._completed.length
        && open === this._openDescriptor
        && prevResult.length === this._completed.length + (open ? 1 : 0);
    this._openDescriptor = open;
    if (!sameShape) {
        const result = this._completed.slice();
        if (open) result.push(open);
        this._result = result;
    }
    return this._result;
};

Splitter.prototype.content = function (key) {
    return this._contents[key] ?? "";
};

Splitter.prototype.openContent = function () {
    return this._openContent;
};

function createSplitter() {
    return new Splitter();
}

// A code block's text fenced again as markdown source.
function fence(lang, code) {
    return FENCE + (lang ?? "") + "\n" + code + (code.endsWith("\n") ? "" : "\n") + FENCE;
}
