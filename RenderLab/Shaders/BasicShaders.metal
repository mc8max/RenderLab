//
//  BasicShaders.metal
//  RenderLab
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

struct SkinnedVertexIn {
    float3 position [[attribute(0)]];
    float3 color [[attribute(1)]];
    ushort4 boneIndices [[attribute(2)]];
    float4 boneWeights [[attribute(3)]];
};

struct SkinningVertexParams {
    uint boneCount;
    int debugMode;
    uint selectedBoneIndex;
    float weightSumTolerance;
};

struct MorphVertexParams {
    uint enabled;
    float weight;
    int debugMode;
    uint selectedTargetIndex;
};

struct FragmentDebugParams {
    int mode;   // 0 vertexColor, 1 flatWhite, 2 rawDepth
    uint isSelected;
    float nearZ;
    float farZ;
};

struct GhostFragmentParams {
    float4 color;
};

inline float3 applySelectionHighlight(float3 color, uint isSelected) {
    if (isSelected == 0u) {
        return color;
    }
    return saturate(color * 1.35);
}

inline float3 debugBoneColor(uint boneIndex) {
    constexpr float3 palette[8] = {
        float3(0.95, 0.24, 0.22),
        float3(0.22, 0.85, 0.30),
        float3(0.22, 0.58, 0.98),
        float3(0.98, 0.78, 0.20),
        float3(0.75, 0.32, 0.95),
        float3(0.15, 0.86, 0.86),
        float3(0.98, 0.52, 0.23),
        float3(0.82, 0.88, 0.20)
    };
    return palette[boneIndex % 8u];
}

inline float3 heatmapColor(float t) {
    t = saturate(t);
    float3 cold = float3(0.06, 0.24, 0.95);
    float3 warm = float3(0.98, 0.15, 0.12);
    return mix(cold, warm, t);
}

vertex VSOut vs_main(VertexIn in [[stage_in]],
                     constant Uniforms& u [[buffer(1)]]) {
    VSOut out;
    out.position = u.mvp * float4(in.position, 1.0);
    out.color = in.color;
    return out;
}

vertex VSOut vs_skin_main(SkinnedVertexIn in [[stage_in]],
                          constant Uniforms& u [[buffer(1)]],
                          constant float4x4* boneMatrices [[buffer(2)]],
                          constant SkinningVertexParams& params [[buffer(3)]]) {
    VSOut out;
    float4 local = float4(in.position, 1.0);

    if (params.boneCount == 0u) {
        out.position = u.mvp * local;
        out.color = in.color;
        return out;
    }

    float4 weights = in.boneWeights;
    float weightSum = weights.x + weights.y + weights.z + weights.w;
    if (weightSum > 1e-6f) {
        weights /= weightSum;
    } else {
        weights = float4(1.0, 0.0, 0.0, 0.0);
    }

    uint maxValidIndex = params.boneCount - 1u;
    uint4 indices = min(uint4(in.boneIndices), uint4(maxValidIndex));

    float4 skinnedPosition =
        weights.x * (boneMatrices[indices.x] * local)
        + weights.y * (boneMatrices[indices.y] * local)
        + weights.z * (boneMatrices[indices.z] * local)
        + weights.w * (boneMatrices[indices.w] * local);

    out.position = u.mvp * skinnedPosition;
    out.color = in.color;

    if (params.debugMode == 1) {
        float4 candidate = weights;
        uint4 rawIndices = uint4(in.boneIndices);
        uint best = 0u;
        float bestWeight = candidate.x;
        if (candidate.y > bestWeight) {
            bestWeight = candidate.y;
            best = 1u;
        }
        if (candidate.z > bestWeight) {
            bestWeight = candidate.z;
            best = 2u;
        }
        if (candidate.w > bestWeight) {
            bestWeight = candidate.w;
            best = 3u;
        }
        out.color = debugBoneColor(min(rawIndices[best], maxValidIndex));
    } else if (params.debugMode == 2) {
        uint selectedBone = min(params.selectedBoneIndex, maxValidIndex);
        float selectedWeight = 0.0f;
        if (uint(in.boneIndices.x) == selectedBone) selectedWeight += max(weights.x, 0.0f);
        if (uint(in.boneIndices.y) == selectedBone) selectedWeight += max(weights.y, 0.0f);
        if (uint(in.boneIndices.z) == selectedBone) selectedWeight += max(weights.z, 0.0f);
        if (uint(in.boneIndices.w) == selectedBone) selectedWeight += max(weights.w, 0.0f);
        out.color = heatmapColor(selectedWeight);
    } else if (params.debugMode == 3) {
        float delta = fabs(weightSum - 1.0f);
        out.color = (delta <= params.weightSumTolerance)
            ? float3(0.18, 0.88, 0.24)
            : float3(0.95, 0.16, 0.16);
    } else if (params.debugMode == 4) {
        bool valid = (uint(in.boneIndices.x) < params.boneCount)
            && (uint(in.boneIndices.y) < params.boneCount)
            && (uint(in.boneIndices.z) < params.boneCount)
            && (uint(in.boneIndices.w) < params.boneCount);
        out.color = valid ? float3(0.18, 0.88, 0.24) : float3(0.95, 0.16, 0.16);
    }
    return out;
}

vertex VSOut vs_morph_main(VertexIn in [[stage_in]],
                           constant Uniforms& u [[buffer(1)]],
                           constant float4* morphDeltaPositions [[buffer(2)]],
                           constant MorphVertexParams& params [[buffer(3)]],
                           uint vertexID [[vertex_id]]) {
    VSOut out;
    float4 local = float4(in.position, 1.0);

    float clampedWeight = clamp(params.weight, 0.0f, 1.0f);
    float3 appliedDelta = float3(0.0);
    if (params.enabled != 0u) {
        appliedDelta = morphDeltaPositions[vertexID].xyz * clampedWeight;
        local.xyz += appliedDelta;
    }

    out.position = u.mvp * local;
    out.color = in.color;

    if (params.debugMode == 1) {
        float normalizedMagnitude = saturate(length(appliedDelta) / 0.35f);
        out.color = heatmapColor(normalizedMagnitude);
    }

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
        case 1: { // Flat white
            float3 color = float3(1.0, 1.0, 1.0);
            color = applySelectionHighlight(color, dbg.isSelected);
            return float4(color, 1.0);
        }

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
            return float4(applySelectionHighlight(in.color, dbg.isSelected), 1.0);
    }
}

fragment float4 fs_ghost(VSOut in [[stage_in]],
                         constant GhostFragmentParams& ghost [[buffer(0)]]) {
    (void)in;
    return ghost.color;
}

struct HUDVertexIn {
    float2 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
};

struct HUDVSOut {
    float4 position [[position]];
    float2 uv;
};

vertex HUDVSOut vs_hud_overlay(HUDVertexIn in [[stage_in]]) {
    HUDVSOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.uv = in.uv;
    return out;
}

fragment float4 fs_hud_overlay(
    HUDVSOut in [[stage_in]],
    texture2d<float> overlayTexture [[texture(0)]],
    sampler overlaySampler [[sampler(0)]]
) {
    return overlayTexture.sample(overlaySampler, in.uv);
}
