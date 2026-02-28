//
//  GridPass.swift
//  RenderLab
//
//  Created by Codex on 28/2/26.
//

import Metal
import MetalKit
import simd

private struct GridVertex {
    var position: SIMD3<Float>
    var color: SIMD3<Float>
}

final class GridPass: RenderPass {
    let name: String = "GridPass"

    private var device: MTLDevice?
    private var pipelineState: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private var appliedDepthTest: DepthTest?

    private var vertexBuffer: MTLBuffer?
    private var vertexCount: Int = 0

    private let halfLineCount: Int = 10
    private let spacing: Float = 1.0
    private let gridPlaneY: Float = -0.501

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
        guard context.frameSettings.showGrid else { return }
        guard
            let device = device,
            let pipelineState = pipelineState,
            let vertexBuffer = vertexBuffer,
            vertexCount > 0
        else {
            return
        }

        if appliedDepthTest != context.frameSettings.depthTest {
            depthState = makeDepthState(device: device, depthTest: context.frameSettings.depthTest)
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

        var uniforms = context.uniforms
        enc.setVertexBytes(&uniforms, length: MemoryLayout<CoreUniforms>.stride, index: 1)

        var fragParams = FragmentDebugParams(
            mode: context.frameSettings.debugMode.rawValue,
            nearZ: context.frameSettings.cameraNear,
            farZ: context.frameSettings.cameraFar
        )
        enc.setFragmentBytes(&fragParams, length: MemoryLayout<FragmentDebugParams>.stride, index: 0)

        enc.drawPrimitives(type: .line, vertexStart: 0, vertexCount: vertexCount)
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
        desc.label = "GridPipeline"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.vertexDescriptor = buildVertexDescriptor()
        desc.inputPrimitiveTopology = .line
        desc.depthAttachmentPixelFormat = .depth32Float

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create grid pipeline state: \(error)")
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

        vDesc.layouts[0].stride = MemoryLayout<GridVertex>.stride
        vDesc.layouts[0].stepFunction = .perVertex
        vDesc.layouts[0].stepRate = 1
        return vDesc
    }

    private func makeDepthState(device: MTLDevice, depthTest: DepthTest) -> MTLDepthStencilState? {
        let dsDesc = MTLDepthStencilDescriptor()
        dsDesc.isDepthWriteEnabled = false
        switch depthTest {
        case .off:
            dsDesc.depthCompareFunction = .always
        case .lessEqual:
            dsDesc.depthCompareFunction = .lessEqual
        }
        return device.makeDepthStencilState(descriptor: dsDesc)
    }

    private func buildGeometry(device: MTLDevice) {
        let extent = Float(halfLineCount) * spacing
        let minorColor = SIMD3<Float>(repeating: 0.25)
        let axisXColor = SIMD3<Float>(0.9, 0.25, 0.25)
        let axisZColor = SIMD3<Float>(0.25, 0.45, 0.9)

        var verts: [GridVertex] = []
        verts.reserveCapacity((halfLineCount * 2 + 1) * 4)

        for i in -halfLineCount...halfLineCount {
            let p = Float(i) * spacing
            let xLineColor = (i == 0) ? axisXColor : minorColor
            let zLineColor = (i == 0) ? axisZColor : minorColor

            // Line parallel to X axis (constant Z = p)
            verts.append(GridVertex(
                position: SIMD3<Float>(-extent, gridPlaneY, p),
                color: xLineColor
            ))
            verts.append(GridVertex(
                position: SIMD3<Float>(extent, gridPlaneY, p),
                color: xLineColor
            ))

            // Line parallel to Z axis (constant X = p)
            verts.append(GridVertex(
                position: SIMD3<Float>(p, gridPlaneY, -extent),
                color: zLineColor
            ))
            verts.append(GridVertex(
                position: SIMD3<Float>(p, gridPlaneY, extent),
                color: zLineColor
            ))
        }

        vertexCount = verts.count
        verts.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                vertexBuffer = nil
                return
            }
            vertexBuffer = device.makeBuffer(
                bytes: baseAddress,
                length: MemoryLayout<GridVertex>.stride * vertexCount,
                options: [.storageModeShared]
            )
        }
    }
}
