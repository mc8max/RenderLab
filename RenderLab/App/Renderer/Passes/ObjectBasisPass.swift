//
//  ObjectBasisPass.swift
//  RenderLab
//
//  Draws selected-object basis vectors in world or local space.
//

import Metal
import MetalKit
import simd

private struct ObjectBasisVertex {
    var position: SIMD3<Float>
    var color: SIMD3<Float>
}

final class ObjectBasisPass: RenderPass {
    let name: String = "ObjectBasisPass"

    private var device: MTLDevice?
    private var pipelineState: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private var appliedDepthTest: DepthTest?

    private var vertexBuffer: MTLBuffer?
    private var vertexCount: Int = 0

    func attach(device: MTLDevice, view: MTKView) {
        self.device = device
        buildPipeline(device: device, view: view)
        buildGeometry(device: device)
    }

    func draw(
        into commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        context: RenderContext
    ) {
        guard context.frameSettings.showObjectBasis else { return }
        guard
            let device = device,
            let pipelineState = pipelineState,
            let vertexBuffer = vertexBuffer,
            vertexCount > 0,
            let selectedObjectID = context.selectedObjectID,
            let object = context.scene.find(objectID: selectedObjectID)
        else {
            return
        }

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

        let basisRotation: SIMD3<Float> = context.frameSettings.transformSpace == .local
            ? object.transform.rotation
            : SIMD3<Float>(repeating: 0)
        let basisTransform = SceneTransform(
            position: object.transform.position,
            rotation: basisRotation,
            scale: SIMD3<Float>(repeating: 1)
        )
        var baseUniforms = context.uniforms
        var rawTransform = basisTransform.toCoreSceneTransform()
        var uniforms = CoreUniforms()
        coreSceneMakeObjectUniforms(&uniforms, &baseUniforms, &rawTransform)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<CoreUniforms>.stride, index: 1)

        PassCommon.bindFragmentDebugParams(context.frameSettings, isSelected: true, encoder: enc)

        enc.drawPrimitives(type: .line, vertexStart: 0, vertexCount: vertexCount)
        enc.endEncoding()
    }

    private func buildPipeline(device: MTLDevice, view: MTKView) {
        let (vfn, ffn) = PassCommon.makeShaderFunctions(device: device)

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "ObjectBasisPipeline"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.vertexDescriptor = PassCommon.makePositionColorVertexDescriptor(
            stride: MemoryLayout<ObjectBasisVertex>.stride
        )
        desc.inputPrimitiveTopology = .line
        desc.depthAttachmentPixelFormat = .depth32Float

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create object basis pipeline state: \(error)")
        }
    }

    private func buildGeometry(device: MTLDevice) {
        let e = SceneGuideConfig.objectBasisExtent
        let xColor = SIMD3<Float>(1.0, 0.2, 0.2)
        let yColor = SIMD3<Float>(0.2, 1.0, 0.3)
        let zColor = SIMD3<Float>(0.2, 0.5, 1.0)

        let verts: [ObjectBasisVertex] = [
            ObjectBasisVertex(position: SIMD3<Float>(0, 0, 0), color: xColor),
            ObjectBasisVertex(position: SIMD3<Float>(e, 0, 0), color: xColor),
            ObjectBasisVertex(position: SIMD3<Float>(0, 0, 0), color: yColor),
            ObjectBasisVertex(position: SIMD3<Float>(0, e, 0), color: yColor),
            ObjectBasisVertex(position: SIMD3<Float>(0, 0, 0), color: zColor),
            ObjectBasisVertex(position: SIMD3<Float>(0, 0, e), color: zColor)
        ]

        vertexCount = verts.count
        verts.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                vertexBuffer = nil
                return
            }
            vertexBuffer = device.makeBuffer(
                bytes: baseAddress,
                length: MemoryLayout<ObjectBasisVertex>.stride * vertexCount,
                options: [.storageModeShared]
            )
        }
    }
}
