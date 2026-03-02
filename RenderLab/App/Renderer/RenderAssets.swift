//
//  RenderAssets.swift
//  RenderLab
//
//  Mesh asset registry keyed by meshID with uploaded GPU buffers.
//

import Foundation
import Metal

struct MeshGPUData {
    let meshID: UInt32
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let vertexCount: Int
    let indexCount: Int
}

final class RenderAssets {
    enum BuiltInMeshID: UInt32 {
        case cube = 1
        case triangle = 2
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
            indexCount: indices.count
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
    func remove(meshID: UInt32) -> Bool {
        return meshes.removeValue(forKey: meshID) != nil
    }

    private func registerBuiltInMeshes() {
        _ = registerCube(meshID: BuiltInMeshID.cube.rawValue)
        _ = registerTriangle(meshID: BuiltInMeshID.triangle.rawValue)
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
            indexCount: indexCount
        )
        return true
    }
}
