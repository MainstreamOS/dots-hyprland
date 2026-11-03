import qs.modules.common
import QtQuick

// An app grid in the scrolling launcher: its recent apps or its full drawer.
ApplicationDrawer {
    id: root
    required property Item launcher

    expandedHeight: collapsedHeight
    availableWidth: width
    headerInteractive: false
    wheelScrolling: true
    workspaceStyle: true
    uiScale: launcher.uiScale
    bare: true
    colBackground: "transparent"
    surfaceRadius: launcher.workspaceRadius(width, height)
    contentColors: Appearance.drawerContent
    compactCells: rowHeight < 110 * uiScale
    columns: 5
    spacing: 10 * uiScale
    iconSize: Math.max(12 * uiScale, Math.min((expanded ? 96 : 75) * uiScale,
        rowHeight - (compactCells ? 28 : 48) * uiScale))
    ownSearchField: false
    onAppDragStarted: (app, sceneX, sceneY) => launcher.beginAppDrag(app, sceneX, sceneY)
    onAppDragUpdate: (sceneX, sceneY) => launcher.updateDrag(sceneX, sceneY)
    onAppDragCancelled: launcher.endAppDrag()
    onAppDropped: (app, sceneX, sceneY) => launcher.dropApp(app, sceneX, sceneY)
}
