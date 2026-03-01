//
//  CoreBridge.h
//  RTRBaseline
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//

#pragma once

#include <stdint.h>
#include "CoreCamera.h"

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

// Opaque scene handle managed by CoreCPP.
typedef struct CoreSceneHandle CoreSceneHandle;

typedef struct CoreSceneTransform {
    float position[3];
    float rotation[3];
    float scale[3];
} CoreSceneTransform;

typedef struct CoreSceneObjectData {
    uint32_t objectID;
    uint32_t meshID;
    uint32_t materialID;
    CoreSceneTransform transform;
    uint32_t visible; // 0 or 1
} CoreSceneObjectData;

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

// Build per-object uniforms from base MVP and object transform.
void coreSceneMakeObjectUniforms(CoreUniforms* outUniforms,
                                 const CoreUniforms* baseUniforms,
                                 const CoreSceneTransform* transform);

// Scene management bridge.
CoreSceneHandle* coreSceneCreate(uint32_t initialCapacity);
void coreSceneDestroy(CoreSceneHandle* scene);
uint32_t coreSceneAdd(CoreSceneHandle* scene, uint32_t meshID, uint32_t materialID);
uint32_t coreSceneCount(const CoreSceneHandle* scene);
int32_t coreSceneFind(const CoreSceneHandle* scene, uint32_t objectID, CoreSceneObjectData* outObject);
int32_t coreSceneGetByIndex(const CoreSceneHandle* scene, uint32_t index, CoreSceneObjectData* outObject);
int32_t coreSceneSetTransform(CoreSceneHandle* scene, uint32_t objectID, const CoreSceneTransform* transform);
int32_t coreSceneSetVisible(CoreSceneHandle* scene, uint32_t objectID, uint32_t visible);

#ifdef __cplusplus
} // extern "C"
#endif
