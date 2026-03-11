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
}

final class RenderAssets {
    private let skinningWeightValidationTolerance: Float = 0.01

    enum BuiltInMeshID: UInt32 {
        case cube = 1
        case triangle = 2
        case skinningRibbon = 3
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
            skinningBoneCount: 0
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
            skinningBoneCount: boneCount
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
        segmentCount: Int = 28,
        halfWidth: Float = 0.18,
        height: Float = 1.4
    ) -> Bool {
        let geometry = makeSkinnedRibbonGeometry(
            segmentCount: segmentCount,
            halfWidth: halfWidth,
            height: height
        )
        return registerSkinned(
            meshID: meshID,
            vertices: geometry.vertices,
            indices: geometry.indices,
            boneCount: 2
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
        height: Float
    ) -> (vertices: [SkinnedVertex], indices: [UInt16]) {
        let clampedSegments = max(1, segmentCount)
        let rowCount = clampedSegments + 1

        var vertices: [SkinnedVertex] = []
        vertices.reserveCapacity(rowCount * 2)

        var indices: [UInt16] = []
        indices.reserveCapacity(clampedSegments * 6)

        let blendStartY = height * 0.28
        let blendEndY = height * 0.9

        for row in 0..<rowCount {
            let t = Float(row) / Float(clampedSegments)
            let y = t * height
            let topColor = SIMD4<Float>(0.20, 0.80, 1.0, 1.0)
            let bottomColor = SIMD4<Float>(1.0, 0.45, 0.20, 1.0)
            let vertexColor = bottomColor + (topColor - bottomColor) * t

            let w1 = saturate((y - blendStartY) / max(0.0001, blendEndY - blendStartY))
            let w0 = 1.0 - w1
            let boneWeights = SIMD4<Float>(w0, w1, 0.0, 0.0)
            let boneIndices = SIMD4<UInt16>(0, 1, 0, 0)

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

    private func saturate(_ value: Float) -> Float {
        min(max(value, 0.0), 1.0)
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
            skinningBoneCount: 0
        )
        return true
    }
}
