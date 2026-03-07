//
//  HUDOverlayPass.swift
//  RenderLab
//
//  Screen-space HUD overlay pass rendered after scene passes.
//

import AppKit
import Metal
import MetalKit
import simd

private struct HUDOverlayVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
}

final class HUDOverlayPass: RenderPass {
    let name: String = "HUDOverlayPass"

    private var device: MTLDevice?
    private var pipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?
    private var depthState: MTLDepthStencilState?
    private var drawableSize: CGSize = .zero

    private let overlayTextureLock = NSLock()
    private var overlayTexture: MTLTexture?
    private var overlaySpareTexture: MTLTexture?
    private var overlayTextureSize: SIMD2<Float> = SIMD2<Float>(repeating: 0.0)
    private var lastOverlayLines: [String] = []
    private var quadVertexBuffer: MTLBuffer?
    private var cachedQuadViewportSize: SIMD2<Float> = SIMD2<Float>(repeating: -1.0)
    private var cachedQuadTextureSize: SIMD2<Float> = SIMD2<Float>(repeating: -1.0)

    private let marginX: Float = 16.0
    private let marginY: Float = 34.0

    func attach(device: MTLDevice, view: MTKView) {
        self.device = device
        drawableSize = view.drawableSize
        buildPipeline(device: device, view: view)
        buildSampler(device: device)
        buildDepthState(device: device)
    }

    func drawableSizeWillChange(size: CGSize) {
        drawableSize = size
    }

    func update(lines: [String]) {
        guard let device else { return }
        let filteredLines = lines.filter { $0.isEmpty == false }

        overlayTextureLock.lock()
        let unchanged = filteredLines == lastOverlayLines
        overlayTextureLock.unlock()
        guard unchanged == false else { return }

        guard filteredLines.isEmpty == false else {
            overlayTextureLock.lock()
            if let currentTexture = overlayTexture {
                overlaySpareTexture = currentTexture
            }
            overlayTexture = nil
            overlayTextureSize = SIMD2<Float>(repeating: 0.0)
            lastOverlayLines = []
            overlayTextureLock.unlock()
            return
        }

        guard let bitmap = makeOverlayBitmap(lines: filteredLines) else { return }

        overlayTextureLock.lock()
        let spareTexture = overlaySpareTexture
        overlayTextureLock.unlock()

        guard let writableTexture = makeReusableOverlayTexture(
            device: device,
            existing: spareTexture,
            width: bitmap.width,
            height: bitmap.height
        ) else {
            return
        }

        writableTexture.replace(
            region: MTLRegionMake2D(0, 0, bitmap.width, bitmap.height),
            mipmapLevel: 0,
            withBytes: bitmap.bytes,
            bytesPerRow: bitmap.bytesPerRow
        )

        overlayTextureLock.lock()
        let currentTexture = overlayTexture
        overlayTexture = writableTexture
        overlayTextureSize = SIMD2<Float>(Float(bitmap.width), Float(bitmap.height))
        overlaySpareTexture = currentTexture
        lastOverlayLines = filteredLines
        overlayTextureLock.unlock()
    }

    func draw(
        into commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        context: RenderContext
    ) {
        guard context.frameSettings.showHUD else { return }
        guard
            let device = device,
            let pipelineState = pipelineState,
            let samplerState = samplerState
        else {
            return
        }
        guard drawableSize.width > 1.0, drawableSize.height > 1.0 else { return }

        overlayTextureLock.lock()
        let texture = overlayTexture
        let textureSize = overlayTextureSize
        overlayTextureLock.unlock()

        guard let texture, textureSize.x > 1.0, textureSize.y > 1.0 else { return }

        let viewportSize = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
        updateQuadVertexBufferIfNeeded(
            device: device,
            viewportSize: viewportSize,
            textureSize: textureSize
        )
        guard let quadVertexBuffer else { return }

        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        enc.label = name
        enc.setRenderPipelineState(pipelineState)
        enc.setCullMode(.none)
        if let depthState {
            enc.setDepthStencilState(depthState)
        }
        enc.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(texture, index: 0)
        enc.setFragmentSamplerState(samplerState, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
    }

    private func buildPipeline(device: MTLDevice, view: MTKView) {
        let (vfn, ffn) = PassCommon.makeShaderFunctions(
            device: device,
            vertexFunctionName: "vs_hud_overlay",
            fragmentFunctionName: "fs_hud_overlay"
        )

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<HUDOverlayVertex>.stride
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        vertexDescriptor.layouts[0].stepRate = 1

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "HUDOverlayPipeline"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.vertexDescriptor = vertexDescriptor
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.depthAttachmentPixelFormat = .depth32Float
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].alphaBlendOperation = .add
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create HUD overlay pipeline state: \(error)")
        }
    }

    private func buildSampler(device: MTLDevice) {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.mipFilter = .notMipmapped
        desc.sAddressMode = .clampToEdge
        desc.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: desc)
    }

    private func buildDepthState(device: MTLDevice) {
        let desc = MTLDepthStencilDescriptor()
        desc.isDepthWriteEnabled = false
        desc.depthCompareFunction = .always
        depthState = device.makeDepthStencilState(descriptor: desc)
    }

    private func makeOverlayBitmap(lines: [String]) -> (bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int)? {
        let titleFont = NSFont.systemFont(ofSize: 17.0, weight: .semibold)
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 15.0, weight: .regular)
        let titleColor = NSColor(calibratedWhite: 1.0, alpha: 0.98)
        let bodyColor = NSColor(calibratedWhite: 0.95, alpha: 0.95)
        let lineSpacing: CGFloat = 4.0
        let paddingX: CGFloat = 14.0
        let paddingY: CGFloat = 12.0

        var items: [(text: String, font: NSFont, color: NSColor)] = []
        items.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() {
            if index == 0 {
                items.append((line, titleFont, titleColor))
            } else {
                items.append((line, bodyFont, bodyColor))
            }
        }

        var measuredWidth: CGFloat = 0.0
        var measuredHeight: CGFloat = 0.0
        for item in items {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: item.font
            ]
            let size = (item.text as NSString).size(withAttributes: attributes)
            measuredWidth = max(measuredWidth, ceil(size.width))
            measuredHeight += ceil(item.font.ascender - item.font.descender + item.font.leading)
        }
        measuredHeight += lineSpacing * CGFloat(max(0, items.count - 1))

        let width = max(1, Int(ceil(measuredWidth + paddingX * 2.0)))
        let height = max(1, Int(ceil(measuredHeight + paddingY * 2.0)))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }

        let panelRect = CGRect(x: 0.0, y: 0.0, width: CGFloat(width), height: CGFloat(height))
        let panelPath = CGPath(
            roundedRect: panelRect,
            cornerWidth: 10.0,
            cornerHeight: 10.0,
            transform: nil
        )
        context.addPath(panelPath)
        context.setFillColor(NSColor(calibratedWhite: 0.06, alpha: 0.72).cgColor)
        context.fillPath()

        context.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.08).cgColor)
        context.setLineWidth(1.0)
        context.addPath(panelPath)
        context.strokePath()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        var y = paddingY
        for item in items {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: item.font,
                .foregroundColor: item.color
            ]
            (item.text as NSString).draw(
                at: CGPoint(x: paddingX, y: y),
                withAttributes: attributes
            )
            y += ceil(item.font.ascender - item.font.descender + item.font.leading) + lineSpacing
        }
        NSGraphicsContext.restoreGraphicsState()

        return (bytes: bytes, width: width, height: height, bytesPerRow: bytesPerRow)
    }

    private func makeReusableOverlayTexture(
        device: MTLDevice,
        existing: MTLTexture?,
        width: Int,
        height: Int
    ) -> MTLTexture? {
        if let existing,
            existing.width == width,
            existing.height == height,
            existing.pixelFormat == .rgba8Unorm
        {
            return existing
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        return device.makeTexture(descriptor: descriptor)
    }

    private func updateQuadVertexBufferIfNeeded(
        device: MTLDevice,
        viewportSize: SIMD2<Float>,
        textureSize: SIMD2<Float>
    ) {
        guard
            quadVertexBuffer == nil
                || cachedQuadViewportSize != viewportSize
                || cachedQuadTextureSize != textureSize
        else {
            return
        }

        let left = -1.0 + 2.0 * (marginX / viewportSize.x)
        let right = -1.0 + 2.0 * ((marginX + textureSize.x) / viewportSize.x)
        let top = 1.0 - 2.0 * (marginY / viewportSize.y)
        let bottom = 1.0 - 2.0 * ((marginY + textureSize.y) / viewportSize.y)

        let vertices: [HUDOverlayVertex] = [
            HUDOverlayVertex(position: SIMD2<Float>(left, top), uv: SIMD2<Float>(0.0, 1.0)),
            HUDOverlayVertex(position: SIMD2<Float>(right, top), uv: SIMD2<Float>(1.0, 1.0)),
            HUDOverlayVertex(position: SIMD2<Float>(left, bottom), uv: SIMD2<Float>(0.0, 0.0)),
            HUDOverlayVertex(position: SIMD2<Float>(left, bottom), uv: SIMD2<Float>(0.0, 0.0)),
            HUDOverlayVertex(position: SIMD2<Float>(right, top), uv: SIMD2<Float>(1.0, 1.0)),
            HUDOverlayVertex(position: SIMD2<Float>(right, bottom), uv: SIMD2<Float>(1.0, 0.0))
        ]

        let byteLength = MemoryLayout<HUDOverlayVertex>.stride * vertices.count
        vertices.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            if let quadVertexBuffer, quadVertexBuffer.length == byteLength {
                memcpy(quadVertexBuffer.contents(), baseAddress, byteLength)
            } else {
                quadVertexBuffer = device.makeBuffer(
                    bytes: baseAddress,
                    length: byteLength,
                    options: [.storageModeShared]
                )
            }
        }

        cachedQuadViewportSize = viewportSize
        cachedQuadTextureSize = textureSize
    }
}
