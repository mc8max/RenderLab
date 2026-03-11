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
    var isEnabled: Bool = true
    var showSkeleton: Bool = true
    var debugMode: SkinningDebugMode = .none
    var selectedBoneIndex: Int32 = 0
    var bone1RotationDegrees: Float = 0.0
    var skinnedObjectIDs: Set<UInt32> = []
    var bonePaletteMatrices: [simd_float4x4]
    var boneGlobalPoseMatrices: [simd_float4x4]
    var bonePaletteBuffer: MTLBuffer?
    var isBonePaletteDirty: Bool = true

    // Two-bone demo rig.
    let boneParentIndices: [Int]
    let boneBindLocalMatrices: [simd_float4x4]
    let boneInverseBindMatrices: [simd_float4x4]

    init() {
        boneParentIndices = [-1, 0]
        boneBindLocalMatrices = [
            matrix_identity_float4x4,
            RendererSkinningLabState.makeTranslationMatrix(SIMD3<Float>(0.0, 0.7, 0.0)),
        ]
        let bindGlobalMatrices = RendererSkinningLabState.computeGlobalMatrices(
            localMatrices: boneBindLocalMatrices,
            parentIndices: boneParentIndices
        )
        boneInverseBindMatrices = bindGlobalMatrices.map { simd_inverse($0) }
        bonePaletteMatrices = Array(repeating: matrix_identity_float4x4, count: boneBindLocalMatrices.count)
        boneGlobalPoseMatrices = bindGlobalMatrices
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
}

extension Renderer {
    func updateSkinningLab(deltaSeconds: Float) {
        _ = deltaSeconds
        ensureSkinningPalettePrepared()
        publishSkinningSnapshot(force: false)
    }

    func setSkinningEnabled(_ enabled: Bool) {
        skinningLabState.isEnabled = enabled
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
        if abs(clamped - skinningLabState.bone1RotationDegrees) > 0.0001 {
            skinningLabState.bone1RotationDegrees = clamped
            skinningLabState.isBonePaletteDirty = true
        }
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

    func publishSkinningSnapshot(force: Bool) {
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
        let radians = skinningLabState.bone1RotationDegrees * .pi / 180.0
        if localPoseMatrices.count > 1 {
            localPoseMatrices[1] = skinningLabState.boneBindLocalMatrices[1] * makeRotationZMatrix(radians)
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
        if skinningLabState.isBonePaletteDirty {
            let rigPose = makeSkinningDemoRigPose()
            skinningLabState.bonePaletteMatrices = rigPose.palette
            skinningLabState.boneGlobalPoseMatrices = rigPose.globalPose
            skinningLabState.isBonePaletteDirty = false
        }

        let matrixByteCount = skinningLabState.bonePaletteMatrices.count * MemoryLayout<simd_float4x4>.stride
        guard matrixByteCount > 0 else {
            skinningLabState.bonePaletteBuffer = nil
            return
        }

        if skinningLabState.bonePaletteBuffer == nil || skinningLabState.bonePaletteBuffer?.length != matrixByteCount {
            skinningLabState.bonePaletteBuffer = device.makeBuffer(
                length: matrixByteCount,
                options: [.storageModeShared]
            )
        }
        guard let bonePaletteBuffer = skinningLabState.bonePaletteBuffer else { return }

        skinningLabState.bonePaletteMatrices.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            bonePaletteBuffer.contents().copyMemory(from: baseAddress, byteCount: rawBuffer.count)
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

    private func shouldSuspendUISyncDuringPlayback() -> Bool {
        settings.suspendUISyncDuringPlayback && interpolationLabState.playback.isPlaying != 0
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
        setPlaybackAppNapSuppressed(interpolationLabState.playback.isPlaying != 0)
    }
}
