//
//  InterpolationGhostPass.swift
//  RenderLab
//
//  Draws Interpolation Lab keyframe ghosts in wireframe/transparent style.
//

import Metal
import MetalKit
import simd

private struct GhostFragmentParams {
    var color: SIMD4<Float>
}

final class InterpolationGhostPass: RenderPass {
    let name: String = "InterpolationGhostPass"

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
            let pipelineState = pipelineState,
            context.interpolationGhostItems.isEmpty == false
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
        enc.setTriangleFillMode(.lines)

        for item in context.interpolationGhostItems {
            guard let mesh = context.renderAssets.mesh(for: item.meshID) else { continue }

            var uniforms = item.uniforms
            var fragmentParams = GhostFragmentParams(color: item.color)
            enc.setVertexBytes(&uniforms, length: MemoryLayout<CoreUniforms>.stride, index: 1)
            enc.setFragmentBytes(
                &fragmentParams,
                length: MemoryLayout<GhostFragmentParams>.stride,
                index: 0
            )
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
        let (vertexFunction, fragmentFunction) = PassCommon.makeShaderFunctions(
            device: device,
            vertexFunctionName: "vs_main",
            fragmentFunctionName: "fs_ghost"
        )

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "InterpolationGhostPipeline"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.vertexDescriptor = PassCommon.makePositionColorVertexDescriptor(
            stride: MemoryLayout<CoreVertex>.stride
        )
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("Failed to create interpolation ghost pipeline state: \(error)")
        }
    }
}
