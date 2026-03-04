//
//  OBJLoader.swift
//  RenderLab
//
//  Loads OBJ files through Model I/O, converts to MTKMesh, then extracts
//  CoreVertex/UInt16 buffers compatible with RenderAssets.
//

import Foundation
import Metal
import MetalKit
import ModelIO
import simd

struct OBJMeshData {
    let vertices: [CoreVertex]
    let indices: [UInt16]
}

enum OBJLoaderError: Error, LocalizedError {
    case fileNotFound(String)
    case noMeshFound(URL)
    case missingVertexBuffer(meshIndex: Int)
    case unsupportedPrimitiveType(MTLPrimitiveType, meshIndex: Int)
    case unsupportedIndexType(MTLIndexType, meshIndex: Int)
    case vertexCountExceedsUInt16Limit(totalVertexCount: Int)
    case indexValueOverflow(UInt32, meshIndex: Int)
    case indexOutOfBounds(UInt32, vertexCount: Int, meshIndex: Int)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "OBJ file not found at path: \(path)"
        case .noMeshFound(let url):
            return "No mesh was found in OBJ file: \(url.lastPathComponent)"
        case .missingVertexBuffer(let meshIndex):
            return "Mesh \(meshIndex) has no vertex buffer."
        case .unsupportedPrimitiveType(let primitiveType, let meshIndex):
            return "Mesh \(meshIndex) uses unsupported primitive type \(primitiveType.rawValue). Only triangles are supported."
        case .unsupportedIndexType(let indexType, let meshIndex):
            return "Mesh \(meshIndex) uses unsupported index type \(indexType.rawValue)."
        case .vertexCountExceedsUInt16Limit(let totalVertexCount):
            return "OBJ has \(totalVertexCount) vertices after merge, exceeding 16-bit index limit (max 65,536 vertices)."
        case .indexValueOverflow(let value, let meshIndex):
            return "Mesh \(meshIndex) has index \(value), exceeding 16-bit index limit (65,535)."
        case .indexOutOfBounds(let index, let vertexCount, let meshIndex):
            return "Mesh \(meshIndex) has index \(index) out of bounds for vertex count \(vertexCount)."
        }
    }
}

final class OBJLoader {
    private let device: MTLDevice
    private let allocator: MTKMeshBufferAllocator
    private static let excludedMeshNames: Set<String> = ["plane"]
    private static let excludedMaterialNames: Set<String> = ["material.001"]

    init(device: MTLDevice) {
        self.device = device
        self.allocator = MTKMeshBufferAllocator(device: device)
    }

    func loadOBJ(fromPath path: String) throws -> OBJMeshData {
        try loadOBJ(from: URL(fileURLWithPath: path))
    }

    func loadOBJ(from url: URL) throws -> OBJMeshData {
        let standardizedURL = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedURL.path) else {
            throw OBJLoaderError.fileNotFound(standardizedURL.path)
        }

        let asset = MDLAsset(
            url: standardizedURL,
            vertexDescriptor: Self.makeOBJVertexDescriptor(),
            bufferAllocator: allocator
        )
        let (mdlMeshes, mtkMeshes) = try MTKMesh.newMeshes(asset: asset, device: device)
        guard !mtkMeshes.isEmpty else {
            throw OBJLoaderError.noMeshFound(standardizedURL)
        }

        var mergedVertices: [CoreVertex] = []
        var mergedIndices: [UInt16] = []

        for (meshIndex, mesh) in mtkMeshes.enumerated() {
            let mdlMesh: MDLMesh? = (meshIndex < mdlMeshes.count) ? mdlMeshes[meshIndex] : nil
            if let mdlMesh, shouldSkipMesh(mdlMesh) {
#if DEBUG
                print("OBJLoader: skipping mesh named '\(mdlMesh.name)'")
#endif
                continue
            }

            let excludedSubmeshIndices = mdlMesh.map(excludedSubmeshIndices) ?? []
#if DEBUG
            if !excludedSubmeshIndices.isEmpty {
                let meshName = mdlMesh?.name ?? "<unnamed>"
                print(
                    "OBJLoader: excluding submeshes \(excludedSubmeshIndices.sorted()) from mesh '\(meshName)' by material name."
                )
            }
#endif
            let hasRenderableSubmesh = mesh.submeshes.enumerated().contains { submeshIndex, _ in
                !excludedSubmeshIndices.contains(submeshIndex)
            }
            if !hasRenderableSubmesh {
                continue
            }

            let localVertices = try extractVertices(from: mesh, meshIndex: meshIndex)
            let localIndices = try extractIndices(
                from: mesh,
                vertexCount: localVertices.count,
                meshIndex: meshIndex,
                excludingSubmeshIndices: excludedSubmeshIndices
            )
            if localIndices.isEmpty {
                continue
            }

            let baseVertex = mergedVertices.count
            let mergedVertexCount = baseVertex + localVertices.count
            guard mergedVertexCount <= Int(UInt16.max) + 1 else {
                throw OBJLoaderError.vertexCountExceedsUInt16Limit(totalVertexCount: mergedVertexCount)
            }

            mergedVertices.append(contentsOf: localVertices)
            mergedIndices.reserveCapacity(mergedIndices.count + localIndices.count)
            for localIndex in localIndices {
                let adjusted = UInt32(baseVertex) + localIndex
                guard adjusted <= UInt32(UInt16.max) else {
                    throw OBJLoaderError.indexValueOverflow(adjusted, meshIndex: meshIndex)
                }
                mergedIndices.append(UInt16(adjusted))
            }
        }

        guard !mergedVertices.isEmpty, !mergedIndices.isEmpty else {
            throw OBJLoaderError.noMeshFound(standardizedURL)
        }

        return OBJMeshData(vertices: mergedVertices, indices: mergedIndices)
    }

    private func shouldSkipMesh(_ mesh: MDLMesh) -> Bool {
        let normalizedName = mesh.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return Self.excludedMeshNames.contains(normalizedName)
    }

    private func excludedSubmeshIndices(for mesh: MDLMesh) -> Set<Int> {
        guard let mdlSubmeshes = mesh.submeshes as? [MDLSubmesh] else {
            return []
        }

        var excluded: Set<Int> = []
        for (index, submesh) in mdlSubmeshes.enumerated() {
            let materialName = (submesh.material?.name ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if Self.excludedMaterialNames.contains(materialName) {
                excluded.insert(index)
            }
        }
        return excluded
    }

    private static func makeOBJVertexDescriptor() -> MDLVertexDescriptor {
        let mtlDescriptor = MTLVertexDescriptor()
        mtlDescriptor.attributes[0].format = .float3
        mtlDescriptor.attributes[0].offset = 0
        mtlDescriptor.attributes[0].bufferIndex = 0
        mtlDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride
        mtlDescriptor.layouts[0].stepFunction = .perVertex
        mtlDescriptor.layouts[0].stepRate = 1

        let mdlDescriptor = MTKModelIOVertexDescriptorFromMetal(mtlDescriptor)
        (mdlDescriptor.attributes[0] as? MDLVertexAttribute)?.name = MDLVertexAttributePosition
        return mdlDescriptor
    }

    private func extractVertices(from mesh: MTKMesh, meshIndex: Int) throws -> [CoreVertex] {
        guard let vertexBuffer = mesh.vertexBuffers.first else {
            throw OBJLoaderError.missingVertexBuffer(meshIndex: meshIndex)
        }

        let descriptor = mesh.vertexDescriptor
        let positionAttribute = descriptor.attributes[0] as? MDLVertexAttribute
        let positionOffset = positionAttribute?.offset ?? 0
        let stride = (descriptor.layouts[0] as? MDLVertexBufferLayout)?.stride
            ?? MemoryLayout<SIMD3<Float>>.stride

        let baseAddress = vertexBuffer.buffer.contents()
            .advanced(by: vertexBuffer.offset + positionOffset)
        let white = SIMD3<Float>(1.0, 1.0, 1.0)

        var vertices: [CoreVertex] = []
        vertices.reserveCapacity(mesh.vertexCount)
        for vertexIndex in 0..<mesh.vertexCount {
            let pointer = baseAddress.advanced(by: vertexIndex * stride).assumingMemoryBound(to: Float.self)
            let x = pointer[0]
            let y = pointer[1]
            let z = pointer[2]
            vertices.append(
                CoreVertex(
                    position: (x, y, z),
                    color: (white.x, white.y, white.z)
                )
            )
        }
        return vertices
    }

    private func extractIndices(
        from mesh: MTKMesh,
        vertexCount: Int,
        meshIndex: Int,
        excludingSubmeshIndices: Set<Int>
    ) throws -> [UInt32] {
        var indices: [UInt32] = []
        indices.reserveCapacity(mesh.submeshes.reduce(0) { $0 + $1.indexCount })

        for (submeshIndex, submesh) in mesh.submeshes.enumerated() {
            if excludingSubmeshIndices.contains(submeshIndex) {
                continue
            }

            guard submesh.primitiveType == .triangle else {
                throw OBJLoaderError.unsupportedPrimitiveType(submesh.primitiveType, meshIndex: meshIndex)
            }

            let baseAddress = submesh.indexBuffer.buffer.contents().advanced(by: submesh.indexBuffer.offset)
            switch submesh.indexType {
            case .uint16:
                let pointer = baseAddress.assumingMemoryBound(to: UInt16.self)
                for index in 0..<submesh.indexCount {
                    let value = UInt32(pointer[index])
                    if Int(value) >= vertexCount {
                        throw OBJLoaderError.indexOutOfBounds(value, vertexCount: vertexCount, meshIndex: meshIndex)
                    }
                    indices.append(value)
                }

            case .uint32:
                let pointer = baseAddress.assumingMemoryBound(to: UInt32.self)
                for index in 0..<submesh.indexCount {
                    let value = pointer[index]
                    if Int(value) >= vertexCount {
                        throw OBJLoaderError.indexOutOfBounds(value, vertexCount: vertexCount, meshIndex: meshIndex)
                    }
                    indices.append(value)
                }

            default:
                throw OBJLoaderError.unsupportedIndexType(submesh.indexType, meshIndex: meshIndex)
            }
        }

        return indices
    }
}
