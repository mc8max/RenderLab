//
//  MetalView.swift
//  RenderLab
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//

import MetalKit
import SwiftUI

struct MetalView: NSViewRepresentable {
    final class Coordinator: NSObject, MTKViewDelegate {
        private let renderer: Renderer

        init(
            hud: HUDModel,
            settings: RenderSettings,
            sceneSink: (any RendererSceneSink)?,
            sceneCommands: SceneCommandBridge
        ) {
            self.renderer = Renderer(hud: hud, settings: settings, sceneSink: sceneSink)
            super.init()
            sceneCommands.bindRendererActions(
                onSelectObject: { [weak self] objectID in
                    self?.renderer.setSelectedObjectID(objectID)
                },
                onSetObjectVisibility: { [weak self] objectID, isVisible in
                    self?.renderer.setObjectVisibility(objectID: objectID, isVisible: isVisible)
                },
                onSetObjectTransform: { [weak self] objectID, transform in
                    self?.renderer.setObjectTransform(objectID: objectID, transform: transform)
                },
                onAddCube: { [weak self] in
                    self?.renderer.addCubeObject()
                }
            )
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

        func rendererPan(deltaX: Float, deltaY: Float) {
            renderer.pan(deltaX: deltaX, deltaY: deltaY)
        }

        func rendererZoom(delta: Float) {
            renderer.zoom(delta: delta)
        }

        func rendererSetDebugMode(_ mode: Int32) {
            renderer.setDebugMode(mode)
        }

        func rendererToggleGrid() {
            renderer.toggleGrid()
        }

        func rendererToggleAxis() {
            renderer.toggleAxis()
        }

        func rendererToggleObjectBasis() {
            renderer.toggleObjectBasis()
        }

        func rendererTogglePivot() {
            renderer.togglePivot()
        }

        func rendererToggleTransformSpace() {
            renderer.toggleTransformSpace()
        }

        func rendererToggleHUD() {
            renderer.toggleHUD()
        }
    }

    var hud: HUDModel
    var settings: RenderSettings
    var sceneSink: (any RendererSceneSink)?
    var sceneCommands: SceneCommandBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(
            hud: hud,
            settings: settings,
            sceneSink: sceneSink,
            sceneCommands: sceneCommands
        )
    }

    func makeNSView(context: Context) -> MTKView {
        let v = OrbitMTKView()
        v.device = MTLCreateSystemDefaultDevice()
        v.colorPixelFormat = .bgra8Unorm_srgb
        v.preferredFramesPerSecond = 60
        v.enableSetNeedsDisplay = false
        v.isPaused = false

        v.onOrbitDrag = { dx, dy in
            context.coordinator.rendererOrbit(deltaX: dx, deltaY: dy)
        }
        v.onPanDrag = { dx, dy in
            context.coordinator.rendererPan(deltaX: dx, deltaY: dy)
        }
        v.onZoom = { delta in
            context.coordinator.rendererZoom(delta: delta)
        }
        v.onDebugModeKey = { mode in
            context.coordinator.rendererSetDebugMode(mode)
        }
        v.onToggleGridKey = {
            context.coordinator.rendererToggleGrid()
        }
        v.onToggleAxisKey = {
            context.coordinator.rendererToggleAxis()
        }
        v.onToggleObjectBasisKey = {
            context.coordinator.rendererToggleObjectBasis()
        }
        v.onTogglePivotKey = {
            context.coordinator.rendererTogglePivot()
        }
        v.onToggleTransformSpaceKey = {
            context.coordinator.rendererToggleTransformSpace()
        }
        v.onToggleHUDKey = {
            context.coordinator.rendererToggleHUD()
        }

        context.coordinator.attach(to: v)
        v.delegate = context.coordinator
        return v
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // SwiftUI updates (e.g., toggles) would be applied here later.
    }
}
