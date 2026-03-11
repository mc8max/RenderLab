//
//  MainPass.swift
//  RenderLab
//
//  Created by Codex on 28/2/26.
//  Primary mesh rendering pass for scene objects.
//

import Metal
import MetalKit

private struct SkinningVertexParams {
    var boneCount: UInt32
}

final class MainPass: RenderPass {
    let name: String = "MainPass"

    private var device: MTLDevice?
    private var rigidPipelineState: MTLRenderPipelineState?
    private var rigidSkinnedLayoutPipelineState: MTLRenderPipelineState?
    private var skinnedPipelineState: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private var appliedDepthTest: DepthTest?

    func attach(device: MTLDevice, view: MTKView) {
        self.device = device
        buildPipelines(device: device, view: view)
    }

    func draw(
        into commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        context: RenderContext
    ) {
        guard
            let device = device,
            let rigidPipelineState = rigidPipelineState,
            let rigidSkinnedLayoutPipelineState = rigidSkinnedLayoutPipelineState,
            let skinnedPipelineState = skinnedPipelineState
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

            switch mesh.vertexLayout {
            case .positionColor:
                PassCommon.apply(cullMode: context.frameSettings.cullMode, encoder: enc)
                enc.setRenderPipelineState(rigidPipelineState)

            case .skinnedPositionColorBone4:
                // The lab ribbon is intentionally rendered two-sided for easier inspection.
                enc.setCullMode(.none)
                if
                    context.skinningLab.isEnabled,
                    context.skinningLab.skinnedObjectIDs.contains(object.objectID),
                    let bonePaletteBuffer = context.skinningLab.bonePaletteBuffer
                {
                    enc.setRenderPipelineState(skinnedPipelineState)
                    enc.setVertexBuffer(bonePaletteBuffer, offset: 0, index: 2)
                    var skinningParams = SkinningVertexParams(
                        boneCount: min(context.skinningLab.boneCount, UInt32(mesh.skinningBoneCount))
                    )
                    enc.setVertexBytes(
                        &skinningParams,
                        length: MemoryLayout<SkinningVertexParams>.stride,
                        index: 3
                    )
                } else {
                    enc.setRenderPipelineState(rigidSkinnedLayoutPipelineState)
                }
            }

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

    private func buildPipelines(device: MTLDevice, view: MTKView) {
        rigidPipelineState = makePipelineState(
            device: device,
            view: view,
            label: "RenderLabMainPipeline.Rigid",
            vertexFunctionName: "vs_main",
            fragmentFunctionName: "fs_main",
            vertexDescriptor: PassCommon.makePositionColorVertexDescriptor(
                stride: MemoryLayout<CoreVertex>.stride
            )
        )
        rigidSkinnedLayoutPipelineState = makePipelineState(
            device: device,
            view: view,
            label: "RenderLabMainPipeline.RigidSkinnedLayout",
            vertexFunctionName: "vs_main",
            fragmentFunctionName: "fs_main",
            vertexDescriptor: PassCommon.makePositionColorVertexDescriptor(
                stride: MemoryLayout<SkinnedVertex>.stride,
                colorOffset: SkinnedVertex.colorOffset
            )
        )
        skinnedPipelineState = makePipelineState(
            device: device,
            view: view,
            label: "RenderLabMainPipeline.Skinned",
            vertexFunctionName: "vs_skin_main",
            fragmentFunctionName: "fs_main",
            vertexDescriptor: PassCommon.makeSkinnedVertexDescriptor(
                stride: MemoryLayout<SkinnedVertex>.stride
            )
        )
    }

    private func makePipelineState(
        device: MTLDevice,
        view: MTKView,
        label: String,
        vertexFunctionName: String,
        fragmentFunctionName: String,
        vertexDescriptor: MTLVertexDescriptor
    ) -> MTLRenderPipelineState {
        let (vfn, ffn) = PassCommon.makeShaderFunctions(
            device: device,
            vertexFunctionName: vertexFunctionName,
            fragmentFunctionName: fragmentFunctionName
        )

        let desc = MTLRenderPipelineDescriptor()
        desc.label = label
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.vertexDescriptor = vertexDescriptor
        desc.depthAttachmentPixelFormat = .depth32Float

        do {
            return try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create pipeline state (\(label)): \(error)")
        }
    }
}
