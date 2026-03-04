//
//  Renderer+HUD.swift
//  RenderLab
//
//  HUD updates and UI toggle controls.
//

import Foundation

extension Renderer {
    /// Update the HUD with current frame timing information.
    func updateHUD(dt: Double) {
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

    func toggleObjectBasis() {
        DispatchQueue.main.async { [weak self] in
            self?.settings.showObjectBasis.toggle()
        }
    }

    func togglePivot() {
        DispatchQueue.main.async { [weak self] in
            self?.settings.showPivot.toggle()
        }
    }

    func toggleTransformSpace() {
        DispatchQueue.main.async { [weak self] in
            self?.settings.toggleTransformSpace()
        }
    }

    func toggleHUD() {
        DispatchQueue.main.async { [weak self] in
            self?.settings.showHUD.toggle()
        }
    }
}
