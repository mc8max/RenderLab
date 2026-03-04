//
//  RenderTypes.swift
//  RenderLab
//
//  Shared frame-level render types consumed across passes and renderer.
//

import simd

struct FragmentDebugParams {
    var mode: Int32
    var isSelected: UInt32 = 0
    var nearZ: Float
    var farZ: Float
}

struct FrameSettingsSnapshot {
    let depthTest: DepthTest
    let cullMode: CullMode
    let debugMode: DebugMode
    let showGrid: Bool
    let showAxis: Bool
    let showObjectBasis: Bool
    let showPivot: Bool
    let transformSpace: TransformSpace
    let showModelMatrixDebug: Bool
    let cameraNear: Float
    let cameraFar: Float
    let clearColorRGBA: SIMD4<Float>
}

struct RenderContext {
    let frameSettings: FrameSettingsSnapshot
    let uniforms: CoreUniforms
    let renderAssets: RenderAssets
    let scene: CoreScene
    let selectedObjectID: UInt32?
}
