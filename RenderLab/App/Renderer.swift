//
//  Renderer.swift
//  RTRBaseline
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//

import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

private enum DebugMode: Int32 {
    case vertexColor = 0
    case flatWhite = 1
    case rawDepth = 2
    case linearDepth = 3

    var label: String {
        switch self {
        case .vertexColor: return "VertexColor"
        case .flatWhite: return "FlatWhite"
        case .rawDepth: return "RawDepth"
        case .linearDepth: return "LinearDepth"
        }
    }
}

private struct FragmentDebugParams {
    var mode: Int32
    var pad0: Int32 = 0
    var nearZ: Float
    var farZ: Float
}

final class Renderer {
    private var device: MTLDevice!
    private var queue: MTLCommandQueue!
    private var pipeline: MTLRenderPipelineState!
    private var depthState: MTLDepthStencilState?

    private var vertexBuffer: MTLBuffer!
    private var indexBuffer: MTLBuffer!
    private var indexCount: Int = 0

    private var startTime = CACurrentMediaTime()
    private var lastFrameTime = CACurrentMediaTime()

    private var elapsedTime: Float = 0
    private var currentUniforms = CoreUniforms()

    private weak var hud: HUDModel?

    private var depthTexture: MTLTexture?

    // Camera States
    private var cameraTarget = SIMD3<Float>(0, 0, 0)
    private var cameraRadius: Float = 2.5
    private var cameraYaw: Float = 0.0
    private var cameraPitch: Float = 0.3
    private let cameraNearZ: Float = 0.1
    private let cameraFarZ: Float = 100.0

    // Debug Mode
    private var debugMode: DebugMode = .vertexColor

    init(hud: HUDModel) {
        self.hud = hud
    }

    func attach(to view: MTKView) {
        guard let d = view.device else {
            fatalError("Metal is not supported on this device.")
        }
        self.device = d

        guard let q = d.makeCommandQueue() else {
            fatalError("Failed to create MTLCommandQueue.")
        }
        self.queue = q

        buildPipeline(view: view)
        uploadGeometry()
        uploadGeometry()

        // Initialize HUD debug mode with value from this class
        setDebugMode(self.debugMode.rawValue)
    }

    func drawableSizeWillChange(size: CGSize) {
        rebuildDepthTextureIfNeeded(for: size)
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()

        // Ensure minimum time change is 0.0001s, which shall avoid value overflow in the FPS
        let dt = max(0.0001, now - self.lastFrameTime)

        self.lastFrameTime = now

        self.updateHUD(dt: dt)
        self.update(dt: dt, view: view)
        self.render(in: view)
    }

    private func update(dt: Double, view: MTKView) {
        // Advance simulation time (useful once you have multiple animated objects/camera)
        self.elapsedTime += Float(dt)

        // Guard against temporary zero-sized drawable during resize/minimize
        let w = max(1.0, view.drawableSize.width)
        let h = max(1.0, view.drawableSize.height)
        let aspect = Float(w / h)

        var target = (
            cameraTarget.x,
            cameraTarget.y,
            cameraTarget.z
        )

        withUnsafePointer(to: &target) { targetPtr in
            targetPtr.withMemoryRebound(to: Float.self, capacity: 3) {
                floatPtr in
                coreMakeOrbitUniforms(
                    &currentUniforms,
                    elapsedTime,
                    aspect,
                    floatPtr,
                    cameraRadius,
                    cameraYaw,
                    cameraPitch
                )
            }
        }
    }

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

    private func render(in view: MTKView) {
        guard let drawable = view.currentDrawable,
            let rpd = view.currentRenderPassDescriptor
        else { return }

        if self.depthTexture == nil {
            rebuildDepthTextureIfNeeded(for: view.drawableSize)
        }
        rpd.depthAttachment.texture = depthTexture
        rpd.depthAttachment.loadAction = .clear
        rpd.depthAttachment.storeAction = .dontCare
        rpd.depthAttachment.clearDepth = 1.0

        guard let cmd = self.queue.makeCommandBuffer(),
            let enc = cmd.makeRenderCommandEncoder(descriptor: rpd)
        else { return }

        enc.setRenderPipelineState(self.pipeline)
        if let ds = self.depthState { enc.setDepthStencilState(ds) }

        enc.setVertexBuffer(self.vertexBuffer, offset: 0, index: 0)
        enc.setVertexBytes(
            &self.currentUniforms,
            length: MemoryLayout<CoreUniforms>.stride,
            index: 1
        )

        var fragParams = FragmentDebugParams(
            mode: debugMode.rawValue,
            nearZ: self.cameraNearZ,
            farZ: self.cameraFarZ
        )
        enc.setFragmentBytes(
            &fragParams,
            length: MemoryLayout<FragmentDebugParams>.stride,
            index: 0
        )

        enc.drawIndexedPrimitives(
            type: .triangle,
            indexCount: self.indexCount,
            indexType: .uint16,
            indexBuffer: self.indexBuffer,
            indexBufferOffset: 0
        )

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    private func buildPipeline(view: MTKView) {
        guard let library = self.device.makeDefaultLibrary() else {
            fatalError(
                "Failed to load default Metal library. Ensure Shaders/*.metal is in the target."
            )
        }

        let vfn = library.makeFunction(name: "vs_main")
        let ffn = library.makeFunction(name: "fs_main")
        if vfn == nil || ffn == nil {
            fatalError("Missing shader functions vs_main/fs_main.")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "RTRBaselinePipeline"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.vertexDescriptor = self.buildVertexDescriptor(view: view)
        desc.depthAttachmentPixelFormat = .depth32Float

        do {
            self.pipeline = try self.device.makeRenderPipelineState(
                descriptor: desc
            )
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }

        let dsDesc = self.buildDepthStateDescriptor()
        self.depthState = self.device.makeDepthStencilState(descriptor: dsDesc)
    }

    private func buildVertexDescriptor(view: MTKView) -> MTLVertexDescriptor {
        let vDesc = MTLVertexDescriptor()
        vDesc.attributes[0].format = .float3
        vDesc.attributes[0].offset = 0
        vDesc.attributes[0].bufferIndex = 0

        vDesc.attributes[1].format = .float3
        vDesc.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vDesc.attributes[1].bufferIndex = 0

        vDesc.layouts[0].stride = MemoryLayout<CoreVertex>.stride
        vDesc.layouts[0].stepFunction = .perVertex
        vDesc.layouts[0].stepRate = 1
        return vDesc
    }

    private func buildDepthStateDescriptor() -> MTLDepthStencilDescriptor {
        let dsDesc = MTLDepthStencilDescriptor()
        dsDesc.isDepthWriteEnabled = true
        dsDesc.depthCompareFunction = .lessEqual
        return dsDesc
    }

    private func uploadGeometry() {
        // Get data from C++ core
        var vPtr: UnsafeMutablePointer<CoreVertex>?
        var vCount: Int32 = 0
        var iPtr: UnsafeMutablePointer<UInt16>?
        var iCount: Int32 = 0

        coreMakeCube(&vPtr, &vCount, &iPtr, &iCount)

        guard let vPtrUnwrapped = vPtr, let iPtrUnwrapped = iPtr else {
            fatalError("coreMakeTriangle returned null pointers.")
        }

        self.indexCount = Int(iCount)

        self.vertexBuffer = self.device.makeBuffer(
            bytes: vPtrUnwrapped,
            length: Int(vCount) * MemoryLayout<CoreVertex>.stride,
            options: [.storageModeShared]
        )

        self.indexBuffer = self.device.makeBuffer(
            bytes: iPtrUnwrapped,
            length: Int(iCount) * MemoryLayout<UInt16>.stride,
            options: [.storageModeShared]
        )

        // Free allocations from C++ core
        coreFreeMesh(vPtrUnwrapped, iPtrUnwrapped)
    }

    private func updateHUD(dt: Double) {
        let fps = 1.0 / dt
        let ms = dt * 1000.0
        DispatchQueue.main.async { [weak hud] in
            hud?.update(fps: fps, frameMs: ms)
        }
    }

    func orbit(deltaX: Float, deltaY: Float) {
        let sensitivity: Float = 0.01
        cameraYaw += deltaX * sensitivity
        cameraPitch += deltaY * sensitivity
        cameraPitch = min(max(cameraPitch, -1.4), 1.4)
    }

    func zoom(delta: Float) {
        // delta > 0 / < 0 direction depends on device preference; flip sign if needed.
        // Multiplicative zoom feels better than linear for orbit cameras.
        let sensitivity: Float = 0.002

        let zoomFactor = exp(delta * sensitivity)
        cameraRadius *= zoomFactor

        cameraRadius = min(max(cameraRadius, 0.8), 20.0)
    }

    func setDebugMode(_ modeRaw: Int32) {
        guard let mode = DebugMode(rawValue: modeRaw) else { return }
        debugMode = mode

        DispatchQueue.main.async { [weak hud] in
            hud?.updateMode(mode.label)
        }
    }
}
