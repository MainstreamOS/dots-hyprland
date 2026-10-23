#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 windowRect;
    vec4 windowRadii;
    vec4 workspaceRect;
    vec4 workspaceRadii;
    float workspaceClipped;
    vec2 itemSize;
} ubuf;

// Radii are top-left, top-right, bottom-left, bottom-right, as in QML.
float roundedRect(vec2 p, vec4 rect, vec4 radii) {
    vec2 local = p - rect.xy - rect.zw * 0.5;
    float r = local.y < 0.0
        ? (local.x < 0.0 ? radii.x : radii.y)
        : (local.x < 0.0 ? radii.z : radii.w);
    r = clamp(r, 0.0, min(rect.z, rect.w) * 0.5);
    vec2 q = abs(local) - rect.zw * 0.5 + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    vec2 p = qt_TexCoord0 * ubuf.itemSize;
    float d = roundedRect(p, ubuf.windowRect, ubuf.windowRadii);
    if (ubuf.workspaceClipped > 0.5)
        d = max(d, roundedRect(p, ubuf.workspaceRect, ubuf.workspaceRadii));
    float alpha = clamp(0.5 - d / max(fwidth(d), 0.001), 0.0, 1.0);
    fragColor = vec4(alpha) * ubuf.qt_Opacity;
}
