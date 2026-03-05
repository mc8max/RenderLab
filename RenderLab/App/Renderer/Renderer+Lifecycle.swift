//
//  Renderer+Lifecycle.swift
//  RenderLab
//
//  Renderer attachment and per-frame draw lifecycle.
//

import Metal
import MetalKit
import QuartzCore
import simd

extension Renderer {
    /// Attach the renderer to the MTKView and prepare Metal resources.
    func attach(to view: MTKView) {
        guard let d = view.device else {
            fatalError("Metal is not supported on this device.")
        }
        device = d

        guard let q = d.makeCommandQueue() else {
            fatalError("Failed to create MTLCommandQueue.")
        }
        queue = q
        renderAssets = RenderAssets(device: d, registerBuiltIns: false)
        if let renderAssets {
            if let interpolationFrames = BootstrapScene.loadDefaultObjects(
                into: scene,
                renderAssets: renderAssets
            ) {
                interpolationLabState.objectID = interpolationFrames.objectID
                interpolationLabState.keyframeA = interpolationFrames.frameA
                interpolationLabState.keyframeB = interpolationFrames.frameB
                interpolationLabState.playback.t = 0.0
                interpolationLabState.playback.isPlaying = 0
                interpolationLabState.playback.direction = 1
                interpolationLabState.interpolatedTransform = interpolationFrames.frameA
                interpolationLabState.distanceToA = 0.0
                interpolationLabState.distanceToB = simd.length(
                    interpolationFrames.frameB.position - interpolationFrames.frameA.position
                )
                _ = scene.setTransform(
                    objectID: interpolationFrames.objectID,
                    transform: interpolationFrames.frameA
                )
            }
        }
        syncScenePanelState()

        let c = settings.clearColorRGBA
        view.clearColor = makeMTLClearColor(from: c)
        configureRenderPasses(view: view)
        setDebugMode(settings.debugMode.rawValue)
    }

    func drawableSizeWillChange(size: CGSize) {
        rebuildDepthTextureIfNeeded(for: size)
        for pass in renderPasses {
            pass.drawableSizeWillChange(size: size)
        }
    }

    /// Called every frame to render content into the MTKView.
    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = max(0.0001, now - lastFrameTime)
        lastFrameTime = now

        updateHUD(dt: dt)
        update(dt: dt, view: view)
        render(in: view)
    }

    private func render(in view: MTKView) {
        guard let drawable = view.currentDrawable, let rpd = view.currentRenderPassDescriptor else { return }
        let context = makeRenderContext()

        if depthTexture == nil {
            rebuildDepthTextureIfNeeded(for: view.drawableSize)
        }
        rpd.depthAttachment.texture = depthTexture
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = renderPasses.count > 1 ? .store : .dontCare
        rpd.depthAttachment.clearDepth = 1.0
        rpd.colorAttachments[0].clearColor = makeMTLClearColor(from: context.frameSettings.clearColorRGBA)

        guard let cmd = queue.makeCommandBuffer() else { return }

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

    private func rebuildDepthTextureIfNeeded(for size: CGSize) {
        guard device != nil else { return }
        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))

        if let tex = depthTexture, tex.width == width, tex.height == height {
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
        depthTexture = device.makeTexture(descriptor: d)
    }

    private func makeMTLClearColor(from rgba: SIMD4<Float>) -> MTLClearColor {
        MTLClearColor(red: Double(rgba.x), green: Double(rgba.y), blue: Double(rgba.z), alpha: Double(rgba.w))
    }

    private func configureRenderPasses(view: MTKView) {
        let passes: [RenderPass] = [
            ClearPass(),
            MainPass(),
            InterpolationGhostPass(),
            ObjectBasisPass(),
            PivotPass(),
            AxisPass(),
            GridPass()
        ]
        for pass in passes {
            pass.attach(device: device, view: view)
        }
        renderPasses = passes
    }
}
