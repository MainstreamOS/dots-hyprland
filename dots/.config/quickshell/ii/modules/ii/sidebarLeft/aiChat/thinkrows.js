.pragma library

const MARKER = /^\u001Factivity:(\d+)\u001F\r?$/;
const FENCE = /^ {0,3}(```|~~~)/;
const BLANK = /^\s*$/;

// Type icon and color by file extension. Colors are hex values or the theme
// token names "subtext", "onSurface", "primary" and "error".
const EXTENSIONS = new Map([
    [".rs", ["code", "#f97316"]],
    [".py", ["code", "#38bdf8"]],
    [".qml", ["code", "#c084fc"]],
    [".js", ["code", "#c084fc"]],
    [".ts", ["code", "#c084fc"]],
    [".jsx", ["code", "#c084fc"]],
    [".tsx", ["code", "#c084fc"]],
    [".c", ["code", "#60a5fa"]],
    [".cpp", ["code", "#60a5fa"]],
    [".h", ["code", "#60a5fa"]],
    [".hpp", ["code", "#60a5fa"]],
    [".go", ["code", "#06b6d4"]],
    [".sh", ["terminal", "#4ade80"]],
    [".bash", ["terminal", "#4ade80"]],
    [".zsh", ["terminal", "#4ade80"]],
    [".json", ["data_object", "#facc15"]],
    [".toml", ["data_object", "#facc15"]],
    [".yaml", ["data_object", "#facc15"]],
    [".yml", ["data_object", "#facc15"]],
    [".md", ["article", "onSurface"]],
    [".txt", ["article", "onSurface"]],
    [".log", ["article", "onSurface"]],
    [".png", ["image", "primary"]],
    [".jpg", ["image", "primary"]],
    [".jpeg", ["image", "primary"]],
    [".webp", ["image", "primary"]],
    [".svg", ["image", "primary"]],
    [".gif", ["image", "primary"]],
    [".html", ["code", "#f43f5e"]],
    [".htm", ["code", "#f43f5e"]],
    [".css", ["style", "#06b6d4"]],
    [".scss", ["style", "#06b6d4"]],
    [".sass", ["style", "#06b6d4"]],
    [".less", ["style", "#06b6d4"]],
    [".vue", ["code", "#10b981"]],
    [".svelte", ["code", "#10b981"]],
    [".lua", ["code", "#0284c7"]],
    [".zig", ["code", "#f59e0b"]],
    [".java", ["code", "#ea580c"]],
    [".kt", ["code", "#ea580c"]],
    [".sql", ["data_object", "#38bdf8"]],
    [".pdf", ["picture_as_pdf", "error"]]
]);

// Type icon for the first token of a target: {icon: "" when none, color}.
function typeIconFor(target) {
    const token = String(target ?? "").split(/[\s:#]/)[0];
    const lower = token.toLowerCase();
    const dot = lower.lastIndexOf(".");
    const ext = dot !== -1 ? lower.slice(dot) : "";
    const known = EXTENSIONS.get(ext);
    if (known) return { icon: known[0], color: known[1] };
    if (lower.endsWith(".lock")) return { icon: "lock", color: "#ca8a04" };
    if (lower.startsWith(".env") || lower.endsWith(".env")) return { icon: "key", color: "#eab308" };
    if (lower.includes("dockerfile") || lower.includes("containerfile")) return { icon: "inventory_2", color: "#0284c7" };
    if (lower === "makefile" || lower.endsWith(".mk")) return { icon: "build", color: "#f97316" };
    if (ext.length > 0) return { icon: "draft", color: "subtext" };
    if (lower.includes("/")) return { icon: "code", color: "primary" };
    return { icon: "", color: "subtext" };
}

function isRunVerb(verb) {
    return verb === "Run" || verb === "Ran";
}

// Icons of an activity row, per the record's verb and target.
function rowIcons(verb, target) {
    if (isRunVerb(verb)) {
        return { fileIcon: "terminal", showFileIcon: true, typeIcon: "", typeColor: "subtext", showTypeIcon: false };
    }
    const type = typeIconFor(target);
    const showType = type.icon !== "";
    return {
        fileIcon: "description",
        showFileIcon: verb === "Added" ? !showType : true,
        typeIcon: type.icon,
        typeColor: type.color,
        showTypeIcon: showType
    };
}

function baseName(path) {
    const parts = String(path).split("/").filter(p => p.length > 0);
    return parts.length ? parts[parts.length - 1] : String(path);
}

function parentName(path) {
    const parts = String(path).split("/").filter(p => p.length > 0);
    return parts.length > 1 ? parts[parts.length - 2] : "";
}

// Records arrive normalized by the service, with the same fields as paragraphRow().
function activityRow(record, index) {
    return Object.assign({ type: "action", text: "", act: index }, record);
}

function paragraphRow(text) {
    return {
        type: "paragraph",
        text: text,
        act: -1,
        kind: "",
        verb: "",
        target: "",
        path: "",
        lineRange: "",
        added: -1,
        removed: -1,
        copyText: ""
    };
}

/*
 * Incremental parser for one think segment. Rows are paragraphs and activity
 * rows (from marker lines); changed files are summed from edit records.
 * feed() consumes only complete lines past its cursor; the trailing partial
 * line is shown in the open paragraph until it completes.
 */
function Parser() {
    this._revision = -1;
    this.reset();
}

Parser.prototype.reset = function () {
    this.rows = [];
    this.files = [];             // {key, name, path, added, removed, typeIcon, typeColor}
    this.totalAdded = 0;
    this.totalRemoved = 0;
    this._fileIndex = new Map();  // key -> index in files
    this._baseNames = new Map();  // basename -> [file indexes]
    this._pos = 0;
    this._length = 0;
    this._final = false;
    this._inFence = false;
    this._text = "";
    this._openPara = -1;
    this._paraStart = 0;         // the open paragraph is _text.slice(_paraStart, _paraEnd)
    this._paraEnd = 0;
    this._paraDirty = false;
    this._rowsDirty = 0;
    this._filesDirty = new Set();
    this._activities = null;
};

Parser.prototype._openParagraph = function (start) {
    this._openPara = this.rows.length;
    this._paraStart = start;
    this.rows.push(paragraphRow(""));
};

Parser.prototype._closeParagraph = function () {
    if (this._openPara !== -1 && this._paraDirty) {
        this.rows[this._openPara].text = this._text.slice(this._paraStart, this._paraEnd);
        this._touchRow(this._openPara);
    }
    this._openPara = -1;
    this._paraDirty = false;
};

Parser.prototype._touchRow = function (index) {
    if (index < this._rowsDirty) this._rowsDirty = index;
};

Parser.prototype._addFile = function (row) {
    const key = row.path || row.target;
    const added = Math.max(0, row.added);
    const removed = Math.max(0, row.removed);
    this.totalAdded += added;
    this.totalRemoved += removed;
    let index = this._fileIndex.get(key);
    if (index === undefined) {
        const type = typeIconFor(row.target);
        const name = row.path ? baseName(row.path) : row.target;
        index = this.files.length;
        this.files.push({
            key: key,
            name: name,
            path: row.path,
            added: 0,
            removed: 0,
            typeIcon: type.icon || "description",
            typeColor: type.color
        });
        this._fileIndex.set(key, index);
        const same = this._baseNames.get(name) ?? [];
        same.push(index);
        this._baseNames.set(name, same);
        if (same.length > 1) {
            for (const i of same) {
                const f = this.files[i];
                const parent = f.path ? parentName(f.path) : "";
                f.name = parent ? parent + "/" + baseName(f.path) : f.name;
                this._filesDirty.add(i);
            }
        }
    }
    const file = this.files[index];
    file.added += added;
    file.removed += removed;
    this._filesDirty.add(index);
};

Parser.prototype._handleLine = function (line, start) {
    const marker = MARKER.exec(line);
    if (marker) {
        this._closeParagraph();
        this._inFence = false;
        const index = Number(marker[1]);
        const record = this._activities?.[index];
        if (!record) return;
        const row = activityRow(record, index);
        this._touchRow(this.rows.length);
        this.rows.push(row);
        if (row.kind === "edit") this._addFile(row);
        return;
    }
    if (!this._inFence && BLANK.test(line)) {
        this._closeParagraph();
        return;
    }
    if (FENCE.test(line)) this._inFence = !this._inFence;
    if (this._openPara === -1) this._openParagraph(start);
    this._paraEnd = start + line.length;
    this._paraDirty = true;
};

/*
 * Returns {reset, rowsFrom, files}: rows from rowsFrom on are new or changed,
 * files lists indexes of changed file entries. reset means start over, which
 * a new revision also does.
 */
Parser.prototype.feed = function (text, final, activities, revision) {
    text = text ?? "";
    let reset = false;
    if (revision !== this._revision || text.length < this._length || (this._final && text.length !== this._length)) {
        this.reset();
        this._revision = revision;
        reset = true;
    }
    this._text = text;
    this._activities = activities;
    this._rowsDirty = this.rows.length;
    this._filesDirty = new Set();

    let nl;
    while ((nl = text.indexOf("\n", this._pos)) !== -1) {
        this._handleLine(text.slice(this._pos, nl), this._pos);
        this._pos = nl + 1;
    }
    const partial = text.slice(this._pos);
    if (final) {
        if (partial.length > 0) this._handleLine(partial, this._pos);
        this._pos = text.length;
        this._final = true;
    }
    const showPartial = !final && partial.length > 0 && !BLANK.test(partial) && partial.charCodeAt(0) !== 0x1F;
    if (showPartial && this._openPara === -1) this._openParagraph(this._pos);
    if (this._openPara !== -1 && (this._paraDirty || showPartial)) {
        const shown = text.slice(this._paraStart, showPartial ? text.length : this._paraEnd);
        if (this.rows[this._openPara].text !== shown) {
            this.rows[this._openPara].text = shown;
            this._touchRow(this._openPara);
        }
        this._paraDirty = false;
    }
    this._length = text.length;
    return {
        reset: reset,
        rowsFrom: this._rowsDirty,
        files: Array.from(this._filesDirty).sort((a, b) => a - b)
    };
};

function createParser() {
    return new Parser();
}
