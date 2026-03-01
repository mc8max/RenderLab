//
//  CoreUniformBridge.cpp
//  RenderLab
//
//  C bridge uniform construction APIs.
//

#include "CoreBridge.h"
#include "CoreMath.hpp"
#include "CoreScene.h"

namespace {
using namespace coremath;

void copyMvpToUniforms(const Mat4& mvp, CoreUniforms* outUniforms) {
    for (int c = 0; c < 4; ++c) {
        for (int r = 0; r < 4; ++r) {
            outUniforms->mvp[c * 4 + r] = mvp.m[c][r];
        }
    }
}

Mat4 uniformsToMat4(const CoreUniforms& uniforms) {
    Mat4 m{};
    for (int c = 0; c < 4; ++c) {
        for (int r = 0; r < 4; ++r) {
            m.m[c][r] = uniforms.mvp[c * 4 + r];
        }
    }
    return m;
}
} // namespace

void coreMakeDefaultUniforms(CoreUniforms* outUniforms, float timeSeconds, float aspect) {
    if (!outUniforms) return;

    using namespace coremath;
    const float safeAspect = (aspect > 0.0f) ? aspect : 1.0f;
    const Mat4 model = rotationY(timeSeconds) * rotationX(timeSeconds * 0.5f);
    const Mat4 view = lookAt({0.0f, 0.0f, 2.2f}, {0.0f, 0.0f, 0.0f}, {0.0f, 1.0f, 0.0f});
    const Mat4 proj = perspective(60.0f * kDegToRad, safeAspect, 0.1f, 100.0f);
    const Mat4 mvp = proj * view * model;
    copyMvpToUniforms(mvp, outUniforms);
}

void coreMakeOrbitUniforms(CoreUniforms* outUniforms,
                           float timeSeconds,
                           float aspect,
                           const float target[3],
                           float radius,
                           float yaw,
                           float pitch) {
    if (!outUniforms || !target) return;

    CoreCameraState camera{};
    camera.target[0] = target[0];
    camera.target[1] = target[1];
    camera.target[2] = target[2];
    camera.radius = radius;
    camera.yaw = yaw;
    camera.pitch = pitch;

    CoreCameraParams params{};
    coreCameraSetDefaultParams(&params);

    coreCameraBuildOrbitUniforms(outUniforms, timeSeconds, aspect, &camera, &params);
}

void coreSceneMakeObjectUniforms(CoreUniforms* outUniforms,
                                 const CoreUniforms* baseUniforms,
                                 const CoreSceneTransform* transform) {
    if (!outUniforms || !baseUniforms || !transform) return;

    const coremath::Mat4 baseMVP = uniformsToMat4(*baseUniforms);
    const CoreTransform coreTransform = {
        {transform->position[0], transform->position[1], transform->position[2]},
        {transform->rotation[0], transform->rotation[1], transform->rotation[2]},
        {transform->scale[0], transform->scale[1], transform->scale[2]}};
    const coremath::Mat4 model = CoreTransform_toMat4(coreTransform);
    const coremath::Mat4 objectMVP = baseMVP * model;
    copyMvpToUniforms(objectMVP, outUniforms);
}
