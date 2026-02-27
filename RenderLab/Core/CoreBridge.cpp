//
//  CoreBridge.cpp
//  RTRBaseline
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//

#include "CoreBridge.h"
#include "CoreMath.hpp"
#include <new>

void coreMakeTriangle(CoreVertex** outVertices, int32_t* outVertexCount,
                      uint16_t** outIndices, int32_t* outIndexCount) {
    if (!outVertices || !outVertexCount || !outIndices || !outIndexCount) return;

    *outVertexCount = 3;
    *outIndexCount = 3;

    CoreVertex* v = new CoreVertex[*outVertexCount];
    uint16_t* i = new uint16_t[*outIndexCount];

    // CCW triangle in clip-friendly space
    v[0] = { { -0.6f, -0.4f, 0.0f }, { 1.0f, 0.2f, 0.2f } };
    v[1] = { {  0.0f,  0.6f, 0.0f }, { 0.2f, 1.0f, 0.2f } };
    v[2] = { {  0.6f, -0.4f, 0.0f }, { 0.2f, 0.4f, 1.0f } };

    i[0] = 0; i[1] = 1; i[2] = 2;

    *outVertices = v;
    *outIndices = i;
}

void coreMakeCube(CoreVertex** outVertices, int32_t* outVertexCount,
                  uint16_t** outIndices, int32_t* outIndexCount) {
    if (!outVertices || !outVertexCount || !outIndices || !outIndexCount) return;

    // 6 faces * 4 verts each = 24 (duplicate corners per face is intentional)
    *outVertexCount = 24;
    *outIndexCount = 36; // 6 faces * 2 tris * 3

    CoreVertex* v = new CoreVertex[*outVertexCount];
    uint16_t* i = new uint16_t[*outIndexCount];

    const float s = 0.5f;

    // Face colors (easy to debug)
    const float red[3]    = {1.0f, 0.2f, 0.2f};
    const float green[3]  = {0.2f, 1.0f, 0.2f};
    const float blue[3]   = {0.2f, 0.4f, 1.0f};
    const float yellow[3] = {1.0f, 1.0f, 0.2f};
    const float mag[3]    = {1.0f, 0.2f, 1.0f};
    const float cyan[3]   = {0.2f, 1.0f, 1.0f};

    auto setV = [&](int idx, float x, float y, float z, const float c[3]) {
        v[idx].position[0] = x;
        v[idx].position[1] = y;
        v[idx].position[2] = z;
        v[idx].color[0] = c[0];
        v[idx].color[1] = c[1];
        v[idx].color[2] = c[2];
    };

    // IMPORTANT:
    // Indices below assume CCW winding when viewed from OUTSIDE the cube.
    // This is good for Metal when frontFacing = .counterClockwise (default is usually clockwise unless set via raster state,
    // but with culling off it still renders; depth test correctness is unaffected by cull state).

    // Face 0: +Z (front) - cyan
    setV( 0, -s, -s,  s, cyan);
    setV( 1,  s, -s,  s, cyan);
    setV( 2,  s,  s,  s, cyan);
    setV( 3, -s,  s,  s, cyan);

    // Face 1: -Z (back) - red
    setV( 4,  s, -s, -s, red);
    setV( 5, -s, -s, -s, red);
    setV( 6, -s,  s, -s, red);
    setV( 7,  s,  s, -s, red);

    // Face 2: -X (left) - green
    setV( 8, -s, -s, -s, green);
    setV( 9, -s, -s,  s, green);
    setV(10, -s,  s,  s, green);
    setV(11, -s,  s, -s, green);

    // Face 3: +X (right) - blue
    setV(12,  s, -s,  s, blue);
    setV(13,  s, -s, -s, blue);
    setV(14,  s,  s, -s, blue);
    setV(15,  s,  s,  s, blue);

    // Face 4: +Y (top) - yellow
    setV(16, -s,  s,  s, yellow);
    setV(17,  s,  s,  s, yellow);
    setV(18,  s,  s, -s, yellow);
    setV(19, -s,  s, -s, yellow);

    // Face 5: -Y (bottom) - magenta
    setV(20, -s, -s, -s, mag);
    setV(21,  s, -s, -s, mag);
    setV(22,  s, -s,  s, mag);
    setV(23, -s, -s,  s, mag);

    // 6 faces * 2 triangles
    uint16_t idx[36] = {
        // +Z
         0,  1,  2,   0,  2,  3,
        // -Z
         4,  5,  6,   4,  6,  7,
        // -X
         8,  9, 10,   8, 10, 11,
        // +X
        12, 13, 14,  12, 14, 15,
        // +Y
        16, 17, 18,  16, 18, 19,
        // -Y
        20, 21, 22,  20, 22, 23
    };

    for (int k = 0; k < 36; ++k) i[k] = idx[k];

    *outVertices = v;
    *outIndices = i;
}

void coreFreeMesh(CoreVertex* vertices, uint16_t* indices) {
    delete[] vertices;
    delete[] indices;
}

void coreMakeDefaultUniforms(CoreUniforms* outUniforms, float timeSeconds, float aspect) {
    if (!outUniforms) return;

    using namespace coremath;
    
    // ASK: what are these functions? especially lookAt and perspective
    const Mat4 model = rotationY(timeSeconds) * rotationX(timeSeconds * 0.5f);
    const Mat4 view  = lookAt({0.0f, 0.0f, 2.2f}, {0.0f, 0.0f, 0.0f}, {0.0f, 1.0f, 0.0f});
    const Mat4 proj  = perspective(60.0f * kDegToRad, aspect, 0.1f, 100.0f);

    const Mat4 mvp = proj * view * model;

    // Copy to float[16] column-major
    for (int c = 0; c < 4; ++c) {
        for (int r = 0; r < 4; ++r) {
            outUniforms->mvp[c*4 + r] = mvp.m[c][r];
        }
    }
}

void coreMakeOrbitUniforms(CoreUniforms* outUniforms,
                           float timeSeconds,
                           float aspect,
                           const float target[3],
                           float radius,
                           float yaw,
                           float pitch) {
    if (!outUniforms || !target) return;

    using namespace coremath;

    // Clamp radius / pitch for stability
    if (radius < 0.8f) radius = 0.8f;
    if (radius > 50.0f) radius = 50.0f;

    const float kPitchLimit = 1.4f; // ~80 degrees
    if (pitch < -kPitchLimit) pitch = -kPitchLimit;
    if (pitch >  kPitchLimit) pitch =  kPitchLimit;

    // Orbit camera position in RH coordinates around target
    const float cp = std::cos(pitch);
    const float sp = std::sin(pitch);
    const float cy = std::cos(yaw);
    const float sy = std::sin(yaw);

    const Vec3 tgt { target[0], target[1], target[2] };
    const Vec3 eye {
        tgt.x + radius * cp * sy,
        tgt.y + radius * sp,
        tgt.z + radius * cp * cy
    };

    // Model (optional rotation so the cube still animates)
    const Mat4 model = rotationY(timeSeconds * 0.1f) * rotationX(timeSeconds * 0.1f);

    // View + Projection
    const Mat4 view = lookAt(eye, tgt, {0.0f, 1.0f, 0.0f});
    const Mat4 proj = perspective(60.0f * kDegToRad, aspect, 0.1f, 100.0f);

    const Mat4 mvp = proj * view * model;

    // Copy to float[16] column-major
    for (int c = 0; c < 4; ++c) {
        for (int r = 0; r < 4; ++r) {
            outUniforms->mvp[c * 4 + r] = mvp.m[c][r];
        }
    }
}
