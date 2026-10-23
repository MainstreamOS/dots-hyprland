.pragma library

function usesLayout(layout) {
    return layout === "scrolling" || layout === "monocle";
}

// Empty previews fill the configured minimum. Explicit additions are local
// to the launcher until a window is opened or dropped on that workspace.
function availableWorkspaceIds(count, workspaces, monitorId, active, emptyIds = []) {
    const occupied = workspaces.filter(w => w.id > 0 && w.windows > 0);
    const used = new Set(occupied.map(w => w.id));
    const ids = new Set(occupied.filter(w => w.monitorID === monitorId).map(w => w.id));
    for (const id of emptyIds)
        if (id > 0 && (!used.has(id) || ids.has(id))) ids.add(id);
    if (active > 0) ids.add(active);
    for (let id = 1; ids.size < count; id++)
        if (!used.has(id)) ids.add(id);
    return Array.from(ids).sort((a, b) => a - b);
}

function workspaceGroup(current, count, ids) {
    let index = ids.indexOf(current);
    if (index < 0) {
        index = ids.findIndex(id => id > current);
        if (index < 0) index = ids.length - 1;
    }
    const start = Math.max(0, Math.min(index - Math.floor(count / 2), ids.length - count));
    return ids.slice(start, start + count);
}

function ordered(windows) {
    return windows.slice().sort((a, b) => (a.at?.[0] ?? 0) - (b.at?.[0] ?? 0)
        || (a.at?.[1] ?? 0) - (b.at?.[1] ?? 0) || a.address.localeCompare(b.address));
}

// Scrolling keeps native geometry. Monocle windows occupy the same rectangle,
// so spread its stack horizontally in focus-history order instead.
function positions(windows, layout, monitor, width, selected, pan = false, fit = false, height = Infinity, gapsIn = [0, 0, 0, 0], gapsOut = [0, 0, 0, 0], border = 0, uiScale = 1, order = []) {
    const logicalWidth = (monitor.transform % 2 === 1 ? monitor.height : monitor.width) / monitor.scale;
    const logicalHeight = (monitor.transform % 2 === 1 ? monitor.width : monitor.height) / monitor.scale;
    const scale = Math.min(width / Math.max(1, logicalWidth), height / Math.max(1, logicalHeight));
    const offsetX = (width - logicalWidth * scale) / 2;
    const offsetY = Number.isFinite(height) ? (height - logicalHeight * scale) / 2 : 0;
    const result = {};
    if (layout === "monocle") {
        const rank = new Map(order.map((address, index) => [address, index]));
        const stack = windows.slice().sort((a, b) => (rank.get(a.address) ?? Infinity) - (rank.get(b.address) ?? Infinity)
            || (a.focusHistoryID ?? 0) - (b.focusHistoryID ?? 0)
            || a.address.localeCompare(b.address));
        stack.forEach((w, i) => {
            result[w.address] = { x: i * (width + 18 * uiScale), y: 8 * uiScale,
                width: Math.max(1, w.size[0] * scale), height: Math.max(1, w.size[1] * scale) };
        });
    } else {
        windows.forEach(w => {
            result[w.address] = { x: (w.at[0] - monitor.x) * scale + offsetX,
                y: (w.at[1] - monitor.y) * scale + offsetY,
                width: Math.max(1, w.size[0] * scale), height: Math.max(1, w.size[1] * scale) };
        });
    }
    const target = result[selected];
    let shift = 0;
    if (target && layout === "scrolling" && pan) {
        // Native fit operates on the whole column, before inner gaps and
        // borders are removed from each window's content rectangle.
        const groups = columns(windows);
        const index = groups.findIndex(c => c.windows.includes(selected));
        if (index >= 0) {
            const reserved = monitor.reserved ?? [0, 0, 0, 0];
            const left = offsetX + (reserved[0] + gapsOut[3]) * scale;
            const right = offsetX + (logicalWidth - reserved[2] - gapsOut[1]) * scale;
            const columnLeft = target.x - ((index > 0 ? gapsIn[3] : 0) + border) * scale;
            const columnRight = target.x + target.width + ((index < groups.length - 1 ? gapsIn[1] : 0) + border) * scale;
            shift = !fit || columnRight - columnLeft > right - left
                ? (left + right - columnLeft - columnRight) / 2
                : columnLeft < left ? left - columnLeft : columnRight > right ? right - columnRight : 0;
        }
    } else if (target && layout !== "scrolling") {
        shift = target.width > width ? -target.x : target.x < 0 ? -target.x
            : target.x + target.width > width ? width - target.x - target.width : 0;
    }
    for (const address in result) result[address].x += shift;
    return result;
}

// A column may contain several vertically stacked windows. Navigation skips
// the stack as a unit, matching ScrollOverview's primary-axis arrow keys.
function columns(windows) {
    const result = [];
    for (const w of ordered(windows.filter(w => !w.floating))) {
        let column = result.find(c => Math.abs(c.x - w.at[0]) <= 3);
        if (!column) {
            column = { x: w.at[0], windows: [] };
            result.push(column);
        }
        column.windows.push(w.address);
    }
    return result;
}

// Hyprland returns CSS order (top, right, bottom, left).
function gaps(value) {
    const v = String(value ?? "0").trim().split(/\s+/).map(Number);
    if (!v.length || v.some(n => !Number.isFinite(n))) return [0, 0, 0, 0];
    return [v[0], v[1] ?? v[0], v[2] ?? v[0], v[3] ?? v[1] ?? v[0]];
}
