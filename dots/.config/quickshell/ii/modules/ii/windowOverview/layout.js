.pragma library

function eligible(windows, monitor) {
    return windows.filter(w => w.mapped && !w.hidden && w.monitor === monitor
        && w.workspace?.id > 0 && w.workspace.id < 2147483600);
}

function spatial(windows) {
    return windows.slice().sort((a, b) => {
        const ay = (a.at?.[1] ?? 0) + (a.size?.[1] ?? 1) / 2;
        const by = (b.at?.[1] ?? 0) + (b.size?.[1] ?? 1) / 2;
        return Math.floor(ay / 160) - Math.floor(by / 160) || (a.at?.[0] ?? 0) - (b.at?.[0] ?? 0)
            || a.address.localeCompare(b.address);
    });
}

// Match the cards from left to right, then each card's rows from top to bottom.
function readingOrder(windows, workspaces) {
    const order = [];
    for (let i = 0; i < workspaces.length; i++) {
        const id = workspaces[i];
        const ordered = spatial(windows.filter(w => w.workspace.id === id));
        for (let j = 0; j < ordered.length; j++)
            order.push(ordered[j].address);
    }
    return order;
}

// Keep the spatial order recognizable, but give every window its own space.
// Try every row count and choose the largest common scale that fits. Large
// windows are capped first so a fullscreen client cannot dwarf all the others.
function arrange(windows, width, height, gap = 40, caption = 44) {
    if (!windows.length || width <= 0 || height <= 0) return {};
    const ordered = spatial(windows);
    const sizes = ordered.map(w => {
        const sw = Math.max(1, w.size?.[0] ?? 640);
        const sh = Math.max(1, w.size?.[1] ?? 480);
        const cap = Math.min(1, 1000 / sw, 700 / sh);
        return { width: sw * cap, height: sh * cap };
    });
    let best = null;
    for (let rows = 1; rows <= ordered.length; rows++) {
        const groups = [];
        let cursor = 0;
        for (let row = 0; row < rows; row++) {
            const count = Math.ceil((ordered.length - cursor) / (rows - row));
            const indices = Array.from({ length: count }, (_, i) => cursor + i);
            cursor += count;
            groups.push({ indices, width: indices.reduce((s, i) => s + sizes[i].width, 0),
                height: Math.max(...indices.map(i => sizes[i].height)) });
        }
        let scale = Math.min(1, (height - gap * (rows - 1) - caption * rows)
            / groups.reduce((s, g) => s + g.height, 0));
        for (const group of groups)
            scale = Math.min(scale, (width - gap * (group.indices.length - 1)) / group.width);
        if (scale > 0 && (!best || scale > best.scale)) best = { scale, groups };
    }
    // Dense desktops still fit: reduce spacing before giving up any windows.
    if (!best) return arrange(windows, width, height, gap / 2, caption / 2);
    const result = {};
    const totalHeight = best.groups.reduce((s, g) => s + g.height * best.scale + caption, 0)
        + gap * (best.groups.length - 1);
    let y = (height - totalHeight) / 2;
    for (const group of best.groups) {
        let x = (width - group.width * best.scale - gap * (group.indices.length - 1)) / 2;
        const rowHeight = group.height * best.scale;
        for (const i of group.indices) {
            const w = sizes[i].width * best.scale;
            const h = sizes[i].height * best.scale;
            result[ordered[i].address] = { x, y: y + rowHeight - h, width: w, height: h };
            x += w + gap;
        }
        y += rowHeight + caption + gap;
    }
    return result;
}

function step(order, selected, direction) {
    if (!order.length) return "";
    const index = order.indexOf(selected);
    if (index < 0) return direction < 0 ? order[order.length - 1] : order[0];
    return order[(index + direction + order.length) % order.length];
}
