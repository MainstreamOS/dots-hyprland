.pragma library

// Which stored picture belongs to which monitor, apart from the singleton so
// the rules can be run against made-up monitors in a test.

var imageExtensions = ["jpg", "jpeg", "png", "webp", "avif", "bmp", "svg"];

// Stills only, by absolute path. A video wallpaper is an mpvpaper surface on
// every monitor, started and stopped by the wallpaper script, not something
// the background layer draws.
function isImagePath(path) {
    const text = String(path ?? "");
    const lower = text.toLowerCase();
    return text.startsWith("/") && imageExtensions.some(ext => lower.endsWith("." + ext));
}

function descriptionOf(monitor) {
    return String(monitor?.description ?? "").trim();
}

// Hyprland's monitor rules name a monitor by description as "desc:" and the
// description, so a key reads the way a rule for that monitor would.
function descriptionKey(description) {
    return "desc:" + description;
}

function usable(entry) {
    return !!entry && typeof entry.path === "string" && entry.path.startsWith("/");
}

// Two of the same model whose EDID carries no serial report one description
// between them, and a description no longer tells them apart.
function alikeCount(monitors, description) {
    if (description === "") return 0;
    return monitors.filter(m => descriptionOf(m) === description).length;
}

// Every stored key that applies to the monitor on this connector, the one
// that is drawn first. A port's picture counts only for the monitor it was
// picked for, so another screen later plugged into that port gets none.
function keysFor(entries, monitors, name) {
    const monitor = monitors.find(m => m?.name === name);
    if (!monitor) return [];
    const description = descriptionOf(monitor);
    const alike = alikeCount(monitors, description);
    const byDescription = descriptionKey(description);
    const keys = [];
    const port = entries[name];
    if (usable(port) && String(port.description ?? "") === description) keys.push(name);
    // Picked on this port, the description's picture comes first. Picked on
    // another, it follows the monitor here, unless a twin shares the name.
    const own = description === "" ? null : entries[byDescription];
    if (usable(own) && (alike === 1 || own.connector === name)) {
        if (own.connector === name) keys.unshift(byDescription);
        else keys.push(byDescription);
    }
    return keys;
}

// The stored keys that are this monitor's own: whatever it draws now, its
// port's picture, and the description's picture when it was picked here. A
// twin's picture it only borrows while the twin is unplugged stays put.
function ownKeys(entries, monitors, name) {
    return keysFor(entries, monitors, name)
        .filter((key, i) => i === 0 || key === name || entries[key]?.connector === name);
}

// Where a new pick for this monitor is saved: its description when that
// names it alone, which follows it to another port or dock, else its port.
function storageKey(monitors, name) {
    const monitor = monitors.find(m => m?.name === name);
    if (!monitor) return "";
    const description = descriptionOf(monitor);
    return alikeCount(monitors, description) === 1 ? descriptionKey(description) : name;
}

// A copy of the entries with this monitor's own pictures gone, and the
// picture saved in their place when one is given.
function withPicture(entries, monitors, name, picture) {
    const next = Object.assign({}, entries);
    for (const key of ownKeys(next, monitors, name))
        delete next[key];
    const key = picture ? storageKey(monitors, name) : "";
    if (key !== "") {
        const description = descriptionOf(monitors.find(m => m?.name === name));
        next[key] = { path: picture.path, width: picture.width, height: picture.height, connector: name, description: description };
    }
    return next;
}

// The order Settings > Display uses: the configured default monitor while it
// is connected, then the one at 0,0 (setting a default moves it there), then
// the first.
function defaultMonitorName(configured, monitors) {
    const wanted = String(configured ?? "");
    if (wanted !== "" && wanted !== "[[EMPTY]]" && monitors.some(m => m?.name === wanted))
        return wanted;
    return (monitors.find(m => m?.x === 0 && m?.y === 0) ?? monitors[0])?.name ?? "";
}
