//
//  MainPass.swift
//  RenderLab
//
//  Created by Codex on 28/2/26.
//

import Metal
import MetalKit

final class MainPass: RenderPass {
    let name: String = "MainPass"

    private var device: MTLDevice?
    private var pipelineState: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private var appliedDepthTest: DepthTest?

    func attach(device: MTLDevice, view: MTKView) {
        self.device = device
        buildPipeline(device: device, view: view)
    }

    func draw(
        into commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        context: RenderContext
    ) {
        guard
            let device = device,
            let pipelineState = pipelineState
        else {
            return
        }

        let visibleObjects = context.scene.allObjects().filter { $0.isVisible }
        if visibleObjects.isEmpty {
            return
        }

        if appliedDepthTest != context.frameSettings.depthTest {
            depthState = PassCommon.makeDepthState(
                device: device,
                depthTest: context.frameSettings.depthTest,
                writeDepthOnLessEqual: true
            )
            appliedDepthTest = context.frameSettings.depthTest
        }

        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        enc.label = name
        enc.setRenderPipelineState(pipelineState)
        enc.setFrontFacing(.counterClockwise)
        if let depthState = depthState {
            enc.setDepthStencilState(depthState)
        }
        PassCommon.apply(cullMode: context.frameSettings.cullMode, encoder: enc)

        var baseUniforms = context.uniforms

        for object in visibleObjects {
            guard let mesh = context.renderAssets.mesh(for: object.meshID) else {
                continue
            }
            PassCommon.bindFragmentDebugParams(
                context.frameSettings,
                isSelected: context.selectedObjectID == object.objectID,
                encoder: enc
            )
            var transform = object.transform.toCoreSceneTransform()
            var uniforms = CoreUniforms()
            coreSceneMakeObjectUniforms(&uniforms, &baseUniforms, &transform)
            enc.setVertexBytes(&uniforms, length: MemoryLayout<CoreUniforms>.stride, index: 1)
            enc.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
            enc.drawIndexedPrimitives(
                type: .triangle,
                indexCount: mesh.indexCount,
                indexType: .uint16,
                indexBuffer: mesh.indexBuffer,
                indexBufferOffset: 0
            )
        }
        enc.endEncoding()
    }

    private func buildPipeline(device: MTLDevice, view: MTKView) {
        let (vfn, ffn) = PassCommon.makeShaderFunctions(device: device)

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "RenderLabMainPipeline"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.vertexDescriptor = PassCommon.makePositionColorVertexDescriptor(
            stride: MemoryLayout<CoreVertex>.stride
        )
        desc.depthAttachmentPixelFormat = .depth32Float

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }
}
