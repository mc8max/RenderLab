//
//  CoreInterpolationBridge.cpp
//  RenderLab
//
//  C bridge wrappers for Interpolation Lab math and uniform computation.
//

#include "CoreBridge.h"
#include "CoreInterpolation.h"

namespace {
CoreInterpScalarMode scalarModeFromRaw(int32_t raw) {
    switch (raw) {
        case CORE_INTERP_SCALAR_SMOOTHSTEP:
            return CORE_INTERP_SCALAR_SMOOTHSTEP;
        case CORE_INTERP_SCALAR_CUBIC:
            return CORE_INTERP_SCALAR_CUBIC;
        case CORE_INTERP_SCALAR_LERP:
        default:
            return CORE_INTERP_SCALAR_LERP;
    }
}

CoreInterpRotationMode rotationModeFromRaw(int32_t raw) {
    switch (raw) {
        case CORE_INTERP_ROT_EULER_LERP:
            return CORE_INTERP_ROT_EULER_LERP;
        case CORE_INTERP_ROT_QUAT_NLERP:
            return CORE_INTERP_ROT_QUAT_NLERP;
        case CORE_INTERP_ROT_QUAT_SLERP:
        default:
            return CORE_INTERP_ROT_QUAT_SLERP;
    }
}

CoreInterpLoopMode loopModeFromRaw(int32_t raw) {
    switch (raw) {
        case CORE_INTERP_LOOP_REPEAT:
            return CORE_INTERP_LOOP_REPEAT;
        case CORE_INTERP_LOOP_PINGPONG:
            return CORE_INTERP_LOOP_PINGPONG;
        case CORE_INTERP_LOOP_CLAMP:
        default:
            return CORE_INTERP_LOOP_CLAMP;
    }
}

CoreTransform toCoreTransform(const CoreSceneTransform& in) {
    CoreTransform out{};
    out.position = {in.position[0], in.position[1], in.position[2]};
    out.rotation = {in.rotation[0], in.rotation[1], in.rotation[2]};
    out.scale = {in.scale[0], in.scale[1], in.scale[2]};
    return out;
}

CoreSceneTransform toBridgeTransform(const CoreTransform& in) {
    CoreSceneTransform out{};
    out.position[0] = in.position.x;
    out.position[1] = in.position.y;
    out.position[2] = in.position.z;
    out.rotation[0] = in.rotation.x;
    out.rotation[1] = in.rotation.y;
    out.rotation[2] = in.rotation.z;
    out.scale[0] = in.scale.x;
    out.scale[1] = in.scale.y;
    out.scale[2] = in.scale.z;
    return out;
}

CoreInterpConfigCpp toCoreConfig(const CoreInterpConfig* config) {
    const CoreInterpConfigCpp defaults = CoreInterpMakeDefaultConfig();
    if (!config) return defaults;

    CoreInterpConfigCpp out{};
    out.positionMode = scalarModeFromRaw(config->positionMode);
    out.rotationMode = rotationModeFromRaw(config->rotationMode);
    out.scaleMode = scalarModeFromRaw(config->scaleMode);
    out.shortestPath = config->shortestPath != 0;
    return out;
}

CoreInterpPlaybackStateCpp toCorePlaybackState(const CoreInterpPlaybackState* state) {
    const CoreInterpPlaybackStateCpp defaults = CoreInterpMakeDefaultPlaybackState();
    if (!state) return defaults;

    CoreInterpPlaybackStateCpp out{};
    out.t = state->t;
    out.speed = state->speed;
    out.loopMode = loopModeFromRaw(state->loopMode);
    out.isPlaying = state->isPlaying != 0;
    out.direction = state->direction;
    return out;
}

CoreInterpPlaybackState toBridgePlaybackState(const CoreInterpPlaybackStateCpp& state) {
    CoreInterpPlaybackState out{};
    out.t = state.t;
    out.speed = state.speed;
    out.loopMode = state.loopMode;
    out.isPlaying = state.isPlaying ? 1u : 0u;
    out.direction = state.direction;
    return out;
}
} // namespace

void coreInterpSetDefaultConfig(CoreInterpConfig* outConfig) {
    if (!outConfig) return;
    const CoreInterpConfigCpp defaults = CoreInterpMakeDefaultConfig();
    outConfig->positionMode = defaults.positionMode;
    outConfig->rotationMode = defaults.rotationMode;
    outConfig->scaleMode = defaults.scaleMode;
    outConfig->shortestPath = defaults.shortestPath ? 1u : 0u;
}

void coreInterpSetDefaultPlaybackState(CoreInterpPlaybackState* outState) {
    if (!outState) return;
    const CoreInterpPlaybackStateCpp defaults = CoreInterpMakeDefaultPlaybackState();
    *outState = toBridgePlaybackState(defaults);
}

int32_t coreInterpAdvancePlaybackState(CoreInterpPlaybackState* ioState,
                                       float deltaSeconds,
                                       float* outT) {
    if (!ioState) return 0;

    CoreInterpPlaybackStateCpp state = toCorePlaybackState(ioState);
    const bool changed = CoreInterpAdvancePlaybackState(state, deltaSeconds);
    *ioState = toBridgePlaybackState(state);
    if (outT) *outT = ioState->t;
    return changed ? 1 : 0;
}

int32_t coreInterpEvaluateTransform(const CoreSceneTransform* a,
                                    const CoreSceneTransform* b,
                                    float t,
                                    const CoreInterpConfig* config,
                                    CoreSceneTransform* outTransform,
                                    CoreInterpDebug* outDebug) {
    if (!a || !b || !outTransform) return 0;

    const CoreTransform transformA = toCoreTransform(*a);
    const CoreTransform transformB = toCoreTransform(*b);
    const CoreInterpConfigCpp coreConfig = toCoreConfig(config);

    CoreTransform outCoreTransform{};
    CoreInterpDebugCpp debug{};
    const bool ok = CoreInterpEvaluateTransform(
        transformA,
        transformB,
        t,
        coreConfig,
        outCoreTransform,
        outDebug ? &debug : nullptr
    );
    if (!ok) return 0;

    *outTransform = toBridgeTransform(outCoreTransform);
    if (outDebug) {
        outDebug->alphaPosition = debug.alphaPosition;
        outDebug->alphaScale = debug.alphaScale;
        outDebug->distanceToA = debug.distanceToA;
        outDebug->distanceToB = debug.distanceToB;
    }
    return 1;
}

int32_t coreInterpMakeObjectUniforms(const CoreUniforms* baseUniforms,
                                     const CoreSceneTransform* a,
                                     const CoreSceneTransform* b,
                                     float t,
                                     const CoreInterpConfig* config,
                                     CoreUniforms* outUniforms,
                                     CoreSceneTransform* outTransform,
                                     CoreInterpDebug* outDebug) {
    if (!baseUniforms || !a || !b || !outUniforms) return 0;

    CoreSceneTransform evaluated{};
    CoreInterpDebug debug{};
    const int32_t ok = coreInterpEvaluateTransform(
        a,
        b,
        t,
        config,
        &evaluated,
        outDebug ? &debug : nullptr
    );
    if (ok == 0) return 0;

    coreSceneMakeObjectUniforms(outUniforms, baseUniforms, &evaluated);
    if (outTransform) {
        *outTransform = evaluated;
    }
    if (outDebug) {
        *outDebug = debug;
    }
    return 1;
}

int32_t coreInterpMakeGhostUniforms(const CoreUniforms* baseUniforms,
                                    const CoreSceneTransform* a,
                                    const CoreSceneTransform* b,
                                    CoreUniforms* outUniformsA,
                                    CoreUniforms* outUniformsB) {
    if (!baseUniforms || !a || !b || !outUniformsA || !outUniformsB) return 0;

    coreSceneMakeObjectUniforms(outUniformsA, baseUniforms, a);
    coreSceneMakeObjectUniforms(outUniformsB, baseUniforms, b);
    return 1;
}
