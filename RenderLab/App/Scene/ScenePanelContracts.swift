//
//  ScenePanelContracts.swift
//  RenderLab
//
//  Shared contracts for scene UI synchronization and commands.
//

import Foundation

struct ScenePanelObjectSnapshot: Identifiable, Equatable {
    let id: UInt32
    var name: String
    var isVisible: Bool
    var meshID: UInt32
    var materialID: UInt32
    var transform: SceneTransform
}

struct ScenePanelSnapshot {
    var objects: [ScenePanelObjectSnapshot]
    var selectedObjectID: UInt32?
}

protocol RendererSceneSink: AnyObject {
    func applySceneSnapshot(_ snapshot: ScenePanelSnapshot)
    func applySelectedObjectTransform(objectID: UInt32, transform: SceneTransform)
    func applyInterpolationSnapshot(_ snapshot: InterpolationLabSnapshot)
    func applySkinningSnapshot(_ snapshot: SkinningLabSnapshot)
    func applyMorphSnapshot(_ snapshot: MorphLabSnapshot)
}

extension RendererSceneSink {
    func applySelectedObjectTransform(objectID: UInt32, transform: SceneTransform) {}
    func applyInterpolationSnapshot(_ snapshot: InterpolationLabSnapshot) {}
    func applySkinningSnapshot(_ snapshot: SkinningLabSnapshot) {}
    func applyMorphSnapshot(_ snapshot: MorphLabSnapshot) {}
}

final class SceneCommandBridge {
    private var onSelectObject: ((UInt32?) -> Void)?
    private var onSetObjectVisibility: ((UInt32, Bool) -> Void)?
    private var onSetObjectTransform: ((UInt32, SceneTransform) -> Void)?
    private var onAddCube: (() -> Void)?
    private var onSetInterpolationKeyframeA: (() -> Void)?
    private var onSetInterpolationKeyframeB: (() -> Void)?
    private var onSwapInterpolationKeyframes: (() -> Void)?
    private var onApplyInterpolationKeyframeA: (() -> Void)?
    private var onApplyInterpolationKeyframeB: (() -> Void)?
    private var onResetInterpolationLab: (() -> Void)?
    private var onSetInterpolationTime: ((Float) -> Void)?
    private var onSetInterpolationPlaying: ((Bool) -> Void)?
    private var onSetInterpolationSpeed: ((Float) -> Void)?
    private var onSetInterpolationLoopMode: ((InterpolationLoopMode) -> Void)?
    private var onSetInterpolationPositionMode: ((InterpolationScalarMode) -> Void)?
    private var onSetInterpolationRotationMode: ((InterpolationRotationMode) -> Void)?
    private var onSetInterpolationScaleMode: ((InterpolationScalarMode) -> Void)?
    private var onSetInterpolationShortestPath: ((Bool) -> Void)?
    private var onSetInterpolationShowGhostA: ((Bool) -> Void)?
    private var onSetInterpolationShowGhostB: ((Bool) -> Void)?
    private var onSetSkinningEnabled: ((Bool) -> Void)?
    private var onSetSkinningPlaying: ((Bool) -> Void)?
    private var onSetSkinningTime: ((Float) -> Void)?
    private var onSetSkinningSpeed: ((Float) -> Void)?
    private var onSetSkinningLoopEnabled: ((Bool) -> Void)?
    private var onSetSkinningBone1RotationDegrees: ((Float) -> Void)?
    private var onSetSkinningShowSkeleton: ((Bool) -> Void)?
    private var onSetSkinningDebugMode: ((SkinningDebugMode) -> Void)?
    private var onSetSkinningSelectedBoneIndex: ((Int32) -> Void)?
    private var onSetMorphEnabled: ((Bool) -> Void)?
    private var onSetMorphWeight: ((Float) -> Void)?
    private var onResetMorphWeights: (() -> Void)?

    func bindRendererActions(
        onSelectObject: @escaping (UInt32?) -> Void,
        onSetObjectVisibility: @escaping (UInt32, Bool) -> Void,
        onSetObjectTransform: @escaping (UInt32, SceneTransform) -> Void,
        onAddCube: @escaping () -> Void,
        onSetInterpolationKeyframeA: @escaping () -> Void,
        onSetInterpolationKeyframeB: @escaping () -> Void,
        onSwapInterpolationKeyframes: @escaping () -> Void,
        onApplyInterpolationKeyframeA: @escaping () -> Void,
        onApplyInterpolationKeyframeB: @escaping () -> Void,
        onResetInterpolationLab: @escaping () -> Void,
        onSetInterpolationTime: @escaping (Float) -> Void,
        onSetInterpolationPlaying: @escaping (Bool) -> Void,
        onSetInterpolationSpeed: @escaping (Float) -> Void,
        onSetInterpolationLoopMode: @escaping (InterpolationLoopMode) -> Void,
        onSetInterpolationPositionMode: @escaping (InterpolationScalarMode) -> Void,
        onSetInterpolationRotationMode: @escaping (InterpolationRotationMode) -> Void,
        onSetInterpolationScaleMode: @escaping (InterpolationScalarMode) -> Void,
        onSetInterpolationShortestPath: @escaping (Bool) -> Void,
        onSetInterpolationShowGhostA: @escaping (Bool) -> Void,
        onSetInterpolationShowGhostB: @escaping (Bool) -> Void,
        onSetSkinningEnabled: @escaping (Bool) -> Void,
        onSetSkinningPlaying: @escaping (Bool) -> Void,
        onSetSkinningTime: @escaping (Float) -> Void,
        onSetSkinningSpeed: @escaping (Float) -> Void,
        onSetSkinningLoopEnabled: @escaping (Bool) -> Void,
        onSetSkinningBone1RotationDegrees: @escaping (Float) -> Void,
        onSetSkinningShowSkeleton: @escaping (Bool) -> Void,
        onSetSkinningDebugMode: @escaping (SkinningDebugMode) -> Void,
        onSetSkinningSelectedBoneIndex: @escaping (Int32) -> Void,
        onSetMorphEnabled: @escaping (Bool) -> Void,
        onSetMorphWeight: @escaping (Float) -> Void,
        onResetMorphWeights: @escaping () -> Void
    ) {
        self.onSelectObject = onSelectObject
        self.onSetObjectVisibility = onSetObjectVisibility
        self.onSetObjectTransform = onSetObjectTransform
        self.onAddCube = onAddCube
        self.onSetInterpolationKeyframeA = onSetInterpolationKeyframeA
        self.onSetInterpolationKeyframeB = onSetInterpolationKeyframeB
        self.onSwapInterpolationKeyframes = onSwapInterpolationKeyframes
        self.onApplyInterpolationKeyframeA = onApplyInterpolationKeyframeA
        self.onApplyInterpolationKeyframeB = onApplyInterpolationKeyframeB
        self.onResetInterpolationLab = onResetInterpolationLab
        self.onSetInterpolationTime = onSetInterpolationTime
        self.onSetInterpolationPlaying = onSetInterpolationPlaying
        self.onSetInterpolationSpeed = onSetInterpolationSpeed
        self.onSetInterpolationLoopMode = onSetInterpolationLoopMode
        self.onSetInterpolationPositionMode = onSetInterpolationPositionMode
        self.onSetInterpolationRotationMode = onSetInterpolationRotationMode
        self.onSetInterpolationScaleMode = onSetInterpolationScaleMode
        self.onSetInterpolationShortestPath = onSetInterpolationShortestPath
        self.onSetInterpolationShowGhostA = onSetInterpolationShowGhostA
        self.onSetInterpolationShowGhostB = onSetInterpolationShowGhostB
        self.onSetSkinningEnabled = onSetSkinningEnabled
        self.onSetSkinningPlaying = onSetSkinningPlaying
        self.onSetSkinningTime = onSetSkinningTime
        self.onSetSkinningSpeed = onSetSkinningSpeed
        self.onSetSkinningLoopEnabled = onSetSkinningLoopEnabled
        self.onSetSkinningBone1RotationDegrees = onSetSkinningBone1RotationDegrees
        self.onSetSkinningShowSkeleton = onSetSkinningShowSkeleton
        self.onSetSkinningDebugMode = onSetSkinningDebugMode
        self.onSetSkinningSelectedBoneIndex = onSetSkinningSelectedBoneIndex
        self.onSetMorphEnabled = onSetMorphEnabled
        self.onSetMorphWeight = onSetMorphWeight
        self.onResetMorphWeights = onResetMorphWeights
    }

    func selectObject(_ objectID: UInt32?) {
        onSelectObject?(objectID)
    }

    func setObjectVisibility(objectID: UInt32, isVisible: Bool) {
        onSetObjectVisibility?(objectID, isVisible)
    }

    func setObjectTransform(objectID: UInt32, transform: SceneTransform) {
        onSetObjectTransform?(objectID, transform)
    }

    func addCubeObject() {
        onAddCube?()
    }

    func setInterpolationKeyframeAFromCurrent() {
        onSetInterpolationKeyframeA?()
    }

    func setInterpolationKeyframeBFromCurrent() {
        onSetInterpolationKeyframeB?()
    }

    func swapInterpolationKeyframes() {
        onSwapInterpolationKeyframes?()
    }

    func applyInterpolationKeyframeA() {
        onApplyInterpolationKeyframeA?()
    }

    func applyInterpolationKeyframeB() {
        onApplyInterpolationKeyframeB?()
    }

    func resetInterpolationLab() {
        onResetInterpolationLab?()
    }

    func setInterpolationTime(_ t: Float) {
        onSetInterpolationTime?(t)
    }

    func setInterpolationPlaying(_ isPlaying: Bool) {
        onSetInterpolationPlaying?(isPlaying)
    }

    func setInterpolationSpeed(_ speed: Float) {
        onSetInterpolationSpeed?(speed)
    }

    func setInterpolationLoopMode(_ mode: InterpolationLoopMode) {
        onSetInterpolationLoopMode?(mode)
    }

    func setInterpolationPositionMode(_ mode: InterpolationScalarMode) {
        onSetInterpolationPositionMode?(mode)
    }

    func setInterpolationRotationMode(_ mode: InterpolationRotationMode) {
        onSetInterpolationRotationMode?(mode)
    }

    func setInterpolationScaleMode(_ mode: InterpolationScalarMode) {
        onSetInterpolationScaleMode?(mode)
    }

    func setInterpolationShortestPath(_ enabled: Bool) {
        onSetInterpolationShortestPath?(enabled)
    }

    func setInterpolationShowGhostA(_ show: Bool) {
        onSetInterpolationShowGhostA?(show)
    }

    func setInterpolationShowGhostB(_ show: Bool) {
        onSetInterpolationShowGhostB?(show)
    }

    func setSkinningEnabled(_ enabled: Bool) {
        onSetSkinningEnabled?(enabled)
    }

    func setSkinningPlaying(_ isPlaying: Bool) {
        onSetSkinningPlaying?(isPlaying)
    }

    func setSkinningTime(_ t: Float) {
        onSetSkinningTime?(t)
    }

    func setSkinningSpeed(_ speed: Float) {
        onSetSkinningSpeed?(speed)
    }

    func setSkinningLoopEnabled(_ enabled: Bool) {
        onSetSkinningLoopEnabled?(enabled)
    }

    func setSkinningBone1RotationDegrees(_ degrees: Float) {
        onSetSkinningBone1RotationDegrees?(degrees)
    }

    func setSkinningShowSkeleton(_ show: Bool) {
        onSetSkinningShowSkeleton?(show)
    }

    func setSkinningDebugMode(_ mode: SkinningDebugMode) {
        onSetSkinningDebugMode?(mode)
    }

    func setSkinningSelectedBoneIndex(_ index: Int32) {
        onSetSkinningSelectedBoneIndex?(index)
    }

    func setMorphEnabled(_ enabled: Bool) {
        onSetMorphEnabled?(enabled)
    }

    func setMorphWeight(_ weight: Float) {
        onSetMorphWeight?(weight)
    }

    func resetMorphWeights() {
        onResetMorphWeights?()
    }
}
