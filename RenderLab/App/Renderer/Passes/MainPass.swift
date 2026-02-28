//
//  MainPass.swift
//  RenderLab
//
//  Created by Codex on 28/2/26.
//

import Metal

final class MainPass: RenderPass {
    let name: String = "MainPass"

    func draw(
        into commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        context: RenderContext
    ) {
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        enc.label = name
        enc.setRenderPipelineState(context.pipelineState)
        enc.setFrontFacing(.counterClockwise)
        if let depthState = context.depthStencilState {
            enc.setDepthStencilState(depthState)
        }

        switch context.settings.cullMode {
        case .none:
            enc.setCullMode(.none)
        case .back:
            enc.setCullMode(.back)
        case .front:
            enc.setCullMode(.front)
        }

        enc.setVertexBuffer(context.vertexBuffer, offset: 0, index: 0)

        var uniforms = context.uniforms
        enc.setVertexBytes(&uniforms, length: MemoryLayout<CoreUniforms>.stride, index: 1)

        var fragParams = context.debugParams
        enc.setFragmentBytes(&fragParams, length: MemoryLayout<FragmentDebugParams>.stride, index: 0)

        enc.drawIndexedPrimitives(
            type: .triangle,
            indexCount: context.indexCount,
            indexType: .uint16,
            indexBuffer: context.indexBuffer,
            indexBufferOffset: 0
        )
        enc.endEncoding()
    }
}
