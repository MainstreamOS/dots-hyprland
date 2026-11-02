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
    // A panel of workspace rows beside a panel of apps. Each row shows the
    // desktop without the bar's and dock's space, plus half of a two-thirds
    // window to either side, which makes it five thirds of a screen wide.
    const unit = o.unit;
    const reserved = o.reserved ?? [0, 0, 0, 0];
    const usableWidth = Math.max(1, o.screenWidth - reserved[0] - reserved[2]);
    const usableHeight = Math.max(1, o.screenHeight - reserved[1] - reserved[3]);
    const padding = 10 * unit, rowGap = 5 * unit;
    const count = Math.max(1, o.count), shown = Math.max(1, o.shown);
    const fit = k => {
        const inner = 964 * k - padding * 2;
        // Three rows set the size, so fewer leave the panels as they are.
        const previewScale = Math.min((inner - 2 * rowGap) / 3, (inner - (count - 1) * rowGap) / count) / usableHeight;
        const rowWidth = usableWidth * previewScale * 5 / 3;
        const panelWidth = rowWidth + padding * 2;
        const appsWidth = 664 * k, panelGap = 24 * k;
        return { k, previewScale, rowWidth, panelWidth, appsWidth, panelGap,
            total: o.workspacesOnly ? panelWidth : panelWidth + panelGap + appsWidth };
    };
    let size = fit(o.height / 1239);
    if (size.total > o.width - size.panelGap * 2)
        size = fit(size.k * (o.width - size.panelGap * 2) / size.total);
    const k = size.k;
    const trayHeight = 964 * k;
    const trayY = Math.max(o.searchHeight, o.searchHeight + (o.height - o.searchHeight - 90 * k - trayHeight) / 2);
    const left = o.centerX - size.total / 2;
    const swapped = o.swapped && !o.workspacesOnly;
    const panelX = swapped ? left + size.total - size.panelWidth : left;
    const appsX = swapped ? left : left + size.panelWidth + size.panelGap;
    const rowHeight = usableHeight * size.previewScale;
    const panelHeight = padding * 2 + shown * rowHeight + (shown - 1) * rowGap;
    const panelY = trayY + (trayHeight - panelHeight) / 2;
    const plusHeight = 56 * k;
    const drawerOffset = o.recentApps ? 236 * k : 0;
    return {
        scale: k, gap: rowGap, padding, panelGap: size.panelGap, plusHeight,
        totalWidth: size.total, panelHeight, previewScale: size.previewScale,
        slotHeight: rowHeight, previewWidth: o.screenWidth * size.previewScale,
        workspace: { x: panelX + padding, y: panelY + padding, width: size.rowWidth,
            height: panelHeight - padding + size.panelGap + plusHeight },
        apps: { x: appsX, y: trayY, width: size.appsWidth, height: trayHeight },
        recentHeight: 226 * k, drawerOffset, drawerHeight: trayHeight - drawerOffset
    };
}
