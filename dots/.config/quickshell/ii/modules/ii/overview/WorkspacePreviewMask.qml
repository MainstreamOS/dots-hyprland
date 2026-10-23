import QtQuick

// A window's rounded shape cut to its workspace's rounded shape, both given in
// the window's own coordinates.
ShaderEffect {
    property vector4d windowRect: Qt.vector4d(0, 0, width, height)
    property vector4d windowRadii: Qt.vector4d(0, 0, 0, 0)
    property vector4d workspaceRect
    property vector4d workspaceRadii
    property real workspaceClipped: 1
    readonly property vector2d itemSize: Qt.vector2d(width, height)
    fragmentShader: Qt.resolvedUrl("../../../shaders/workspace_preview_mask.frag.qsb")
}
