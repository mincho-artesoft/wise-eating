#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// -----------------------------------------------------------------------------
// Simple hash-based random & value-noise helpers
// -----------------------------------------------------------------------------
float random(float2 p)
{
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453123);
}

float noise(float2 p)
{
    float2 i = floor(p);
    float2 f = fract(p);

    float  a = random(i);
    float  b = random(i + float2(1.0, 0.0));
    float  c = random(i + float2(0.0, 1.0));
    float  d = random(i + float2(1.0, 1.0));

    float2 u = f * f * (3.0 - 2.0 * f);      // smooth-step curve

    return mix(a, b, u.x) +
           (c - a) * u.y * (1.0 - u.x) +
           (d - b) * u.x * u.y;
}

// -----------------------------------------------------------------------------
// Liquid-glass shader
// -----------------------------------------------------------------------------
[[stitchable]]
half4 liquidGlass(float2          pos,
                  texture2d<half> sourceTexture,
                  sampler         sourceSampler,
                  float           time,
                  float           strength,
                  float4          frame)
{
    // 1. Get dimensions from the TEXTURE.
    float2 texSize = float2(sourceTexture.get_width(), sourceTexture.get_height());

    // 2. Convert local pos to global UV
    float2 globalPos = frame.xy + pos;
    float2 uv        = globalPos / texSize;

    // 3. Scrolling noise (unchanged)
    float2 p1 = float2(uv.x * 2.0 + time * 0.04, uv.y * 2.0 - time * 0.04);
    float  n1 = noise(p1 * 4.0);
    float2 p2 = float2(uv.x * 1.5 - time * 0.02, uv.y * 1.5 + time * 0.02);
    float  n2 = noise(p2 * 6.0);

    // 4. Displacement with edge fade (unchanged)
    float2 displacement = (float2(n1, n2) * 2.0 - 1.0) * strength;
    float2 localUv = pos / frame.zw;
    float  edgeDist = min(min(localUv.x, 1.0 - localUv.x), min(localUv.y, 1.0 - localUv.y));
    float  edgeFade = smoothstep(0.0, 0.02, edgeDist);
    displacement   *= edgeFade;

    // 5. Distort sampling address
    float2 distortedUv = uv + displacement / texSize;

    // 6. Sample from the TEXTURE using the SAMPLER.
    half4 color = sourceTexture.sample(sourceSampler, distortedUv);

    // 7. Vignette (unchanged)
    float vignette = 1.0 - distance(localUv, float2(0.5)) * 0.3;
    return color * half4(vignette);
}
