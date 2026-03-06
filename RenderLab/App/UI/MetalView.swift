//
//  MetalView.swift
//  RenderLab
//
//  Created by Hoàng Trí Tâm on 19/2/26.
//

import Foundation
import AppKit
import MetalKit
import SwiftUI

struct MetalView: NSViewRepresentable {
    final class Coordinator: NSObject, MTKViewDelegate {
        private let renderer: Renderer
        private let renderLoopLock = NSLock()
        private var isFrameQueued: Bool = false
        private let renderTickerQueue = DispatchQueue(label: "RenderLab.RenderTicker", qos: .userInteractive)
        private var renderTicker: DispatchSourceTimer?
        private var renderTickerFPS: Int = 60
        private weak var attachedView: MTKView?

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
                },
                onSetInterpolationKeyframeA: { [weak self] in
                    self?.renderer.setInterpolationKeyframeAFromCurrent()
                },
                onSetInterpolationKeyframeB: { [weak self] in
                    self?.renderer.setInterpolationKeyframeBFromCurrent()
                },
                onSwapInterpolationKeyframes: { [weak self] in
                    self?.renderer.swapInterpolationKeyframes()
                },
                onApplyInterpolationKeyframeA: { [weak self] in
                    self?.renderer.applyInterpolationKeyframeA()
                },
                onApplyInterpolationKeyframeB: { [weak self] in
                    self?.renderer.applyInterpolationKeyframeB()
                },
                onResetInterpolationLab: { [weak self] in
                    self?.renderer.resetInterpolationLab()
                },
                onSetInterpolationTime: { [weak self] t in
                    self?.renderer.setInterpolationTime(t)
                },
                onSetInterpolationPlaying: { [weak self] isPlaying in
                    self?.renderer.setInterpolationPlaying(isPlaying)
                },
                onSetInterpolationSpeed: { [weak self] speed in
                    self?.renderer.setInterpolationSpeed(speed)
                },
                onSetInterpolationLoopMode: { [weak self] mode in
                    self?.renderer.setInterpolationLoopMode(mode)
                },
                onSetInterpolationPositionMode: { [weak self] mode in
                    self?.renderer.setInterpolationPositionMode(mode)
                },
                onSetInterpolationRotationMode: { [weak self] mode in
                    self?.renderer.setInterpolationRotationMode(mode)
                },
                onSetInterpolationScaleMode: { [weak self] mode in
                    self?.renderer.setInterpolationScaleMode(mode)
                },
                onSetInterpolationShortestPath: { [weak self] enabled in
                    self?.renderer.setInterpolationShortestPath(enabled)
                },
                onSetInterpolationShowGhostA: { [weak self] show in
                    self?.renderer.setInterpolationShowGhostA(show)
                },
                onSetInterpolationShowGhostB: { [weak self] show in
                    self?.renderer.setInterpolationShowGhostB(show)
                }
            )
        }

        deinit {
            stopRenderTicker()
        }

        func attach(to view: MTKView) {
            renderer.attach(to: view)
            attachedView = view
            renderer.refreshCachedRuntimeStateOnMain(view: view)
            restartRenderTickerIfNeeded(for: view)
            scheduleRender()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer.drawableSizeWillChange(size: size)
            renderer.refreshCachedRuntimeStateOnMain(view: view)
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

        func rendererToggleDiagnosticsLogDump() {
            renderer.toggleDiagnosticsLogDump()
        }

        func refreshRuntimeState(view: MTKView) {
            renderer.refreshCachedRuntimeStateOnMain(view: view)
            restartRenderTickerIfNeeded(for: view)
        }

        private func restartRenderTickerIfNeeded(for view: MTKView) {
            let preferredFPS = max(1, view.preferredFramesPerSecond)
            guard preferredFPS != renderTickerFPS || renderTicker == nil else { return }
            renderTickerFPS = preferredFPS
            stopRenderTicker()
            startRenderTicker()
        }

        private func startRenderTicker() {
            guard renderTicker == nil else { return }

            let timer = DispatchSource.makeTimerSource(queue: renderTickerQueue)
            let interval = max(1.0 / Double(renderTickerFPS), 1.0 / 240.0)
            let intervalNanoseconds = max(1, Int(interval * 1_000_000_000.0))
            timer.schedule(
                deadline: .now(),
                repeating: .nanoseconds(intervalNanoseconds),
                leeway: .milliseconds(1)
            )
            timer.setEventHandler { [weak self] in
                self?.scheduleRender()
            }
            renderTicker = timer
            timer.resume()
        }

        private func stopRenderTicker() {
            guard let renderTicker else { return }
            renderTicker.setEventHandler {}
            renderTicker.cancel()
            self.renderTicker = nil
        }

        private func scheduleRender() {
            renderLoopLock.lock()
            let shouldSchedule = isFrameQueued == false
            if shouldSchedule {
                isFrameQueued = true
            }
            renderLoopLock.unlock()

            guard shouldSchedule else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                defer { self.completeScheduledFrame() }
                guard let view = self.attachedView else { return }
                self.renderer.refreshCachedRuntimeStateOnMain(view: view)
                view.draw()
            }
        }

        private func completeScheduledFrame() {
            renderLoopLock.lock()
            isFrameQueued = false
            renderLoopLock.unlock()
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
        v.isPaused = true

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
        v.onToggleDiagnosticsLogDumpKey = {
            context.coordinator.rendererToggleDiagnosticsLogDump()
        }

        context.coordinator.attach(to: v)
        v.delegate = context.coordinator
        return v
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.refreshRuntimeState(view: nsView)
    }
}
