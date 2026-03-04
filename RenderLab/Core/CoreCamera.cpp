//
//  CoreCamera.cpp
//  RenderLab
//
//  Engine-style orbit camera implementation for platform-agnostic reuse.
//

#include "CoreBridge.h"
#include "CoreMath.hpp"
#include <cmath>

namespace {
using namespace coremath;

constexpr float kPi = 3.14159265358979323846f;
constexpr float kTwoPi = 6.28318530717958647692f;

CoreCameraParams makeDefaultCameraParams() {
    CoreCameraParams p{};
    p.fovYDegrees = 60.0f;
    p.nearZ = 0.1f;
    p.farZ = 100.0f;
    p.minRadius = 0.8f;
    p.maxRadius = 20.0f;
    p.minPitch = -1.4f;
    p.maxPitch = 1.4f;
    p.orbitSensitivity = 0.01f;
    p.zoomSensitivity = 0.002f;
    p.panSensitivity = 0.001f;
    return p;
}

CoreCameraParams normalizedCameraParams(const CoreCameraParams* maybeParams) {
    CoreCameraParams p = maybeParams ? *maybeParams : makeDefaultCameraParams();

    if (p.fovYDegrees < 1.0f) p.fovYDegrees = 1.0f;
    if (p.fovYDegrees > 170.0f) p.fovYDegrees = 170.0f;

    if (p.nearZ < 0.001f) p.nearZ = 0.001f;
    if (p.farZ < p.nearZ + 0.01f) p.farZ = p.nearZ + 0.01f;

    if (p.minRadius < 0.001f) p.minRadius = 0.001f;
    if (p.maxRadius < p.minRadius + 0.001f) p.maxRadius = p.minRadius + 0.001f;

    if (p.minPitch < -1.55f) p.minPitch = -1.55f;
    if (p.maxPitch > 1.55f) p.maxPitch = 1.55f;
    if (p.maxPitch < p.minPitch + 0.001f) p.maxPitch = p.minPitch + 0.001f;

    if (p.orbitSensitivity <= 0.0f) p.orbitSensitivity = 0.01f;
    if (p.zoomSensitivity <= 0.0f) p.zoomSensitivity = 0.002f;
    if (p.panSensitivity <= 0.0f) p.panSensitivity = 0.001f;
    return p;
}

float wrapAnglePi(float radians) {
    float wrapped = std::fmod(radians + kPi, kTwoPi);
    if (wrapped < 0.0f) wrapped += kTwoPi;
    return wrapped - kPi;
}

Vec3 cameraTargetVec(const CoreCameraState& camera) {
    return {camera.target[0], camera.target[1], camera.target[2]};
}

Vec3 orbitEye(const CoreCameraState& camera) {
    const float cp = std::cos(camera.pitch);
    const float sp = std::sin(camera.pitch);
    const float cy = std::cos(camera.yaw);
    const float sy = std::sin(camera.yaw);
    const Vec3 tgt = cameraTargetVec(camera);
    return {
        tgt.x + camera.radius * cp * sy,
        tgt.y + camera.radius * sp,
        tgt.z + camera.radius * cp * cy
    };
}

void copyMvpToUniforms(const Mat4& mvp, CoreUniforms* outUniforms) {
    for (int c = 0; c < 4; ++c) {
        for (int r = 0; r < 4; ++r) {
            outUniforms->mvp[c * 4 + r] = mvp.m[c][r];
        }
    }
}
} // namespace

void coreCameraSetDefaultState(CoreCameraState* outState) {
    if (!outState) return;
    outState->target[0] = 0.0f;
    outState->target[1] = 0.0f;
    outState->target[2] = 0.0f;
    outState->radius = 2.5f;
    outState->yaw = 0.0f;
    outState->pitch = 0.3f;
}

void coreCameraSetDefaultParams(CoreCameraParams* outParams) {
    if (!outParams) return;
    *outParams = makeDefaultCameraParams();
}

void coreCameraSanitize(CoreCameraState* ioState, const CoreCameraParams* params) {
    if (!ioState) return;
    const CoreCameraParams p = normalizedCameraParams(params);

    ioState->radius = std::fmax(p.minRadius, std::fmin(ioState->radius, p.maxRadius));
    ioState->pitch = std::fmax(p.minPitch, std::fmin(ioState->pitch, p.maxPitch));
    ioState->yaw = wrapAnglePi(ioState->yaw);
}

void coreCameraOrbit(CoreCameraState* ioState, float deltaX, float deltaY, const CoreCameraParams* params) {
    if (!ioState) return;
    const CoreCameraParams p = normalizedCameraParams(params);
    ioState->yaw += deltaX * p.orbitSensitivity;
    ioState->pitch += deltaY * p.orbitSensitivity;
    coreCameraSanitize(ioState, &p);
}

void coreCameraZoom(CoreCameraState* ioState, float delta, const CoreCameraParams* params) {
    if (!ioState) return;
    const CoreCameraParams p = normalizedCameraParams(params);
    const float zoomFactor = std::exp(delta * p.zoomSensitivity);
    ioState->radius *= zoomFactor;
    coreCameraSanitize(ioState, &p);
}

void coreCameraPan(CoreCameraState* ioState, float deltaRight, float deltaUp, const CoreCameraParams* params) {
    if (!ioState) return;
    const CoreCameraParams p = normalizedCameraParams(params);
    coreCameraSanitize(ioState, &p);

    const Vec3 worldUp = {0.0f, 1.0f, 0.0f};
    const Vec3 tgt = cameraTargetVec(*ioState);
    const Vec3 eye = orbitEye(*ioState);
    const Vec3 forward = normalize(tgt - eye);
    Vec3 right = normalize(cross(forward, worldUp));
    Vec3 up = normalize(cross(right, forward));

    // Degenerate vertical view fallback.
    if (length(right) <= 0.0f) right = {1.0f, 0.0f, 0.0f};
    if (length(up) <= 0.0f) up = worldUp;

    const float panScale = ioState->radius * p.panSensitivity;
    const Vec3 panOffset = right * (deltaRight * panScale) + up * (deltaUp * panScale);

    ioState->target[0] += panOffset.x;
    ioState->target[1] += panOffset.y;
    ioState->target[2] += panOffset.z;
}

void coreCameraBuildOrbitUniforms(CoreUniforms* outUniforms,
                                  float timeSeconds,
                                  float aspect,
                                  const CoreCameraState* camera,
                                  const CoreCameraParams* params) {
    if (!outUniforms || !camera) return;

    const CoreCameraParams p = normalizedCameraParams(params);
    CoreCameraState c = *camera;
    coreCameraSanitize(&c, &p);

    const float safeAspect = (aspect > 0.0f) ? aspect : 1.0f;
    const Vec3 tgt = cameraTargetVec(c);
    const Vec3 eye = orbitEye(c);

//    const Mat4 model = rotationY(timeSeconds * 0.1f) * rotationX(timeSeconds * 0.1f);
    const Mat4 view = lookAt(eye, tgt, {0.0f, 1.0f, 0.0f});
    const Mat4 proj = perspective(p.fovYDegrees * kDegToRad, safeAspect, p.nearZ, p.farZ);
    const Mat4 mvp = proj * view; // * model

    copyMvpToUniforms(mvp, outUniforms);
}
