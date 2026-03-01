//
//  RenderAssets.swift
//  RenderLab
//
//  Mesh asset registry keyed by meshID with uploaded GPU buffers.
//

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

    init(device: MTLDevice) {
        self.device = device
        registerBuiltInMeshes()
    }

    var allMeshIDs: [UInt32] {
        return meshes.keys.sorted()
    }

    func mesh(for meshID: UInt32) -> MeshGPUData? {
        return meshes[meshID]
    }

    @discardableResult
    func registerCube(meshID: UInt32 = BuiltInMeshID.cube.rawValue) -> Bool {
        var vPtr: UnsafeMutablePointer<CoreVertex>?
        var vCount: Int32 = 0
        var iPtr: UnsafeMutablePointer<UInt16>?
        var iCount: Int32 = 0

        coreMakeCube(&vPtr, &vCount, &iPtr, &iCount)
        return uploadAndStoreMesh(
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
        return uploadAndStoreMesh(
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

    private func uploadAndStoreMesh(
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
