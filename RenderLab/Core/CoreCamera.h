//
//  CoreCamera.h
//  RenderLab
//
//  Engine-style orbit camera state + controls exposed through C ABI.
//

#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Forward declaration from CoreBridge.h (shared shader uniforms).
typedef struct CoreUniforms CoreUniforms;

// Orbit camera POD state (C ABI safe).
typedef struct CoreCameraState {
    float target[3];
    float radius;
    float yaw;
    float pitch;
} CoreCameraState;

// Camera params/config (C ABI safe).
typedef struct CoreCameraParams {
    float fovYDegrees;
    float nearZ;
    float farZ;

    float minRadius;
    float maxRadius;
    float minPitch;
    float maxPitch;

    float orbitSensitivity;
    float zoomSensitivity;
    float panSensitivity;
} CoreCameraParams;

void coreCameraSetDefaultState(CoreCameraState* outState);
void coreCameraSetDefaultParams(CoreCameraParams* outParams);
void coreCameraSanitize(CoreCameraState* ioState, const CoreCameraParams* params);
void coreCameraOrbit(CoreCameraState* ioState, float deltaX, float deltaY, const CoreCameraParams* params);
void coreCameraZoom(CoreCameraState* ioState, float delta, const CoreCameraParams* params);
void coreCameraPan(CoreCameraState* ioState, float deltaRight, float deltaUp, const CoreCameraParams* params);
void coreCameraBuildOrbitUniforms(CoreUniforms* outUniforms,
                                  float timeSeconds,
                                  float aspect,
                                  const CoreCameraState* camera,
                                  const CoreCameraParams* params);

#ifdef __cplusplus
} // extern "C"
#endif
