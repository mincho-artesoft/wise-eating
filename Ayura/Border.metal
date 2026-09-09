#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// Signed Distance Function for a 2D capsule shape.
// This function is very efficient for defining shapes with rounded corners.
float capsuleSDF(float2 p, float2 size, float radius) {
    p.x = abs(p.x);
    p = p - size;
    return length(max(p, float2(0.0))) - radius;
}

// ✅ NEW SHADER FUNCTION
[[stitchable]]
half4 glassyBorder(float2          pos,
                   texture2d<half> sourceTexture,
                   sampler         sourceSampler,
                   float4          frame,
                   float           thickness,
                   float           refraction)
{
    float2 size = frame.zw;
    float2 texSize = float2(sourceTexture.get_width(), sourceTexture.get_height());
    float  radius = min(size.x, size.y) / 2.0;

    // Center the coordinates so (0,0) is the middle of the shape
    float2 centerRelativePos = pos - size / 2.0;
    
    // Calculate distance from the center-line of the border stroke.
    // Negative values are inside the stroke, positive are outside.
    float dist = abs(capsuleSDF(centerRelativePos, float2(size.x / 2.0 - radius, 0.0), radius)) - thickness / 2.0;
    
    // If we are outside the border area, return a transparent color.
    if (dist > 0.0) {
        return half4(0.0);
    }
    
    // Calculate the surface normal using the gradient of the SDF.
    // This gives us the direction pointing away from the surface, crucial for lighting.
    float2 epsilon = float2(0.5, 0.0);
    float2 normal = normalize(
        float2(capsuleSDF(centerRelativePos + epsilon.xy, float2(size.x / 2.0 - radius, 0.0), radius) -
               capsuleSDF(centerRelativePos - epsilon.xy, float2(size.x / 2.0 - radius, 0.0), radius),
               capsuleSDF(centerRelativePos + epsilon.yx, float2(size.x / 2.0 - radius, 0.0), radius) -
               capsuleSDF(centerRelativePos - epsilon.yx, float2(size.x / 2.0 - radius, 0.0), radius)
        )
    );

    // --- REFRACTION ---
    // Displace the texture coordinates based on the surface normal to simulate light bending.
    float2 refractedUV = (frame.xy + pos - normal * refraction) / texSize;
    half4 refractedColor = sourceTexture.sample(sourceSampler, refractedUV);

    // --- LIGHTING ---
    // Simulate a light source from the top-left.
    float3 lightDir = normalize(float3(-0.7, -0.7, 1.0));
    float ndotl = saturate(dot(float3(normal, 1.0), lightDir));

    // Create a bright, sharp specular highlight.
    half3 highlight = half3(pow(ndotl, 90.0) * 0.8);
    
    // Create a subtle ambient occlusion/shadow effect on the opposite side.
    half3 shadow = half3(1.0 - pow(saturate(1.0 - ndotl), 2.0)) * 0.1;
    
    // --- COMBINE & APPLY ALPHA ---
    // Combine the refracted color with the lighting effects.
    half3 finalColor = refractedColor.rgb * 0.8 + highlight - shadow;
    
    // Use smoothstep to create a soft, anti-aliased alpha for the border.
    half alpha = smoothstep(0.0, -1.0, dist);
    
    return half4(finalColor, alpha);
}
