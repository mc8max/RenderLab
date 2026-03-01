//
//  PassCommon.swift
//  RenderLab
//
//  Shared helpers to reduce pass boilerplate.
//

import Metal
import MetalKit
import simd

enum PassCommon {
    static func makeShaderFunctions(
        device: MTLDevice,
        vertexFunctionName: String = "vs_main",
        fragmentFunctionName: String = "fs_main"
    ) -> (MTLFunction, MTLFunction) {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to load default Metal library. Ensure Shaders/*.metal is in the target.")
        }

        guard
            let vertexFunction = library.makeFunction(name: vertexFunctionName),
            let fragmentFunction = library.makeFunction(name: fragmentFunctionName)
        else {
            fatalError("Missing shader functions \(vertexFunctionName)/\(fragmentFunctionName).")
        }
        return (vertexFunction, fragmentFunction)
    }

    static func makePositionColorVertexDescriptor(stride: Int) -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0

        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        descriptor.attributes[1].bufferIndex = 0

        descriptor.layouts[0].stride = stride
        descriptor.layouts[0].stepFunction = .perVertex
        descriptor.layouts[0].stepRate = 1
        return descriptor
    }

    static func makeDepthState(
        device: MTLDevice,
        depthTest: DepthTest,
        writeDepthOnLessEqual: Bool
    ) -> MTLDepthStencilState? {
        let descriptor = MTLDepthStencilDescriptor()
        switch depthTest {
        case .off:
            descriptor.isDepthWriteEnabled = false
            descriptor.depthCompareFunction = .always
        case .lessEqual:
            descriptor.isDepthWriteEnabled = writeDepthOnLessEqual
            descriptor.depthCompareFunction = .lessEqual
        }
        return device.makeDepthStencilState(descriptor: descriptor)
    }

    static func apply(cullMode: CullMode, encoder: MTLRenderCommandEncoder) {
        switch cullMode {
        case .none:
            encoder.setCullMode(.none)
        case .back:
            encoder.setCullMode(.back)
        case .front:
            encoder.setCullMode(.front)
        }
    }

    static func bindFragmentDebugParams(
        _ frameSettings: FrameSettingsSnapshot,
        encoder: MTLRenderCommandEncoder,
        index: Int = 0
    ) {
        var params = FragmentDebugParams(
            mode: frameSettings.debugMode.rawValue,
            nearZ: frameSettings.cameraNear,
            farZ: frameSettings.cameraFar
        )
        encoder.setFragmentBytes(&params, length: MemoryLayout<FragmentDebugParams>.stride, index: index)
    }
}
