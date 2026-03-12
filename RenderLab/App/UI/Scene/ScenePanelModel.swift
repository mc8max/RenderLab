//
//  ScenePanelModel.swift
//  RenderLab
//
//  UI-facing scene list state.
//

import Foundation
import Combine

final class ScenePanelModel: ObservableObject {
    @Published private(set) var objects: [ScenePanelObjectSnapshot] = []
    @Published private(set) var selectedObjectID: UInt32?
    @Published private(set) var selectedObjectTransform: SceneTransform?
    @Published private(set) var interpolationLab: InterpolationLabSnapshot = .empty
    @Published private(set) var skinningLab: SkinningLabSnapshot = .empty
    @Published private(set) var morphLab: MorphLabSnapshot = .empty

    private let pendingSinkLock = NSLock()
    private var pendingSceneSnapshot: ScenePanelSnapshot?
    private var pendingSelectedTransform: (objectID: UInt32, transform: SceneTransform)?
    private var pendingInterpolationSnapshot: InterpolationLabSnapshot?
    private var pendingSkinningSnapshot: SkinningLabSnapshot?
    private var pendingMorphSnapshot: MorphLabSnapshot?
    private var isPendingSinkFlushScheduled: Bool = false

    private func enqueueMainMutation(_ mutation: @escaping () -> Void) {
        DispatchQueue.main.async(execute: mutation)
    }

    var selectedObject: ScenePanelObjectSnapshot? {
        guard let selectedObjectID else { return nil }
        guard var object = objects.first(where: { $0.id == selectedObjectID }) else {
            return nil
        }
        if let selectedObjectTransform {
            object.transform = selectedObjectTransform
        }
        return object
    }

    func setLocalSelection(_ objectID: UInt32?) {
        selectedObjectID = objectID
        if let objectID {
            selectedObjectTransform = objects.first(where: { $0.id == objectID })?.transform
        } else {
            selectedObjectTransform = nil
        }
    }

    func setLocalVisibility(objectID: UInt32, isVisible: Bool) {
        if let index = objects.firstIndex(where: { $0.id == objectID }) {
            objects[index].isVisible = isVisible
        }
    }

    func setLocalTransform(objectID: UInt32, transform: SceneTransform) {
        guard selectedObjectID == objectID else { return }
        selectedObjectTransform = transform
    }

    func refreshSelectedTransformFromSnapshot() {
        guard let selectedObjectID else {
            selectedObjectTransform = nil
            return
        }
        selectedObjectTransform = objects.first(where: { $0.id == selectedObjectID })?.transform
    }

    func setLocalInterpolationTime(_ t: Float) {
        let clamped = min(max(t, 0.0), 1.0)
        enqueueMainMutation { [weak self] in
            self?.interpolationLab.t = clamped
        }
    }

    func setLocalInterpolationPlaying(_ isPlaying: Bool) {
        enqueueMainMutation { [weak self] in
            self?.interpolationLab.isPlaying = isPlaying
        }
    }

    func setLocalInterpolationSpeed(_ speed: Float) {
        let clamped = max(0.0, speed)
        enqueueMainMutation { [weak self] in
            self?.interpolationLab.speed = clamped
        }
    }

    func setLocalInterpolationLoopMode(_ mode: InterpolationLoopMode) {
        enqueueMainMutation { [weak self] in
            self?.interpolationLab.loopMode = mode
        }
    }

    func setLocalInterpolationPositionMode(_ mode: InterpolationScalarMode) {
        enqueueMainMutation { [weak self] in
            self?.interpolationLab.positionMode = mode
        }
    }

    func setLocalInterpolationRotationMode(_ mode: InterpolationRotationMode) {
        enqueueMainMutation { [weak self] in
            self?.interpolationLab.rotationMode = mode
        }
    }

    func setLocalInterpolationScaleMode(_ mode: InterpolationScalarMode) {
        enqueueMainMutation { [weak self] in
            self?.interpolationLab.scaleMode = mode
        }
    }

    func setLocalInterpolationShortestPath(_ enabled: Bool) {
        enqueueMainMutation { [weak self] in
            self?.interpolationLab.shortestPath = enabled
        }
    }

    func setLocalInterpolationShowGhostA(_ show: Bool) {
        enqueueMainMutation { [weak self] in
            self?.interpolationLab.showGhostA = show
        }
    }

    func setLocalInterpolationShowGhostB(_ show: Bool) {
        enqueueMainMutation { [weak self] in
            self?.interpolationLab.showGhostB = show
        }
    }

    func setLocalSkinningEnabled(_ enabled: Bool) {
        enqueueMainMutation { [weak self] in
            self?.skinningLab.skinningEnabled = enabled
        }
    }

    func setLocalSkinningPlaying(_ isPlaying: Bool) {
        enqueueMainMutation { [weak self] in
            self?.skinningLab.isPlaying = isPlaying
        }
    }

    func setLocalSkinningTime(_ t: Float) {
        let clamped = min(max(t, 0.0), 1.0)
        enqueueMainMutation { [weak self] in
            self?.skinningLab.playbackTime = clamped
        }
    }

    func setLocalSkinningSpeed(_ speed: Float) {
        let clamped = max(0.0, speed)
        enqueueMainMutation { [weak self] in
            self?.skinningLab.playbackSpeed = clamped
        }
    }

    func setLocalSkinningLoopEnabled(_ enabled: Bool) {
        enqueueMainMutation { [weak self] in
            self?.skinningLab.loopEnabled = enabled
        }
    }

    func setLocalSkinningBone1RotationDegrees(_ degrees: Float) {
        let clamped = min(max(degrees, -180.0), 180.0)
        enqueueMainMutation { [weak self] in
            self?.skinningLab.bone1RotationDegrees = clamped
        }
    }

    func setLocalSkinningShowSkeleton(_ show: Bool) {
        enqueueMainMutation { [weak self] in
            self?.skinningLab.showSkeleton = show
        }
    }

    func setLocalSkinningDebugMode(_ mode: SkinningDebugMode) {
        enqueueMainMutation { [weak self] in
            self?.skinningLab.debugMode = mode
        }
    }

    func setLocalSkinningSelectedBoneIndex(_ index: Int32) {
        let clamped = max(0, index)
        enqueueMainMutation { [weak self] in
            guard let self else { return }
            let maxIndex = max(0, self.skinningLab.boneCount - 1)
            self.skinningLab.selectedBoneIndex = min(clamped, maxIndex)
        }
    }

    func setLocalMorphEnabled(_ enabled: Bool) {
        enqueueMainMutation { [weak self] in
            self?.morphLab.morphEnabled = enabled
        }
    }

    func setLocalMorphTargetWeight(index: Int, weight: Float) {
        let clamped = min(max(weight, 0.0), 1.0)
        enqueueMainMutation { [weak self] in
            guard let self else { return }
            guard index >= 0, index < self.morphLab.targetWeights.count else { return }
            self.morphLab.targetWeights[index] = clamped
        }
    }

    func resetLocalMorphWeights() {
        enqueueMainMutation { [weak self] in
            guard let self else { return }
            self.morphLab.targetWeights = self.morphLab.targetWeights.map { _ in 0.0 }
        }
    }
}

extension ScenePanelModel: RendererSceneSink {
    func applySceneSnapshot(_ snapshot: ScenePanelSnapshot) {
        enqueuePendingSinkUpdates(
            sceneSnapshot: snapshot,
            selectedTransform: nil,
            interpolationSnapshot: nil,
            skinningSnapshot: nil,
            morphSnapshot: nil
        )
    }

    func applyInterpolationSnapshot(_ snapshot: InterpolationLabSnapshot) {
        enqueuePendingSinkUpdates(
            sceneSnapshot: nil,
            selectedTransform: nil,
            interpolationSnapshot: snapshot,
            skinningSnapshot: nil,
            morphSnapshot: nil
        )
    }

    func applySkinningSnapshot(_ snapshot: SkinningLabSnapshot) {
        enqueuePendingSinkUpdates(
            sceneSnapshot: nil,
            selectedTransform: nil,
            interpolationSnapshot: nil,
            skinningSnapshot: snapshot,
            morphSnapshot: nil
        )
    }

    func applyMorphSnapshot(_ snapshot: MorphLabSnapshot) {
        enqueuePendingSinkUpdates(
            sceneSnapshot: nil,
            selectedTransform: nil,
            interpolationSnapshot: nil,
            skinningSnapshot: nil,
            morphSnapshot: snapshot
        )
    }

    func applySelectedObjectTransform(objectID: UInt32, transform: SceneTransform) {
        enqueuePendingSinkUpdates(
            sceneSnapshot: nil,
            selectedTransform: (objectID: objectID, transform: transform),
            interpolationSnapshot: nil,
            skinningSnapshot: nil,
            morphSnapshot: nil
        )
    }

    private func enqueuePendingSinkUpdates(
        sceneSnapshot: ScenePanelSnapshot?,
        selectedTransform: (objectID: UInt32, transform: SceneTransform)?,
        interpolationSnapshot: InterpolationLabSnapshot?,
        skinningSnapshot: SkinningLabSnapshot?,
        morphSnapshot: MorphLabSnapshot?
    ) {
        pendingSinkLock.lock()
        if let sceneSnapshot {
            pendingSceneSnapshot = sceneSnapshot
        }
        if let selectedTransform {
            pendingSelectedTransform = selectedTransform
        }
        if let interpolationSnapshot {
            pendingInterpolationSnapshot = interpolationSnapshot
        }
        if let skinningSnapshot {
            pendingSkinningSnapshot = skinningSnapshot
        }
        if let morphSnapshot {
            pendingMorphSnapshot = morphSnapshot
        }
        let shouldSchedule = isPendingSinkFlushScheduled == false
        if shouldSchedule {
            isPendingSinkFlushScheduled = true
        }
        pendingSinkLock.unlock()

        guard shouldSchedule else { return }
        DispatchQueue.main.async { [weak self] in
            self?.flushPendingSinkUpdatesOnMain()
        }
    }

    private func flushPendingSinkUpdatesOnMain() {
        let sceneSnapshot: ScenePanelSnapshot?
        let selectedTransform: (objectID: UInt32, transform: SceneTransform)?
        let interpolationSnapshot: InterpolationLabSnapshot?
        let skinningSnapshot: SkinningLabSnapshot?
        let morphSnapshot: MorphLabSnapshot?

        pendingSinkLock.lock()
        sceneSnapshot = pendingSceneSnapshot
        selectedTransform = pendingSelectedTransform
        interpolationSnapshot = pendingInterpolationSnapshot
        skinningSnapshot = pendingSkinningSnapshot
        morphSnapshot = pendingMorphSnapshot
        pendingSceneSnapshot = nil
        pendingSelectedTransform = nil
        pendingInterpolationSnapshot = nil
        pendingSkinningSnapshot = nil
        pendingMorphSnapshot = nil
        isPendingSinkFlushScheduled = false
        pendingSinkLock.unlock()

        if let sceneSnapshot {
            objects = sceneSnapshot.objects
            selectedObjectID = sceneSnapshot.selectedObjectID
            refreshSelectedTransformFromSnapshot()
        }
        if let selectedTransform {
            setLocalTransform(objectID: selectedTransform.objectID, transform: selectedTransform.transform)
        }
        if let interpolationSnapshot {
            interpolationLab = interpolationSnapshot
        }
        if let skinningSnapshot {
            skinningLab = skinningSnapshot
        }
        if let morphSnapshot {
            morphLab = morphSnapshot
        }
    }
}
