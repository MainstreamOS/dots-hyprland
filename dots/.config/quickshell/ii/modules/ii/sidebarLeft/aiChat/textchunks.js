.pragma library

// Size after which a chunk also ends at paragraphs and top-level list items.
const CHUNK_SIZE = 1000;

const HEADING = /^#{1,6} /;
const FENCE = /^ {0,3}(```|~~~)/;
const BLANK = /^\s*$/;
const LIST_ITEM = /^(\d+[.)]|[-*+]) /;
const INDENTED = /^[ \t]/;
const TABLE_ROW = /^ {0,3}\|/;
const TABLE_DELIMITER = /^ {0,3}\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/;
// The split the fade-in uses: every blank line and every bullet line.
const FADE_BULLET = /^ {0,2}[-*]/;

/*
 * Splits a text block into chunks at line starts, per the rules in mode
 * "blocks" (headings after a blank line, tables on their own, and paragraphs
 * or top-level list items once a chunk is large), "fade" (every paragraph and
 * bullet), or "single" (one chunk). Only complete lines decide a boundary, so
 * chunks before the tail never change while text is appended.
 */
function Chunker(mode) {
    this.mode = mode;
    this.starts = [0];           // start offset of every chunk; the last one is the tail
    this.sawPipeLine = false;    // a line after the first starts with "|"
    this._pos = 0;
    this._length = 0;
    this._final = false;
    this._lineCount = 0;
    this._inFence = false;
    this._inTable = false;
    this._tableEnded = false;    // blank line seen after a table; split at the next text
    this._prevBlank = true;
    this._prevStart = -1;
    this._prevHasPipe = false;
    this._prevPrevBlank = true;
    this._candidate = -1;        // a large chunk may end where this line starts
    this._inList = false;
    this._firstText = -1;        // first non-blank line of the tail chunk; chunks start at text
}

// The tail chunk is a table still receiving rows.
Chunker.prototype.inTable = function () {
    return this._inTable;
};

Chunker.prototype._tailStart = function () {
    return this.starts[this.starts.length - 1];
};

Chunker.prototype._split = function (offset) {
    if (this._firstText !== -1 && this._firstText < offset) {
        this.starts.push(offset);
        this._firstText = offset;
    }
};

Chunker.prototype._lineBlocks = function (line, start) {
    const blank = BLANK.test(line);
    const large = start - this._tailStart() > CHUNK_SIZE;

    if (this._inFence) {
        if (FENCE.test(line)) this._inFence = false;
        return blank;
    }
    if (this._inTable) {
        if (blank) {
            this._inTable = false;
            this._tableEnded = true;
        }
        return blank;
    }
    if (!blank && this._tableEnded) {
        this._tableEnded = false;
        this._split(start);
    }
    if (FENCE.test(line)) {
        this._inFence = true;
        this._candidate = -1;
        return false;
    }
    if (!blank && TABLE_DELIMITER.test(line) && this._prevHasPipe && this._prevPrevBlank && this._prevStart >= 0) {
        this._inTable = true;
        this._candidate = -1;
        this._split(this._prevStart);
        return false;
    }
    if (!blank && HEADING.test(line) && this._prevBlank) {
        this._split(start);
    }
    const listItem = LIST_ITEM.test(line);
    if (large && listItem && (this._prevBlank || this._inList)) {
        this._split(start);
    }
    if (large && this._candidate === start && !blank && !TABLE_ROW.test(line) && !INDENTED.test(line)) {
        this._split(start);
    }
    if (blank) {
        if (large) this._candidate = start + line.length + 1;
    } else {
        this._candidate = -1;
    }
    if (listItem) this._inList = true;
    else if (!blank && !INDENTED.test(line) && this._prevBlank) this._inList = false;
    return blank;
};

Chunker.prototype._lineFade = function (line, start) {
    const blank = BLANK.test(line);
    if (!blank && start > this._tailStart() && (this._prevBlank || FADE_BULLET.test(line))) {
        this._split(start);
    }
    return blank;
};

Chunker.prototype._handleLine = function (line, start) {
    if (this._lineCount > 0 && line.charCodeAt(0) === 124) this.sawPipeLine = true;
    this._lineCount++;
    if (this.mode === "single") return;
    const prevBlank = this._prevBlank;
    const blank = this.mode === "fade" ? this._lineFade(line, start) : this._lineBlocks(line, start);
    if (!blank && this._firstText === -1) this._firstText = start;
    this._prevPrevBlank = prevBlank;
    this._prevBlank = blank;
    this._prevStart = start;
    this._prevHasPipe = line.indexOf("|") !== -1;
};

/*
 * Consumes complete lines; with final, the last partial line too. Returns
 * {reset, stable}: chunks below `stable` will not change again.
 */
Chunker.prototype.update = function (text, final) {
    text = text ?? "";
    let reset = false;
    if (text.length < this._length || (this._final && text.length !== this._length)) {
        Chunker.call(this, this.mode);
        reset = true;
    }
    let nl;
    while ((nl = text.indexOf("\n", this._pos)) !== -1) {
        this._handleLine(text.slice(this._pos, nl), this._pos);
        this._pos = nl + 1;
    }
    if (final) {
        if (this._pos < text.length) this._handleLine(text.slice(this._pos), this._pos);
        this._pos = text.length;
        this._final = true;
    } else if (this.mode === "fade" && this._pos < text.length) {
        // A started paragraph or bullet already fades in on its own; the split
        // depends only on text that can no longer change.
        const partial = text.slice(this._pos);
        if (!BLANK.test(partial) && (this._prevBlank || FADE_BULLET.test(partial))) this._split(this._pos);
    }
    this._length = text.length;
    return { reset: reset, stable: final ? this.starts.length : this.starts.length - 1 };
};

Chunker.prototype.count = function () {
    return this.starts.length;
};

Chunker.prototype.chunk = function (text, index) {
    const end = index + 1 < this.starts.length ? this.starts[index + 1] : text.length;
    return text.slice(this.starts[index], end);
};

function createChunker(mode) {
    return new Chunker(mode);
}
