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

    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var indexCount: Int = 0

    func attach(device: MTLDevice, view: MTKView) {
        self.device = device
        buildPipeline(device: device, view: view)
        uploadGeometry(device: device)
    }

    func draw(
        into commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        context: RenderContext
    ) {
        guard
            let device = device,
            let pipelineState = pipelineState,
            let vertexBuffer = vertexBuffer,
            let indexBuffer = indexBuffer
        else {
            return
        }

        if appliedDepthTest != context.settings.depthTest {
            depthState = makeDepthState(device: device, depthTest: context.settings.depthTest)
            appliedDepthTest = context.settings.depthTest
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

        switch context.settings.cullMode {
        case .none:
            enc.setCullMode(.none)
        case .back:
            enc.setCullMode(.back)
        case .front:
            enc.setCullMode(.front)
        }

        enc.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        var uniforms = context.uniforms
        enc.setVertexBytes(&uniforms, length: MemoryLayout<CoreUniforms>.stride, index: 1)

        var fragParams = context.debugParams
        enc.setFragmentBytes(&fragParams, length: MemoryLayout<FragmentDebugParams>.stride, index: 0)

        enc.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint16,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )
        enc.endEncoding()
    }

    private func buildPipeline(device: MTLDevice, view: MTKView) {
        guard let library = device.makeDefaultLibrary() else {
            fatalError(
                "Failed to load default Metal library. Ensure Shaders/*.metal is in the target."
            )
        }

        let vfn = library.makeFunction(name: "vs_main")
        let ffn = library.makeFunction(name: "fs_main")
        if vfn == nil || ffn == nil {
            fatalError("Missing shader functions vs_main/fs_main.")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "RTRBaselinePipeline"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.vertexDescriptor = buildVertexDescriptor()
        desc.depthAttachmentPixelFormat = .depth32Float

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }

    private func buildVertexDescriptor() -> MTLVertexDescriptor {
        let vDesc = MTLVertexDescriptor()
        vDesc.attributes[0].format = .float3
        vDesc.attributes[0].offset = 0
        vDesc.attributes[0].bufferIndex = 0

        vDesc.attributes[1].format = .float3
        vDesc.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vDesc.attributes[1].bufferIndex = 0

        vDesc.layouts[0].stride = MemoryLayout<CoreVertex>.stride
        vDesc.layouts[0].stepFunction = .perVertex
        vDesc.layouts[0].stepRate = 1
        return vDesc
    }

    private func makeDepthState(device: MTLDevice, depthTest: DepthTest) -> MTLDepthStencilState? {
        let dsDesc = MTLDepthStencilDescriptor()
        switch depthTest {
        case .off:
            dsDesc.isDepthWriteEnabled = false
            dsDesc.depthCompareFunction = .always
        case .lessEqual:
            dsDesc.isDepthWriteEnabled = true
            dsDesc.depthCompareFunction = .lessEqual
        }
        return device.makeDepthStencilState(descriptor: dsDesc)
    }

    private func uploadGeometry(device: MTLDevice) {
        var vPtr: UnsafeMutablePointer<CoreVertex>?
        var vCount: Int32 = 0
        var iPtr: UnsafeMutablePointer<UInt16>?
        var iCount: Int32 = 0

        coreMakeCube(&vPtr, &vCount, &iPtr, &iCount)

        guard let vPtrUnwrapped = vPtr, let iPtrUnwrapped = iPtr else {
            fatalError("coreMakeCube returned null pointers.")
        }

        self.indexCount = Int(iCount)

        self.vertexBuffer = device.makeBuffer(
            bytes: vPtrUnwrapped,
            length: Int(vCount) * MemoryLayout<CoreVertex>.stride,
            options: [.storageModeShared]
        )

        self.indexBuffer = device.makeBuffer(
            bytes: iPtrUnwrapped,
            length: Int(iCount) * MemoryLayout<UInt16>.stride,
            options: [.storageModeShared]
        )

        coreFreeMesh(vPtrUnwrapped, iPtrUnwrapped)
    }
}
