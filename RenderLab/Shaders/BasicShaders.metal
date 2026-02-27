//
//  BasicShaders.metal
//  RTRBaseline
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 color    [[attribute(1)]];
};

struct Uniforms {
    float4x4 mvp;
};

struct VSOut {
    float4 position [[position]];
    float3 color;
};

struct FragmentDebugParams {
    int mode;   // 0 vertexColor, 1 flatWhite, 2 rawDepth
    int pad0;
    float nearZ;
    float farZ;
};

vertex VSOut vs_main(VertexIn in [[stage_in]],
                     constant Uniforms& u [[buffer(1)]]) {
    VSOut out;
    out.position = u.mvp * float4(in.position, 1.0);
    out.color = in.color;
    return out;
}

// Metal clip-space depth is [0,1] after projection/viewport.
// This reconstructs a view-space-like linear distance (positive).
inline float linearizeDepth01(float depth01, float nearZ, float farZ) {
    // Perspective depth inversion for RH camera with Metal depth [0,1]
    // depth01 is non-linear depth value in [0,1]
    return (nearZ * farZ) / (farZ - depth01 * (farZ - nearZ));
}

fragment float4 fs_main(VSOut in [[stage_in]],
                        constant FragmentDebugParams& dbg [[buffer(0)]]) {
    switch (dbg.mode) {
        case 1: // Flat white
            return float4(1.0, 1.0, 1.0, 1.0);

        case 2: {
            // RawDepth (enhanced for visibility)
            float d = saturate(in.position.z);
            d = 1.0 - d;          // near -> brighter
//            d = pow(d, 0.35);     // contrast boost
            return float4(d, d, d, 1.0);
        }
            
        case 3: {
            // LinearDepth (display-normalized)
            float d = saturate(in.position.z);
            float lin = linearizeDepth01(d, dbg.nearZ, dbg.farZ);

            // Normalize for display. Since your cube is near the camera,
            // showing first few world units gives better contrast than farZ.
            float displayRange = 2.5;
            float v = saturate(lin / displayRange);

            // Invert so near is bright, far is dark
            v = 1.0 - v;

            // Optional contrast shaping
//            v = pow(v, 0.8);

            return float4(v, v, v, 1.0);
        }

        case 0: // Vertex color
        default:
            return float4(in.color, 1.0);
    }
}		
