.pragma library

function workspaceGrid(o) {
    const monitor = o.monitor;
    const reserved = o.reserved;
    const rotated = monitor.transform % 2 === 1;
    const desktopWidth = ((rotated ? monitor.height : monitor.width) - reserved[0] - reserved[2]) / monitor.scale;
    const desktopHeight = Math.max(1, ((rotated ? monitor.width : monitor.height) - reserved[1] - reserved[3]) / monitor.scale);
    const rows = Math.max(1, o.rows), columns = Math.max(1, o.columns);
    const gap = 5 * o.unit;
    // The default 5x2 grid defines the height ceiling. Fewer rows may use
    // taller cells; the Size setting scales the fitted cells, not the gaps.
    const cellHeight = o.size / 100 * Math.max(0, Math.min(
        (desktopHeight * 0.36 + gap * (2 - rows)) / rows,
        desktopHeight * 0.9 / columns, desktopHeight * 0.9 / rows));
    const previewScale = cellHeight / desktopHeight;
    const height = rows * cellHeight + (rows - 1) * gap;
    return {
        reserved, gap, previewScale,
        cellWidth: desktopWidth * previewScale, cellHeight,
        // Shared height budget from the workspace grid through the drawer.
        bodyHeight: height + (400 + 40 + o.elevation) * o.unit
    };
}

function scrolling(o) {
    // Fit workspace previews and panels to the available logical screen area.
    // Text and controls retain their native logical sizes in the callers.
    const unit = o.unit;
    const width = o.width / unit, height = o.height / unit;
    const aspect = o.aspect;
    const top = o.searchHeight / unit;
    const availableHeight = Math.max(1 / unit, Math.min(o.bodyHeight / unit, height - top));
    const designWidth = Math.max(1, Math.min(2512,
        (1440 * aspect - (o.horizontalDock ? 0 : o.dockSize * 2)) * 0.89,
        (1440 - 114 - (o.horizontalDock ? o.dockSize : 0)) * aspect));
    const designColumn = o.workspacesOnly ? designWidth : (designWidth - 24) / 2;
    // The body is 0.945 columns tall plus 76 units of gutters, fitted directly
    // whatever the number of occupied workspaces.
    const designStack = Math.min(designWidth / aspect, designColumn * 0.945 + 76);
    const fit = Math.max(0.01 / unit, Math.min(width / 2512, availableHeight / designStack));
    const scale = unit * fit;
    const gap = 24 * scale, plusHeight = 56 * scale;
    const columnWidth = Math.max(1, designColumn * scale);
    const stackHeight = designStack * scale;

    // The app launcher UI keeps a fixed geometry based on the default 3-workspace
    // composition so changing the number of visible workspaces does not resize it.
    const baseCount = 3;
    let baseSlotHeight = Math.max(1, Math.min(
        (stackHeight - plusHeight - gap * baseCount) / baseCount,
        columnWidth * 0.8 / aspect));
    let basePreviewWidth = Math.max(1, Math.min(columnWidth * 0.8, baseSlotHeight * aspect));
    // Symmetrical 9-inch panel sizing:
    // Both windows on the left and right of the workspace card overhang symmetrically,
    // each showing ~half the window and fading out to transparent at the panel edge.
    // Added together, the visible workspace (left overhang + card + right overhang)
    // and the 6-column app drawer each measure exactly ~9 inches.
    const overhang = Math.round(basePreviewWidth * 0.30);
    let appsWidth = basePreviewWidth + 2 * overhang;
    if (!o.workspacesOnly) {
        const drawerEdge = w => {
            const oh = Math.round(w * 0.30);
            return o.centerX + gap / 2 + w + 2 * oh;
        };
        const limit = Math.min(o.width, 2 * o.centerX) - gap;
        if (drawerEdge(basePreviewWidth) > limit) {
            let lo = 1, hi = basePreviewWidth;
            for (let i = 0; i < 24; i++) {
                const mid = (lo + hi) / 2;
                if (drawerEdge(mid) > limit) hi = mid; else lo = mid;
            }
            basePreviewWidth = lo;
            baseSlotHeight = Math.min(baseSlotHeight, basePreviewWidth / aspect);
            appsWidth = basePreviewWidth + 2 * Math.round(basePreviewWidth * 0.30);
        }
    }
    const panelHeight = (baseCount - 1) * (baseSlotHeight + gap) + basePreviewWidth / aspect;
    const panelTop = Math.max(top * unit, o.centerY - panelHeight / 2);
    const visibleWidth = o.workspacesOnly ? columnWidth : appsWidth;
    const leftWorkspaceX = o.workspacesOnly ? (o.width - columnWidth) / 2
        : o.centerX - gap / 2 - visibleWidth;
    const rightAppsX = o.centerX + gap / 2;
    // Mirror each complete panel symmetrically when sides are swapped.
    const swapped = o.swapped && !o.workspacesOnly;
    const workspaceX = swapped ? rightAppsX : leftWorkspaceX;
    const appsX = swapped ? o.centerX - gap / 2 - appsWidth : rightAppsX;
    const drawerOffset = o.recentApps ? 294 * scale : 0;

    // Workspace preview slots scale to fit the configured visible count.
    const maxPreviewWidth = o.workspacesOnly ? columnWidth * 0.8 : basePreviewWidth;
    let slotHeight = Math.max(1, Math.min(
        (stackHeight - plusHeight - gap * o.count) / o.count,
        maxPreviewWidth / aspect));
    let previewWidth = Math.max(1, Math.min(maxPreviewWidth, slotHeight * aspect));
    const insetFor = count => Math.max(0, (stackHeight - count * (slotHeight + gap) - plusHeight) / 2);
    const workspaceOffset = insetFor(o.shown) - (o.count > 1 ? insetFor(o.count) : 0);

    return {
        scale, gap, plusHeight, columnWidth, slotHeight, previewWidth, inset: 0,
        overhang,
        workspace: { x: workspaceX, y: panelTop + workspaceOffset, width: visibleWidth,
            height: stackHeight - insetFor(o.shown) },
        apps: { x: appsX, y: panelTop, width: appsWidth, height: panelHeight },
        recentHeight: 270 * scale,
        drawerOffset, drawerHeight: Math.max(1, panelHeight - drawerOffset)
    };
}
