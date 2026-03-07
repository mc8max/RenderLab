//
//  Renderer.swift
//  RenderLab
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//  Core renderer state container shared across rendering extensions.
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
    let diagnosticsLock = NSLock()
    var diagnosticsUpdateMsAccum: Double = 0.0
    var diagnosticsRenderMsAccum: Double = 0.0
    var diagnosticsFrameGapMsAccum: Double = 0.0
    var diagnosticsFrameGapMaxMs: Double = 0.0
    var diagnosticsFrameGapOver33Count: Int = 0
    var diagnosticsFrameGapOver100Count: Int = 0
    var diagnosticsFrameSamples: Int = 0
    var diagnosticsPassMsAccum: [String: Double] = [:]
    var diagnosticsPassOrder: [String] = []
    var diagnosticsCommandBufferLatencyMsAccum: Double = 0.0
    var diagnosticsCommandBufferLatencySamples: Int = 0
    var diagnosticsMainQueueLatencyMsAccum: Double = 0.0
    var diagnosticsMainQueueLatencySamples: Int = 0
    var diagnosticsMainQueueLatencyMaxMs: Double = 0.0
    var diagnosticsMainQueueLatencyOver16Count: Int = 0
    var diagnosticsMainQueueLatencyOver33Count: Int = 0
    var diagnosticsInFlightCommandBuffers: Int = 0
    var diagnosticsPeakInFlightCommandBuffers: Int = 0
    var diagnosticsSceneSnapshotPublishes: Int = 0
    var diagnosticsSelectedTransformPublishes: Int = 0
    var diagnosticsInterpolationPublishes: Int = 0
    let diagnosticsDumpInterval: Double = 30.0
    var diagnosticsDumpAccumulatedTime: Double = 0.0
    var diagnosticsDumpFrameTime: Double = 0.0
    var diagnosticsDumpFrames: Int = 0
    var diagnosticsDumpUpdateMsAccum: Double = 0.0
    var diagnosticsDumpRenderMsAccum: Double = 0.0
    var diagnosticsDumpFrameGapMsAccum: Double = 0.0
    var diagnosticsDumpFrameGapMaxMs: Double = 0.0
    var diagnosticsDumpFrameGapOver33Count: Int = 0
    var diagnosticsDumpFrameGapOver100Count: Int = 0
    var diagnosticsDumpPassMsAccum: [String: Double] = [:]
    var diagnosticsDumpPassOrder: [String] = []
    var diagnosticsDumpCommandBufferLatencyMsAccum: Double = 0.0
    var diagnosticsDumpCommandBufferLatencySamples: Int = 0
    var diagnosticsDumpMainQueueLatencyMsAccum: Double = 0.0
    var diagnosticsDumpMainQueueLatencySamples: Int = 0
    var diagnosticsDumpMainQueueLatencyMaxMs: Double = 0.0
    var diagnosticsDumpMainQueueLatencyOver16Count: Int = 0
    var diagnosticsDumpMainQueueLatencyOver33Count: Int = 0
    var diagnosticsDumpPeakInFlightCommandBuffers: Int = 0
    var diagnosticsDumpSceneSnapshotPublishes: Int = 0
    var diagnosticsDumpSelectedTransformPublishes: Int = 0
    var diagnosticsDumpInterpolationPublishes: Int = 0
    let mainQueueProbeIntervalSeconds: Double = 0.25
    let mainQueueProbeQueue = DispatchQueue(label: "RenderLab.MainQueueProbe", qos: .utility)
    var mainQueueProbeTimer: DispatchSourceTimer?
    let runtimeStateLock = NSLock()
    var cachedAppIsActive: Bool = true
    var cachedWindowIsVisible: Bool?
    var cachedWindowIsOccluded: Bool?
    var cachedViewIsPaused: Bool?
    var cachedViewEnableSetNeedsDisplay: Bool?
    var cachedPreferredFramesPerSecond: Int?
    let playbackActivityLock = NSLock()
    var playbackActivityToken: NSObjectProtocol?

    var elapsedTime: Float = 0

    // MARK: Scene state

    var currentUniforms = CoreUniforms()

    var hudOverlayPass: HUDOverlayPass?
    weak var attachedView: MTKView?

    var depthTexture: MTLTexture?
    var renderPasses: [RenderPass] = []
    var renderAssets: RenderAssets?
    let scene = CoreScene()
    weak var sceneSink: (any RendererSceneSink)?
    var selectedObjectID: UInt32?
    var objectNamesByID: [UInt32: String] = [:]
    var cubeNameCounter: Int = 1
    var selectedObjectCache: SceneObjectSnapshot?
    var interpolationLabState = RendererInterpolationLabState()
    var lastInterpolationSnapshot: InterpolationLabSnapshot?
    let interpolationSnapshotPublishIntervalIdle: Double = 1.0 / 30.0
    let interpolationSnapshotPublishIntervalPlaying: Double = 1.0 / 6.0
    var interpolationSnapshotAccumulatedTime: Double = 0.0
    let selectedTransformPublishIntervalIdle: Double = 1.0 / 20.0
    let selectedTransformPublishIntervalPlaying: Double = 1.0 / 10.0
    var selectedTransformAccumulatedTime: Double = 0.0
    var lastPublishedSelectedTransformObjectID: UInt32?
    var lastPublishedSelectedTransform: SceneTransform?

    // MARK: Camera

    var cameraState = CoreCameraState()
    var baseCameraParams = CoreCameraParams()
    var cameraDebugNear: Float = 0.1
    var cameraDebugFar: Float = 100.0

    // MARK: - Init & Setup

    init(settings: RenderSettings, sceneSink: (any RendererSceneSink)?) {
        self.settings = settings
        self.sceneSink = sceneSink
        coreCameraSetDefaultState(&cameraState)
        coreCameraSetDefaultParams(&baseCameraParams)
        cameraDebugNear = baseCameraParams.nearZ
        cameraDebugFar = baseCameraParams.farZ
        startMainQueueLatencyProbe()
    }

    deinit {
        setPlaybackAppNapSuppressed(false)
        stopMainQueueLatencyProbe()
    }
}
