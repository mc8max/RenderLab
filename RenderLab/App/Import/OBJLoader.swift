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
        let (_, mtkMeshes) = try MTKMesh.newMeshes(asset: asset, device: device)
        guard !mtkMeshes.isEmpty else {
            throw OBJLoaderError.noMeshFound(standardizedURL)
        }

        var mergedVertices: [CoreVertex] = []
        var mergedIndices: [UInt16] = []

        for (meshIndex, mesh) in mtkMeshes.enumerated() {
            let localVertices = try extractVertices(from: mesh, meshIndex: meshIndex)
            let localIndices = try extractIndices(from: mesh, vertexCount: localVertices.count, meshIndex: meshIndex)

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

        return OBJMeshData(vertices: mergedVertices, indices: mergedIndices)
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

    private func extractIndices(from mesh: MTKMesh, vertexCount: Int, meshIndex: Int) throws -> [UInt32] {
        var indices: [UInt32] = []
        indices.reserveCapacity(mesh.submeshes.reduce(0) { $0 + $1.indexCount })

        for submesh in mesh.submeshes {
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
