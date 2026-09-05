#version 440

// The new picture grows out of the center as a circle. Distances are
// measured in screen proportions, so it is a circle on any screen shape,
// and the radius is scaled to the far corner so the last of the old
// picture is gone exactly at the end.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    vec2 aspectRatio;
};

layout(binding = 1) uniform sampler2D toImage;
layout(binding = 2) uniform sampler2D fromImage;

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 scaled = (uv - vec2(0.5)) * aspectRatio;
    float dist = length(scaled);
    float reach = length(vec2(0.5) * aspectRatio);
    float threshold = progress * reach;
    float edge = 0.004;
    float newMix = 1.0 - smoothstep(threshold - edge, threshold, dist);
    fragColor = mix(texture(fromImage, uv), texture(toImage, uv), newMix) * qt_Opacity;
}
