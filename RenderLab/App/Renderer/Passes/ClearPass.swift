//
//  ClearPass.swift
//  RenderLab
//
//  Created by Codex on 28/2/26.
//  Minimal pass that clears color/depth attachments for the frame.
//

import Metal
import MetalKit

final class ClearPass: RenderPass {
    let name: String = "ClearPass"

    func attach(device: MTLDevice, view: MTKView) {}

    func draw(
        into commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        context: RenderContext
    ) {
        // Force execution of pass 0 so clear load actions are applied.
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        enc.label = name
        enc.endEncoding()
    }
}
