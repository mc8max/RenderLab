//
//  CoreBridge.h
//  RTRBaseline
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//

#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Shared vertex layout (matches Metal shader)
typedef struct CoreVertex {
    float position[3];
    float color[3];
} CoreVertex;

// Shared uniforms (matches Metal shader)
typedef struct CoreUniforms {
    float mvp[16]; // column-major 4x4
} CoreUniforms;

// Allocates a simple triangle. Call coreFreeMesh to free.
void coreMakeTriangle(CoreVertex** outVertices, int32_t* outVertexCount,
                      uint16_t** outIndices, int32_t* outIndexCount);

// Allocate a Cube. Call coreFreeMesh to free.
void coreMakeCube(CoreVertex** outVertices, int32_t* outVertexCount,
                  uint16_t** outIndices, int32_t* outIndexCount);


// Frees allocations returned by coreMakeTriangle or coreMakeCube.
void coreFreeMesh(CoreVertex* vertices, uint16_t* indices);

// Fills CoreUniforms with a default rotating model + perspective projection.
void coreMakeDefaultUniforms(CoreUniforms* outUniforms, float timeSeconds, float aspect);

// Camera Introduction
void coreMakeOrbitUniforms(CoreUniforms* outUniforms,
                           float timeSeconds,
                           float aspect,
                           const float target[3],
                           float radius,
                           float yaw,
                           float pitch);

#ifdef __cplusplus
} // extern "C"
#endif
