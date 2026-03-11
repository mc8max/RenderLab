//
//  SkinningSkeletonPass.swift
//  RenderLab
//
//  Draws Skinning Lab skeleton overlay lines/joints in object space.
//

import Metal
import MetalKit
import simd

private struct SkinningSkeletonVertex {
    var position: SIMD3<Float>
    var color: SIMD3<Float>
}

final class SkinningSkeletonPass: RenderPass {
    let name: String = "SkinningSkeletonPass"

    private var device: MTLDevice?
    private var pipelineState: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private var appliedDepthTest: DepthTest?

    private var vertexBuffer: MTLBuffer?
    private var vertexBufferCapacity: Int = 0
    private var vertexCount: Int = 0

    func attach(device: MTLDevice, view: MTKView) {
        self.device = device
        buildPipeline(device: device, view: view)
    }

    func draw(
        into commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        context: RenderContext
    ) {
        guard context.skinningLab.showSkeleton else { return }
        guard
            let device = device,
            let pipelineState = pipelineState
        else {
            return
        }
        let skinnedObjects = context.scene.allObjects().filter {
            $0.isVisible && context.skinningLab.skinnedObjectIDs.contains($0.objectID)
        }
        guard skinnedObjects.isEmpty == false else { return }

        let skeletonVertices = makeSkeletonVertices(
            parentIndices: context.skinningLab.boneParentIndices,
            globalPoseMatrices: context.skinningLab.boneGlobalPoseMatrices
        )
        guard skeletonVertices.isEmpty == false else { return }
        guard updateVertexBuffer(device: device, vertices: skeletonVertices) else { return }
        guard let vertexBuffer = vertexBuffer else { return }

        if appliedDepthTest != context.frameSettings.depthTest {
            depthState = PassCommon.makeDepthState(
                device: device,
                depthTest: context.frameSettings.depthTest,
                writeDepthOnLessEqual: false
            )
            appliedDepthTest = context.frameSettings.depthTest
        }

        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        enc.label = name
        enc.setRenderPipelineState(pipelineState)
        if let depthState = depthState {
            enc.setDepthStencilState(depthState)
        }
        enc.setCullMode(.none)
        enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        var baseUniforms = context.uniforms
        for object in skinnedObjects {
            var transform = object.transform.toCoreSceneTransform()
            var objectUniforms = CoreUniforms()
            coreSceneMakeObjectUniforms(&objectUniforms, &baseUniforms, &transform)
            enc.setVertexBytes(&objectUniforms, length: MemoryLayout<CoreUniforms>.stride, index: 1)

            var fragmentParams = FragmentDebugParams(
                mode: DebugMode.vertexColor.rawValue,
                isSelected: context.selectedObjectID == object.objectID ? 1 : 0,
                nearZ: context.frameSettings.cameraNear,
                farZ: context.frameSettings.cameraFar
            )
            enc.setFragmentBytes(
                &fragmentParams,
                length: MemoryLayout<FragmentDebugParams>.stride,
                index: 0
            )
            enc.drawPrimitives(type: .line, vertexStart: 0, vertexCount: vertexCount)
        }

        enc.endEncoding()
    }

    private func buildPipeline(device: MTLDevice, view: MTKView) {
        let (vfn, ffn) = PassCommon.makeShaderFunctions(device: device)

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "SkinningSkeletonPipeline"
        descriptor.vertexFunction = vfn
        descriptor.fragmentFunction = ffn
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.inputPrimitiveTopology = .line
        descriptor.vertexDescriptor = PassCommon.makePositionColorVertexDescriptor(
            stride: MemoryLayout<SkinningSkeletonVertex>.stride
        )

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("Failed to create skinning skeleton pipeline state: \(error)")
        }
    }

    private func updateVertexBuffer(device: MTLDevice, vertices: [SkinningSkeletonVertex]) -> Bool {
        let requiredByteCount = vertices.count * MemoryLayout<SkinningSkeletonVertex>.stride
        guard requiredByteCount > 0 else { return false }

        if vertexBuffer == nil || vertexBufferCapacity < requiredByteCount {
            vertexBuffer = device.makeBuffer(
                length: requiredByteCount,
                options: [.storageModeShared]
            )
            vertexBufferCapacity = requiredByteCount
        }
        guard let vertexBuffer = vertexBuffer else { return false }

        vertices.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            vertexBuffer.contents().copyMemory(from: baseAddress, byteCount: rawBuffer.count)
        }
        vertexCount = vertices.count
        return true
    }

    private func makeSkeletonVertices(
        parentIndices: [Int32],
        globalPoseMatrices: [simd_float4x4]
    ) -> [SkinningSkeletonVertex] {
        guard parentIndices.count == globalPoseMatrices.count else { return [] }

        let boneColor = SIMD3<Float>(1.0, 0.85, 0.25)
        let jointColor = SIMD3<Float>(0.20, 0.95, 0.85)
        let markerHalfExtent: Float = 0.03
        var vertices: [SkinningSkeletonVertex] = []
        vertices.reserveCapacity(parentIndices.count * 8)

        for boneIndex in globalPoseMatrices.indices {
            let bonePosition = positionFromMatrix(globalPoseMatrices[boneIndex])
            appendJointMarker(
                to: &vertices,
                center: bonePosition,
                halfExtent: markerHalfExtent,
                color: jointColor
            )

            let parentIndex = Int(parentIndices[boneIndex])
            guard parentIndex >= 0, parentIndex < globalPoseMatrices.count else { continue }
            let parentPosition = positionFromMatrix(globalPoseMatrices[parentIndex])
            vertices.append(SkinningSkeletonVertex(position: parentPosition, color: boneColor))
            vertices.append(SkinningSkeletonVertex(position: bonePosition, color: boneColor))
        }
        return vertices
    }

    private func positionFromMatrix(_ matrix: simd_float4x4) -> SIMD3<Float> {
        SIMD3<Float>(
            matrix.columns.3.x,
            matrix.columns.3.y,
            matrix.columns.3.z
        )
    }

    private func appendJointMarker(
        to vertices: inout [SkinningSkeletonVertex],
        center: SIMD3<Float>,
        halfExtent: Float,
        color: SIMD3<Float>
    ) {
        vertices.append(SkinningSkeletonVertex(
            position: center + SIMD3<Float>(-halfExtent, 0, 0),
            color: color
        ))
        vertices.append(SkinningSkeletonVertex(
            position: center + SIMD3<Float>(halfExtent, 0, 0),
            color: color
        ))

        vertices.append(SkinningSkeletonVertex(
            position: center + SIMD3<Float>(0, -halfExtent, 0),
            color: color
        ))
        vertices.append(SkinningSkeletonVertex(
            position: center + SIMD3<Float>(0, halfExtent, 0),
            color: color
        ))

        vertices.append(SkinningSkeletonVertex(
            position: center + SIMD3<Float>(0, 0, -halfExtent),
            color: color
        ))
        vertices.append(SkinningSkeletonVertex(
            position: center + SIMD3<Float>(0, 0, halfExtent),
            color: color
        ))
    }
}
