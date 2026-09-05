#version 440

// A ring that travels out from the center and reveals the new picture
// behind it. Distances are measured in screen proportions, so the ring
// is a circle on any screen shape and reaches the far corners at the end.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float time;
    vec2 aspectRatio;
};

layout(binding = 1) uniform sampler2D source1;
layout(binding = 2) uniform sampler2D source2;

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 center = vec2(0.5);
    vec2 scaled = (uv - center) * aspectRatio;
    float dist = length(scaled);
    float reach = length(vec2(0.5) * aspectRatio) + 0.05;
    float waveFront = progress * reach;
    float wave = sin((dist - waveFront) * 35.0) * exp(-abs(dist - waveFront) * 10.0);
    float strength = wave * 0.04;
    vec2 dir = normalize((uv - center) + vec2(0.0001));
    vec2 uvDistorted = uv + dir * strength;
    float revealMask = step(dist, waveFront);
    vec4 colorOld = texture(source1, uvDistorted);
    vec4 colorNew = texture(source2, uvDistorted);
    vec4 result = mix(colorOld, colorNew, revealMask);
    result.rgb += vec3(max(wave, 0.0)) * 0.25;
    fragColor = result * qt_Opacity;
}
