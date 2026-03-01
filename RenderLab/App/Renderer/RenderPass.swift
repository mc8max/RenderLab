//
//  RenderPass.swift
//  RenderLab
//
//  Pass interface used by the renderer pass graph.
//

import Metal
import MetalKit

protocol RenderPass: AnyObject {
    var name: String { get }
    func attach(device: MTLDevice, view: MTKView)
    func drawableSizeWillChange(size: CGSize)
    func draw(
        into commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        context: RenderContext
    )
}

extension RenderPass {
    func drawableSizeWillChange(size: CGSize) {}
}
