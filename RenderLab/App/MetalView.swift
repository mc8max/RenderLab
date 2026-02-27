//
//  MetalView.swift
//  RTRBaseline
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//

import MetalKit
import SwiftUI

struct MetalView: NSViewRepresentable {
    final class Coordinator: NSObject, MTKViewDelegate {
        private let renderer: Renderer

        init(hud: HUDModel) {
            self.renderer = Renderer(hud: hud)
            super.init()
        }

        func attach(to view: MTKView) {
            renderer.attach(to: view)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer.drawableSizeWillChange(size: size)
        }

        func draw(in view: MTKView) {
            renderer.draw(in: view)
        }

        func rendererOrbit(deltaX: Float, deltaY: Float) {
            renderer.orbit(deltaX: deltaX, deltaY: deltaY)
        }

        func rendererZoom(delta: Float) {
            renderer.zoom(delta: delta)
        }

        func rendererSetDebugMode(_ mode: Int32) {
            renderer.setDebugMode(mode)
        }
    }

    var hud: HUDModel

    func makeCoordinator() -> Coordinator {
        Coordinator(hud: hud)
    }

    func makeNSView(context: Context) -> MTKView {
        let v = OrbitMTKView()
        v.device = MTLCreateSystemDefaultDevice()
        v.colorPixelFormat = .bgra8Unorm_srgb
        v.clearColor = MTLClearColor(
            red: 0.08,
            green: 0.09,
            blue: 0.11,
            alpha: 1.0
        )
        v.preferredFramesPerSecond = 60
        v.enableSetNeedsDisplay = false
        v.isPaused = false

        v.onOrbitDrag = { dx, dy in
            context.coordinator.rendererOrbit(deltaX: dx, deltaY: dy)
        }
        v.onZoom = { delta in
            context.coordinator.rendererZoom(delta: delta)
        }
        v.onDebugModeKey = { mode in
            context.coordinator.rendererSetDebugMode(mode)
        }

        context.coordinator.attach(to: v)
        v.delegate = context.coordinator
        return v
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // SwiftUI updates (e.g., toggles) would be applied here later.
    }
}
