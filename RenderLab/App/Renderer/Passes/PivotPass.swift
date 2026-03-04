//
//  PivotPass.swift
//  RenderLab
//
//  Draws a pivot marker at the selected object's origin.
//

import Metal
import MetalKit
import simd

private struct PivotVertex {
    var position: SIMD3<Float>
    var color: SIMD3<Float>
}

final class PivotPass: RenderPass {
    let name: String = "PivotPass"

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
        guard context.frameSettings.showPivot else { return }
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
        guard object.isVisible else { return }

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

        let pivotTransform = SceneTransform(
            position: object.transform.position,
            rotation: SIMD3<Float>(repeating: 0),
            scale: SIMD3<Float>(repeating: 1)
        )
        var baseUniforms = context.uniforms
        var rawTransform = pivotTransform.toCoreSceneTransform()
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
        desc.label = "PivotPipeline"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.vertexDescriptor = PassCommon.makePositionColorVertexDescriptor(
            stride: MemoryLayout<PivotVertex>.stride
        )
        desc.inputPrimitiveTopology = .line
        desc.depthAttachmentPixelFormat = .depth32Float

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create pivot pipeline state: \(error)")
        }
    }

    private func buildGeometry(device: MTLDevice) {
        let e = SceneGuideConfig.pivotMarkerExtent
        let color = SIMD3<Float>(1.0, 0.9, 0.2)

        let verts: [PivotVertex] = [
            PivotVertex(position: SIMD3<Float>(-e, 0, 0), color: color),
            PivotVertex(position: SIMD3<Float>(e, 0, 0), color: color),
            PivotVertex(position: SIMD3<Float>(0, -e, 0), color: color),
            PivotVertex(position: SIMD3<Float>(0, e, 0), color: color),
            PivotVertex(position: SIMD3<Float>(0, 0, -e), color: color),
            PivotVertex(position: SIMD3<Float>(0, 0, e), color: color)
        ]

        vertexCount = verts.count
        verts.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                vertexBuffer = nil
                return
            }
            vertexBuffer = device.makeBuffer(
                bytes: baseAddress,
                length: MemoryLayout<PivotVertex>.stride * vertexCount,
                options: [.storageModeShared]
            )
        }
    }
}
