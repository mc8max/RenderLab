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

    private let settings: RenderSettings

    private var device: MTLDevice!
    private var queue: MTLCommandQueue!

    // MARK: Timing

    private var startTime = CACurrentMediaTime()
    private var lastFrameTime = CACurrentMediaTime()
    private let hudUpdateInterval: Double = 0.1
    private var hudAccumulatedTime: Double = 0.0
    private var hudAccumulatedFrameTime: Double = 0.0
    private var hudAccumulatedFrames: Int = 0

    private var elapsedTime: Float = 0

    // MARK: Scene state

    private var currentUniforms = CoreUniforms()

    private weak var hud: HUDModel?

    private var depthTexture: MTLTexture?
    private var renderPasses: [RenderPass] = []
    private var renderAssets: RenderAssets?
    private let scene = CoreScene()

    // MARK: Camera

    private var cameraState = CoreCameraState()
    private var baseCameraParams = CoreCameraParams()
    private var cameraDebugNear: Float = 0.1
    private var cameraDebugFar: Float = 100.0

    // MARK: - Init & Setup

    init(hud: HUDModel, settings: RenderSettings) {
        self.hud = hud
        self.settings = settings
        coreCameraSetDefaultState(&cameraState)
        coreCameraSetDefaultParams(&baseCameraParams)
        cameraDebugNear = baseCameraParams.nearZ
        cameraDebugFar = baseCameraParams.farZ
    }

    /// Attach the renderer to the MTKView and prepare Metal resources.
    func attach(to view: MTKView) {
        // Get device
        guard let d = view.device else {
            fatalError("Metal is not supported on this device.")
        }
        self.device = d

        // Create command queue
        guard let q = d.makeCommandQueue() else {
            fatalError("Failed to create MTLCommandQueue.")
        }
        self.queue = q
        self.renderAssets = RenderAssets(device: d)
        BootstrapScene.loadDefaultObjects(into: scene)

        // Apply initial clear color from settings
        let c = settings.clearColorRGBA
        view.clearColor = makeMTLClearColor(from: c)

        // Build passes and their resources
        configureRenderPasses(view: view)

        setDebugMode(settings.debugMode.rawValue)
    }

    // MARK: - MTKView Drawable Loop

    func drawableSizeWillChange(size: CGSize) {
        rebuildDepthTextureIfNeeded(for: size)
        for pass in renderPasses {
            pass.drawableSizeWillChange(size: size)
        }
    }

    /// Called every frame to render content into the MTKView.
    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()

        // Ensure minimum time change is 0.0001s, which shall avoid value overflow in the FPS
        let dt = max(0.0001, now - self.lastFrameTime)

        self.lastFrameTime = now

        self.updateHUD(dt: dt)
        self.update(dt: dt, view: view)
        self.render(in: view)
    }

    /// Render the scene into the current drawable.
    private func render(in view: MTKView) {
        guard let drawable = view.currentDrawable,
            let rpd = view.currentRenderPassDescriptor
        else { return }
        let context = makeRenderContext()

        if self.depthTexture == nil {
            rebuildDepthTextureIfNeeded(for: view.drawableSize)
        }
        rpd.depthAttachment.texture = depthTexture
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = renderPasses.count > 1 ? .store : .dontCare
        rpd.depthAttachment.clearDepth = 1.0

        // Update clear color each frame from settings
        rpd.colorAttachments[0].clearColor = makeMTLClearColor(from: context.frameSettings.clearColorRGBA)

        guard let cmd = self.queue.makeCommandBuffer() else { return }

        for (index, pass) in renderPasses.enumerated() {
            guard let passDescriptor = rpd.copy() as? MTLRenderPassDescriptor else {
                continue
            }
            if index > 0 {
                passDescriptor.colorAttachments[0].loadAction = .load
                passDescriptor.depthAttachment.loadAction = .load
            }
            pass.draw(into: cmd, renderPassDescriptor: passDescriptor, context: context)
        }

        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: - Updates

    /// Update simulation parameters including camera and uniforms.
    private func update(dt: Double, view: MTKView) {
        // Advance simulation time (useful once you have multiple animated objects/camera)
        self.elapsedTime += Float(dt)

        // Guard against temporary zero-sized drawable during resize/minimize
        let w = max(1.0, view.drawableSize.width)
        let h = max(1.0, view.drawableSize.height)
        let aspect = Float(w / h)

        var cameraParams = makeCameraParamsSnapshot()
        cameraDebugNear = cameraParams.nearZ
        cameraDebugFar = cameraParams.farZ

        coreCameraSanitize(&cameraState, &cameraParams)
        coreCameraBuildOrbitUniforms(
            &currentUniforms,
            elapsedTime,
            aspect,
            &cameraState,
            &cameraParams
        )
    }

    /// Update the HUD with current frame timing information.
    private func updateHUD(dt: Double) {
        hudAccumulatedTime += dt
        hudAccumulatedFrameTime += dt
        hudAccumulatedFrames += 1

        guard hudAccumulatedTime >= hudUpdateInterval, hudAccumulatedFrames > 0 else {
            return
        }

        let avgDt = hudAccumulatedFrameTime / Double(hudAccumulatedFrames)
        let fps = 1.0 / avgDt
        let ms = avgDt * 1000.0
        hudAccumulatedTime.formTruncatingRemainder(dividingBy: hudUpdateInterval)
        hudAccumulatedFrameTime = 0.0
        hudAccumulatedFrames = 0

        DispatchQueue.main.async { [weak hud] in
            hud?.update(fps: fps, frameMs: ms)
        }
    }

    // MARK: - Pipeline & Resources

    /// Rebuild the depth texture if the drawable size changes.
    private func rebuildDepthTextureIfNeeded(for size: CGSize) {
        guard self.device != nil else { return }
        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))

        if let tex = self.depthTexture,
            tex.width == width,
            tex.height == height
        {
            return
        }

        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        d.usage = [.renderTarget]
        d.storageMode = .private

        self.depthTexture = self.device.makeTexture(descriptor: d)
    }

    // MARK: - Input

    func orbit(deltaX: Float, deltaY: Float) {
        var cameraParams = makeCameraParamsSnapshot()
        coreCameraOrbit(&cameraState, deltaX, deltaY, &cameraParams)
    }

    func pan(deltaX: Float, deltaY: Float) {
        var cameraParams = makeCameraParamsSnapshot()
        coreCameraPan(&cameraState, deltaX, deltaY, &cameraParams)
    }

    func zoom(delta: Float) {
        var cameraParams = makeCameraParamsSnapshot()
        coreCameraZoom(&cameraState, delta, &cameraParams)
    }

    func setDebugMode(_ modeRaw: Int32) {
        guard let mode = DebugMode(rawValue: modeRaw) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.settings.debugMode = mode
            self.hud?.updateMode(mode.label)
        }
    }

    func toggleGrid() {
        DispatchQueue.main.async { [weak self] in
            self?.settings.showGrid.toggle()
        }
    }

    func toggleAxis() {
        DispatchQueue.main.async { [weak self] in
            self?.settings.showAxis.toggle()
        }
    }

    func toggleHUD() {
        DispatchQueue.main.async { [weak self] in
            self?.settings.showHUD.toggle()
        }
    }

    // MARK: - Helpers

    private func makeMTLClearColor(from rgba: SIMD4<Float>) -> MTLClearColor {
        MTLClearColor(red: Double(rgba.x), green: Double(rgba.y), blue: Double(rgba.z), alpha: Double(rgba.w))
    }

    private func configureRenderPasses(view: MTKView) {
        let passes: [RenderPass] = [
            ClearPass(),
            MainPass(),
            AxisPass(),
            GridPass()
        ]
        for pass in passes {
            pass.attach(device: device, view: view)
        }
        renderPasses = passes
    }

    private func makeCameraParamsSnapshot() -> CoreCameraParams {
        let nearZ = max(0.001, settings.cameraNear)
        let farZ = max(settings.cameraFar, nearZ + 0.01)
        let fovYDegrees = min(max(settings.cameraFovYDegrees, 1.0), 170.0)

        var params = baseCameraParams
        params.nearZ = nearZ
        params.farZ = farZ
        params.fovYDegrees = fovYDegrees
        return params
    }

    private func makeRenderContext() -> RenderContext {
        guard let renderAssets else {
            fatalError("RenderAssets must be initialized before rendering.")
        }
        let frameSettings = FrameSettingsSnapshot(
            depthTest: settings.depthTest,
            cullMode: settings.cullMode,
            debugMode: settings.debugMode,
            showGrid: settings.showGrid,
            showAxis: settings.showAxis,
            cameraNear: cameraDebugNear,
            cameraFar: cameraDebugFar,
            clearColorRGBA: settings.clearColorRGBA
        )
        let uniforms = currentUniforms

        return RenderContext(
            frameSettings: frameSettings,
            uniforms: uniforms,
            renderAssets: renderAssets,
            scene: scene
        )
    }
}
