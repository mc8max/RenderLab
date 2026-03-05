//
//  CoreInterpolation.h
//  RenderLab
//
//  Engine-side interpolation math for Interpolation Lab.
//

#pragma once

#include "CoreBridge.h"
#include "CoreScene.h"

struct CoreInterpConfigCpp {
    CoreInterpScalarMode positionMode = CORE_INTERP_SCALAR_LERP;
    CoreInterpRotationMode rotationMode = CORE_INTERP_ROT_QUAT_SLERP;
    CoreInterpScalarMode scaleMode = CORE_INTERP_SCALAR_LERP;
    bool shortestPath = true;
};

struct CoreInterpPlaybackStateCpp {
    float t = 0.0f;
    float speed = 1.0f;
    CoreInterpLoopMode loopMode = CORE_INTERP_LOOP_CLAMP;
    bool isPlaying = false;
    int32_t direction = 1;
};

struct CoreInterpDebugCpp {
    float alphaPosition = 0.0f;
    float alphaScale = 0.0f;
    float distanceToA = 0.0f;
    float distanceToB = 0.0f;
};

CoreInterpConfigCpp CoreInterpMakeDefaultConfig();
CoreInterpPlaybackStateCpp CoreInterpMakeDefaultPlaybackState();
bool CoreInterpAdvancePlaybackState(CoreInterpPlaybackStateCpp& ioState, float deltaSeconds);
bool CoreInterpEvaluateTransform(const CoreTransform& a,
                                 const CoreTransform& b,
                                 float t,
                                 const CoreInterpConfigCpp& config,
                                 CoreTransform& outTransform,
                                 CoreInterpDebugCpp* outDebug);
