#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float sdrPaperWhite;  // SDR reference white in nits (default 203)
    float toneMapHdr;
    vec2 texelStep;
    vec2 footprint;
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

// Catmull-Rom area filter adapted from Andrew Lee's end4-pC a247231.
const int maxTaps = 8;

float catmullRom(float x) {
    x = abs(x);
    if (x < 1.0) return (1.5 * x - 2.5) * x * x + 1.0;
    if (x < 2.0) return ((-0.5 * x + 2.5) * x - 4.0) * x + 2.0;
    return 0.0;
}

vec4 samplePreview() {
    if (max(footprint.x, footprint.y) <= 0.0)
        return texture(source, qt_TexCoord0);

    vec2 scale = max(footprint, vec2(1.0));
    vec2 stride = max(vec2(1.0), ceil(2.0 * scale / float(maxTaps)));
    vec2 pos = qt_TexCoord0 / texelStep;
    vec2 center = floor(pos) + 0.5;
    vec2 weights[2 * maxTaps + 1];
    for (int i = 0; i <= 2 * maxTaps; i++) {
        vec2 distance = (center + float(i - maxTaps) * stride - pos) / scale;
        weights[i] = vec2(catmullRom(distance.x), catmullRom(distance.y));
    }

    vec4 sum = vec4(0.0);
    float weightSum = 0.0;
    for (int y = 0; y <= 2 * maxTaps; y++) {
        if (weights[y].y == 0.0) continue;
        for (int x = 0; x <= 2 * maxTaps; x++) {
            if (weights[x].x == 0.0) continue;
            float weight = weights[x].x * weights[y].y;
            vec2 tap = center + vec2(float(x - maxTaps), float(y - maxTaps)) * stride;
            sum += weight * texture(source, tap * texelStep);
            weightSum += weight;
        }
    }
    vec4 color = clamp(sum / max(weightSum, 1e-6), 0.0, 1.0);
    return vec4(min(color.rgb, vec3(color.a)), color.a);
}

void main() {
    vec4 tex = samplePreview();
    if (toneMapHdr == 0.0) {
        fragColor = tex * qt_Opacity;
        return;
    }

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
