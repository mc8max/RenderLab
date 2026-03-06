//
//  GridPass.swift
//  RenderLab
//
//  Created by Codex on 28/2/26.
//  Draws the world-space ground grid guide.
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

        var uniforms = context.uniforms
        enc.setVertexBytes(&uniforms, length: MemoryLayout<CoreUniforms>.stride, index: 1)

        PassCommon.bindFragmentDebugParams(context.frameSettings, encoder: enc)

        enc.drawPrimitives(type: .line, vertexStart: 0, vertexCount: vertexCount)
        enc.endEncoding()
    }

    private func buildPipeline(device: MTLDevice, view: MTKView) {
        let (vfn, ffn) = PassCommon.makeShaderFunctions(device: device)

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "GridPipeline"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.vertexDescriptor = PassCommon.makePositionColorVertexDescriptor(
            stride: MemoryLayout<GridVertex>.stride
        )
        desc.inputPrimitiveTopology = .line
        desc.depthAttachmentPixelFormat = .depth32Float

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create grid pipeline state: \(error)")
        }
    }

    private func buildGeometry(device: MTLDevice) {
        let halfLineCount = SceneGuideConfig.gridHalfLineCount
        let spacing = SceneGuideConfig.gridSpacing
        let extent = SceneGuideConfig.gridExtent
        let gridPlaneY = SceneGuideConfig.gridPlaneY
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
