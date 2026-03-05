//
//  CoreInterpolationBridge.swift
//  RenderLab
//
//  Swift wrappers over Interpolation Lab C bridge APIs.
//

import Foundation

enum CoreInterpolationBridge {
    static func defaultConfig() -> CoreInterpConfig {
        var config = CoreInterpConfig()
        coreInterpSetDefaultConfig(&config)
        return config
    }

    static func defaultPlaybackState() -> CoreInterpPlaybackState {
        var state = CoreInterpPlaybackState()
        coreInterpSetDefaultPlaybackState(&state)
        return state
    }

    @discardableResult
    static func advancePlayback(
        _ state: inout CoreInterpPlaybackState,
        deltaSeconds: Float
    ) -> Bool {
        var t: Float = state.t
        let changed = coreInterpAdvancePlaybackState(&state, deltaSeconds, &t)
        state.t = t
        return changed != 0
    }

    static func evaluateTransform(
        a: SceneTransform,
        b: SceneTransform,
        t: Float,
        config: CoreInterpConfig
    ) -> (transform: SceneTransform, debug: CoreInterpDebug)? {
        var transformA = a.toCoreSceneTransform()
        var transformB = b.toCoreSceneTransform()
        var config = config
        var outTransform = CoreSceneTransform()
        var outDebug = CoreInterpDebug()
        let ok = coreInterpEvaluateTransform(
            &transformA,
            &transformB,
            t,
            &config,
            &outTransform,
            &outDebug
        )
        guard ok != 0 else { return nil }
        return (SceneTransform.fromCoreSceneTransform(outTransform), outDebug)
    }

    static func makeObjectUniforms(
        baseUniforms: CoreUniforms,
        a: SceneTransform,
        b: SceneTransform,
        t: Float,
        config: CoreInterpConfig
    ) -> (uniforms: CoreUniforms, transform: SceneTransform, debug: CoreInterpDebug)? {
        var baseUniforms = baseUniforms
        var transformA = a.toCoreSceneTransform()
        var transformB = b.toCoreSceneTransform()
        var config = config
        var outUniforms = CoreUniforms()
        var outTransform = CoreSceneTransform()
        var outDebug = CoreInterpDebug()

        let ok = coreInterpMakeObjectUniforms(
            &baseUniforms,
            &transformA,
            &transformB,
            t,
            &config,
            &outUniforms,
            &outTransform,
            &outDebug
        )
        guard ok != 0 else { return nil }
        return (outUniforms, SceneTransform.fromCoreSceneTransform(outTransform), outDebug)
    }

    static func makeGhostUniforms(
        baseUniforms: CoreUniforms,
        a: SceneTransform,
        b: SceneTransform
    ) -> (uniformsA: CoreUniforms, uniformsB: CoreUniforms)? {
        var baseUniforms = baseUniforms
        var transformA = a.toCoreSceneTransform()
        var transformB = b.toCoreSceneTransform()
        var outUniformsA = CoreUniforms()
        var outUniformsB = CoreUniforms()

        let ok = coreInterpMakeGhostUniforms(
            &baseUniforms,
            &transformA,
            &transformB,
            &outUniformsA,
            &outUniformsB
        )
        guard ok != 0 else { return nil }
        return (outUniformsA, outUniformsB)
    }
}
