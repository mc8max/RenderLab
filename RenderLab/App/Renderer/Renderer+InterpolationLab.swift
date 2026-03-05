//
//  Renderer+InterpolationLab.swift
//  RenderLab
//
//  Renderer-side state + command handling for Interpolation Lab.
//

import Foundation
import simd

struct RendererInterpolationLabState {
    var objectID: UInt32?
    var keyframeA: SceneTransform?
    var keyframeB: SceneTransform?
    var playback: CoreInterpPlaybackState
    var config: CoreInterpConfig
    var showGhostA: Bool
    var showGhostB: Bool
    var interpolatedTransform: SceneTransform?
    var distanceToA: Float?
    var distanceToB: Float?

    init() {
        playback = CoreInterpolationBridge.defaultPlaybackState()
        config = CoreInterpolationBridge.defaultConfig()
        showGhostA = true
        showGhostB = true
    }

    mutating func resetKeyframes() {
        keyframeA = nil
        keyframeB = nil
        playback.t = 0.0
        playback.isPlaying = 0
        playback.direction = 1
        interpolatedTransform = nil
        distanceToA = nil
        distanceToB = nil
    }
}

extension Renderer {
    func syncInterpolationSelectionState() {
        guard interpolationLabState.objectID != selectedObjectID else { return }
        interpolationLabState.objectID = selectedObjectID
        interpolationLabState.resetKeyframes()
        if let selectedObjectID,
            let object = scene.find(objectID: selectedObjectID)
        {
            interpolationLabState.interpolatedTransform = object.transform
        }
    }

    func updateInterpolationLab(deltaSeconds: Float) {
        syncInterpolationSelectionState()
        interpolationSnapshotAccumulatedTime += Double(max(0.0, deltaSeconds))
        _ = CoreInterpolationBridge.advancePlayback(
            &interpolationLabState.playback,
            deltaSeconds: deltaSeconds
        )

        let didApply = applyInterpolationToSceneIfPossible()
        if didApply {
            if let selectedObjectID,
                let transform = interpolationLabState.interpolatedTransform
            {
                sceneSink?.applySelectedObjectTransform(objectID: selectedObjectID, transform: transform)
            }
        }
        publishInterpolationSnapshot(force: false)
    }

    func setInterpolationKeyframeAFromCurrent() {
        guard let selectedObjectID,
            let object = scene.find(objectID: selectedObjectID)
        else {
            return
        }
        syncInterpolationSelectionState()
        interpolationLabState.keyframeA = object.transform
        if interpolationLabState.interpolatedTransform == nil {
            interpolationLabState.interpolatedTransform = object.transform
        }
        publishInterpolationSnapshot(force: true)
    }

    func setInterpolationKeyframeBFromCurrent() {
        guard let selectedObjectID,
            let object = scene.find(objectID: selectedObjectID)
        else {
            return
        }
        syncInterpolationSelectionState()
        interpolationLabState.keyframeB = object.transform
        if interpolationLabState.interpolatedTransform == nil {
            interpolationLabState.interpolatedTransform = object.transform
        }
        publishInterpolationSnapshot(force: true)
    }

    func swapInterpolationKeyframes() {
        syncInterpolationSelectionState()
        let oldA = interpolationLabState.keyframeA
        interpolationLabState.keyframeA = interpolationLabState.keyframeB
        interpolationLabState.keyframeB = oldA
        let didApply = applyInterpolationToSceneIfPossible()
        if didApply {
            syncScenePanelState()
            return
        }
        publishInterpolationSnapshot(force: true)
    }

    func applyInterpolationKeyframeA() {
        guard let selectedObjectID,
            let keyframe = interpolationLabState.keyframeA
        else {
            return
        }
        interpolationLabState.playback.t = 0.0
        interpolationLabState.playback.isPlaying = 0
        interpolationLabState.playback.direction = 1
        interpolationLabState.interpolatedTransform = keyframe
        interpolationLabState.distanceToA = 0.0
        if let keyframeB = interpolationLabState.keyframeB {
            interpolationLabState.distanceToB = simd.length(keyframe.position - keyframeB.position)
        } else {
            interpolationLabState.distanceToB = nil
        }
        _ = scene.setTransform(objectID: selectedObjectID, transform: keyframe)
        syncScenePanelState()
    }

    func applyInterpolationKeyframeB() {
        guard let selectedObjectID,
            let keyframe = interpolationLabState.keyframeB
        else {
            return
        }
        interpolationLabState.playback.t = 1.0
        interpolationLabState.playback.isPlaying = 0
        interpolationLabState.playback.direction = 1
        interpolationLabState.interpolatedTransform = keyframe
        interpolationLabState.distanceToB = 0.0
        if let keyframeA = interpolationLabState.keyframeA {
            interpolationLabState.distanceToA = simd.length(keyframe.position - keyframeA.position)
        } else {
            interpolationLabState.distanceToA = nil
        }
        _ = scene.setTransform(objectID: selectedObjectID, transform: keyframe)
        syncScenePanelState()
    }

    func resetInterpolationLab() {
        interpolationLabState.resetKeyframes()
        if let selectedObjectID,
            let object = scene.find(objectID: selectedObjectID)
        {
            interpolationLabState.interpolatedTransform = object.transform
        }
        publishInterpolationSnapshot(force: true)
    }

    func setInterpolationTime(_ t: Float) {
        interpolationLabState.playback.t = min(max(t, 0.0), 1.0)
        let didApply = applyInterpolationToSceneIfPossible()
        if didApply {
            syncScenePanelState()
            return
        }
        publishInterpolationSnapshot(force: true)
    }

    func setInterpolationPlaying(_ isPlaying: Bool) {
        interpolationLabState.playback.isPlaying = isPlaying ? 1 : 0
        if interpolationLabState.playback.direction != 1
            && interpolationLabState.playback.direction != -1
        {
            interpolationLabState.playback.direction = 1
        }
        publishInterpolationSnapshot(force: true)
    }

    func setInterpolationSpeed(_ speed: Float) {
        interpolationLabState.playback.speed = max(0.0, speed)
        publishInterpolationSnapshot(force: true)
    }

    func setInterpolationLoopMode(_ mode: InterpolationLoopMode) {
        interpolationLabState.playback.loopMode = mode.rawValue
        if mode != .pingPong {
            interpolationLabState.playback.direction = 1
        }
        publishInterpolationSnapshot(force: true)
    }

    func setInterpolationPositionMode(_ mode: InterpolationScalarMode) {
        interpolationLabState.config.positionMode = mode.rawValue
        let didApply = applyInterpolationToSceneIfPossible()
        if didApply {
            syncScenePanelState()
            return
        }
        publishInterpolationSnapshot(force: true)
    }

    func setInterpolationRotationMode(_ mode: InterpolationRotationMode) {
        interpolationLabState.config.rotationMode = mode.rawValue
        let didApply = applyInterpolationToSceneIfPossible()
        if didApply {
            syncScenePanelState()
            return
        }
        publishInterpolationSnapshot(force: true)
    }

    func setInterpolationScaleMode(_ mode: InterpolationScalarMode) {
        interpolationLabState.config.scaleMode = mode.rawValue
        let didApply = applyInterpolationToSceneIfPossible()
        if didApply {
            syncScenePanelState()
            return
        }
        publishInterpolationSnapshot(force: true)
    }

    func setInterpolationShortestPath(_ enabled: Bool) {
        interpolationLabState.config.shortestPath = enabled ? 1 : 0
        let didApply = applyInterpolationToSceneIfPossible()
        if didApply {
            syncScenePanelState()
            return
        }
        publishInterpolationSnapshot(force: true)
    }

    func setInterpolationShowGhostA(_ show: Bool) {
        interpolationLabState.showGhostA = show
        publishInterpolationSnapshot(force: true)
    }

    func setInterpolationShowGhostB(_ show: Bool) {
        interpolationLabState.showGhostB = show
        publishInterpolationSnapshot(force: true)
    }

    func makeInterpolationGhostDrawItems(baseUniforms: CoreUniforms) -> [InterpolationGhostDrawItem] {
        guard let selectedObjectID,
            interpolationLabState.objectID == selectedObjectID,
            let object = scene.find(objectID: selectedObjectID),
            object.isVisible,
            let keyframeA = interpolationLabState.keyframeA,
            let keyframeB = interpolationLabState.keyframeB
        else {
            return []
        }

        if !interpolationLabState.showGhostA && !interpolationLabState.showGhostB {
            return []
        }

        guard let uniforms = CoreInterpolationBridge.makeGhostUniforms(
            baseUniforms: baseUniforms,
            a: keyframeA,
            b: keyframeB
        ) else {
            return []
        }

        var items: [InterpolationGhostDrawItem] = []
        if interpolationLabState.showGhostA {
            items.append(
                InterpolationGhostDrawItem(
                    meshID: object.meshID,
                    uniforms: uniforms.uniformsA,
                    color: SIMD4<Float>(1.0, 0.6, 0.2, 0.45)
                )
            )
        }
        if interpolationLabState.showGhostB {
            items.append(
                InterpolationGhostDrawItem(
                    meshID: object.meshID,
                    uniforms: uniforms.uniformsB,
                    color: SIMD4<Float>(0.2, 0.85, 1.0, 0.45)
                )
            )
        }
        return items
    }

    func publishInterpolationSnapshot(force: Bool) {
        if !force {
            guard interpolationSnapshotAccumulatedTime >= interpolationSnapshotPublishInterval else {
                return
            }
        }
        if force {
            interpolationSnapshotAccumulatedTime = 0.0
        } else {
            interpolationSnapshotAccumulatedTime.formTruncatingRemainder(
                dividingBy: interpolationSnapshotPublishInterval
            )
        }

        let positionMode = InterpolationScalarMode(rawValue: interpolationLabState.config.positionMode) ?? .lerp
        let rotationMode = InterpolationRotationMode(rawValue: interpolationLabState.config.rotationMode)
            ?? .quaternionSlerp
        let scaleMode = InterpolationScalarMode(rawValue: interpolationLabState.config.scaleMode) ?? .lerp
        let loopMode = InterpolationLoopMode(rawValue: interpolationLabState.playback.loopMode) ?? .clamp

        let selectedName: String? = {
            guard let selectedObjectID else { return nil }
            return objectNamesByID[selectedObjectID] ?? "Object \(selectedObjectID)"
        }()

        let snapshot = InterpolationLabSnapshot(
            selectedObjectID: selectedObjectID,
            selectedObjectName: selectedName,
            hasKeyframeA: interpolationLabState.keyframeA != nil,
            hasKeyframeB: interpolationLabState.keyframeB != nil,
            keyframeA: interpolationLabState.keyframeA,
            keyframeB: interpolationLabState.keyframeB,
            t: interpolationLabState.playback.t,
            isPlaying: interpolationLabState.playback.isPlaying != 0,
            speed: interpolationLabState.playback.speed,
            loopMode: loopMode,
            positionMode: positionMode,
            rotationMode: rotationMode,
            scaleMode: scaleMode,
            shortestPath: interpolationLabState.config.shortestPath != 0,
            showGhostA: interpolationLabState.showGhostA,
            showGhostB: interpolationLabState.showGhostB,
            interpolatedTransform: interpolationLabState.interpolatedTransform,
            distanceToA: interpolationLabState.distanceToA,
            distanceToB: interpolationLabState.distanceToB
        )
        if lastInterpolationSnapshot == snapshot {
            return
        }
        lastInterpolationSnapshot = snapshot
        sceneSink?.applyInterpolationSnapshot(snapshot)
    }

    @discardableResult
    private func applyInterpolationToSceneIfPossible() -> Bool {
        guard let selectedObjectID,
            interpolationLabState.objectID == selectedObjectID,
            let keyframeA = interpolationLabState.keyframeA,
            let keyframeB = interpolationLabState.keyframeB
        else {
            interpolationLabState.distanceToA = nil
            interpolationLabState.distanceToB = nil
            if let selectedObjectID,
                let object = scene.find(objectID: selectedObjectID)
            {
                interpolationLabState.interpolatedTransform = object.transform
            } else {
                interpolationLabState.interpolatedTransform = nil
            }
            return false
        }

        guard let evaluated = CoreInterpolationBridge.evaluateTransform(
            a: keyframeA,
            b: keyframeB,
            t: interpolationLabState.playback.t,
            config: interpolationLabState.config
        ) else {
            interpolationLabState.distanceToA = nil
            interpolationLabState.distanceToB = nil
            return false
        }

        interpolationLabState.interpolatedTransform = evaluated.transform
        interpolationLabState.distanceToA = evaluated.debug.distanceToA
        interpolationLabState.distanceToB = evaluated.debug.distanceToB

        if let current = scene.find(objectID: selectedObjectID)?.transform,
            current.isApproximatelyEqual(to: evaluated.transform)
        {
            return false
        }
        return scene.setTransform(objectID: selectedObjectID, transform: evaluated.transform)
    }
}
