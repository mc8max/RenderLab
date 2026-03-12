//
//  Renderer+InterpolationLab.swift
//  RenderLab
//
//  Renderer-side state + command handling for Interpolation Lab.
//

import Foundation
import Metal
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

struct RendererSkinningLabState {
    static let defaultDemoBoneCount: Int = 16
    static let defaultDemoChainHeight: Float = 1.4

    var isEnabled: Bool = true
    var showSkeleton: Bool = true
    var debugMode: SkinningDebugMode = .none
    var selectedBoneIndex: Int32 = 0
    var isPlaying: Bool = false
    var playbackTime: Float = 0.0
    var playbackSpeed: Float = 1.0
    var isLoopEnabled: Bool = true
    var useAnimationPose: Bool = false
    var bone1RotationDegrees: Float = 0.0
    var manualBone1RotationDegrees: Float = 0.0
    var skinnedObjectIDs: Set<UInt32> = []
    var bonePaletteMatrices: [simd_float4x4]
    var boneGlobalPoseMatrices: [simd_float4x4]
    var bonePaletteBuffer: MTLBuffer?
    var isBonePaletteDirty: Bool = true
    var isBonePaletteBufferDirty: Bool = true

    // Chain rig used by the skinning lab demo.
    var boneParentIndices: [Int]
    var boneBindLocalMatrices: [simd_float4x4]
    var boneInverseBindMatrices: [simd_float4x4]
    let clipAmplitudeDegrees: Float = 60.0

    init() {
        let rig = RendererSkinningLabState.makeChainRig(
            boneCount: RendererSkinningLabState.defaultDemoBoneCount,
            chainHeight: RendererSkinningLabState.defaultDemoChainHeight
        )
        boneParentIndices = rig.parentIndices
        boneBindLocalMatrices = rig.bindLocalMatrices
        boneInverseBindMatrices = rig.inverseBindMatrices
        bonePaletteMatrices = Array(repeating: matrix_identity_float4x4, count: rig.parentIndices.count)
        boneGlobalPoseMatrices = rig.bindGlobalMatrices
    }

    private static func makeTranslationMatrix(_ t: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(t.x, t.y, t.z, 1)
        )
    }

    static func computeGlobalMatrices(
        localMatrices: [simd_float4x4],
        parentIndices: [Int]
    ) -> [simd_float4x4] {
        guard localMatrices.count == parentIndices.count else {
            return []
        }

        var globalMatrices = Array(repeating: matrix_identity_float4x4, count: localMatrices.count)
        for index in localMatrices.indices {
            let parentIndex = parentIndices[index]
            if parentIndex >= 0 && parentIndex < localMatrices.count {
                globalMatrices[index] = globalMatrices[parentIndex] * localMatrices[index]
            } else {
                globalMatrices[index] = localMatrices[index]
            }
        }
        return globalMatrices
    }

    static func makeChainRig(
        boneCount: Int,
        chainHeight: Float
    ) -> (
        parentIndices: [Int],
        bindLocalMatrices: [simd_float4x4],
        inverseBindMatrices: [simd_float4x4],
        bindGlobalMatrices: [simd_float4x4]
    ) {
        let clampedBoneCount = max(2, boneCount)
        let segmentLength = chainHeight / Float(max(1, clampedBoneCount - 1))

        var parentIndices = Array(repeating: -1, count: clampedBoneCount)
        var bindLocalMatrices = Array(repeating: matrix_identity_float4x4, count: clampedBoneCount)
        for boneIndex in 1..<clampedBoneCount {
            parentIndices[boneIndex] = boneIndex - 1
            bindLocalMatrices[boneIndex] = makeTranslationMatrix(
                SIMD3<Float>(0.0, segmentLength, 0.0)
            )
        }

        let bindGlobalMatrices = computeGlobalMatrices(
            localMatrices: bindLocalMatrices,
            parentIndices: parentIndices
        )
        let inverseBindMatrices = bindGlobalMatrices.map { simd_inverse($0) }
        return (parentIndices, bindLocalMatrices, inverseBindMatrices, bindGlobalMatrices)
    }
}

struct RendererMorphLabState {
    var isEnabled: Bool = true
    var targetWeights: [Float] = Array(repeating: 0.0, count: MorphLabLimits.maxTargets)
    var debugMode: MorphDebugMode = .none
    var morphedObjectIDs: Set<UInt32> = []
}

extension Renderer {
    func updateSkinningLab(deltaSeconds: Float) {
        skinningSnapshotAccumulatedTime += Double(max(0.0, deltaSeconds))
        let wasPlaying = skinningLabState.isPlaying
        if skinningLabState.isPlaying {
            advanceSkinningPlayback(deltaSeconds: deltaSeconds)
            applySkinningAnimationPoseFromPlaybackTime()
        } else if skinningLabState.useAnimationPose {
            applySkinningAnimationPoseFromPlaybackTime()
        } else {
            applyManualSkinningPoseIfNeeded()
        }
        if wasPlaying != skinningLabState.isPlaying {
            updatePlaybackAppNapSuppressionFromState()
        }
        ensureSkinningPalettePrepared()
        publishSkinningSnapshot(force: false)
    }

    func setSkinningEnabled(_ enabled: Bool) {
        skinningLabState.isEnabled = enabled
        publishSkinningSnapshot(force: true)
    }

    func setSkinningPlaying(_ isPlaying: Bool) {
        skinningLabState.isPlaying = isPlaying
        if isPlaying {
            skinningLabState.useAnimationPose = true
            applySkinningAnimationPoseFromPlaybackTime()
        }
        updatePlaybackAppNapSuppressionFromState()
        publishSkinningSnapshot(force: true)
    }

    func setSkinningTime(_ t: Float) {
        let clamped = min(max(t, 0.0), 1.0)
        if abs(clamped - skinningLabState.playbackTime) <= 0.0001, skinningLabState.useAnimationPose {
            return
        }
        skinningLabState.playbackTime = clamped
        skinningLabState.useAnimationPose = true
        applySkinningAnimationPoseFromPlaybackTime()
        publishSkinningSnapshot(force: true)
    }

    func setSkinningSpeed(_ speed: Float) {
        let clamped = max(0.0, speed)
        if abs(clamped - skinningLabState.playbackSpeed) <= 0.0001 {
            return
        }
        skinningLabState.playbackSpeed = clamped
        publishSkinningSnapshot(force: true)
    }

    func setSkinningLoopEnabled(_ enabled: Bool) {
        skinningLabState.isLoopEnabled = enabled
        publishSkinningSnapshot(force: true)
    }

    func setSkinningShowSkeleton(_ show: Bool) {
        skinningLabState.showSkeleton = show
        publishSkinningSnapshot(force: true)
    }

    func setSkinningDebugMode(_ mode: SkinningDebugMode) {
        skinningLabState.debugMode = mode
        publishSkinningSnapshot(force: true)
    }

    func setSkinningSelectedBoneIndex(_ index: Int32) {
        let maxIndex = Int32(max(0, skinningLabState.boneBindLocalMatrices.count - 1))
        let clamped = min(max(0, index), maxIndex)
        if clamped != skinningLabState.selectedBoneIndex {
            skinningLabState.selectedBoneIndex = clamped
            publishSkinningSnapshot(force: true)
        }
    }

    func setSkinningBone1RotationDegrees(_ degrees: Float) {
        let clamped = min(max(degrees, -180.0), 180.0)
        if abs(clamped - skinningLabState.manualBone1RotationDegrees) > 0.0001 {
            skinningLabState.manualBone1RotationDegrees = clamped
        }
        skinningLabState.isPlaying = false
        skinningLabState.useAnimationPose = false
        applyManualSkinningPoseIfNeeded()
        updatePlaybackAppNapSuppressionFromState()
        publishSkinningSnapshot(force: true)
    }

    func makeSkinningLabFrameState() -> SkinningLabFrameState {
        ensureSkinningPalettePrepared()
        let skinnedObjectIDs = Set(
            skinningLabState.skinnedObjectIDs.filter { scene.find(objectID: $0) != nil }
        )

        return SkinningLabFrameState(
            isEnabled: skinningLabState.isEnabled,
            showSkeleton: skinningLabState.showSkeleton,
            debugMode: skinningLabState.debugMode,
            selectedBoneIndex: clampedSelectedBoneIndex(),
            skinnedObjectIDs: skinnedObjectIDs,
            bonePaletteBuffer: skinningLabState.bonePaletteBuffer,
            boneCount: UInt32(skinningLabState.bonePaletteMatrices.count),
            boneParentIndices: skinningLabState.boneParentIndices.map { Int32($0) },
            boneGlobalPoseMatrices: skinningLabState.boneGlobalPoseMatrices
        )
    }

    func updateMorphLab(deltaSeconds: Float) {
        morphSnapshotAccumulatedTime += Double(max(0.0, deltaSeconds))
        publishMorphSnapshot(force: false)
    }

    func setMorphEnabled(_ enabled: Bool) {
        morphLabState.isEnabled = enabled
        publishMorphSnapshot(force: true)
    }

    func setMorphTargetWeight(index: Int32, weight: Float) {
        let targetIndex = Int(min(max(index, 0), Int32(MorphLabLimits.maxTargets - 1)))
        let clamped = min(max(weight, 0.0), 1.0)
        guard targetIndex < morphLabState.targetWeights.count else {
            return
        }
        if abs(clamped - morphLabState.targetWeights[targetIndex]) <= 0.0001 {
            return
        }
        morphLabState.targetWeights[targetIndex] = clamped
        publishMorphSnapshot(force: true)
    }

    func resetMorphWeights() {
        var changed = false
        for index in morphLabState.targetWeights.indices {
            if abs(morphLabState.targetWeights[index]) > 0.0001 {
                morphLabState.targetWeights[index] = 0.0
                changed = true
            }
        }
        if changed == false {
            return
        }
        publishMorphSnapshot(force: true)
    }

    func makeMorphLabFrameState() -> MorphLabFrameState {
        let morphedObjectIDs = Set(
            morphLabState.morphedObjectIDs.filter { scene.find(objectID: $0) != nil }
        )
        let clampedWeights = morphLabState.targetWeights.map { min(max($0, 0.0), 1.0) }
        return MorphLabFrameState(
            isEnabled: morphLabState.isEnabled,
            targetWeights: clampedWeights,
            debugMode: morphLabState.debugMode,
            morphedObjectIDs: morphedObjectIDs
        )
    }

    func publishMorphSnapshot(force: Bool) {
        if shouldSuspendUISync() {
            return
        }
        if !force {
            guard morphSnapshotAccumulatedTime >= morphSnapshotPublishInterval else {
                return
            }
        }
        if force {
            morphSnapshotAccumulatedTime = 0.0
        } else {
            morphSnapshotAccumulatedTime.formTruncatingRemainder(
                dividingBy: morphSnapshotPublishInterval
            )
        }

        let selectedName: String? = {
            guard let selectedObjectID else { return nil }
            return objectNamesByID[selectedObjectID] ?? "Object \(selectedObjectID)"
        }()
        let isSelectedObjectMorphed = selectedObjectID.map {
            morphLabState.morphedObjectIDs.contains($0)
        } ?? false

        let targetCount: Int32 = {
            guard
                let selectedObjectID,
                isSelectedObjectMorphed,
                let object = scene.find(objectID: selectedObjectID),
                let renderAssets,
                let mesh = renderAssets.mesh(for: object.meshID)
            else {
                return 0
            }
            return Int32(max(0, min(mesh.morphTargetCount, MorphLabLimits.maxTargets)))
        }()

        let activeWeightCount = max(0, min(Int(targetCount), morphLabState.targetWeights.count))
        let targetWeights = Array(morphLabState.targetWeights.prefix(activeWeightCount))

        let snapshot = MorphLabSnapshot(
            selectedObjectID: selectedObjectID,
            selectedObjectName: selectedName,
            isSelectedObjectMorphed: isSelectedObjectMorphed,
            morphEnabled: morphLabState.isEnabled,
            targetWeights: targetWeights,
            targetCount: targetCount,
            debugMode: morphLabState.debugMode
        )
        if snapshot == lastMorphSnapshot {
            return
        }
        lastMorphSnapshot = snapshot
        sceneSink?.applyMorphSnapshot(snapshot)
    }

    func publishSkinningSnapshot(force: Bool) {
        if shouldSuspendUISync() {
            return
        }
        let publishInterval = currentSkinningSnapshotPublishInterval()
        if !force {
            guard skinningSnapshotAccumulatedTime >= publishInterval else {
                return
            }
        }
        if force {
            skinningSnapshotAccumulatedTime = 0.0
        } else {
            skinningSnapshotAccumulatedTime.formTruncatingRemainder(
                dividingBy: publishInterval
            )
        }
        _ = force
        let selectedName: String? = {
            guard let selectedObjectID else { return nil }
            return objectNamesByID[selectedObjectID] ?? "Object \(selectedObjectID)"
        }()
        let isSelectedObjectSkinned = selectedObjectID.map {
            skinningLabState.skinnedObjectIDs.contains($0)
        } ?? false

        let snapshot = SkinningLabSnapshot(
            selectedObjectID: selectedObjectID,
            selectedObjectName: selectedName,
            isSelectedObjectSkinned: isSelectedObjectSkinned,
            skinningEnabled: skinningLabState.isEnabled,
            isPlaying: skinningLabState.isPlaying,
            playbackTime: skinningLabState.playbackTime,
            playbackSpeed: skinningLabState.playbackSpeed,
            loopEnabled: skinningLabState.isLoopEnabled,
            showSkeleton: skinningLabState.showSkeleton,
            debugMode: skinningLabState.debugMode,
            selectedBoneIndex: Int32(clampedSelectedBoneIndex()),
            boneCount: Int32(skinningLabState.bonePaletteMatrices.count),
            bone1RotationDegrees: skinningLabState.bone1RotationDegrees
        )
        if snapshot == lastSkinningSnapshot {
            return
        }
        lastSkinningSnapshot = snapshot
        sceneSink?.applySkinningSnapshot(snapshot)
    }

    private func makeSkinningDemoRigPose() -> (palette: [simd_float4x4], globalPose: [simd_float4x4]) {
        guard
            skinningLabState.boneBindLocalMatrices.count == skinningLabState.boneParentIndices.count,
            skinningLabState.boneBindLocalMatrices.count == skinningLabState.boneInverseBindMatrices.count
        else {
            return ([matrix_identity_float4x4], [matrix_identity_float4x4])
        }

        var localPoseMatrices = skinningLabState.boneBindLocalMatrices
        let baseRadians = skinningLabState.bone1RotationDegrees * .pi / 180.0
        if localPoseMatrices.count > 1 {
            for boneIndex in 1..<localPoseMatrices.count {
                let propagation = exp(-0.22 * Float(boneIndex - 1))
                let radians = baseRadians * propagation
                localPoseMatrices[boneIndex] = skinningLabState.boneBindLocalMatrices[boneIndex]
                    * makeRotationZMatrix(radians)
            }
        }

        let globalPoseMatrices = RendererSkinningLabState.computeGlobalMatrices(
            localMatrices: localPoseMatrices,
            parentIndices: skinningLabState.boneParentIndices
        )
        if globalPoseMatrices.count != skinningLabState.boneInverseBindMatrices.count {
            return ([matrix_identity_float4x4], [matrix_identity_float4x4])
        }

        let palette = zip(globalPoseMatrices, skinningLabState.boneInverseBindMatrices).map {
            globalPose, inverseBind in
            globalPose * inverseBind
        }
        return (palette, globalPoseMatrices)
    }

    private func makeRotationZMatrix(_ radians: Float) -> simd_float4x4 {
        let c = cos(radians)
        let s = sin(radians)
        return simd_float4x4(
            SIMD4<Float>(c, s, 0, 0),
            SIMD4<Float>(-s, c, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    private func ensureSkinningPalettePrepared() {
        alignSkinningRigWithSkinnedMeshesIfNeeded()
        if skinningLabState.isBonePaletteDirty {
            let rigPose = makeSkinningDemoRigPose()
            skinningLabState.bonePaletteMatrices = rigPose.palette
            skinningLabState.boneGlobalPoseMatrices = rigPose.globalPose
            skinningLabState.isBonePaletteDirty = false
            skinningLabState.isBonePaletteBufferDirty = true
        }

        let matrixByteCount = skinningLabState.bonePaletteMatrices.count * MemoryLayout<simd_float4x4>.stride
        guard matrixByteCount > 0 else {
            skinningLabState.bonePaletteBuffer = nil
            skinningLabState.isBonePaletteBufferDirty = true
            return
        }

        if skinningLabState.bonePaletteBuffer == nil || skinningLabState.bonePaletteBuffer?.length != matrixByteCount {
            skinningLabState.bonePaletteBuffer = device.makeBuffer(
                length: matrixByteCount,
                options: [.storageModeShared]
            )
            skinningLabState.isBonePaletteBufferDirty = true
        }
        guard let bonePaletteBuffer = skinningLabState.bonePaletteBuffer else { return }
        guard skinningLabState.isBonePaletteBufferDirty else { return }

        skinningLabState.bonePaletteMatrices.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            bonePaletteBuffer.contents().copyMemory(from: baseAddress, byteCount: rawBuffer.count)
        }
        skinningLabState.isBonePaletteBufferDirty = false
    }

    private func alignSkinningRigWithSkinnedMeshesIfNeeded() {
        guard let renderAssets else {
            return
        }

        var desiredBoneCount = 0
        for objectID in skinningLabState.skinnedObjectIDs {
            guard
                let object = scene.find(objectID: objectID),
                let mesh = renderAssets.mesh(for: object.meshID),
                mesh.vertexLayout == .skinnedPositionColorBone4
            else {
                continue
            }
            desiredBoneCount = max(desiredBoneCount, mesh.skinningBoneCount)
        }

        guard desiredBoneCount > 0 else {
            return
        }
        let clampedDesiredBoneCount = max(2, desiredBoneCount)
        guard clampedDesiredBoneCount != skinningLabState.boneBindLocalMatrices.count else {
            return
        }

        let rig = RendererSkinningLabState.makeChainRig(
            boneCount: clampedDesiredBoneCount,
            chainHeight: RendererSkinningLabState.defaultDemoChainHeight
        )
        skinningLabState.boneParentIndices = rig.parentIndices
        skinningLabState.boneBindLocalMatrices = rig.bindLocalMatrices
        skinningLabState.boneInverseBindMatrices = rig.inverseBindMatrices
        skinningLabState.bonePaletteMatrices = Array(
            repeating: matrix_identity_float4x4,
            count: clampedDesiredBoneCount
        )
        skinningLabState.boneGlobalPoseMatrices = rig.bindGlobalMatrices
        skinningLabState.bonePaletteBuffer = nil
        skinningLabState.isBonePaletteDirty = true
        skinningLabState.isBonePaletteBufferDirty = true
        let maxBoneIndex = Int32(max(0, clampedDesiredBoneCount - 1))
        skinningLabState.selectedBoneIndex = min(max(0, skinningLabState.selectedBoneIndex), maxBoneIndex)
    }

    private func advanceSkinningPlayback(deltaSeconds: Float) {
        let dt = max(0.0, deltaSeconds)
        if dt <= 0.0 || skinningLabState.playbackSpeed <= 0.0 {
            return
        }

        var next = skinningLabState.playbackTime + dt * skinningLabState.playbackSpeed
        if skinningLabState.isLoopEnabled {
            next.formTruncatingRemainder(dividingBy: 1.0)
            if next < 0.0 {
                next += 1.0
            }
        } else if next >= 1.0 {
            next = 1.0
            skinningLabState.isPlaying = false
        }
        skinningLabState.playbackTime = next
    }

    private func applySkinningAnimationPoseFromPlaybackTime() {
        let phase = skinningLabState.playbackTime * (2.0 * Float.pi)
        let animatedDegrees = sin(phase) * skinningLabState.clipAmplitudeDegrees
        if abs(animatedDegrees - skinningLabState.bone1RotationDegrees) > 0.0001 {
            skinningLabState.bone1RotationDegrees = animatedDegrees
            skinningLabState.isBonePaletteDirty = true
        }
    }

    private func applyManualSkinningPoseIfNeeded() {
        if abs(skinningLabState.manualBone1RotationDegrees - skinningLabState.bone1RotationDegrees) > 0.0001 {
            skinningLabState.bone1RotationDegrees = skinningLabState.manualBone1RotationDegrees
            skinningLabState.isBonePaletteDirty = true
        }
    }

    private func clampedSelectedBoneIndex() -> UInt32 {
        let boneCount = Int32(skinningLabState.bonePaletteMatrices.count)
        if boneCount <= 0 {
            return 0
        }
        let clamped = min(max(0, skinningLabState.selectedBoneIndex), boneCount - 1)
        return UInt32(clamped)
    }
}

extension Renderer {
    func syncInterpolationSelectionState() {
        guard interpolationLabState.objectID != selectedObjectID else { return }
        interpolationLabState.objectID = selectedObjectID
        interpolationLabState.resetKeyframes()
        updatePlaybackAppNapSuppressionFromState()
        interpolationLabState.interpolatedTransform = currentSelectedObjectTransform()
        selectedTransformAccumulatedTime = 0.0
        lastPublishedSelectedTransformObjectID = nil
        lastPublishedSelectedTransform = nil
    }

    func updateInterpolationLab(deltaSeconds: Float) {
        syncInterpolationSelectionState()
        interpolationSnapshotAccumulatedTime += Double(max(0.0, deltaSeconds))
        selectedTransformAccumulatedTime += Double(max(0.0, deltaSeconds))
        _ = CoreInterpolationBridge.advancePlayback(
            &interpolationLabState.playback,
            deltaSeconds: deltaSeconds
        )
        updatePlaybackAppNapSuppressionFromState()

        let didApply = applyInterpolationToSceneIfPossible()
        if didApply {
            pushSelectedTransformToSceneSinkIfAvailable(force: false)
        }
        publishInterpolationSnapshot(force: false)
    }

    func setInterpolationKeyframeAFromCurrent() {
        syncInterpolationSelectionState()
        guard selectedObjectID != nil,
            let transform = currentSelectedObjectTransform()
        else {
            return
        }
        interpolationLabState.keyframeA = transform
        if interpolationLabState.interpolatedTransform == nil {
            interpolationLabState.interpolatedTransform = transform
        }
        publishInterpolationSnapshot(force: true)
    }

    func setInterpolationKeyframeBFromCurrent() {
        syncInterpolationSelectionState()
        guard selectedObjectID != nil,
            let transform = currentSelectedObjectTransform()
        else {
            return
        }
        interpolationLabState.keyframeB = transform
        if interpolationLabState.interpolatedTransform == nil {
            interpolationLabState.interpolatedTransform = transform
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
            pushSelectedTransformToSceneSinkIfAvailable(force: true)
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
        updatePlaybackAppNapSuppressionFromState()
        interpolationLabState.interpolatedTransform = keyframe
        interpolationLabState.distanceToA = 0.0
        if let keyframeB = interpolationLabState.keyframeB {
            interpolationLabState.distanceToB = simd.length(keyframe.position - keyframeB.position)
        } else {
            interpolationLabState.distanceToB = nil
        }
        guard scene.setTransform(objectID: selectedObjectID, transform: keyframe) else {
            syncScenePanelState()
            return
        }
        if selectedObjectCache?.objectID == selectedObjectID {
            selectedObjectCache?.transform = keyframe
        }
        pushSelectedTransformToSceneSinkIfAvailable(force: true)
        publishInterpolationSnapshot(force: true)
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
        updatePlaybackAppNapSuppressionFromState()
        interpolationLabState.interpolatedTransform = keyframe
        interpolationLabState.distanceToB = 0.0
        if let keyframeA = interpolationLabState.keyframeA {
            interpolationLabState.distanceToA = simd.length(keyframe.position - keyframeA.position)
        } else {
            interpolationLabState.distanceToA = nil
        }
        guard scene.setTransform(objectID: selectedObjectID, transform: keyframe) else {
            syncScenePanelState()
            return
        }
        if selectedObjectCache?.objectID == selectedObjectID {
            selectedObjectCache?.transform = keyframe
        }
        pushSelectedTransformToSceneSinkIfAvailable(force: true)
        publishInterpolationSnapshot(force: true)
    }

    func resetInterpolationLab() {
        interpolationLabState.resetKeyframes()
        updatePlaybackAppNapSuppressionFromState()
        interpolationLabState.interpolatedTransform = currentSelectedObjectTransform()
        publishInterpolationSnapshot(force: true)
    }

    func setInterpolationTime(_ t: Float) {
        interpolationLabState.playback.t = min(max(t, 0.0), 1.0)
        let didApply = applyInterpolationToSceneIfPossible()
        if didApply {
            pushSelectedTransformToSceneSinkIfAvailable(force: true)
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
        updatePlaybackAppNapSuppressionFromState()
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
            pushSelectedTransformToSceneSinkIfAvailable(force: true)
        }
        publishInterpolationSnapshot(force: true)
    }

    func setInterpolationRotationMode(_ mode: InterpolationRotationMode) {
        interpolationLabState.config.rotationMode = mode.rawValue
        let didApply = applyInterpolationToSceneIfPossible()
        if didApply {
            pushSelectedTransformToSceneSinkIfAvailable(force: true)
        }
        publishInterpolationSnapshot(force: true)
    }

    func setInterpolationScaleMode(_ mode: InterpolationScalarMode) {
        interpolationLabState.config.scaleMode = mode.rawValue
        let didApply = applyInterpolationToSceneIfPossible()
        if didApply {
            pushSelectedTransformToSceneSinkIfAvailable(force: true)
        }
        publishInterpolationSnapshot(force: true)
    }

    func setInterpolationShortestPath(_ enabled: Bool) {
        interpolationLabState.config.shortestPath = enabled ? 1 : 0
        let didApply = applyInterpolationToSceneIfPossible()
        if didApply {
            pushSelectedTransformToSceneSinkIfAvailable(force: true)
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
            let object = currentSelectedObjectSnapshot(),
            let renderAssets,
            let mesh = renderAssets.mesh(for: object.meshID),
            mesh.vertexLayout == .positionColor,
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
        if shouldSuspendUISync() {
            return
        }
        let publishInterval = currentInterpolationSnapshotPublishInterval()
        if !force {
            guard interpolationSnapshotAccumulatedTime >= publishInterval else {
                return
            }
        }
        if force {
            interpolationSnapshotAccumulatedTime = 0.0
        } else {
            interpolationSnapshotAccumulatedTime.formTruncatingRemainder(
                dividingBy: publishInterval
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
        if let sceneSink {
            recordInterpolationSnapshotPublish()
            sceneSink.applyInterpolationSnapshot(snapshot)
        }
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
            interpolationLabState.interpolatedTransform = currentSelectedObjectTransform()
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

        if let current = currentSelectedObjectTransform(),
            current.isApproximatelyEqual(to: evaluated.transform)
        {
            return false
        }
        let didSet = scene.setTransform(objectID: selectedObjectID, transform: evaluated.transform)
        if didSet, selectedObjectCache?.objectID == selectedObjectID {
            selectedObjectCache?.transform = evaluated.transform
        }
        return didSet
    }

    private func pushSelectedTransformToSceneSinkIfAvailable(force: Bool) {
        if shouldSuspendUISync() {
            return
        }
        guard let selectedObjectID,
            let transform = interpolationLabState.interpolatedTransform
        else {
            return
        }
        let publishInterval = currentSelectedTransformPublishInterval()

        if !force {
            guard selectedTransformAccumulatedTime >= publishInterval else {
                return
            }
        }
        if force {
            selectedTransformAccumulatedTime = 0.0
        } else {
            selectedTransformAccumulatedTime.formTruncatingRemainder(
                dividingBy: publishInterval
            )
        }

        if lastPublishedSelectedTransformObjectID == selectedObjectID,
            let lastPublishedSelectedTransform,
            lastPublishedSelectedTransform.isApproximatelyEqual(to: transform)
        {
            return
        }

        lastPublishedSelectedTransformObjectID = selectedObjectID
        lastPublishedSelectedTransform = transform
        if let sceneSink {
            recordSelectedTransformPublish()
            sceneSink.applySelectedObjectTransform(objectID: selectedObjectID, transform: transform)
        }
    }

    private func currentSelectedObjectSnapshot() -> SceneObjectSnapshot? {
        guard let selectedObjectID else { return nil }
        if let cached = selectedObjectCache, cached.objectID == selectedObjectID {
            return cached
        }
        selectedObjectCache = scene.find(objectID: selectedObjectID)
        return selectedObjectCache
    }

    private func currentSelectedObjectTransform() -> SceneTransform? {
        currentSelectedObjectSnapshot()?.transform
    }

    private func currentInterpolationSnapshotPublishInterval() -> Double {
        interpolationLabState.playback.isPlaying != 0
            ? interpolationSnapshotPublishIntervalPlaying
            : interpolationSnapshotPublishIntervalIdle
    }

    private func currentSelectedTransformPublishInterval() -> Double {
        interpolationLabState.playback.isPlaying != 0
            ? selectedTransformPublishIntervalPlaying
            : selectedTransformPublishIntervalIdle
    }

    private func currentSkinningSnapshotPublishInterval() -> Double {
        skinningLabState.isPlaying
            ? skinningSnapshotPublishIntervalPlaying
            : skinningSnapshotPublishIntervalIdle
    }

    private func shouldSuspendUISyncDuringPlayback() -> Bool {
        settings.suspendUISyncDuringPlayback
            && (interpolationLabState.playback.isPlaying != 0 || skinningLabState.isPlaying)
    }

    private func shouldSuspendUISync() -> Bool {
        shouldSuspendUISyncDuringPlayback() || shouldSuspendUISyncForBackgroundState()
    }

    func setPlaybackAppNapSuppressed(_ suppressed: Bool) {
        playbackActivityLock.lock()
        defer { playbackActivityLock.unlock() }

        if suppressed {
            guard playbackActivityToken == nil else { return }
            playbackActivityToken = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: "RenderLab Interpolation Playback"
            )
            return
        }

        guard let playbackActivityToken else { return }
        ProcessInfo.processInfo.endActivity(playbackActivityToken)
        self.playbackActivityToken = nil
    }

    private func updatePlaybackAppNapSuppressionFromState() {
        setPlaybackAppNapSuppressed(interpolationLabState.playback.isPlaying != 0 || skinningLabState.isPlaying)
    }
}
