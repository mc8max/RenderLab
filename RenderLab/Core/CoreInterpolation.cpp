//
//  CoreInterpolation.cpp
//  RenderLab
//
//  Engine-side interpolation math for Interpolation Lab.
//

#include "CoreInterpolation.h"
#include <cmath>

namespace {
using namespace coremath;

float sanitizeT(float t) {
    return clamp01(t);
}

float sanitizeSpeed(float speed) {
    if (speed < 0.0f) return 0.0f;
    return speed;
}

float alphaFromMode(float t, CoreInterpScalarMode mode) {
    switch (mode) {
        case CORE_INTERP_SCALAR_SMOOTHSTEP:
            return smoothstep01(t);
        case CORE_INTERP_SCALAR_CUBIC:
            return smootherstep01(t);
        case CORE_INTERP_SCALAR_LERP:
        default:
            return sanitizeT(t);
    }
}

CoreInterpLoopMode sanitizeLoopMode(CoreInterpLoopMode mode) {
    switch (mode) {
        case CORE_INTERP_LOOP_CLAMP:
        case CORE_INTERP_LOOP_REPEAT:
        case CORE_INTERP_LOOP_PINGPONG:
            return mode;
        default:
            return CORE_INTERP_LOOP_CLAMP;
    }
}

CoreInterpScalarMode sanitizeScalarMode(CoreInterpScalarMode mode) {
    switch (mode) {
        case CORE_INTERP_SCALAR_LERP:
        case CORE_INTERP_SCALAR_SMOOTHSTEP:
        case CORE_INTERP_SCALAR_CUBIC:
            return mode;
        default:
            return CORE_INTERP_SCALAR_LERP;
    }
}

CoreInterpRotationMode sanitizeRotationMode(CoreInterpRotationMode mode) {
    switch (mode) {
        case CORE_INTERP_ROT_EULER_LERP:
        case CORE_INTERP_ROT_QUAT_NLERP:
        case CORE_INTERP_ROT_QUAT_SLERP:
            return mode;
        default:
            return CORE_INTERP_ROT_QUAT_SLERP;
    }
}

Vec3 interpolateRotation(const Vec3& a,
                         const Vec3& b,
                         float t,
                         CoreInterpRotationMode mode,
                         bool shortestPath) {
    switch (sanitizeRotationMode(mode)) {
        case CORE_INTERP_ROT_EULER_LERP:
            return lerp(a, b, sanitizeT(t));
        case CORE_INTERP_ROT_QUAT_NLERP: {
            const Quat qa = quatFromEulerZYX(a);
            const Quat qb = quatFromEulerZYX(b);
            const Quat q = nlerp(qa, qb, sanitizeT(t), shortestPath);
            return eulerZYXFromQuat(q);
        }
        case CORE_INTERP_ROT_QUAT_SLERP:
        default: {
            const Quat qa = quatFromEulerZYX(a);
            const Quat qb = quatFromEulerZYX(b);
            const Quat q = slerp(qa, qb, sanitizeT(t), shortestPath);
            return eulerZYXFromQuat(q);
        }
    }
}
} // namespace

CoreInterpConfigCpp CoreInterpMakeDefaultConfig() {
    CoreInterpConfigCpp config{};
    config.positionMode = CORE_INTERP_SCALAR_LERP;
    config.rotationMode = CORE_INTERP_ROT_QUAT_SLERP;
    config.scaleMode = CORE_INTERP_SCALAR_LERP;
    config.shortestPath = true;
    return config;
}

CoreInterpPlaybackStateCpp CoreInterpMakeDefaultPlaybackState() {
    CoreInterpPlaybackStateCpp state{};
    state.t = 0.0f;
    state.speed = 1.0f;
    state.loopMode = CORE_INTERP_LOOP_CLAMP;
    state.isPlaying = false;
    state.direction = 1;
    return state;
}

bool CoreInterpAdvancePlaybackState(CoreInterpPlaybackStateCpp& ioState, float deltaSeconds) {
    ioState.t = sanitizeT(ioState.t);
    ioState.speed = sanitizeSpeed(ioState.speed);
    ioState.loopMode = sanitizeLoopMode(ioState.loopMode);
    if (ioState.direction != 1 && ioState.direction != -1) {
        ioState.direction = 1;
    }

    if (!ioState.isPlaying || ioState.speed <= 0.0f || deltaSeconds <= 0.0f) {
        return false;
    }

    const float delta = deltaSeconds * ioState.speed * static_cast<float>(ioState.direction);
    switch (ioState.loopMode) {
        case CORE_INTERP_LOOP_REPEAT: {
            float t = ioState.t + delta;
            while (t > 1.0f) t -= 1.0f;
            while (t < 0.0f) t += 1.0f;
            ioState.t = sanitizeT(t);
            return true;
        }
        case CORE_INTERP_LOOP_PINGPONG: {
            float t = ioState.t + delta;
            int32_t direction = ioState.direction;
            while (t > 1.0f || t < 0.0f) {
                if (t > 1.0f) {
                    t = 2.0f - t;
                    direction = -1;
                } else if (t < 0.0f) {
                    t = -t;
                    direction = 1;
                }
            }
            ioState.t = sanitizeT(t);
            ioState.direction = direction;
            return true;
        }
        case CORE_INTERP_LOOP_CLAMP:
        default: {
            float t = ioState.t + delta;
            if (t >= 1.0f) {
                ioState.t = 1.0f;
                ioState.isPlaying = false;
            } else if (t <= 0.0f) {
                ioState.t = 0.0f;
                ioState.isPlaying = false;
            } else {
                ioState.t = t;
            }
            return true;
        }
    }
}

bool CoreInterpEvaluateTransform(const CoreTransform& a,
                                 const CoreTransform& b,
                                 float t,
                                 const CoreInterpConfigCpp& inputConfig,
                                 CoreTransform& outTransform,
                                 CoreInterpDebugCpp* outDebug) {
    const float alphaT = sanitizeT(t);
    const CoreInterpConfigCpp config = {
        sanitizeScalarMode(inputConfig.positionMode),
        sanitizeRotationMode(inputConfig.rotationMode),
        sanitizeScalarMode(inputConfig.scaleMode),
        inputConfig.shortestPath
    };
    const float alphaPosition = alphaFromMode(alphaT, config.positionMode);
    const float alphaScale = alphaFromMode(alphaT, config.scaleMode);

    outTransform.position = lerp(a.position, b.position, alphaPosition);
    outTransform.rotation = interpolateRotation(
        a.rotation,
        b.rotation,
        alphaT,
        config.rotationMode,
        config.shortestPath
    );
    outTransform.scale = lerp(a.scale, b.scale, alphaScale);

    if (outDebug) {
        outDebug->alphaPosition = alphaPosition;
        outDebug->alphaScale = alphaScale;
        outDebug->distanceToA = distance(outTransform.position, a.position);
        outDebug->distanceToB = distance(outTransform.position, b.position);
    }
    return true;
}
