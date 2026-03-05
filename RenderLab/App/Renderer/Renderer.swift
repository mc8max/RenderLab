//
//  Renderer.swift
//  RenderLab
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//

import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

// MARK: - Renderer

final class Renderer {
    // MARK: Metal objects

    let settings: RenderSettings

    var device: MTLDevice!
    var queue: MTLCommandQueue!

    // MARK: Timing

    var startTime = CACurrentMediaTime()
    var lastFrameTime = CACurrentMediaTime()
    let hudUpdateInterval: Double = 0.1
    var hudAccumulatedTime: Double = 0.0
    var hudAccumulatedFrameTime: Double = 0.0
    var hudAccumulatedFrames: Int = 0

    var elapsedTime: Float = 0

    // MARK: Scene state

    var currentUniforms = CoreUniforms()

    weak var hud: HUDModel?

    var depthTexture: MTLTexture?
    var renderPasses: [RenderPass] = []
    var renderAssets: RenderAssets?
    let scene = CoreScene()
    weak var sceneSink: (any RendererSceneSink)?
    var selectedObjectID: UInt32?
    var objectNamesByID: [UInt32: String] = [:]
    var cubeNameCounter: Int = 1
    var interpolationLabState = RendererInterpolationLabState()
    var lastInterpolationSnapshot: InterpolationLabSnapshot?
    let interpolationSnapshotPublishInterval: Double = 1.0 / 30.0
    var interpolationSnapshotAccumulatedTime: Double = 0.0

    // MARK: Camera

    var cameraState = CoreCameraState()
    var baseCameraParams = CoreCameraParams()
    var cameraDebugNear: Float = 0.1
    var cameraDebugFar: Float = 100.0

    // MARK: - Init & Setup

    init(hud: HUDModel, settings: RenderSettings, sceneSink: (any RendererSceneSink)?) {
        self.hud = hud
        self.settings = settings
        self.sceneSink = sceneSink
        coreCameraSetDefaultState(&cameraState)
        coreCameraSetDefaultParams(&baseCameraParams)
        cameraDebugNear = baseCameraParams.nearZ
        cameraDebugFar = baseCameraParams.farZ
    }
}
