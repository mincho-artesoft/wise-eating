#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// This "Intelligent Contrast" shader accepts a 'whiteThreshold' from SwiftUI
// to create a bias in the color decision, preventing fragmentation.
[[stitchable]] half4 intelligentContrastColor(float2 pos, half4 color, float whiteThreshold) {
    // The input 'color' comes from a layer with .grayscale(1.0) applied in SwiftUI.
    // This means its r, g, and b components are all equal to the background's luminance.
    // We can simply pick one channel (e.g., 'r') instead of doing a full luminance
    // calculation, which is more efficient.
    float luminance = color.r;

    // Define our contrast colors, preserving the original alpha.
    half4 black = half4(0.0, 0.0, 0.0, color.a);
    half4 white = half4(1.0, 1.0, 1.0, color.a);

    // THE CORE LOGIC:
    // The step function returns 0.0 if luminance is less than whiteThreshold, and 1.0 otherwise.
    // The mix() function then interpolates between 'white' and 'black'.
    //
    // Example with whiteThreshold = 0.65:
    // - If background is dark/mid-tone (luminance < 0.65), step() returns 0.0, mix() chooses 'white'.
    // - If background is very bright (luminance >= 0.65), step() returns 1.0, mix() chooses 'black'.
    //
    // This correctly implements the desired "prefer white" behavior.
    return mix(white, black, step(whiteThreshold, luminance));
}
