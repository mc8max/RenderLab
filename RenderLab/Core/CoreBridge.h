//
//  CoreBridge.h
//  RenderLab
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

typedef enum CoreInterpScalarMode {
    CORE_INTERP_SCALAR_LERP = 0,
    CORE_INTERP_SCALAR_SMOOTHSTEP = 1,
    CORE_INTERP_SCALAR_CUBIC = 2
} CoreInterpScalarMode;

typedef enum CoreInterpRotationMode {
    CORE_INTERP_ROT_EULER_LERP = 0,
    CORE_INTERP_ROT_QUAT_NLERP = 1,
    CORE_INTERP_ROT_QUAT_SLERP = 2
} CoreInterpRotationMode;

typedef enum CoreInterpLoopMode {
    CORE_INTERP_LOOP_CLAMP = 0,
    CORE_INTERP_LOOP_REPEAT = 1,
    CORE_INTERP_LOOP_PINGPONG = 2
} CoreInterpLoopMode;

typedef struct CoreInterpConfig {
    int32_t positionMode;
    int32_t rotationMode;
    int32_t scaleMode;
    uint32_t shortestPath;
} CoreInterpConfig;

typedef struct CoreInterpPlaybackState {
    float t;
    float speed;
    int32_t loopMode;
    uint32_t isPlaying;
    int32_t direction;
} CoreInterpPlaybackState;

typedef struct CoreInterpDebug {
    float alphaPosition;
    float alphaScale;
    float distanceToA;
    float distanceToB;
} CoreInterpDebug;

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

void coreInterpSetDefaultConfig(CoreInterpConfig* outConfig);
void coreInterpSetDefaultPlaybackState(CoreInterpPlaybackState* outState);
int32_t coreInterpAdvancePlaybackState(CoreInterpPlaybackState* ioState,
                                       float deltaSeconds,
                                       float* outT);
int32_t coreInterpEvaluateTransform(const CoreSceneTransform* a,
                                    const CoreSceneTransform* b,
                                    float t,
                                    const CoreInterpConfig* config,
                                    CoreSceneTransform* outTransform,
                                    CoreInterpDebug* outDebug);
int32_t coreInterpMakeObjectUniforms(const CoreUniforms* baseUniforms,
                                     const CoreSceneTransform* a,
                                     const CoreSceneTransform* b,
                                     float t,
                                     const CoreInterpConfig* config,
                                     CoreUniforms* outUniforms,
                                     CoreSceneTransform* outTransform,
                                     CoreInterpDebug* outDebug);
int32_t coreInterpMakeGhostUniforms(const CoreUniforms* baseUniforms,
                                    const CoreSceneTransform* a,
                                    const CoreSceneTransform* b,
                                    CoreUniforms* outUniformsA,
                                    CoreUniforms* outUniformsB);

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
