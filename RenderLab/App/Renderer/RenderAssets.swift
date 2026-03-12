//
//  RenderAssets.swift
//  RenderLab
//
//  Mesh asset registry keyed by meshID with uploaded GPU buffers.
//

import Foundation
import Metal
import simd

enum MeshVertexLayout {
    case positionColor
    case skinnedPositionColorBone4
}

struct SkinnedVertex {
    var position: SIMD4<Float>
    var color: SIMD4<Float>
    var boneIndices: SIMD4<UInt16>
    var boneWeights: SIMD4<Float>

    static var colorOffset: Int {
        MemoryLayout<SkinnedVertex>.offset(of: \.color) ?? 16
    }

    static var boneIndicesOffset: Int {
        MemoryLayout<SkinnedVertex>.offset(of: \.boneIndices) ?? 32
    }

    static var boneWeightsOffset: Int {
        MemoryLayout<SkinnedVertex>.offset(of: \.boneWeights) ?? 48
    }
}

struct MeshGPUData {
    let meshID: UInt32
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let vertexCount: Int
    let indexCount: Int
    let vertexLayout: MeshVertexLayout
    let skinningBoneCount: Int
    // Packed target-major layout: targetIndex * vertexCount + vertexIndex
    let morphDeltaBuffer: MTLBuffer?
    let morphTargetCount: Int
}

final class RenderAssets {
    private let skinningWeightValidationTolerance: Float = 0.01
    private let maxMorphTargetCount: Int = MorphLabLimits.maxTargets
    private let morphDeltaMagnitudeSanityLimit: Float = 1000.0

    enum BuiltInMeshID: UInt32 {
        case cube = 1
        case triangle = 2
        case skinningRibbon = 3
        case morphRibbon = 4
    }

    private let device: MTLDevice
    private var meshes: [UInt32: MeshGPUData] = [:]

    init(device: MTLDevice, registerBuiltIns: Bool = true) {
        self.device = device
        if registerBuiltIns {
            registerBuiltInMeshes()
        }
    }

    var allMeshIDs: [UInt32] {
        return meshes.keys.sorted()
    }

    func mesh(for meshID: UInt32) -> MeshGPUData? {
        return meshes[meshID]
    }

    func registerOBJ(meshID: UInt32, from url: URL) throws {
        let loader = OBJLoader(device: device)
        let meshData = try loader.loadOBJ(from: url)
        guard register(meshID: meshID, vertices: meshData.vertices, indices: meshData.indices) else {
            throw NSError(
                domain: "RenderAssets",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to upload OBJ mesh to GPU buffers."]
            )
        }
    }

    func registerOBJ(meshID: UInt32, fromPath path: String) throws {
        try registerOBJ(meshID: meshID, from: URL(fileURLWithPath: path))
    }

    @discardableResult
    func register(meshID: UInt32, vertices: [CoreVertex], indices: [UInt16]) -> Bool {
        guard !vertices.isEmpty, !indices.isEmpty else {
            return false
        }
        if let maxIndex = indices.max(), Int(maxIndex) >= vertices.count {
            return false
        }

        let vertexByteCount = vertices.count * MemoryLayout<CoreVertex>.stride
        let indexByteCount = indices.count * MemoryLayout<UInt16>.stride

        let vertexBuffer = vertices.withUnsafeBytes { rawBuffer in
            device.makeBuffer(
                bytes: rawBuffer.baseAddress!,
                length: vertexByteCount,
                options: [.storageModeShared]
            )
        }
        let indexBuffer = indices.withUnsafeBytes { rawBuffer in
            device.makeBuffer(
                bytes: rawBuffer.baseAddress!,
                length: indexByteCount,
                options: [.storageModeShared]
            )
        }

        guard let vertexBuffer, let indexBuffer else {
            return false
        }

        meshes[meshID] = MeshGPUData(
            meshID: meshID,
            vertexBuffer: vertexBuffer,
            indexBuffer: indexBuffer,
            vertexCount: vertices.count,
            indexCount: indices.count,
            vertexLayout: .positionColor,
            skinningBoneCount: 0,
            morphDeltaBuffer: nil,
            morphTargetCount: 0
        )
        return true
    }

    @discardableResult
    func registerSkinned(
        meshID: UInt32,
        vertices: [SkinnedVertex],
        indices: [UInt16],
        boneCount: Int
    ) -> Bool {
        guard !vertices.isEmpty, !indices.isEmpty, boneCount > 0 else {
            return false
        }
        guard validateSkinnedVertices(vertices, boneCount: boneCount) else {
            return false
        }
        if let maxIndex = indices.max(), Int(maxIndex) >= vertices.count {
            return false
        }

        let vertexByteCount = vertices.count * MemoryLayout<SkinnedVertex>.stride
        let indexByteCount = indices.count * MemoryLayout<UInt16>.stride

        let vertexBuffer = vertices.withUnsafeBytes { rawBuffer in
            device.makeBuffer(
                bytes: rawBuffer.baseAddress!,
                length: vertexByteCount,
                options: [.storageModeShared]
            )
        }
        let indexBuffer = indices.withUnsafeBytes { rawBuffer in
            device.makeBuffer(
                bytes: rawBuffer.baseAddress!,
                length: indexByteCount,
                options: [.storageModeShared]
            )
        }
        guard let vertexBuffer, let indexBuffer else {
            return false
        }

        meshes[meshID] = MeshGPUData(
            meshID: meshID,
            vertexBuffer: vertexBuffer,
            indexBuffer: indexBuffer,
            vertexCount: vertices.count,
            indexCount: indices.count,
            vertexLayout: .skinnedPositionColorBone4,
            skinningBoneCount: boneCount,
            morphDeltaBuffer: nil,
            morphTargetCount: 0
        )
        return true
    }

    @discardableResult
    func registerMorphed(
        meshID: UInt32,
        vertices: [CoreVertex],
        indices: [UInt16],
        deltaPositions: [SIMD4<Float>],
        morphTargetCount: Int
    ) -> Bool {
        guard !vertices.isEmpty, !indices.isEmpty else {
            return false
        }
        guard morphTargetCount > 0 else {
            print("RenderAssets: morph target count must be positive.")
            return false
        }
        guard morphTargetCount <= maxMorphTargetCount else {
            print(
                "RenderAssets: morph target count \(morphTargetCount) exceeds supported maximum \(maxMorphTargetCount)."
            )
            return false
        }
        guard indices.count % 3 == 0 else {
            print("RenderAssets: morph mesh index count must be a multiple of 3.")
            return false
        }
        guard deltaPositions.count == vertices.count * morphTargetCount else {
            print(
                "RenderAssets: morph delta count mismatch (\(deltaPositions.count)) expected \(vertices.count * morphTargetCount)."
            )
            return false
        }
        guard validateCoreVertices(vertices) else {
            return false
        }
        guard validateMorphDeltas(deltaPositions, vertexCount: vertices.count, targetCount: morphTargetCount)
        else {
            return false
        }
        if let maxIndex = indices.max(), Int(maxIndex) >= vertices.count {
            print("RenderAssets: morph mesh index out of range for vertex count \(vertices.count).")
            return false
        }

        let vertexByteCount = vertices.count * MemoryLayout<CoreVertex>.stride
        let indexByteCount = indices.count * MemoryLayout<UInt16>.stride
        let deltaByteCount = deltaPositions.count * MemoryLayout<SIMD4<Float>>.stride

        let vertexBuffer = vertices.withUnsafeBytes { rawBuffer in
            device.makeBuffer(
                bytes: rawBuffer.baseAddress!,
                length: vertexByteCount,
                options: [.storageModeShared]
            )
        }
        let indexBuffer = indices.withUnsafeBytes { rawBuffer in
            device.makeBuffer(
                bytes: rawBuffer.baseAddress!,
                length: indexByteCount,
                options: [.storageModeShared]
            )
        }
        let deltaBuffer = deltaPositions.withUnsafeBytes { rawBuffer in
            device.makeBuffer(
                bytes: rawBuffer.baseAddress!,
                length: deltaByteCount,
                options: [.storageModeShared]
            )
        }
        guard let vertexBuffer, let indexBuffer, let deltaBuffer else {
            return false
        }

        meshes[meshID] = MeshGPUData(
            meshID: meshID,
            vertexBuffer: vertexBuffer,
            indexBuffer: indexBuffer,
            vertexCount: vertices.count,
            indexCount: indices.count,
            vertexLayout: .positionColor,
            skinningBoneCount: 0,
            morphDeltaBuffer: deltaBuffer,
            morphTargetCount: morphTargetCount
        )
        return true
    }

    @discardableResult
    func registerCube(meshID: UInt32 = BuiltInMeshID.cube.rawValue) -> Bool {
        var vPtr: UnsafeMutablePointer<CoreVertex>?
        var vCount: Int32 = 0
        var iPtr: UnsafeMutablePointer<UInt16>?
        var iCount: Int32 = 0

        coreMakeCube(&vPtr, &vCount, &iPtr, &iCount)
        return uploadAndStoreCoreAllocatedMesh(
            meshID: meshID,
            vertices: vPtr,
            vertexCount: Int(vCount),
            indices: iPtr,
            indexCount: Int(iCount)
        )
    }

    @discardableResult
    func registerTriangle(meshID: UInt32 = BuiltInMeshID.triangle.rawValue) -> Bool {
        var vPtr: UnsafeMutablePointer<CoreVertex>?
        var vCount: Int32 = 0
        var iPtr: UnsafeMutablePointer<UInt16>?
        var iCount: Int32 = 0

        coreMakeTriangle(&vPtr, &vCount, &iPtr, &iCount)
        return uploadAndStoreCoreAllocatedMesh(
            meshID: meshID,
            vertices: vPtr,
            vertexCount: Int(vCount),
            indices: iPtr,
            indexCount: Int(iCount)
        )
    }

    @discardableResult
    func registerSkinnedRibbon(
        meshID: UInt32 = BuiltInMeshID.skinningRibbon.rawValue,
        segmentCount: Int = 96,
        halfWidth: Float = 0.18,
        height: Float = 1.4,
        boneCount: Int = 16
    ) -> Bool {
        let clampedBoneCount = max(2, boneCount)
        let geometry = makeSkinnedRibbonGeometry(
            segmentCount: segmentCount,
            halfWidth: halfWidth,
            height: height,
            boneCount: clampedBoneCount
        )
        return registerSkinned(
            meshID: meshID,
            vertices: geometry.vertices,
            indices: geometry.indices,
            boneCount: clampedBoneCount
        )
    }

    @discardableResult
    func registerMorphRibbon(
        meshID: UInt32 = BuiltInMeshID.morphRibbon.rawValue,
        segmentCount: Int = 72,
        halfWidth: Float = 0.2,
        height: Float = 1.4,
        amplitude: Float = 0.28,
        morphTargetCount: Int = 4
    ) -> Bool {
        let geometry = makeMorphRibbonGeometry(
            segmentCount: segmentCount,
            halfWidth: halfWidth,
            height: height,
            amplitude: amplitude,
            morphTargetCount: morphTargetCount
        )
        return registerMorphed(
            meshID: meshID,
            vertices: geometry.vertices,
            indices: geometry.indices,
            deltaPositions: geometry.deltaPositions,
            morphTargetCount: geometry.morphTargetCount
        )
    }

    @discardableResult
    func remove(meshID: UInt32) -> Bool {
        return meshes.removeValue(forKey: meshID) != nil
    }

    private func registerBuiltInMeshes() {
        _ = registerCube(meshID: BuiltInMeshID.cube.rawValue)
        _ = registerTriangle(meshID: BuiltInMeshID.triangle.rawValue)
    }

    private func makeSkinnedRibbonGeometry(
        segmentCount: Int,
        halfWidth: Float,
        height: Float,
        boneCount: Int
    ) -> (vertices: [SkinnedVertex], indices: [UInt16]) {
        let clampedSegments = max(1, segmentCount)
        let rowCount = clampedSegments + 1
        let clampedBoneCount = max(2, boneCount)

        var vertices: [SkinnedVertex] = []
        vertices.reserveCapacity(rowCount * 2)

        var indices: [UInt16] = []
        indices.reserveCapacity(clampedSegments * 6)

        for row in 0..<rowCount {
            let t = Float(row) / Float(clampedSegments)
            let y = t * height
            let topColor = SIMD4<Float>(0.20, 0.80, 1.0, 1.0)
            let bottomColor = SIMD4<Float>(1.0, 0.45, 0.20, 1.0)
            let vertexColor = bottomColor + (topColor - bottomColor) * t

            let boneCoordinate = t * Float(clampedBoneCount - 1)
            let influences = makeBoneInfluences(
                boneCoordinate: boneCoordinate,
                boneCount: clampedBoneCount
            )
            let boneWeights = influences.weights
            let boneIndices = influences.indices

            let left = SkinnedVertex(
                position: SIMD4<Float>(-halfWidth, y, 0.0, 1.0),
                color: vertexColor,
                boneIndices: boneIndices,
                boneWeights: boneWeights
            )
            let right = SkinnedVertex(
                position: SIMD4<Float>(halfWidth, y, 0.0, 1.0),
                color: vertexColor,
                boneIndices: boneIndices,
                boneWeights: boneWeights
            )
            vertices.append(left)
            vertices.append(right)
        }

        for row in 0..<clampedSegments {
            let base = row * 2
            let i0 = UInt16(base + 0)
            let i1 = UInt16(base + 1)
            let i2 = UInt16(base + 2)
            let i3 = UInt16(base + 3)

            indices.append(i0)
            indices.append(i1)
            indices.append(i2)

            indices.append(i1)
            indices.append(i3)
            indices.append(i2)
        }

        return (vertices, indices)
    }

    private func makeBoneInfluences(
        boneCoordinate: Float,
        boneCount: Int
    ) -> (indices: SIMD4<UInt16>, weights: SIMD4<Float>) {
        var rankedBones: [(index: Int, distance: Float)] = []
        rankedBones.reserveCapacity(boneCount)
        for boneIndex in 0..<boneCount {
            let distance = abs(Float(boneIndex) - boneCoordinate)
            rankedBones.append((index: boneIndex, distance: distance))
        }
        rankedBones.sort { lhs, rhs in
            if lhs.distance == rhs.distance {
                return lhs.index < rhs.index
            }
            return lhs.distance < rhs.distance
        }

        let influenceCount = min(4, rankedBones.count)
        var indices = [Int](repeating: 0, count: 4)
        var weights = [Float](repeating: 0.0, count: 4)
        var weightSum: Float = 0.0

        for slot in 0..<influenceCount {
            let candidate = rankedBones[slot]
            indices[slot] = candidate.index
            let weight = 1.0 / (1.0 + candidate.distance * candidate.distance * 4.0)
            weights[slot] = weight
            weightSum += weight
        }

        if weightSum <= 0.000001 {
            weights[0] = 1.0
            weightSum = 1.0
        }
        for slot in 0..<4 {
            weights[slot] /= weightSum
        }

        return (
            indices: SIMD4<UInt16>(
                UInt16(indices[0]),
                UInt16(indices[1]),
                UInt16(indices[2]),
                UInt16(indices[3])
            ),
            weights: SIMD4<Float>(
                weights[0],
                weights[1],
                weights[2],
                weights[3]
            )
        )
    }

    private func makeMorphRibbonGeometry(
        segmentCount: Int,
        halfWidth: Float,
        height: Float,
        amplitude: Float,
        morphTargetCount: Int
    ) -> (
        vertices: [CoreVertex],
        deltaPositions: [SIMD4<Float>],
        indices: [UInt16],
        morphTargetCount: Int
    ) {
        let clampedSegments = max(1, segmentCount)
        let rowCount = clampedSegments + 1
        let clampedAmplitude = max(0.0, amplitude)
        let clampedTargetCount = min(max(1, morphTargetCount), maxMorphTargetCount)

        var vertices: [CoreVertex] = []
        vertices.reserveCapacity(rowCount * 2)

        var indices: [UInt16] = []
        indices.reserveCapacity(clampedSegments * 6)

        for row in 0..<rowCount {
            let t = Float(row) / Float(clampedSegments)
            let y = t * height
            let topColor = SIMD3<Float>(0.55, 0.92, 0.32)
            let bottomColor = SIMD3<Float>(0.24, 0.65, 1.0)
            let color = bottomColor + (topColor - bottomColor) * t

            for side in 0...1 {
                let x = side == 0 ? -halfWidth : halfWidth
                vertices.append(
                    CoreVertex(
                        position: (x, y, 0.0),
                        color: (color.x, color.y, color.z)
                    )
                )
            }
        }

        let vertexCount = vertices.count
        var deltaPositions = [SIMD4<Float>](
            repeating: SIMD4<Float>(repeating: 0.0),
            count: vertexCount * clampedTargetCount
        )

        for targetIndex in 0..<clampedTargetCount {
            for row in 0..<rowCount {
                let t = Float(row) / Float(clampedSegments)
                let signedT = t * 2.0 - 1.0
                let bend = sin(t * .pi)
                for side in 0...1 {
                    let sideSign: Float = side == 0 ? -1.0 : 1.0
                    let sideScale: Float = side == 0 ? 0.85 : 1.0

                    let delta: SIMD3<Float>
                    switch targetIndex {
                    case 0:
                        let wave = bend * clampedAmplitude * sideScale
                        let arch = (0.5 - abs(t - 0.5)) * clampedAmplitude * 0.22
                        delta = SIMD3<Float>(0.0, arch, wave)
                    case 1:
                        let twist = sideSign * bend * clampedAmplitude * 0.75
                        let lift = signedT * signedT * clampedAmplitude * 0.18
                        delta = SIMD3<Float>(twist, lift, 0.0)
                    case 2:
                        let pinch = -sideSign * abs(signedT) * clampedAmplitude * 0.65
                        let bulge = cos(t * .pi * 2.0) * clampedAmplitude * 0.30
                        delta = SIMD3<Float>(pinch, 0.0, bulge)
                    case 3:
                        let roll = sin(t * .pi * 2.0) * clampedAmplitude * 0.55
                        let lift = bend * clampedAmplitude * 0.24
                        delta = SIMD3<Float>(0.0, lift, roll * sideSign)
                    default:
                        let phase = Float(targetIndex - 3)
                        let offset = sin((t + phase * 0.17) * .pi * 2.0) * clampedAmplitude * 0.25
                        let lift = cos((t + phase * 0.13) * .pi) * clampedAmplitude * 0.12
                        delta = SIMD3<Float>(offset * sideSign, lift, offset * 0.35)
                    }

                    let vertexIndex = row * 2 + side
                    let packedIndex = targetIndex * vertexCount + vertexIndex
                    deltaPositions[packedIndex] = SIMD4<Float>(delta.x, delta.y, delta.z, 0.0)
                }
            }
        }

        for row in 0..<clampedSegments {
            let base = row * 2
            let i0 = UInt16(base + 0)
            let i1 = UInt16(base + 1)
            let i2 = UInt16(base + 2)
            let i3 = UInt16(base + 3)

            indices.append(i0)
            indices.append(i1)
            indices.append(i2)

            indices.append(i1)
            indices.append(i3)
            indices.append(i2)
        }

        return (vertices, deltaPositions, indices, clampedTargetCount)
    }

    private func validateSkinnedVertices(_ vertices: [SkinnedVertex], boneCount: Int) -> Bool {
        for (vertexIndex, vertex) in vertices.enumerated() {
            let weights = vertex.boneWeights
            let sum = weights.x + weights.y + weights.z + weights.w

            if !sum.isFinite {
                print("RenderAssets: invalid skinning weight sum at vertex \(vertexIndex).")
                return false
            }

            if weights.x < 0 || weights.y < 0 || weights.z < 0 || weights.w < 0 {
                print("RenderAssets: negative skinning weight at vertex \(vertexIndex).")
                return false
            }

            if abs(sum - 1.0) > skinningWeightValidationTolerance {
                print(
                    "RenderAssets: skinning weights must sum to 1 (\(sum)) at vertex \(vertexIndex)."
                )
                return false
            }

            let indices = vertex.boneIndices
            if Int(indices.x) >= boneCount
                || Int(indices.y) >= boneCount
                || Int(indices.z) >= boneCount
                || Int(indices.w) >= boneCount
            {
                print("RenderAssets: skinning bone index out of range at vertex \(vertexIndex).")
                return false
            }
        }
        return true
    }

    private func validateCoreVertices(_ vertices: [CoreVertex]) -> Bool {
        for (index, vertex) in vertices.enumerated() {
            let position = vertex.position
            let color = vertex.color
            if position.0.isFinite == false
                || position.1.isFinite == false
                || position.2.isFinite == false
                || color.0.isFinite == false
                || color.1.isFinite == false
                || color.2.isFinite == false
            {
                print("RenderAssets: invalid base vertex data at index \(index).")
                return false
            }
        }
        return true
    }

    private func validateMorphDeltas(
        _ deltas: [SIMD4<Float>],
        vertexCount: Int,
        targetCount: Int
    ) -> Bool {
        guard vertexCount > 0 else {
            print("RenderAssets: morph vertex count must be positive.")
            return false
        }
        guard targetCount > 0 else {
            print("RenderAssets: morph target count must be positive.")
            return false
        }
        guard deltas.count == vertexCount * targetCount else {
            print(
                "RenderAssets: morph packed delta count mismatch (\(deltas.count)); expected \(vertexCount * targetCount)."
            )
            return false
        }

        for targetIndex in 0..<targetCount {
            let start = targetIndex * vertexCount
            let end = start + vertexCount
            for packedIndex in start..<end {
                let delta = deltas[packedIndex]
                if delta.x.isFinite == false
                    || delta.y.isFinite == false
                    || delta.z.isFinite == false
                    || delta.w.isFinite == false
                {
                    print(
                        "RenderAssets: invalid morph delta at target \(targetIndex), packed index \(packedIndex)."
                    )
                    return false
                }
                let magnitudeSquared = delta.x * delta.x + delta.y * delta.y + delta.z * delta.z
                if magnitudeSquared > morphDeltaMagnitudeSanityLimit * morphDeltaMagnitudeSanityLimit {
                    print(
                        "RenderAssets: morph delta magnitude exceeds sanity limit at target \(targetIndex), packed index \(packedIndex)."
                    )
                    return false
                }
            }
        }
        return true
    }

    private func uploadAndStoreCoreAllocatedMesh(
        meshID: UInt32,
        vertices: UnsafeMutablePointer<CoreVertex>?,
        vertexCount: Int,
        indices: UnsafeMutablePointer<UInt16>?,
        indexCount: Int
    ) -> Bool {
        guard let vertices, let indices, vertexCount > 0, indexCount > 0 else {
            if let vertices, let indices {
                coreFreeMesh(vertices, indices)
            }
            return false
        }

        defer {
            coreFreeMesh(vertices, indices)
        }

        guard
            let vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: vertexCount * MemoryLayout<CoreVertex>.stride,
                options: [.storageModeShared]
            ),
            let indexBuffer = device.makeBuffer(
                bytes: indices,
                length: indexCount * MemoryLayout<UInt16>.stride,
                options: [.storageModeShared]
            )
        else {
            return false
        }

        meshes[meshID] = MeshGPUData(
            meshID: meshID,
            vertexBuffer: vertexBuffer,
            indexBuffer: indexBuffer,
            vertexCount: vertexCount,
            indexCount: indexCount,
            vertexLayout: .positionColor,
            skinningBoneCount: 0,
            morphDeltaBuffer: nil,
            morphTargetCount: 0
        )
        return true
    }
}
