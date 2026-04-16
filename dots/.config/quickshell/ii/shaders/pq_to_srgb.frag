#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float sdrPaperWhite;  // SDR reference white in nits (default 203)
};

// ST.2084 (PQ) constants
const float m1 = 0.1593017578125;
const float m2 = 78.84375;
const float c1 = 0.8359375;
const float c2 = 18.8515625;
const float c3 = 18.6875;
const float peakNits = 10000.0;

// Decode PQ transfer function: PQ-encoded [0,1] -> linear nits [0,10000]
vec3 pqToLinear(vec3 pq) {
    vec3 p = pow(clamp(pq, 0.0, 1.0), vec3(1.0 / m2));
    vec3 num = max(p - c1, 0.0);
    vec3 den = c2 - c3 * p;
    return pow(num / max(den, 1e-6), vec3(1.0 / m1)) * peakNits;
}

// BT.2020 -> BT.709 (sRGB) color matrix
vec3 bt2020ToSrgb(vec3 c) {
    return vec3(
        dot(c, vec3( 1.6605, -0.5877, -0.0728)),
        dot(c, vec3(-0.1246,  1.1330, -0.0084)),
        dot(c, vec3(-0.0182, -0.1006,  1.1187))
    );
}

// Reinhard tone-mapping: maps paperWhite -> 0.5 linear, compresses highlights
vec3 tonemap(vec3 nits, float paperWhite) {
    vec3 scaled = nits / paperWhite;
    return scaled / (1.0 + scaled);
}

// Linear -> sRGB gamma
vec3 linearToSrgb(vec3 c) {
    vec3 lo = c * 12.92;
    vec3 hi = 1.055 * pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.4)) - 0.055;
    return mix(lo, hi, step(0.0031308, c));
}

void main() {
    vec4 tex = texture(source, qt_TexCoord0);

    // PQ decode -> linear nits
    vec3 linearHdr = pqToLinear(tex.rgb);

    // BT.2020 -> BT.709 gamut
    vec3 srgbLinear = bt2020ToSrgb(linearHdr);

    // Tone-map to SDR range (paperWhite maps to 0.5)
    vec3 tonemapped = tonemap(max(srgbLinear, 0.0), sdrPaperWhite);

    // Apply sRGB gamma
    vec3 srgb = linearToSrgb(clamp(tonemapped, 0.0, 1.0));

    fragColor = vec4(srgb, tex.a) * qt_Opacity;
}
