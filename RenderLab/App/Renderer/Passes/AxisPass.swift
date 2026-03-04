//
//  AxisPass.swift
//  RenderLab
//
//  Draws a simple world-space XYZ axis guide at the origin.
//

import Metal
import MetalKit
import simd

private struct AxisVertex {
    var position: SIMD3<Float>
    var color: SIMD3<Float>
}

final class AxisPass: RenderPass {
    let name: String = "AxisPass"

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
        guard context.frameSettings.showAxis else { return }
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
        desc.label = "AxisPipeline"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.vertexDescriptor = PassCommon.makePositionColorVertexDescriptor(
            stride: MemoryLayout<AxisVertex>.stride
        )
        desc.inputPrimitiveTopology = .line
        desc.depthAttachmentPixelFormat = .depth32Float

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create axis pipeline state: \(error)")
        }
    }

    private func buildGeometry(device: MTLDevice) {
        let axisExtent = SceneGuideConfig.axisExtent
        let headLength = min(SceneGuideConfig.axisArrowHeadLength, axisExtent * 0.35)
        let headWidth = SceneGuideConfig.axisArrowHeadWidth
        // Keep axis hues visually distinct from grid highlight colors.
        let xColor = SIMD3<Float>(1.0, 0.62, 0.08)
        let yColor = SIMD3<Float>(0.20, 0.95, 0.55)
        let zColor = SIMD3<Float>(0.72, 0.36, 1.0)

        var verts: [AxisVertex] = []
        verts.reserveCapacity(30)

        appendArrow(
            to: &verts,
            extent: axisExtent,
            headLength: headLength,
            headWidth: headWidth,
            direction: SIMD3<Float>(1, 0, 0),
            orthoA: SIMD3<Float>(0, 1, 0),
            orthoB: SIMD3<Float>(0, 0, 1),
            color: xColor
        )
        appendArrow(
            to: &verts,
            extent: axisExtent,
            headLength: headLength,
            headWidth: headWidth,
            direction: SIMD3<Float>(0, 1, 0),
            orthoA: SIMD3<Float>(1, 0, 0),
            orthoB: SIMD3<Float>(0, 0, 1),
            color: yColor
        )
        appendArrow(
            to: &verts,
            extent: axisExtent,
            headLength: headLength,
            headWidth: headWidth,
            direction: SIMD3<Float>(0, 0, 1),
            orthoA: SIMD3<Float>(1, 0, 0),
            orthoB: SIMD3<Float>(0, 1, 0),
            color: zColor
        )

        vertexCount = verts.count
        verts.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                vertexBuffer = nil
                return
            }
            vertexBuffer = device.makeBuffer(
                bytes: baseAddress,
                length: MemoryLayout<AxisVertex>.stride * vertexCount,
                options: [.storageModeShared]
            )
        }
    }

    private func appendArrow(
        to vertices: inout [AxisVertex],
        extent: Float,
        headLength: Float,
        headWidth: Float,
        direction: SIMD3<Float>,
        orthoA: SIMD3<Float>,
        orthoB: SIMD3<Float>,
        color: SIMD3<Float>
    ) {
        let origin = SIMD3<Float>(repeating: 0)
        let tip = direction * extent
        let base = tip - direction * headLength

        vertices.append(AxisVertex(position: origin, color: color))
        vertices.append(AxisVertex(position: tip, color: color))

        vertices.append(AxisVertex(position: tip, color: color))
        vertices.append(AxisVertex(position: base + orthoA * headWidth, color: color))

        vertices.append(AxisVertex(position: tip, color: color))
        vertices.append(AxisVertex(position: base - orthoA * headWidth, color: color))

        vertices.append(AxisVertex(position: tip, color: color))
        vertices.append(AxisVertex(position: base + orthoB * headWidth, color: color))

        vertices.append(AxisVertex(position: tip, color: color))
        vertices.append(AxisVertex(position: base - orthoB * headWidth, color: color))
    }
}
